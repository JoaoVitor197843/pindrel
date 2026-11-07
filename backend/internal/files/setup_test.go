package files_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/auth"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"pindrel/internal/database/db"
	"pindrel/internal/files"
	contextkeys "pindrel/pkg/context"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"google.golang.org/protobuf/proto"
)

type env struct {
	t       *testing.T
	pool    *pgxpool.Pool
	q       *db.Queries
	svc     *files.Service
	store   *files.Store
	dir     string
	router  http.Handler
	cfg     files.Config
	secret  []byte
	nowFunc *time.Time
}

// newEnv builds the real service on the real database, with a temporary directory and small limits.
func newEnv(t *testing.T, mod func(*files.Config)) *env {
	t.Helper()
	_ = godotenv.Load("../../.env")
	conf, err := config.Load()
	if err != nil {
		t.Fatalf("configuration: %v", err)
	}
	// a small pool on purpose: a request that held a connection while asking for a second would deadlock the concurrent
	// tests, and a CI that runs packages in parallel has few connections to share
	conf.Database.MaxConns = 3
	pool, err := database.NewConnection(context.Background(), conf.Database)
	if err != nil {
		t.Fatalf("database: %v", err)
	}
	t.Cleanup(pool.Close)
	dir := t.TempDir()
	store, err := files.NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	cfg := files.Config{
		Dir: dir, MaxFileBytes: 8 << 20, QuotaBytes: 16 << 20, MinFreeBytes: 0, MaxOpenUploads: 4,
		UploadTTL: time.Hour, OrphanGrace: 7 * 24 * time.Hour, LinkTTL: 10 * time.Minute, Secret: []byte("segredo-de-teste"),
	}
	if mod != nil {
		mod(&cfg)
	}
	q := db.New(pool)
	svc := files.NewService(pool, q, store, cfg)
	h := files.NewHandler(svc)
	r := chi.NewRouter()
	// the tests stand in for the session: the user id comes in a header, the way the auth middleware would put it
	r.Group(func(r chi.Router) {
		r.Use(func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				id, err := uuid.Parse(req.Header.Get("X-Test-User"))
				if err != nil {
					http.Error(w, "no user", http.StatusUnauthorized)
					return
				}
				next.ServeHTTP(w, req.WithContext(context.WithValue(req.Context(), contextkeys.UserIDKey, id)))
			})
		})
		r.Get("/files/", h.List)
		r.Post("/files/uploads/", h.CreateUpload)
		r.Get("/files/uploads/{id}", h.UploadStatus)
		r.Put("/files/uploads/{id}/{n}", h.PutChunk)
		r.Post("/files/uploads/{id}/finish", h.Finish)
		r.Delete("/files/uploads/{id}", h.CancelUpload)
		r.Post("/files/{id}/link", h.Link)
		r.Put("/files/{id}/orphan", h.SetOrphan(true))
		r.Delete("/files/{id}/orphan", h.SetOrphan(false))
		r.Delete("/files/{id}", h.Delete)
	})
	r.Get("/files/{id}", h.Download)
	r.Head("/files/{id}", h.Download)
	return &env{t: t, pool: pool, q: q, svc: svc, store: store, dir: dir, router: r, cfg: cfg, secret: cfg.Secret}
}

func (e *env) user() uuid.UUID {
	e.t.Helper()
	hash, err := auth.HashPassword("senha_valida_123")
	if err != nil {
		e.t.Fatal(err)
	}
	u, err := e.q.CreateUser(context.Background(), db.CreateUserParams{Email: "files-" + uuid.NewString() + "@test.com", PasswordHash: hash})
	if err != nil {
		e.t.Fatal(err)
	}
	e.t.Cleanup(func() { _ = e.q.DeleteUser(context.Background(), u.ID) })
	return u.ID
}

func (e *env) do(user uuid.UUID, method, path string, body io.Reader, headers ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, body)
	if user != uuid.Nil {
		req.Header.Set("X-Test-User", user.String())
	}
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	e.router.ServeHTTP(rec, req)
	return rec
}

func protoBody(m proto.Message) io.Reader {
	b, _ := proto.Marshal(m)
	return bytes.NewReader(b)
}

func (e *env) create(user uuid.UUID, size int64, name string, encrypted bool) (*dto.CreateUploadResponse, *httptest.ResponseRecorder) {
	rec := e.do(user, http.MethodPost, "/files/uploads/", protoBody(&dto.CreateUploadRequest{Size: size, Name: name, Encrypted: encrypted}))
	if rec.Code != http.StatusCreated {
		return nil, rec
	}
	var out dto.CreateUploadResponse
	if err := proto.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return &out, rec
}

func hexSum(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }

func (e *env) put(user uuid.UUID, uploadID string, n int, piece []byte) *httptest.ResponseRecorder {
	return e.do(user, http.MethodPut, "/files/uploads/"+uploadID+"/"+strconv.Itoa(n), bytes.NewReader(piece), "X-Chunk-Sha256", hexSum(piece), "Content-Type", "application/octet-stream")
}

func (e *env) finish(user uuid.UUID, uploadID string) (*dto.FileInfo, *httptest.ResponseRecorder) {
	rec := e.do(user, http.MethodPost, "/files/uploads/"+uploadID+"/finish", nil)
	if rec.Code != http.StatusCreated {
		return nil, rec
	}
	var out dto.FinishUploadResponse
	if err := proto.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return out.File, rec
}

// upload runs the whole flow: open, send every piece, finish.
func (e *env) upload(user uuid.UUID, data []byte, name string) *dto.FileInfo {
	e.t.Helper()
	up, rec := e.create(user, int64(len(data)), name, false)
	if up == nil {
		e.t.Fatalf("create: %d %s", rec.Code, rec.Body.String())
	}
	for n := 0; n < int(up.ChunkCount); n++ {
		lo := n * int(up.ChunkSize)
		hi := min(lo+int(up.ChunkSize), len(data))
		if rec := e.put(user, up.UploadId, n, data[lo:hi]); rec.Code != http.StatusNoContent {
			e.t.Fatalf("piece %d: %d %s", n, rec.Code, rec.Body.String())
		}
	}
	f, rec := e.finish(user, up.UploadId)
	if f == nil {
		e.t.Fatalf("finish: %d %s", rec.Code, rec.Body.String())
	}
	return f
}

func (e *env) link(user uuid.UUID, id string) string {
	e.t.Helper()
	rec := e.do(user, http.MethodPost, "/files/"+id+"/link", nil)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("link: %d %s", rec.Code, rec.Body.String())
	}
	var out dto.FileLinkResponse
	if err := proto.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return out.Url
}

func errCode(rec *httptest.ResponseRecorder) string {
	var out dto.ErrorHttp
	_ = proto.Unmarshal(rec.Body.Bytes(), &out)
	return out.Code
}

// blobs counts the finished files on disk.
func (e *env) blobs() int {
	e.t.Helper()
	n := 0
	_ = filepath.WalkDir(filepath.Join(e.dir, "blobs"), func(_ string, d os.DirEntry, _ error) error {
		if d != nil && !d.IsDir() {
			n++
		}
		return nil
	})
	return n
}

func walkFiles(root string, fn func(path string)) error {
	return filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			fn(p)
		}
		return err
	})
}
