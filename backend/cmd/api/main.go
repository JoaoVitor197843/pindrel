package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"pindrel/internal/api/route"
	"pindrel/internal/auth"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"pindrel/internal/database/db"
	"pindrel/internal/files"
	"pindrel/internal/middleware"
	"syscall"
	"time"

	"github.com/joho/godotenv"
	"golang.org/x/time/rate"
)

// @title Pindrel API
// @version 1.0
// @description Pindrel API, self-hosted notes workspace
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
	// the schema is part of the release: apply what the binary ships before serving (replicas wait on a lock)
	if err := database.Migrate(database.CreateConnString(cfg.Database)); err != nil {
		log.Fatalf("failed to migrate the database: %v", err)
	}
	authRepo := db.New(dbPool)
	authService := auth.NewService(authRepo, cfg.RegistrationEnabled)
	authHandler := auth.NewHandler(authService, cfg.JWTSecret, cfg.JWTAccessExpiry, cfg.JWTRefreshExpiry)
	var loginLimiter, registerLimiter *middleware.IPRateLimiter
	if cfg.InAppRateLimit {
		loginLimiter = middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
		registerLimiter = middleware.NewIPRateLimiter(rate.Every(1*time.Minute/5), 5)
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
	}
	var extras route.Extras
	if cfg.Files.Dir != "" {
		store, err := files.NewStore(cfg.Files.Dir)
		if err != nil {
			log.Fatalf("failed to prepare the files directory: %v", err)
		}
		filesService := files.NewService(dbPool, authRepo, store, files.Config{
			Dir: cfg.Files.Dir, MaxFileBytes: cfg.Files.MaxFileBytes, QuotaBytes: cfg.Files.QuotaBytes, MinFreeBytes: cfg.Files.MinFreeBytes,
			MaxOpenUploads: cfg.Files.MaxOpenUploads, UploadTTL: cfg.Files.UploadTTL, OrphanGrace: cfg.Files.OrphanGrace,
			LinkTTL: cfg.Files.LinkTTL, Secret: []byte(cfg.JWTSecret),
		})
		extras.Files = files.NewHandler(filesService)
		if cfg.InAppRateLimit {
			extras.FileLimiters = &route.FileLimiters{
				Chunks:  middleware.NewIPRateLimiter(rate.Every(time.Minute/time.Duration(cfg.Files.ChunksPerMinute)), 20),
				Control: middleware.NewIPRateLimiter(rate.Every(time.Minute/120), 30),
			}
		}
		if extras.FileLimiters != nil {
			go func() {
				for range time.Tick(10 * time.Minute) {
					extras.FileLimiters.Chunks.Cleanup(30 * time.Minute)
					extras.FileLimiters.Control.Cleanup(30 * time.Minute)
				}
			}()
		}
		go filesService.RunCleanup(context.Background(), 10*time.Minute)
		log.Printf("files: stored in %s (up to %d MiB each, %d MiB per person)", cfg.Files.Dir, cfg.Files.MaxFileBytes>>20, cfg.Files.QuotaBytes>>20)
	}
	r := route.SetupRouter(cfg, authRepo, authHandler, loginLimiter, registerLimiter, extras)

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
