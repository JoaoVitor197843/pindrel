package auth_test

import (
	"context"
	"plany/internal/auth"
	"plany/internal/config"
	"plany/internal/database"
	"plany/internal/database/db"
	"testing"

	"github.com/joho/godotenv"
)

func setupTest(t *testing.T, registrationEnabled bool) (*auth.Handler, *db.Queries, *auth.BlocklistRepository, func()) {
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	blocklist := auth.NewBlocklistRepository(dbPool)
	repo := db.New(dbPool)
	service := auth.NewService(repo, blocklist, registrationEnabled)
	handler := auth.NewHandler(service)

	cleanup := func() {
		dbPool.Close()
	}

	return handler, repo, blocklist, cleanup
}
