package database_test

import (
	"context"
	"plany/internal/config"
	"plany/internal/database"
	"testing"
	"time"

	"github.com/joho/godotenv"
)

func TestPostgresConnection(t *testing.T) {
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
