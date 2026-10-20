package route

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newPublicDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html>spa</html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "app.js"), []byte("console.log(1)"), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func get(h http.Handler, target string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, target, nil))
	return rec
}

func TestSPAHandler_ServesExistingFile(t *testing.T) {
	rec := get(spaHandler(newPublicDir(t)), "/assets/app.js")
	if rec.Code != http.StatusOK || rec.Body.String() != "console.log(1)" {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}

func TestSPAHandler_WebRoutesServeIndex(t *testing.T) {
	h := spaHandler(newPublicDir(t))
	for _, target := range []string{"/", "/login", "/login/", "/notes/123", "/notes/7c1e-aa/"} {
		rec := get(h, target)
		if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "spa") {
			t.Errorf("%s: got %d %q", target, rec.Code, rec.Body.String())
		}
		if rec.Header().Get("Cache-Control") != "no-cache" {
			t.Errorf("%s: index must not be cached", target)
		}
	}
}

func TestSPAHandler_UnknownPathsAreNotFound(t *testing.T) {
	h := spaHandler(newPublicDir(t))
	targets := []string{
		"/api/auth/login/", "/auth/nope/", "/auth", "/sync/bulk/", "/health", "/swagger/index.html",
		"/rota-aleatoria", "/authors", "/loginx", "/notes", "/notes/", "/notes/1/edit", "/assets/", "/assets/missing.js",
	}
	for _, target := range targets {
		if rec := get(h, target); rec.Code != http.StatusNotFound {
			t.Errorf("%s: got %d, want 404", target, rec.Code)
		}
	}
}

func TestSPAHandler_HeadRequest(t *testing.T) {
	h := spaHandler(newPublicDir(t))
	for _, target := range []string{"/login", "/assets/app.js"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodHead, target, nil))
		if rec.Code != http.StatusOK || rec.Body.Len() != 0 {
			t.Errorf("HEAD %s: got %d with %d body bytes", target, rec.Code, rec.Body.Len())
		}
	}
}

func TestIsWebRoute(t *testing.T) {
	cases := map[string]bool{
		"/": true, "/login": true, "/notes/abc": true,
		"/notes": false, "/notes/": false, "/notes/a/b": false, "/auth/login/": false, "": false,
	}
	for p, want := range cases {
		if got := isWebRoute(p); got != want {
			t.Errorf("isWebRoute(%q) = %v, want %v", p, got, want)
		}
	}
}

func TestSPAHandler_CannotEscapePublicDir(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "secret.txt"), []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	pub := filepath.Join(root, "public")
	if err := os.Mkdir(pub, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pub, "index.html"), []byte("spa"), 0o644); err != nil {
		t.Fatal(err)
	}
	rec := get(spaHandler(pub), "/../secret.txt")
	if strings.Contains(rec.Body.String(), "secret") {
		t.Fatal("served a file outside the public dir")
	}
}

func TestSPAHandler_WithoutBuild(t *testing.T) {
	h := spaHandler(t.TempDir())
	if rec := get(h, "/"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Plany API is running") {
		t.Errorf("/: got %d %q", rec.Code, rec.Body.String())
	}
	if rec := get(h, "/notes"); rec.Code != http.StatusNotFound {
		t.Errorf("/notes: got %d, want 404", rec.Code)
	}
}
