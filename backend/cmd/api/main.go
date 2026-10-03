package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"plany/internal/auth"
	"plany/internal/config"
	"plany/internal/database"
	"plany/internal/database/db"
	"plany/internal/middleware"
	"time"

	_ "plany/docs"

	"github.com/joho/godotenv"
	httpSwagger "github.com/swaggo/http-swagger"
	"golang.org/x/time/rate"
)

// @title Plany API
// @version 1.0
// @description Plany API, self-hosted notes workspace
// @host localhost:8080
// @BasePath /
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
func main() {
	godotenv.Load()
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed on configuration: %v", err)
	}
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer dbPool.Close()
	authRepo := db.New(dbPool)

	authService := auth.NewService(authRepo, cfg.RegistrationEnabled)
	authHandler := auth.NewHandler(authService)
	loginLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
	registerLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
	mux := http.NewServeMux()

	mux.Handle("POST /auth/register", middleware.RateLimitMiddleware(registerLimiter, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHandler.Register(w, r)
	})))
	mux.Handle("POST /auth/login", middleware.RateLimitMiddleware(loginLimiter, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHandler.Login(w, r, cfg.JWTSecret, cfg.JWTAccessExpiry, cfg.JWTRefreshExpiry)
	})))
	mux.HandleFunc("POST /auth/logout", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Logout(w, r, cfg.JWTSecret)
	})
	mux.HandleFunc("POST /auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Refresh(w, r, cfg.JWTSecret, cfg.JWTAccessExpiry)
	})
	mux.HandleFunc("GET /auth/me", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Me(w, r, cfg.JWTSecret)
	})

	// pagesRepo, err := pages.NewRepository(context.Background(), db)
	// if err != nil {
	// 	log.Fatalf("failed to setup pages repo: %v", err)
	// }
	// pagesService := pages.NewService(pagesRepo, authRepo)
	// pagesHandler := pages.NewHandler(pagesService)

	// mux.Handle("GET /pages", middleware.AuthMiddleware(jwtSecret, blocklist, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	// 	pagesHandler.GetPages(w, r)
	// })))

	// mux.Handle("POST /pages", middleware.AuthMiddleware(jwtSecret, blocklist, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	// 	pagesHandler.CreatePage(w, r)
	// })))

	if cfg.DebugMode {
		mux.HandleFunc("GET /swagger/", httpSwagger.WrapHandler)
		log.Println("swagger UI enabled at /swagger/index.html")
	}
	go func() {
		ticker := time.NewTicker(10 * time.Minute)
		cleanupAge := 30 * time.Minute
		for range ticker.C {
			log.Println("Cleaning Limiters...")
			loginLimiter.Cleanup(cleanupAge)
			registerLimiter.Cleanup(cleanupAge)
			log.Println("Limiters Cleaned")
		}
	}()
	log.Println("server running on port ", cfg.Port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", cfg.Port), mux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
