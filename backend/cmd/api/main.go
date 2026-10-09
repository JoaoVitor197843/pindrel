package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"plany/internal/api/route"
	"plany/internal/auth"
	"plany/internal/config"
	"plany/internal/database"
	"plany/internal/database/db"
	"plany/internal/middleware"
	"syscall"
	"time"

	_ "plany/docs"

	"github.com/joho/godotenv"
	"golang.org/x/time/rate"
)

// @title Plany API
// @version 1.0
// @description Plany API, self-hosted notes workspace
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
	authHandler := auth.NewHandler(authService, cfg.JWTSecret, cfg.JWTAccessExpiry, cfg.JWTRefreshExpiry)
	loginLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
	registerLimiter := middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
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
	r := route.SetupRouter(cfg, authRepo, authHandler, loginLimiter, registerLimiter)

	srv := &http.Server{
		Addr:         cfg.Port,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("Server running in port %s 🚀", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Critical error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutdown server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("forcing the server shutdown: %v", err)
	}

	log.Println("Server shut down successfully.")
}
