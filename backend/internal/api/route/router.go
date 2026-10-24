package route

import (
	"net/http"
	"os"
	"path"
	"path/filepath"
	"plany/internal/auth"
	"plany/internal/clientip"
	"plany/internal/config"
	"plany/internal/database/db"
	AuthMiddleware "plany/internal/middleware"
	"plany/internal/server"
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
				w.Write([]byte("Plany API is running! 🚀"))
				return
			}
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFile(w, r, index)
	}
}
