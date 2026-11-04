package route

import (
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"pindrel/internal/auth"
	"pindrel/internal/clientip"
	"pindrel/internal/config"
	"pindrel/internal/database/db"
	AuthMiddleware "pindrel/internal/middleware"
	"pindrel/internal/server"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"
	httpSwagger "github.com/swaggo/http-swagger"
)

func SetupRouter(cfg *config.Config, repo *db.Queries, h *auth.Handler, loginLimiter *AuthMiddleware.IPRateLimiter, registerLimiter *AuthMiddleware.IPRateLimiter) *chi.Mux {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(AuthMiddleware.SecurityHeaders)

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"http://localhost:*", "https://seu-app.com"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		AllowCredentials: true,
		MaxAge:           300,
	}))
	// who a request belongs to: its connection, or the client a TRUSTED_PROXIES proxy vouches for (never a header
	// from anyone else: see internal/clientip)
	clientKey := cfg.ClientKey
	if clientKey == nil {
		clientKey = clientip.PeerKey
	}
	if cfg.InAppRateLimit {
		r.Use(httprate.LimitBy(100, 1*time.Minute, func(r *http.Request) (string, error) {
			return clientKey(r), nil
		}))
	}
	// with InAppRateLimit off, the load balancer in front does the rate limiting (keeps the API stateless)
	loginRL, registerRL := noMiddleware, noMiddleware
	if cfg.InAppRateLimit {
		loginRL = AuthMiddleware.RateLimitMiddleware(loginLimiter, clientKey)
		registerRL = AuthMiddleware.RateLimitMiddleware(registerLimiter, clientKey)
	}
	r.With(loginRL).Post("/auth/login/", h.Login)
	r.With(registerRL).Post("/auth/register/", h.Register)
	r.Get("/server/info/", server.NewHandler(cfg.ServerName, cfg.RegistrationEnabled).Info)
	r.Post("/auth/logout/", h.Logout)
	r.Post("/auth/refresh/", h.Refresh)
	r.Get("/auth/me/", h.Me)
	if cfg.DebugMode {
		r.Get("/swagger/*", httpSwagger.WrapHandler)
	}
	r.Group(func(r chi.Router) {
		r.Use(AuthMiddleware.AuthMiddleware(cfg.JWTSecret, repo, cfg.DebugMode))

		// r.Get("/api/notes", GetNotesHandler)
		// r.Get("/api/ws/sync", WebSocketSyncHandler)
	})

	// NotFound (and not a GET /* wildcard) so that an unknown path answers 404 for every method;
	// a wildcard would make chi answer 405 for e.g. POST /auth/lo/.
	r.NotFound(spaHandler(publicDir))

	return r
}

func noMiddleware(next http.Handler) http.Handler { return next }

// webCSP is the Content-Security-Policy of the web page: scripts only from this server (plus WebAssembly, for libsodium),
// styles may be inline (the build puts the stylesheet inside index.html), nothing can be framed or embedded, and the page
// may talk to other Pindrel servers the person added (any http or https address, and WebSockets).
const webCSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; " +
	"img-src 'self' data: blob:; font-src 'self'; connect-src 'self' http: https: ws: wss:; worker-src 'self' blob:; " +
	"object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"

// publicDir is where the Docker image places the web build.
const publicDir = "./public"

// isWebRoute is the allowlist of page routes of the web SPA (web/src/routes). Keep it in sync
// with the web router: a path that is not a static file and not listed here is a 404.
func isWebRoute(p string) bool {
	switch p {
	case "/", "/login":
		return true
	}
	// /notes/:id, exactly one non-empty segment
	if id, ok := strings.CutPrefix(p, "/notes/"); ok {
		return id != "" && !strings.Contains(id, "/")
	}
	return false
}

// spaHandler is the router's NotFound handler. Only GET/HEAD can reach the web; any other method is a 404.
// For GET/HEAD requests that did not match an API route it works in three steps:
//  1. the path is a real file inside dir (JS/CSS/images): serve it;
//  2. the path is a web page route (isWebRoute): serve index.html so the SPA can render it;
//  3. anything else: 404.
func spaHandler(dir string) http.HandlerFunc {
	files := http.FileServer(http.Dir(dir))
	index := filepath.Join(dir, "index.html")
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.NotFound(w, r)
			return
		}
		// path.Clean on a rooted path drops any ".." segments, so it cannot escape dir
		clean := path.Clean("/" + r.URL.Path)
		if info, err := os.Stat(filepath.Join(dir, filepath.FromSlash(clean))); err == nil && !info.IsDir() {
			// Vite names everything under /assets/ after its content: it can be kept for good
			if strings.HasPrefix(clean, "/assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			}
			if servePrecompressed(w, r, filepath.Join(dir, filepath.FromSlash(clean)), info.ModTime()) {
				return
			}
			files.ServeHTTP(w, r)
			return
		}
		if !isWebRoute(clean) {
			http.NotFound(w, r)
			return
		}
		if _, err := os.Stat(index); err != nil {
			// no web build next to the binary (e.g. running the API alone in development)
			if clean == "/" {
				w.Write([]byte("Pindrel API is running! 🚀"))
				return
			}
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Content-Security-Policy", webCSP)
		if info, err := os.Stat(index); err == nil && servePrecompressed(w, r, index, info.ModTime()) {
			return
		}
		http.ServeFile(w, r, index)
	}
}

// servePrecompressed answers with `<file>.br` or `<file>.gz` when the build left one next to the file and the client
// accepts it (Vite does it at build time, vite.assets.ts), so the server compresses nothing: no CPU and no RAM per
// request, only a file read. It reports false when it did not answer and the plain file must be served.
func servePrecompressed(w http.ResponseWriter, r *http.Request, file string, modTime time.Time) bool {
	w.Header().Add("Vary", "Accept-Encoding")
	// a byte range of a compressed body is not a byte range of the file the client asked for
	if r.Header.Get("Range") != "" {
		return false
	}
	accepted := r.Header.Get("Accept-Encoding")
	for _, enc := range []struct{ token, ext string }{{"br", ".br"}, {"gzip", ".gz"}} {
		if !acceptsEncoding(accepted, enc.token) {
			continue
		}
		f, err := os.Open(file + enc.ext)
		if err != nil {
			continue
		}
		defer f.Close()
		// older than the file it compresses: a stale leftover of a previous build, not to be trusted
		if info, err := f.Stat(); err != nil || info.IsDir() || info.ModTime().Before(modTime.Add(-time.Minute)) {
			continue
		}
		w.Header().Set("Content-Encoding", enc.token)
		// the type comes from the original name, since ServeContent would read ".br" as unknown
		w.Header().Set("Content-Type", contentType(file))
		http.ServeContent(w, r, "", modTime, f)
		return true
	}
	return false
}

// acceptsEncoding is a small reading of Accept-Encoding: the token must be listed and not refused with q=0.
func acceptsEncoding(header, token string) bool {
	for _, part := range strings.Split(header, ",") {
		name, params, _ := strings.Cut(strings.TrimSpace(part), ";")
		if !strings.EqualFold(strings.TrimSpace(name), token) {
			continue
		}
		q := strings.ReplaceAll(strings.ToLower(params), " ", "")
		return q != "q=0" && q != "q=0.0" && q != "q=0.00" && q != "q=0.000"
	}
	return false
}

func contentType(file string) string {
	if t := mime.TypeByExtension(filepath.Ext(file)); t != "" {
		return t
	}
	return "application/octet-stream"
}
