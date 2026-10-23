package route

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"plany/internal/auth"
	"plany/internal/config"
	AuthMiddleware "plany/internal/middleware"
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

func TestSPAHandler_NonGetMethodsAreNotFound(t *testing.T) {
	h := spaHandler(newPublicDir(t))
	for _, method := range allMethods {
		for _, target := range []string{"/", "/login", "/notes/1", "/assets/app.js"} {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(method, target, nil))
			want := http.StatusNotFound
			if method == http.MethodGet || method == http.MethodHead {
				want = http.StatusOK
			}
			if rec.Code != want {
				t.Errorf("%s %s: got %d, want %d", method, target, rec.Code, want)
			}
		}
	}
}

var allMethods = []string{
	http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut, http.MethodPatch,
	http.MethodDelete, http.MethodConnect, http.MethodOptions, http.MethodTrace,
}

// TestRouter_UnknownPathStatusByMethod: unknown paths are 404 for every method, while a known
// path used with the wrong method stays 405.
func TestRouter_UnknownPathStatusByMethod(t *testing.T) {
	r := SetupRouter(&config.Config{}, nil, &auth.Handler{},
		AuthMiddleware.NewIPRateLimiter(1, 1), AuthMiddleware.NewIPRateLimiter(1, 1))

	do := func(method, target string) int {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(method, target, nil))
		return rec.Code
	}

	for _, method := range allMethods {
		for _, target := range []string{"/auth/lo/", "/random", "/api/auth/login/"} {
			if got := do(method, target); got != http.StatusNotFound {
				t.Errorf("%s %s: got %d, want 404", method, target, got)
			}
		}
	}

	// /auth/me/ only accepts GET (HEAD and OPTIONS are not registered for it either)
	for _, method := range allMethods {
		if method == http.MethodGet {
			continue
		}
		if got := do(method, "/auth/me/"); got != http.StatusMethodNotAllowed {
			t.Errorf("%s /auth/me/: got %d, want 405", method, got)
		}
	}
	// /auth/login/ only accepts POST
	for _, method := range allMethods {
		if method == http.MethodPost {
			continue
		}
		if got := do(method, "/auth/login/"); got != http.StatusMethodNotAllowed {
			t.Errorf("%s /auth/login/: got %d, want 405", method, got)
		}
	}
}

// With InAppRateLimit on the login route is limited per instance; with it off (load balancer
// does the limiting) the API keeps no counters and never answers 429 itself.
func TestRouter_InAppRateLimitToggle(t *testing.T) {
	statuses := func(inApp bool) []int {
		r := SetupRouter(&config.Config{InAppRateLimit: inApp}, nil, &auth.Handler{},
			AuthMiddleware.NewIPRateLimiter(0, 1), AuthMiddleware.NewIPRateLimiter(0, 1))
		var out []int
		for range 3 {
			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/auth/login/", nil))
			out = append(out, rec.Code)
		}
		return out
	}
	if got := statuses(true); got[1] != http.StatusTooManyRequests || got[2] != http.StatusTooManyRequests {
		t.Errorf("limit on: got %v, want 429 after the burst", got)
	}
	for _, c := range statuses(false) {
		if c == http.StatusTooManyRequests {
			t.Errorf("limit off: unexpected 429")
		}
	}
}
