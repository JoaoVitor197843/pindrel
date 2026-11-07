package files_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"mime"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/database/db"
	"pindrel/internal/files"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
)

// content makes `size` bytes that start like the given format and then vary, so no two pieces are equal.
func content(t *testing.T, kind string, size int) []byte {
	t.Helper()
	head := files.Sample(t, kind)
	if size < len(head) {
		return head
	}
	out := make([]byte, size)
	copy(out, head)
	for i := len(head); i < size; i++ {
		out[i] = byte(i*31 + i>>8)
	}
	return out
}

func fetch(e *env, method, url string, headers ...string) *httptest.ResponseRecorder {
	return e.do(uuid.Nil, method, url, nil, headers...)
}

func TestDB_FullFlow_UploadFinishListDownload(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "png", 1_300_000) // three pieces: 512 KiB, 512 KiB, the rest
	f := e.upload(u, data, "foto.png")
	if f.Mime != "image/png" || f.Level != 1 || f.Size != int64(len(data)) || f.Name != "foto.png" || f.Encrypted {
		t.Fatalf("file info: %+v", f)
	}
	url := e.link(u, f.Id)
	rec := fetch(e, http.MethodGet, url)
	if rec.Code != http.StatusOK || !bytes.Equal(rec.Body.Bytes(), data) {
		t.Fatalf("download: %d, %d bytes", rec.Code, rec.Body.Len())
	}
	h := rec.Header()
	if h.Get("Content-Type") != "image/png" || !strings.HasPrefix(h.Get("Content-Disposition"), "inline") || h.Get("X-Content-Type-Options") != "nosniff" || h.Get("Accept-Ranges") != "bytes" || h.Get("ETag") == "" {
		t.Errorf("headers: %v", h)
	}
	if h.Get("Content-Security-Policy") != "sandbox; default-src 'none'" || h.Get("Cross-Origin-Resource-Policy") != "same-origin" {
		t.Errorf("security headers: %v", h)
	}
	// the list shows it, and the quota counts it
	rec = e.do(u, http.MethodGet, "/files/", nil)
	var list dto.ListFilesResponse
	_ = proto.Unmarshal(rec.Body.Bytes(), &list)
	if len(list.Files) != 1 || list.Files[0].Id != f.Id || list.UsedBytes != int64(len(data)) || list.QuotaBytes != e.cfg.QuotaBytes {
		t.Errorf("list: %+v", &list)
	}
	// the disk holds the pieces no more
	if entries, _ := os.ReadDir(e.dir + "/uploads"); len(entries) != 0 {
		t.Errorf("%d upload directories left after finishing", len(entries))
	}
}

func TestDB_Download_RangeConditionalAndHead(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "mp4", 700_000)
	f := e.upload(u, data, "aula.mp4")
	url := e.link(u, f.Id)
	cases := []struct {
		name, rng string
		code      int
		body      []byte
	}{
		{"first bytes", "bytes=0-9", http.StatusPartialContent, data[:10]},
		{"middle across a piece", "bytes=524280-524300", http.StatusPartialContent, data[524280:524301]},
		{"open ended", "bytes=699990-", http.StatusPartialContent, data[699990:]},
		{"suffix", "bytes=-5", http.StatusPartialContent, data[len(data)-5:]},
		{"past the end", "bytes=700000-700010", http.StatusRequestedRangeNotSatisfiable, nil},
		{"garbage", "bytes=abc", http.StatusRequestedRangeNotSatisfiable, nil},
		{"huge end is clamped", "bytes=0-99999999999", http.StatusPartialContent, data},
	}
	for _, c := range cases {
		rec := fetch(e, http.MethodGet, url, "Range", c.rng)
		if rec.Code != c.code {
			t.Errorf("%s: %d, want %d", c.name, rec.Code, c.code)
			continue
		}
		if c.body != nil && !bytes.Equal(rec.Body.Bytes(), c.body) {
			t.Errorf("%s: wrong bytes (%d)", c.name, rec.Body.Len())
		}
	}
	// many ranges are answered, never an amplification beyond the file
	rec := fetch(e, http.MethodGet, url, "Range", "bytes=0-1,5-6,9-10")
	if rec.Body.Len() > 4*len(data) {
		t.Errorf("multi-range answer of %d bytes", rec.Body.Len())
	}
	tag := fetch(e, http.MethodGet, url).Header().Get("ETag")
	if rec := fetch(e, http.MethodGet, url, "If-None-Match", tag); rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
		t.Errorf("conditional: %d", rec.Code)
	}
	if rec := fetch(e, http.MethodHead, url); rec.Code != http.StatusOK || rec.Body.Len() != 0 || rec.Header().Get("Content-Length") != fmt.Sprint(len(data)) {
		t.Errorf("head: %d len=%q", rec.Code, rec.Header().Get("Content-Length"))
	}
}

func TestDB_EachLevelIsHandedOutTheRightWay(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	cases := []struct {
		kind, name string
		level      int32
		inline     bool
		wantType   string
	}{
		{"png", "a.png", 1, true, "image/png"},
		{"pdf", "manual.pdf", 1, true, "application/pdf"},
		{"docx", "carta.docx", 2, false, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
		{"zip", "fotos.zip", 2, false, "application/zip"},
		{"text", "notas.txt", 2, false, "text/plain"},
		{"html", "pagina.png", 3, false, "application/octet-stream"}, // the name says picture, the bytes say HTML
		{"svg", "desenho.svg", 3, false, "application/octet-stream"},
		{"exe", "programa.pdf", 3, false, "application/octet-stream"},
	}
	for _, c := range cases {
		size := 5000
		if c.kind == "text" {
			size = 1 // text is sent as it is, with nothing binary after it
		}
		f := e.upload(u, content(t, c.kind, size), c.name)
		if f.Level != c.level {
			t.Errorf("%s: level %d, want %d (mime %s)", c.kind, f.Level, c.level, f.Mime)
		}
		rec := fetch(e, http.MethodGet, e.link(u, f.Id))
		disp, _, _ := mime.ParseMediaType(rec.Header().Get("Content-Disposition"))
		if (disp == "inline") != c.inline {
			t.Errorf("%s: disposition %q", c.kind, rec.Header().Get("Content-Disposition"))
		}
		if ct := rec.Header().Get("Content-Type"); ct != c.wantType {
			t.Errorf("%s: content type %q, want %q", c.kind, ct, c.wantType)
		}
		if !c.inline && !strings.Contains(rec.Header().Get("Content-Security-Policy"), "sandbox") {
			t.Errorf("%s: a download must carry the sandbox policy", c.kind)
		}
	}
}

func TestDB_VaultFilesAreOpaqueAndNeverInline(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	// the bytes of a PNG, but declared encrypted: the server must not look inside nor open it
	data := content(t, "png", 3000)
	up, rec := e.create(u, int64(len(data)), "segredo.png", true)
	if up == nil {
		t.Fatalf("create: %d", rec.Code)
	}
	if r := e.put(u, up.UploadId, 0, data); r.Code != http.StatusNoContent {
		t.Fatal(r.Code)
	}
	f, rec := e.finish(u, up.UploadId)
	if f == nil || !f.Encrypted || f.Level != 3 || f.Mime != "application/octet-stream" {
		t.Fatalf("encrypted file: %+v (%d)", f, rec.Code)
	}
	got := fetch(e, http.MethodGet, e.link(u, f.Id))
	if got.Header().Get("Content-Type") != "application/octet-stream" || !strings.HasPrefix(got.Header().Get("Content-Disposition"), "attachment") {
		t.Errorf("headers: %v", got.Header())
	}
}

func TestDB_HostileNamesNeverReachAPathOrABrokenHeader(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	for _, name := range []string{"../../etc/passwd", "a\r\nSet-Cookie: x=1", `"quoted".txt`, "relatório ç.txt", strings.Repeat("x", 4000)[:1000], "\x00\x01", ""} {
		up, rec := e.create(u, 10, name, false)
		if up == nil && len(name) > 1024 {
			continue
		}
		if up == nil {
			t.Fatalf("name %q: %d", name, rec.Code)
		}
		e.put(u, up.UploadId, 0, []byte("0123456789"))
		f, _ := e.finish(u, up.UploadId)
		if f == nil {
			t.Fatalf("name %q: finish", name)
		}
		got := fetch(e, http.MethodGet, e.link(u, f.Id))
		for k, v := range got.Header() {
			for _, s := range v {
				if strings.ContainsAny(s, "\r\n") {
					t.Errorf("name %q put a line break in %s", name, k)
				}
			}
		}
		if got.Header().Get("Set-Cookie") != "" {
			t.Errorf("name %q injected a header", name)
		}
		if strings.Contains(f.Name, "/") || strings.Contains(f.Name, "\\") {
			t.Errorf("name %q kept a separator: %q", name, f.Name)
		}
	}
	// nothing was written outside the files directory
	if _, err := os.Stat("/tmp/etc/passwd"); err == nil {
		t.Error("a path in a name was followed")
	}
}

func TestDB_ChunkValidation(t *testing.T) {
	e := newEnv(t, nil)
	u, other := e.user(), e.user()
	size := int64(files.ChunkSize + 100)
	up, _ := e.create(u, size, "x", false)
	good0 := bytes.Repeat([]byte{1}, files.ChunkSize)
	good1 := bytes.Repeat([]byte{2}, 100)
	id := up.UploadId

	check := func(name string, rec *httptest.ResponseRecorder, code int, errc string) {
		t.Helper()
		if rec.Code != code || (errc != "" && errCode(rec) != errc) {
			t.Errorf("%s: %d %q, want %d %q", name, rec.Code, errCode(rec), code, errc)
		}
	}
	check("wrong hash", e.do(u, http.MethodPut, "/files/uploads/"+id+"/0", bytes.NewReader(good0), "X-Chunk-Sha256", hexSum([]byte("outra"))), http.StatusUnprocessableEntity, "chunk_hash_mismatch")
	check("no hash header", e.do(u, http.MethodPut, "/files/uploads/"+id+"/0", bytes.NewReader(good0)), http.StatusBadRequest, "invalid_input")
	check("hash not hex", e.do(u, http.MethodPut, "/files/uploads/"+id+"/0", bytes.NewReader(good0), "X-Chunk-Sha256", "zz"), http.StatusBadRequest, "invalid_input")
	check("short first piece", e.put(u, id, 0, good0[:1000]), http.StatusBadRequest, "bad_chunk_size")
	check("long last piece", e.put(u, id, 1, bytes.Repeat([]byte{2}, 101)), http.StatusBadRequest, "bad_chunk_size")
	check("past the end", e.put(u, id, 2, good1), http.StatusBadRequest, "chunk_out_of_range")
	check("negative", e.do(u, http.MethodPut, "/files/uploads/"+id+"/-1", bytes.NewReader(good1), "X-Chunk-Sha256", hexSum(good1)), http.StatusBadRequest, "chunk_out_of_range")
	check("not a number", e.do(u, http.MethodPut, "/files/uploads/"+id+"/um", bytes.NewReader(good1), "X-Chunk-Sha256", hexSum(good1)), http.StatusBadRequest, "chunk_out_of_range")
	check("absurd number", e.do(u, http.MethodPut, "/files/uploads/"+id+"/99999999999999999999", bytes.NewReader(good1), "X-Chunk-Sha256", hexSum(good1)), http.StatusBadRequest, "chunk_out_of_range")
	check("a body far over a piece", e.put(u, id, 0, bytes.Repeat([]byte{9}, 3<<20)), http.StatusRequestEntityTooLarge, "payload_too_large")
	check("someone else's upload", e.put(other, id, 0, good0), http.StatusNotFound, "upload_not_found")
	check("an id that is not one", e.do(u, http.MethodPut, "/files/uploads/nada/0", bytes.NewReader(good0), "X-Chunk-Sha256", hexSum(good0)), http.StatusBadRequest, "invalid_input")
	check("an upload that does not exist", e.put(u, uuid.NewString(), 0, good0), http.StatusNotFound, "upload_not_found")
	// the same piece twice, and out of order, is fine
	check("last piece first", e.put(u, id, 1, good1), http.StatusNoContent, "")
	check("piece again", e.put(u, id, 1, good1), http.StatusNoContent, "")
	check("first piece", e.put(u, id, 0, good0), http.StatusNoContent, "")
	// the refused pieces left nothing behind: finishing gives exactly what was sent
	f, rec := e.finish(u, id)
	if f == nil || f.Size != size {
		t.Fatalf("finish: %d", rec.Code)
	}
	got := fetch(e, http.MethodGet, e.link(u, f.Id))
	if !bytes.Equal(got.Body.Bytes(), append(append([]byte{}, good0...), good1...)) {
		t.Error("finished bytes differ from the accepted pieces")
	}
}

func TestDB_StatusAndResume(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "pdf", 3*files.ChunkSize)
	up, _ := e.create(u, int64(len(data)), "x.pdf", false)
	e.put(u, up.UploadId, 2, data[2*files.ChunkSize:])
	e.put(u, up.UploadId, 0, data[:files.ChunkSize])
	rec := e.do(u, http.MethodGet, "/files/uploads/"+up.UploadId, nil)
	var st dto.UploadStatus
	_ = proto.Unmarshal(rec.Body.Bytes(), &st)
	if st.ChunkCount != 3 || len(st.Received) != 1 || st.Received[0] != 0b101 {
		t.Fatalf("status: %+v", &st)
	}
	// finishing too early gives the upload back so the missing piece can be sent
	if f, rec := e.finish(u, up.UploadId); f != nil || errCode(rec) != "upload_incomplete" {
		t.Fatalf("early finish: %d %q", rec.Code, errCode(rec))
	}
	if r := e.put(u, up.UploadId, 1, data[files.ChunkSize:2*files.ChunkSize]); r.Code != http.StatusNoContent {
		t.Fatalf("put after a failed finish: %d %q", r.Code, errCode(r))
	}
	if f, rec := e.finish(u, up.UploadId); f == nil {
		t.Fatalf("finish: %d %q", rec.Code, errCode(rec))
	}
}

func TestDB_FinishByManyRequestsAtOnceHasOneWinner(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "png", 2*files.ChunkSize+5)
	up, _ := e.create(u, int64(len(data)), "x.png", false)
	for n := 0; n < int(up.ChunkCount); n++ {
		e.put(u, up.UploadId, n, data[n*files.ChunkSize:min((n+1)*files.ChunkSize, len(data))])
	}
	var wins, losses atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if f, _ := e.finish(u, up.UploadId); f != nil {
				wins.Add(1)
			} else {
				losses.Add(1)
			}
		}()
	}
	wg.Wait()
	if wins.Load() != 1 || losses.Load() != 11 {
		t.Fatalf("%d winners, %d losers", wins.Load(), losses.Load())
	}
	var n int
	_ = e.pool.QueryRow(context.Background(), "SELECT count(*) FROM files WHERE user_id = $1", u).Scan(&n)
	if n != 1 || e.blobs() != 1 {
		t.Errorf("%d rows, %d blobs after twelve finishes", n, e.blobs())
	}
}

func TestDB_PiecesSentAllAtOnceFromManyGoroutines(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "mp4", 6<<20) // twelve pieces
	up, _ := e.create(u, int64(len(data)), "grande.mp4", false)
	var wg sync.WaitGroup
	var bad atomic.Int32
	for n := 0; n < int(up.ChunkCount); n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if rec := e.put(u, up.UploadId, n, data[n*files.ChunkSize:min((n+1)*files.ChunkSize, len(data))]); rec.Code != http.StatusNoContent {
				bad.Add(1)
			}
		}()
	}
	wg.Wait()
	if bad.Load() != 0 {
		t.Fatalf("%d pieces failed", bad.Load())
	}
	f, rec := e.finish(u, up.UploadId)
	if f == nil {
		t.Fatalf("finish: %d %q", rec.Code, errCode(rec))
	}
	want := sha256.Sum256(data)
	got := sha256.Sum256(fetch(e, http.MethodGet, e.link(u, f.Id)).Body.Bytes())
	if want != got {
		t.Error("bitmap lost a bit or the join mixed pieces")
	}
}

func TestDB_Limits(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.MaxFileBytes = 3 << 20; c.QuotaBytes = 5 << 20; c.MaxOpenUploads = 3 })
	u := e.user()
	for name, tc := range map[string]struct {
		size int64
		code int
		err  string
	}{
		"zero":     {0, http.StatusBadRequest, "invalid_input"},
		"negative": {-5, http.StatusBadRequest, "invalid_input"},
		"too big":  {3<<20 + 1, http.StatusRequestEntityTooLarge, "file_too_large"},
		"huge":     {1 << 62, http.StatusRequestEntityTooLarge, "file_too_large"},
	} {
		_, rec := e.create(u, tc.size, "x", false)
		if rec.Code != tc.code || errCode(rec) != tc.err {
			t.Errorf("%s: %d %q", name, rec.Code, errCode(rec))
		}
	}
	// 3 MiB + 2 MiB fill the 5 MiB quota; one byte more does not fit
	if up, rec := e.create(u, 3<<20, "a", false); up == nil {
		t.Fatal(rec.Code)
	}
	if up, rec := e.create(u, 2<<20, "b", false); up == nil {
		t.Fatal(rec.Code)
	}
	if _, rec := e.create(u, 1, "c", false); rec.Code != http.StatusRequestEntityTooLarge || errCode(rec) != "quota_exceeded" {
		t.Errorf("quota: %d %q", rec.Code, errCode(rec))
	}
}

func TestDB_TooManyOpenUploads(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.MaxOpenUploads = 2 })
	u := e.user()
	for i := 0; i < 2; i++ {
		if up, rec := e.create(u, 10, "x", false); up == nil {
			t.Fatal(rec.Code)
		}
	}
	if _, rec := e.create(u, 10, "x", false); rec.Code != http.StatusTooManyRequests || errCode(rec) != "too_many_uploads" {
		t.Errorf("%d %q", rec.Code, errCode(rec))
	}
	// another person is not affected
	if up, rec := e.create(e.user(), 10, "x", false); up == nil {
		t.Errorf("a second person is blocked: %d", rec.Code)
	}
}

func TestDB_QuotaHoldsWhenManyUploadsStartTogether(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.QuotaBytes = 5 << 20; c.MaxOpenUploads = 50 })
	u := e.user()
	var ok atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if up, _ := e.create(u, 2<<20, "x", false); up != nil {
				ok.Add(1)
			}
		}()
	}
	wg.Wait()
	if ok.Load() != 2 {
		t.Fatalf("%d uploads of 2 MiB fit in a 5 MiB quota, want exactly 2", ok.Load())
	}
	used, _ := e.q.QuotaUsed(context.Background(), u)
	if used > e.cfg.QuotaBytes {
		t.Errorf("%d bytes promised over a quota of %d", used, e.cfg.QuotaBytes)
	}
}

func TestDB_ServerOutOfSpaceRefusesNewUploads(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.MinFreeBytes = 1 << 60 })
	if _, rec := e.create(e.user(), 10, "x", false); rec.Code != http.StatusInsufficientStorage || errCode(rec) != "storage_full" {
		t.Errorf("%d %q", rec.Code, errCode(rec))
	}
}

func TestDB_EqualContentSharesTheBytesAndTheLastDeleteFreesThem(t *testing.T) {
	e := newEnv(t, nil)
	a, b := e.user(), e.user()
	data := content(t, "pdf", 40_000)
	fa := e.upload(a, data, "a.pdf")
	fa2 := e.upload(a, data, "copia.pdf")
	fb := e.upload(b, data, "b.pdf")
	if e.blobs() != 1 {
		t.Fatalf("%d blobs for equal content", e.blobs())
	}
	// one person cannot delete, link or read another's file
	if rec := e.do(b, http.MethodDelete, "/files/"+fa.Id, nil); rec.Code != http.StatusNotFound {
		t.Errorf("delete of someone else's file: %d", rec.Code)
	}
	if rec := e.do(b, http.MethodPost, "/files/"+fa.Id+"/link", nil); rec.Code != http.StatusNotFound || errCode(rec) != "file_not_found" {
		t.Errorf("link to someone else's file: %d %q", rec.Code, errCode(rec))
	}
	for _, id := range []string{fa.Id, fa2.Id} {
		if rec := e.do(a, http.MethodDelete, "/files/"+id, nil); rec.Code != http.StatusNoContent {
			t.Fatalf("delete: %d", rec.Code)
		}
	}
	if e.blobs() != 1 {
		t.Error("the bytes went away while another person still has the file")
	}
	if got := fetch(e, http.MethodGet, e.link(b, fb.Id)); !bytes.Equal(got.Body.Bytes(), data) {
		t.Error("the other person's file is damaged")
	}
	if rec := e.do(b, http.MethodDelete, "/files/"+fb.Id, nil); rec.Code != http.StatusNoContent {
		t.Fatal(rec.Code)
	}
	if e.blobs() != 0 {
		t.Errorf("%d blobs left after the last delete", e.blobs())
	}
	if rec := e.do(b, http.MethodDelete, "/files/"+fb.Id, nil); rec.Code != http.StatusNotFound {
		t.Errorf("deleting twice: %d", rec.Code)
	}
}

func TestDB_DeleteRacingAFinishOfTheSameContentNeverLosesTheBytes(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	data := content(t, "pdf", 30_000)
	first := e.upload(u, data, "um.pdf")
	for round := 0; round < 25; round++ {
		up, _ := e.create(u, int64(len(data)), "dois.pdf", false)
		e.put(u, up.UploadId, 0, data)
		var wg sync.WaitGroup
		var second *dto.FileInfo
		wg.Add(2)
		go func() { defer wg.Done(); e.do(u, http.MethodDelete, "/files/"+first.Id, nil) }()
		go func() { defer wg.Done(); second, _ = e.finish(u, up.UploadId) }()
		wg.Wait()
		if second == nil {
			t.Fatal("finish failed")
		}
		got := fetch(e, http.MethodGet, e.link(u, second.Id))
		if got.Code != http.StatusOK || !bytes.Equal(got.Body.Bytes(), data) {
			t.Fatalf("round %d: the file has no bytes (%d)", round, got.Code)
		}
		first = second
	}
}

func TestDB_DownloadAddressRules(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	f1 := e.upload(u, content(t, "png", 2000), "a.png")
	f2 := e.upload(u, content(t, "png", 3000), "b.png")
	url1 := e.link(u, f1.Id)
	cut := func(s, sep string) string { return strings.SplitN(s, sep, 2)[1] }
	sig1 := cut(url1, "sig=")
	for name, rec := range map[string]*httptest.ResponseRecorder{
		"no query":                  fetch(e, http.MethodGet, "/files/"+f1.Id),
		"no signature":              fetch(e, http.MethodGet, strings.Split(url1, "&sig=")[0]),
		"wrong signature":           fetch(e, http.MethodGet, strings.Replace(url1, sig1, strings.Repeat("0", 64), 1)),
		"signature of another file": fetch(e, http.MethodGet, "/files/"+f2.Id+"?"+cut(url1, "?")),
		"later expiry":              fetch(e, http.MethodGet, strings.Replace(url1, "exp=", "exp=9", 1)),
		"expiry not a number":       fetch(e, http.MethodGet, "/files/"+f1.Id+"?exp=x&sig="+sig1),
		"long signature":            fetch(e, http.MethodGet, url1+strings.Repeat("a", 10000)),
	} {
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s: %d, want 403", name, rec.Code)
		}
	}
	if rec := fetch(e, http.MethodGet, "/files/not-an-id?exp=1&sig=00"); rec.Code != http.StatusBadRequest {
		t.Errorf("bad id: %d", rec.Code)
	}
	// an address for a file that was deleted in the meantime
	e.do(u, http.MethodDelete, "/files/"+f1.Id, nil)
	if rec := fetch(e, http.MethodGet, url1); rec.Code != http.StatusNotFound {
		t.Errorf("deleted file: %d", rec.Code)
	}
}

func TestDB_ExpiredAddressStopsWorking(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.LinkTTL = time.Second })
	u := e.user()
	f := e.upload(u, content(t, "png", 2000), "a.png")
	url := e.link(u, f.Id)
	if rec := fetch(e, http.MethodGet, url); rec.Code != http.StatusOK {
		t.Fatalf("fresh: %d", rec.Code)
	}
	time.Sleep(2200 * time.Millisecond)
	if rec := fetch(e, http.MethodGet, url); rec.Code != http.StatusForbidden {
		t.Errorf("expired: %d", rec.Code)
	}
}

func TestDB_CancelRemovesThePiecesAndTheRow(t *testing.T) {
	e := newEnv(t, nil)
	u, other := e.user(), e.user()
	up, _ := e.create(u, 2*files.ChunkSize, "x", false)
	e.put(u, up.UploadId, 0, bytes.Repeat([]byte{1}, files.ChunkSize))
	if rec := e.do(other, http.MethodDelete, "/files/uploads/"+up.UploadId, nil); rec.Code != http.StatusNotFound {
		t.Errorf("cancelling someone else's upload: %d", rec.Code)
	}
	if rec := e.do(u, http.MethodDelete, "/files/uploads/"+up.UploadId, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("cancel: %d", rec.Code)
	}
	if entries, _ := os.ReadDir(e.dir + "/uploads"); len(entries) != 0 {
		t.Errorf("%d upload dirs left", len(entries))
	}
	if rec := e.do(u, http.MethodGet, "/files/uploads/"+up.UploadId, nil); rec.Code != http.StatusNotFound {
		t.Errorf("status of a cancelled upload: %d", rec.Code)
	}
	used, _ := e.q.QuotaUsed(context.Background(), u)
	if used != 0 {
		t.Errorf("quota still holds %d bytes", used)
	}
}

func TestDB_CleanupRemovesExpiredUploadsOrphansAndLeftovers(t *testing.T) {
	e := newEnv(t, func(c *files.Config) { c.OrphanGrace = time.Hour })
	u := e.user()
	ctx := context.Background()

	// an upload nobody finished
	stale, _ := e.create(u, files.ChunkSize+1, "x", false)
	e.put(u, stale.UploadId, 0, bytes.Repeat([]byte{1}, files.ChunkSize))
	_, _ = e.pool.Exec(ctx, "UPDATE uploads SET expires_at = now() - interval '1 minute' WHERE id = $1", stale.UploadId)
	// a file that lost its page long ago, one that lost it a minute ago, and one that was claimed again
	due := e.upload(u, content(t, "png", 1000), "velho.png")
	recent := e.upload(u, content(t, "png", 2000), "novo.png")
	back := e.upload(u, content(t, "png", 3000), "volta.png")
	for _, id := range []string{due.Id, recent.Id, back.Id} {
		if rec := e.do(u, http.MethodPut, "/files/"+id+"/orphan", nil); rec.Code != http.StatusNoContent {
			t.Fatalf("orphan: %d", rec.Code)
		}
	}
	e.do(u, http.MethodDelete, "/files/"+back.Id+"/orphan", nil)
	_, _ = e.pool.Exec(ctx, "UPDATE files SET orphan_since = now() - interval '2 hours' WHERE id = $1", due.Id)
	_, _ = e.pool.Exec(ctx, "UPDATE files SET orphan_since = now() - interval '5 minutes' WHERE id = $1", recent.Id)
	// leftovers of a crash
	oldDir := e.dir + "/uploads/" + uuid.NewString()
	_ = os.MkdirAll(oldDir, 0o700)
	old := time.Now().Add(-72 * time.Hour)
	_ = os.Chtimes(oldDir, old, old)
	oldTmp := e.dir + "/tmp/join-crashed"
	_ = os.WriteFile(oldTmp, []byte("x"), 0o600)
	_ = os.Chtimes(oldTmp, old, old)

	st, err := e.svc.Cleanup(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if st.ExpiredUploads != 1 || st.Orphans != 1 || st.StrayDirs != 1 || st.StrayTmp != 1 {
		t.Errorf("stats: %+v", st)
	}
	if rec := e.do(u, http.MethodPost, "/files/"+due.Id+"/link", nil); rec.Code != http.StatusNotFound {
		t.Errorf("the orphan past its grace is still there: %d", rec.Code)
	}
	for _, id := range []string{recent.Id, back.Id} {
		if rec := e.do(u, http.MethodPost, "/files/"+id+"/link", nil); rec.Code != http.StatusOK {
			t.Errorf("file %s was removed too early: %d", id, rec.Code)
		}
	}
	if e.blobs() != 2 {
		t.Errorf("%d blobs, want 2", e.blobs())
	}
	if _, err := os.Stat(oldDir); err == nil {
		t.Error("the stray upload directory is still there")
	}
	used, _ := e.q.QuotaUsed(ctx, u)
	if used != 2000+3000 {
		t.Errorf("quota %d", used)
	}
	// a second pass finds nothing more
	if st, _ := e.svc.Cleanup(ctx); st != (files.CleanupStats{}) {
		t.Errorf("second pass: %+v", st)
	}
}

func TestDB_CleanupSweepsBytesThatNoFileUsesAfterTheOwnerIsGone(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	f := e.upload(u, content(t, "png", 4000), "x.png")
	_ = f
	// the account goes away: its rows cascade, the bytes stay on disk
	if _, err := e.pool.Exec(context.Background(), "DELETE FROM users WHERE id = $1", u); err != nil {
		t.Fatal(err)
	}
	if e.blobs() != 1 {
		t.Fatal("setup")
	}
	// too fresh: left alone (a file being finished must never be in the way)
	if _, err := e.svc.Cleanup(context.Background()); err != nil {
		t.Fatal(err)
	}
	if e.blobs() != 1 {
		t.Error("a fresh blob was swept")
	}
	// the sweep looks again only once a day, so a new service stands for the next day
	_ = filepathChtimes(e.dir+"/blobs", time.Now().Add(-3*time.Hour))
	e2 := files.NewService(e.pool, e.q, e.store, e.cfg)
	if _, err := e2.Cleanup(context.Background()); err != nil {
		t.Fatal(err)
	}
	if e.blobs() != 0 {
		t.Error("the unused bytes stayed")
	}
}

func filepathChtimes(root string, t time.Time) error {
	return walkFiles(root, func(p string) { _ = os.Chtimes(p, t, t) })
}

func TestDB_DeletingAnAccountDropsItsRows(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	e.upload(u, content(t, "png", 100), "x.png")
	e.create(u, 10, "y", false)
	_, _ = e.pool.Exec(context.Background(), "DELETE FROM users WHERE id = $1", u)
	var n int
	_ = e.pool.QueryRow(context.Background(), "SELECT (SELECT count(*) FROM files WHERE user_id=$1) + (SELECT count(*) FROM uploads WHERE user_id=$1)", u).Scan(&n)
	if n != 0 {
		t.Errorf("%d rows left for a deleted account", n)
	}
}

func TestDB_RequiresASession(t *testing.T) {
	e := newEnv(t, nil)
	for _, route := range [][2]string{{"GET", "/files/"}, {"POST", "/files/uploads/"}, {"PUT", "/files/uploads/x/0"}, {"POST", "/files/x/link"}, {"DELETE", "/files/x"}} {
		if rec := e.do(uuid.Nil, route[0], route[1], nil); rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without a session: %d", route[0], route[1], rec.Code)
		}
	}
}

func TestDB_CreateUploadBodyIsCappedAndMalformedInputIsRefused(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	if rec := e.do(u, http.MethodPost, "/files/uploads/", bytes.NewReader(bytes.Repeat([]byte{0xff}, 1<<20))); rec.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("huge body: %d", rec.Code)
	}
	if rec := e.do(u, http.MethodPost, "/files/uploads/", strings.NewReader("não é protobuf \xff\xff")); rec.Code != http.StatusBadRequest {
		t.Errorf("garbage body: %d", rec.Code)
	}
	if _, rec := e.create(u, 10, strings.Repeat("n", 5000), false); rec.Code != http.StatusBadRequest && rec.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("name of 5000 bytes: %d", rec.Code)
	}
}

func TestDB_ListPagesNewestFirst(t *testing.T) {
	e := newEnv(t, nil)
	u := e.user()
	for i := 0; i < 53; i++ {
		e.upload(u, []byte(fmt.Sprintf("arquivo %d", i)), fmt.Sprintf("f%d.txt", i))
	}
	var seen []string
	url := "/files/"
	for pages := 0; pages < 5; pages++ {
		rec := e.do(u, http.MethodGet, url, nil)
		var list dto.ListFilesResponse
		_ = proto.Unmarshal(rec.Body.Bytes(), &list)
		for _, f := range list.Files {
			seen = append(seen, f.Name)
		}
		if list.NextCursor == "" {
			break
		}
		parts := strings.SplitN(list.NextCursor, ".", 2)
		url = "/files/?after=" + parts[0] + "&after_id=" + parts[1]
	}
	if len(seen) != 53 || seen[0] != "f52.txt" || seen[52] != "f0.txt" {
		t.Fatalf("%d files listed, first %q last %q", len(seen), first(seen), last(seen))
	}
	if rec := e.do(u, http.MethodGet, "/files/?after=abc&after_id=x", nil); rec.Code != http.StatusBadRequest {
		t.Errorf("bad cursor: %d", rec.Code)
	}
	// a person sees only their own
	if rec := e.do(e.user(), http.MethodGet, "/files/", nil); rec.Code != http.StatusOK {
		t.Fatal(rec.Code)
	} else {
		var list dto.ListFilesResponse
		_ = proto.Unmarshal(rec.Body.Bytes(), &list)
		if len(list.Files) != 0 {
			t.Error("another person's files are listed")
		}
	}
}

func first(s []string) string {
	if len(s) == 0 {
		return ""
	}
	return s[0]
}

func last(s []string) string {
	if len(s) == 0 {
		return ""
	}
	return s[len(s)-1]
}

var _ = db.File{}
