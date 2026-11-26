package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
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
	"slices"
	"syscall"
	"time"

	"github.com/joho/godotenv"
	"golang.org/x/time/rate"
)

const usage = `pindrel-server: the Pindrel API (and the web it serves).

  --config <file>  read the settings from a KEY=VALUE file (also PINDREL_CONFIG); the real environment wins
  --check          validate the settings and exit (0 = fine)
  --check-db       validate the settings, connect to the database once and exit (0 = reachable)
  --new-secret     print a new random secret (for JWT_SECRET or a database password) and exit

Without --config, a .env in the current folder is read when there is one (development).`

// @title Pindrel API
// @version 1.0
// @description Pindrel API, self-hosted notes workspace
// @BasePath /
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
func main() {
	args := os.Args[1:]
	if slices.Contains(args, "--help") || slices.Contains(args, "-h") {
		fmt.Println(usage)
		return
	}
	if slices.Contains(args, "--new-secret") {
		fmt.Println(newSecret())
		return
	}
	if err := loadSettingsFile(args); err != nil {
		log.Fatal(err)
	}
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed on configuration: %v", err)
	}
	if slices.Contains(args, "--check") {
		fmt.Println("configuração OK")
		return
	}
	if slices.Contains(args, "--check-db") {
		if err := checkDatabase(cfg.Database); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("banco de dados OK")
		return
	}
	if err := run(cfg); err != nil {
		log.Fatal(err)
	}
}

// loadSettingsFile reads --config (or PINDREL_CONFIG). Without one, a .env in the current folder is read if it exists,
// as in development.
func loadSettingsFile(args []string) error {
	path, err := config.EnvFilePath(args, os.Getenv)
	if err != nil {
		return err
	}
	if path == "" {
		_ = godotenv.Load()
		return nil
	}
	return config.LoadEnvFile(path)
}

// newSecret is 48 random bytes in URL-safe base64 (64 characters, no symbol that a settings file or a shell would read).
func newSecret() string {
	b := make([]byte, 48)
	_, _ = rand.Read(b) // never fails: crypto/rand panics instead of returning an error since Go 1.24
	return base64.RawURLEncoding.EncodeToString(b)
}

// checkDatabase is one connection attempt with a short deadline, for an installer asking "do these settings work?".
func checkDatabase(cfg config.DatabaseConfig) error {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cfg.MaxConns = 1
	pool, err := database.Connect(ctx, cfg, 1)
	if err != nil {
		return fmt.Errorf("não foi possível conectar ao PostgreSQL em %s:%d: %w", cfg.Host, cfg.Port, err)
	}
	pool.Close()
	return nil
}

func run(cfg *config.Config) error {
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		return fmt.Errorf("failed to connect to postgres: %w", err)
	}
	defer dbPool.Close()
	// the schema is part of the release: apply what the binary ships before serving (replicas wait on a lock)
	if err := database.Migrate(database.CreateConnString(cfg.Database)); err != nil {
		return fmt.Errorf("failed to migrate the database: %w", err)
	}

	ctx, stop := context.WithCancel(context.Background())
	defer stop()

	repo := db.New(dbPool)
	authService := auth.NewService(repo, cfg.RegistrationEnabled)
	authHandler := auth.NewHandler(authService, cfg.JWTSecret, cfg.JWTAccessExpiry, cfg.JWTRefreshExpiry)
	// an expired token is refused anyway: its line in revoked_tokens only takes space (any replica may do it)
	go every(ctx, time.Hour, func() {
		if err := authService.PruneRevokedTokens(ctx); err != nil && ctx.Err() == nil {
			log.Printf("revoked tokens clean-up: %v", err)
		}
	})

	var loginLimiter, registerLimiter *middleware.IPRateLimiter
	var limiters []*middleware.IPRateLimiter
	if cfg.InAppRateLimit {
		loginLimiter = middleware.NewIPRateLimiter(rate.Every(time.Minute/5), 5)
		registerLimiter = middleware.NewIPRateLimiter(rate.Every(time.Minute/5), 5)
		limiters = append(limiters, loginLimiter, registerLimiter)
	}
	var extras route.Extras
	if cfg.Files.Dir != "" {
		store, err := files.NewStore(cfg.Files.Dir)
		if err != nil {
			return fmt.Errorf("failed to prepare the files directory: %w", err)
		}
		filesService := files.NewService(dbPool, repo, store, files.Config{
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
			limiters = append(limiters, extras.FileLimiters.Chunks, extras.FileLimiters.Control)
		}
		go filesService.RunCleanup(ctx, 10*time.Minute)
		log.Printf("files: stored in %s (up to %d MiB each, %d MiB per person)", cfg.Files.Dir, cfg.Files.MaxFileBytes>>20, cfg.Files.QuotaBytes>>20)
	}
	if len(limiters) > 0 {
		go every(ctx, 10*time.Minute, func() {
			for _, l := range limiters {
				l.Cleanup(30 * time.Minute)
			}
		})
	}
	r := route.SetupRouter(cfg, repo, authHandler, loginLimiter, registerLimiter, extras)

	srv := &http.Server{
		Addr:         cfg.Port,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}
	served := make(chan error, 1)
	go func() {
		log.Printf("server listening on %s", cfg.Port)
		served <- srv.ListenAndServe()
	}()

	// Ctrl+C everywhere; SIGTERM from Docker/systemd; on Windows Go also turns closing the console window, logging off and
	// shutting down into SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	select {
	case err := <-served:
		// the port is taken or not allowed: say so and leave, the deferred pool close still runs
		return fmt.Errorf("server stopped: %w", err)
	case <-quit:
	}
	log.Println("shutting down...")
	stop()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil && !errors.Is(err, context.DeadlineExceeded) {
		return fmt.Errorf("shutdown: %w", err)
	}
	log.Println("server shut down")
	return nil
}

// every runs fn each period until ctx ends.
func every(ctx context.Context, period time.Duration, fn func()) {
	t := time.NewTicker(period)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			fn()
		}
	}
}
