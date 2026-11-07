package route

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/auth"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"pindrel/internal/database/db"
	"pindrel/internal/files"
	AuthMiddleware "pindrel/internal/middleware"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
	"golang.org/x/time/rate"
	"google.golang.org/protobuf/proto"
)

const filesSecret = "segredo-das-rotas-de-arquivos"

type filesRig struct {
	t      *testing.T
	router http.Handler
	token  string
	chunks *AuthMiddleware.IPRateLimiter
}

// newFilesRig builds the real router with the real file service on the real database.
func newFilesRig(t *testing.T, withFiles bool, chunkBurst int) *filesRig {
	t.Helper()
	_ = godotenv.Load("../../../.env")
	conf, err := config.Load()
	if err != nil {
		t.Fatalf("configuration: %v", err)
	}
	conf.Database.MaxConns = 2
	pool, err := database.NewConnection(context.Background(), conf.Database)
	if err != nil {
		t.Fatalf("database: %v", err)
	}
	t.Cleanup(pool.Close)
	q := db.New(pool)
	hash, _ := auth.HashPassword("senha_valida_123")
	u, err := q.CreateUser(context.Background(), db.CreateUserParams{Email: "route-" + uuid.NewString() + "@test.com", PasswordHash: hash})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = q.DeleteUser(context.Background(), u.ID) })
	token, err := auth.GenerateToken(u.ID, filesSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	cfg := &config.Config{InAppRateLimit: true, JWTSecret: filesSecret}
	rig := &filesRig{t: t, token: token}
	var extras Extras
	if withFiles {
		store, err := files.NewStore(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		svc := files.NewService(pool, q, store, files.Config{MaxFileBytes: 8 << 20, QuotaBytes: 64 << 20, MaxOpenUploads: 4, UploadTTL: time.Hour, OrphanGrace: time.Hour, LinkTTL: time.Minute, Secret: []byte(filesSecret)})
		rig.chunks = AuthMiddleware.NewIPRateLimiter(rate.Every(time.Hour), chunkBurst)
		extras = Extras{Files: files.NewHandler(svc), FileLimiters: &FileLimiters{Chunks: rig.chunks, Control: AuthMiddleware.NewIPRateLimiter(rate.Every(time.Millisecond), 1000)}}
	}
	rig.router = SetupRouter(cfg, q, &auth.Handler{}, AuthMiddleware.NewIPRateLimiter(0, 5), AuthMiddleware.NewIPRateLimiter(0, 5), extras)
	return rig
}

func (r *filesRig) do(method, path string, body []byte, auth bool, headers ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	req.RemoteAddr = "203.0.113.9:4000"
	if auth {
		req.Header.Set("Authorization", "Bearer "+r.token)
	}
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	r.router.ServeHTTP(rec, req)
	return rec
}

func (r *filesRig) open(size int64) string {
	r.t.Helper()
	b, _ := proto.Marshal(&dto.CreateUploadRequest{Size: size, Name: "x.txt"})
	rec := r.do(http.MethodPost, "/files/uploads/", b, true)
	if rec.Code != http.StatusCreated {
		r.t.Fatalf("create: %d %s", rec.Code, rec.Body.String())
	}
	var out dto.CreateUploadResponse
	_ = proto.Unmarshal(rec.Body.Bytes(), &out)
	return out.UploadId
}

func piece(r *filesRig, id string, n int, data []byte) *httptest.ResponseRecorder {
	s := sha256.Sum256(data)
	return r.do(http.MethodPut, "/files/uploads/"+id+"/"+strconv.Itoa(n), data, true, "X-Chunk-Sha256", hex.EncodeToString(s[:]))
}

func TestDB_FileRoutes_NeedASessionExceptTheSignedDownload(t *testing.T) {
	r := newFilesRig(t, true, 100)
	for _, route := range [][2]string{{"GET", "/files/"}, {"POST", "/files/uploads/"}, {"GET", "/files/uploads/" + uuid.NewString()}, {"PUT", "/files/uploads/" + uuid.NewString() + "/0"}, {"POST", "/files/uploads/" + uuid.NewString() + "/finish"}, {"DELETE", "/files/uploads/" + uuid.NewString()}, {"POST", "/files/" + uuid.NewString() + "/link"}, {"DELETE", "/files/" + uuid.NewString()}, {"PUT", "/files/" + uuid.NewString() + "/orphan"}} {
		if rec := r.do(route[0], route[1], nil, false); rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without a token: %d", route[0], route[1], rec.Code)
		}
	}
	// the download asks for a signature, not a session
	if rec := r.do(http.MethodGet, "/files/"+uuid.NewString(), nil, false); rec.Code != http.StatusForbidden {
		t.Errorf("unsigned download: %d", rec.Code)
	}
}

func TestDB_FileRoutes_AreAbsentWhenFilesAreOff(t *testing.T) {
	r := newFilesRig(t, false, 100)
	for _, route := range [][2]string{{"GET", "/files/"}, {"POST", "/files/uploads/"}, {"GET", "/files/" + uuid.NewString()}} {
		if rec := r.do(route[0], route[1], nil, true); rec.Code != http.StatusNotFound {
			t.Errorf("%s %s with files off: %d", route[0], route[1], rec.Code)
		}
	}
}

func TestDB_FileRoutes_ManyPiecesAreNotStoppedByTheGlobalLimitOfOneHundredAMinute(t *testing.T) {
	r := newFilesRig(t, true, 1000)
	data := bytes.Repeat([]byte("a"), files.ChunkSize)
	id := r.open(int64(len(data)))
	// the same piece again is harmless, and each send is one request against the global limit
	for n := 0; n < 150; n++ {
		if rec := piece(r, id, 0, data); rec.Code != http.StatusNoContent {
			t.Fatalf("send %d: %d (the per-IP limit of the API must not apply here)", n, rec.Code)
		}
	}
	// ...while the rest of the API keeps its limit
	limited := false
	for i := 0; i < 130; i++ {
		if rec := r.do(http.MethodGet, "/server/info/", nil, false); rec.Code == http.StatusTooManyRequests {
			limited = true
			break
		}
	}
	if !limited {
		t.Error("the global limit no longer applies to the other routes")
	}
}

func TestDB_FileRoutes_PiecesHaveALimitPerPerson(t *testing.T) {
	r := newFilesRig(t, true, 3)
	data := []byte("0123456789")
	id := r.open(int64(len(data)))
	codes := map[int]int{}
	for i := 0; i < 8; i++ {
		codes[piece(r, id, 0, data).Code]++
	}
	if codes[http.StatusNoContent] != 3 || codes[http.StatusTooManyRequests] != 5 {
		t.Errorf("pieces: %v", codes)
	}
}

func TestDB_FileRoutes_TheWholeTripThroughTheRealRouter(t *testing.T) {
	r := newFilesRig(t, true, 100)
	data := []byte(strings.Repeat("olá, mundo\n", 60_000)) // ~660 KB, two pieces, text
	id := r.open(int64(len(data)))
	for n := 0; n*files.ChunkSize < len(data); n++ {
		if rec := piece(r, id, n, data[n*files.ChunkSize:min((n+1)*files.ChunkSize, len(data))]); rec.Code != http.StatusNoContent {
			t.Fatalf("piece %d: %d", n, rec.Code)
		}
	}
	rec := r.do(http.MethodPost, "/files/uploads/"+id+"/finish", nil, true)
	var done dto.FinishUploadResponse
	if rec.Code != http.StatusCreated || proto.Unmarshal(rec.Body.Bytes(), &done) != nil {
		t.Fatalf("finish: %d", rec.Code)
	}
	if done.File.Level != 2 || !strings.HasPrefix(done.File.Mime, "text/") {
		t.Errorf("file: %+v", done.File)
	}
	rec = r.do(http.MethodPost, "/files/"+done.File.Id+"/link", nil, true)
	var link dto.FileLinkResponse
	_ = proto.Unmarshal(rec.Body.Bytes(), &link)
	got := r.do(http.MethodGet, link.Url, nil, false, "Range", "bytes=0-10")
	if got.Code != http.StatusPartialContent || got.Body.String() != string(data[:11]) {
		t.Errorf("range download: %d %q", got.Code, got.Body.String())
	}
	if !strings.HasPrefix(got.Header().Get("Content-Disposition"), "attachment") {
		t.Errorf("a document must download, not open: %q", got.Header().Get("Content-Disposition"))
	}
}
