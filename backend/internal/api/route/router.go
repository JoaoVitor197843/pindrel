package route

import (
	"net"
	"net/http"
	"plany/internal/auth"
	"plany/internal/config"
	"plany/internal/database/db"
	AuthMiddleware "plany/internal/middleware"
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
	r.Use(httprate.LimitBy(
		100,
		1*time.Minute,
		func(r *http.Request) (string, error) {
			ip, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				ip = r.RemoteAddr
			}
			parsedIP := net.ParseIP(ip)
			if parsedIP != nil && (parsedIP.IsLoopback() || parsedIP.IsPrivate()) {
				if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
					ips := strings.Split(xff, ",")
					clientIP := strings.TrimSpace(ips[0])
					if clientIP != "" {
						return clientIP, nil
					}
				}
			}
			return ip, err
		}))

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("Plany API is running! 🚀"))
    })

	r.With(AuthMiddleware.RateLimitMiddleware(loginLimiter)).
		Post("/auth/login/", h.Login)
	r.With(AuthMiddleware.RateLimitMiddleware(registerLimiter)).
		Post("/auth/register/", h.Register)
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

	return r
}
