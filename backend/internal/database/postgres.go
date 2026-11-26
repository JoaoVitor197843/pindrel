package database

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"pindrel/internal/config"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func CreateConnString(cfg config.DatabaseConfig) string {
	u := &url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(cfg.User, cfg.Password),
		Host:   fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		Path:   cfg.DBName,
	}

	q := u.Query()
	q.Set("sslmode", string(cfg.SSLMode))
	u.RawQuery = q.Encode()

	return u.String()
}

// NewConnection opens the pool, trying for a while (the database may still be starting next to the API).
func NewConnection(ctx context.Context, cfg config.DatabaseConfig) (*pgxpool.Pool, error) {
	return Connect(ctx, cfg, 5)
}

// Connect opens the pool and checks it with a ping, up to attempts times, 2 s apart.
func Connect(ctx context.Context, cfg config.DatabaseConfig, attempts int) (*pgxpool.Pool, error) {
	attempts = max(1, attempts)
	dsn := CreateConnString(cfg)
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to create the connection pool: %w", err)
	}

	// small pool: each API replica opens its own, and the shared Postgres has a tiny RAM budget
	config.MaxConns = int32(cfg.MaxConns)
	config.MinConns = min(2, config.MaxConns)
	config.MaxConnLifetime = 1 * time.Hour
	config.MaxConnIdleTime = 15 * time.Minute

	var pool *pgxpool.Pool
	for attempt := 1; attempt <= attempts; attempt++ {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		pool, err = pgxpool.NewWithConfig(pingCtx, config)
		if err == nil {
			err = pool.Ping(pingCtx)
		}
		cancel()

		if err == nil {
			return pool, nil
		}

		if pool != nil {
			pool.Close()
		}
		if attempt == attempts {
			break
		}
		log.Printf("postgres: attempt %d/%d failed: %v; trying again in 2s", attempt, attempts, err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}

	return nil, fmt.Errorf("could not connect to Postgres after %d attempts: %w", attempts, err)
}
