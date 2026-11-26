package route

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"pindrel/internal/auth"
	"pindrel/internal/config"
	AuthMiddleware "pindrel/internal/middleware"
)

func preflight(h http.Handler, origin string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodOptions, "/auth/refresh/", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

// By default no other site may call the API with the person's cookie. The old hardcoded list let any page on
// localhost and a placeholder domain nobody owned ("seu-app.com") do it.
func TestRouter_NoOtherSiteIsAllowedByDefault(t *testing.T) {
	r := SetupRouter(&config.Config{}, nil, &auth.Handler{}, nil, nil)
	for _, origin := range []string{"https://seu-app.com", "http://localhost:5173", "https://evil.example", "null"} {
		rec := preflight(r, origin)
		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
			t.Errorf("%s: Access-Control-Allow-Origin %q", origin, got)
		}
		if rec.Header().Get("Access-Control-Allow-Credentials") != "" {
			t.Errorf("%s: credentials allowed", origin)
		}
	}
}

func TestRouter_AllowedOriginsAreTheOnlyOnes(t *testing.T) {
	r := SetupRouter(&config.Config{AllowedOrigins: []string{"https://notas.exemplo.com"}}, nil, &auth.Handler{}, nil, nil)
	if rec := preflight(r, "https://notas.exemplo.com"); rec.Header().Get("Access-Control-Allow-Origin") != "https://notas.exemplo.com" ||
		rec.Header().Get("Access-Control-Allow-Credentials") != "true" {
		t.Errorf("listed origin: %v", rec.Header())
	}
	for _, origin := range []string{"https://evil.example", "https://notas.exemplo.com.evil.example", "http://notas.exemplo.com"} {
		if got := preflight(r, origin).Header().Get("Access-Control-Allow-Origin"); got != "" {
			t.Errorf("%s: %q", origin, got)
		}
	}
}

// The web build is looked for where WEB_DIR says (the Windows install keeps it next to the program).
func TestRouter_ServesTheWebFromWebDir(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html>daqui</html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	r := SetupRouter(&config.Config{WebDir: dir}, nil, &auth.Handler{},
		AuthMiddleware.NewIPRateLimiter(1, 1), AuthMiddleware.NewIPRateLimiter(1, 1))
	if rec := get(r, "/login"); rec.Code != http.StatusOK || rec.Body.String() != "<html>daqui</html>" {
		t.Errorf("got %d %q", rec.Code, rec.Body.String())
	}
}
