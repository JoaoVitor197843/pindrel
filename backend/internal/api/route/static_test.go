package route

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"pindrel/internal/auth"
	"pindrel/internal/config"
	AuthMiddleware "pindrel/internal/middleware"
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
	if rec := get(h, "/"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Pindrel API is running") {
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

// withCompressed puts `.br`/`.gz` siblings (with recognisable bodies) next to the files, as the web build does.
func withCompressed(t *testing.T, dir string) {
	t.Helper()
	for name, body := range map[string]string{
		"assets/app.js.br": "BROTLI-JS", "assets/app.js.gz": "GZIP-JS",
		"index.html.br": "BROTLI-HTML", "index.html.gz": "GZIP-HTML",
	} {
		if err := os.WriteFile(filepath.Join(dir, filepath.FromSlash(name)), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func getWith(h http.Handler, target string, headers map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, target, nil)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestSPAHandler_ServesPrecompressedFiles(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	cases := []struct {
		name, target, accept, wantBody, wantEnc string
	}{
		{"brotli wins when both are accepted", "/assets/app.js", "gzip, deflate, br", "BROTLI-JS", "br"},
		{"gzip when brotli is not accepted", "/assets/app.js", "gzip", "GZIP-JS", "gzip"},
		{"nothing accepted", "/assets/app.js", "", "console.log(1)", ""},
		{"identity only", "/assets/app.js", "identity", "console.log(1)", ""},
		{"brotli refused with q=0", "/assets/app.js", "br;q=0, gzip", "GZIP-JS", "gzip"},
		{"all refused", "/assets/app.js", "br;q=0, gzip; q=0", "console.log(1)", ""},
		{"upper case and spaces", "/assets/app.js", "  BR ; q=1 ", "BROTLI-JS", "br"},
		{"index through a page route", "/login", "br", "BROTLI-HTML", "br"},
		{"index at the root", "/", "gzip", "GZIP-HTML", "gzip"},
		{"a file with no compressed sibling stays plain", "/assets/other.txt", "br, gzip", "plain", ""},
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "other.txt"), []byte("plain"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		rec := getWith(h, c.target, map[string]string{"Accept-Encoding": c.accept})
		if rec.Code != http.StatusOK || rec.Body.String() != c.wantBody {
			t.Errorf("%s: got %d %q, want %q", c.name, rec.Code, rec.Body.String(), c.wantBody)
		}
		if got := rec.Header().Get("Content-Encoding"); got != c.wantEnc {
			t.Errorf("%s: Content-Encoding %q, want %q", c.name, got, c.wantEnc)
		}
		if rec.Header().Get("Vary") != "Accept-Encoding" && c.target != "/assets/other.txt" {
			t.Errorf("%s: Vary must name Accept-Encoding (caches would mix the versions), got %q", c.name, rec.Header().Get("Vary"))
		}
	}
}

func TestSPAHandler_PrecompressedKeepsTheOriginalType(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	if ct := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": "br"}).Header().Get("Content-Type"); !strings.Contains(ct, "javascript") {
		t.Errorf("js served as %q", ct)
	}
	if ct := getWith(h, "/login", map[string]string{"Accept-Encoding": "br"}).Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("html served as %q", ct)
	}
}

func TestSPAHandler_AssetsAreImmutableAndTheIndexIsNot(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	for _, accept := range []string{"", "br"} {
		rec := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": accept})
		if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "immutable") || !strings.Contains(cc, "max-age=31536000") {
			t.Errorf("accept=%q: assets must be cached for good, got %q", accept, cc)
		}
	}
	if cc := getWith(h, "/", map[string]string{"Accept-Encoding": "br"}).Header().Get("Cache-Control"); cc != "no-cache" {
		t.Errorf("index must revalidate, got %q", cc)
	}
	if err := os.WriteFile(filepath.Join(dir, "favicon.svg"), []byte("<svg/>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if cc := get(h, "/favicon.svg").Header().Get("Cache-Control"); strings.Contains(cc, "immutable") {
		t.Errorf("a file outside /assets/ has no hash in its name and must not be immutable, got %q", cc)
	}
}

func TestSPAHandler_RangeRequestsGetThePlainFile(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	rec := getWith(spaHandler(dir), "/assets/app.js", map[string]string{"Accept-Encoding": "br", "Range": "bytes=0-3"})
	if rec.Header().Get("Content-Encoding") != "" || rec.Body.String() != "cons" {
		t.Fatalf("a range of a compressed body is not a range of the file: %d %q enc=%q", rec.Code, rec.Body.String(), rec.Header().Get("Content-Encoding"))
	}
}

func TestSPAHandler_StaleCompressedLeftoversAreIgnored(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	old := time.Now().Add(-48 * time.Hour)
	if err := os.Chtimes(filepath.Join(dir, "assets", "app.js.br"), old, old); err != nil {
		t.Fatal(err)
	}
	rec := getWith(spaHandler(dir), "/assets/app.js", map[string]string{"Accept-Encoding": "br, gzip"})
	// the old .br is skipped, the fresh .gz is used
	if rec.Body.String() != "GZIP-JS" {
		t.Fatalf("got %q", rec.Body.String())
	}
}

func TestSPAHandler_ConditionalAndHeadRequestsWork(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	first := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": "br"})
	lm := first.Header().Get("Last-Modified")
	if lm == "" {
		t.Fatal("no Last-Modified")
	}
	if rec := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": "br", "If-Modified-Since": lm}); rec.Code != http.StatusNotModified {
		t.Errorf("revalidation: got %d", rec.Code)
	}
	req := httptest.NewRequest(http.MethodHead, "/assets/app.js", nil)
	req.Header.Set("Accept-Encoding", "br")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || rec.Body.Len() != 0 || rec.Header().Get("Content-Encoding") != "br" {
		t.Errorf("HEAD: %d body=%d enc=%q", rec.Code, rec.Body.Len(), rec.Header().Get("Content-Encoding"))
	}
}

func TestSPAHandler_HostileAcceptEncodingAndPaths(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	hostile := []string{
		strings.Repeat("br,", 5000), ";;;;", "br;q=", "br;q=abc", ",,,", "\x00\x01br", "br\r\nX-Evil: 1", strings.Repeat("a", 1<<16),
	}
	for _, accept := range hostile {
		rec := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": accept})
		if rec.Code != http.StatusOK {
			t.Errorf("accept %.20q: got %d", accept, rec.Code)
		}
	}
	// a compressed sibling must not open a way out of the directory or to a file that has no original
	for _, target := range []string{"/assets/../../etc/passwd", "/assets/%2e%2e/%2e%2e/etc/passwd", "/assets/missing.js"} {
		if rec := getWith(h, target, map[string]string{"Accept-Encoding": "br"}); rec.Code != http.StatusNotFound {
			t.Errorf("%s: got %d, want 404", target, rec.Code)
		}
	}
	// only an orphan .br exists: the original is missing, so it is a 404, not a download of the compressed bytes
	if err := os.WriteFile(filepath.Join(dir, "assets", "orphan.js.br"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if rec := getWith(h, "/assets/orphan.js", map[string]string{"Accept-Encoding": "br"}); rec.Code != http.StatusNotFound {
		t.Errorf("orphan: got %d", rec.Code)
	}
}

func TestSPAHandler_ManyConcurrentCompressedRequests(t *testing.T) {
	dir := newPublicDir(t)
	withCompressed(t, dir)
	h := spaHandler(dir)
	var wg sync.WaitGroup
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			accept := []string{"br", "gzip", "", "br, gzip"}[i%4]
			rec := getWith(h, "/assets/app.js", map[string]string{"Accept-Encoding": accept})
			want := map[string]string{"br": "BROTLI-JS", "gzip": "GZIP-JS", "": "console.log(1)", "br, gzip": "BROTLI-JS"}[accept]
			if rec.Body.String() != want {
				t.Errorf("accept %q: got %q", accept, rec.Body.String())
			}
		}(i)
	}
	wg.Wait()
}

func TestSPAHandler_PageCarriesTheContentSecurityPolicyAndAssetsDoNot(t *testing.T) {
	dir := newPublicDir(t)
	h := spaHandler(dir)
	for _, target := range []string{"/", "/login", "/notes/1"} {
		csp := get(h, target).Header().Get("Content-Security-Policy")
		for _, want := range []string{"default-src 'self'", "script-src 'self' 'wasm-unsafe-eval'", "frame-ancestors 'none'", "object-src 'none'", "base-uri 'none'"} {
			if !strings.Contains(csp, want) {
				t.Errorf("%s: CSP lacks %q: %s", target, want, csp)
			}
		}
		if strings.Contains(csp, "script-src 'self' 'unsafe-inline'") || strings.Contains(csp, "unsafe-eval'") && !strings.Contains(csp, "wasm-unsafe-eval") {
			t.Errorf("%s: scripts may run inline: %s", target, csp)
		}
	}
	if csp := get(h, "/assets/app.js").Header().Get("Content-Security-Policy"); csp != "" {
		t.Errorf("a script file does not need a document policy: %q", csp)
	}
}
