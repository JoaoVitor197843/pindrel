package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load()

	mongoURI := os.Getenv("MONGO_URI")
	dbName := os.Getenv("MONGO_DB_NAME")
	jwtSecret := os.Getenv("JWT_SECRET")
	port := os.Getenv("PORT")
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
	repo := auth.NewRepository(db)
	blocklist, err := auth.NewBlocklistRepository(context.Background(), db)
	if err != nil {
		log.Fatalf("failed to create blocklist repo: %v", err)
	}
	service := auth.NewService(repo, blocklist, registrationEnabled)
	handler := auth.NewHandler(service)

	accessExpiry, err := time.ParseDuration(os.Getenv("JWT_ACCESS_EXPIRY"))
	if err != nil {
		accessExpiry = 15 * time.Minute
	}

	refreshExpiry, err := time.ParseDuration(os.Getenv("JWT_REFRESH_EXPIRY"))
	if err != nil {
		refreshExpiry = 720 * time.Hour
	}

	mux := http.NewServeMux()

	mux.HandleFunc("POST /auth/register", func(w http.ResponseWriter, r *http.Request) {
		handler.Register(w, r)
	})
	mux.HandleFunc("POST /auth/login", func(w http.ResponseWriter, r *http.Request) {
		handler.Login(w, r, jwtSecret, accessExpiry, refreshExpiry)
	})
	mux.HandleFunc("POST /auth/logout", func(w http.ResponseWriter, r *http.Request) {
		handler.Logout(w, r, jwtSecret)
	})
	mux.HandleFunc("POST /auth/refresh", func(w http.ResponseWriter, r *http.Request) {
		handler.Refresh(w, r, jwtSecret, accessExpiry)
	})
	mux.HandleFunc("GET /auth/me", func(w http.ResponseWriter, r *http.Request) {
		handler.Me(w, r, jwtSecret)
	})

	log.Printf("server running on port %s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
