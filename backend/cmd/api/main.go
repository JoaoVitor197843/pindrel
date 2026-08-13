package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"plany/internal/middleware"
	"plany/internal/pages"
	"strconv"
	"strings"
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

	mongoURI := os.Getenv("MONGO_URI")
	dbName := os.Getenv("MONGO_DB_NAME")
	jwtSecret := os.Getenv("JWT_SECRET")
	var missing []string
	if mongoURI == "" {
		missing = append(missing, "MONGO_URI")
	}
	if dbName == "" {
		missing = append(missing, "MONGO_DB_NAME")
	}
	if jwtSecret == "" {
		missing = append(missing, "JWT_SECRET")
	}

	if len(missing) > 0 {
		log.Fatalf("missing required environment variables: %s", strings.Join(missing, ", "))
	}
	rawRegistrationEnabled := os.Getenv("REGISTRATION_ENABLED")
	if rawRegistrationEnabled == "" {
		rawRegistrationEnabled = "true"
	}
	registrationEnabled, err := strconv.ParseBool(rawRegistrationEnabled)
	if err != nil {
		log.Fatalf("invalid REGISTRATION_ENABLED value: %v", err)
	}
	client, err := database.DefaultConnect(mongoURI)
	if err != nil {
		log.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())
	db := client.Database(dbName)
	authRepo, err := auth.NewRepository(context.Background(), db)
	if err != nil {
		log.Fatalf("failed to create auth repo: %v", err)
	}
	blocklist, err := auth.NewBlocklistRepository(context.Background(), db)
	if err != nil {
		log.Fatalf("failed to create blocklist repo: %v", err)
	}
	authService := auth.NewService(authRepo, blocklist, registrationEnabled)
	authHandler := auth.NewHandler(authService)

	accessExpiry, err := time.ParseDuration(os.Getenv("JWT_ACCESS_EXPIRY"))
	if err != nil {
		accessExpiry = 15 * time.Minute
	}

	refreshExpiry, err := time.ParseDuration(os.Getenv("JWT_REFRESH_EXPIRY"))
	if err != nil {
		refreshExpiry = 720 * time.Hour
	}
	loginLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
	registerLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
	mux := http.NewServeMux()

	mux.Handle("POST /auth/register", middleware.RateLimitMiddleware(registerLimiter, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHandler.Register(w, r)
	})))
	mux.Handle("POST /auth/login", middleware.RateLimitMiddleware(loginLimiter, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHandler.Login(w, r, jwtSecret, accessExpiry, refreshExpiry)
	})))
	mux.HandleFunc("POST /auth/logout", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Logout(w, r, jwtSecret)
	})
	mux.HandleFunc("POST /auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Refresh(w, r, jwtSecret, accessExpiry)
	})
	mux.HandleFunc("GET /auth/me", func(w http.ResponseWriter, r *http.Request) {
		authHandler.Me(w, r, jwtSecret)
	})

	pagesRepo, err := pages.NewRepository(context.Background(), db)
	if err != nil {
		log.Fatalf("failed to setup pages repo: %v", err)
	}
	pagesService := pages.NewService(pagesRepo, authRepo)
	pagesHandler := pages.NewHandler(pagesService)

	mux.Handle("GET /pages", middleware.AuthMiddleware(jwtSecret, blocklist, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		pagesHandler.GetPages(w, r)
	})))

	mux.Handle("POST /pages", middleware.AuthMiddleware(jwtSecret, blocklist, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		pagesHandler.CreatePage(w, r)
	})))

	debugMode, _ := strconv.ParseBool(os.Getenv("DEBUG_MODE"))
	if debugMode {
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
	log.Printf("server running on port 8080")
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
