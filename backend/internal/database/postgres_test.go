package database_test

import (
	"context"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"testing"
	"time"

	"github.com/joho/godotenv"
)

func TestDB_PostgresConnection(t *testing.T) {
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := database.NewConnection(ctx, cfg.Database)
	if err != nil {
		t.Fatalf("error on postgres connection: %v", err)
	}
	defer pool.Close()
}

// One attempt against a port where nothing listens fails at once, with the address in the error (what --check-db shows
// to the person installing).
func TestConnect_UnreachableFailsFastWithOneAttempt(t *testing.T) {
	cfg := config.DatabaseConfig{Host: "127.0.0.1", Port: 1, User: "x", Password: "x", DBName: "x", SSLMode: config.SSLDisable, MaxConns: 1}
	start := time.Now()
	if _, err := database.Connect(context.Background(), cfg, 1); err == nil {
		t.Fatal("connected to a port where nothing listens")
	}
	if took := time.Since(start); took > 4*time.Second {
		t.Errorf("one attempt took %v: it waited for retries", took)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := database.Connect(ctx, cfg, 5); err == nil {
		t.Fatal("a cancelled context still connected")
	}
}
