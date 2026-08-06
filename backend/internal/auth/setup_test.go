package auth_test

import (
	"context"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"testing"

	"github.com/joho/godotenv"
)

func setupTest(t *testing.T, registrationEnabled bool) (*auth.Handler, *auth.Repository, *auth.BlocklistRepository, func()) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	blocklist, err := auth.NewBlocklistRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("failed to create blocklist repo: %v", err)
	}
	service := auth.NewService(repo, blocklist, registrationEnabled)
	handler := auth.NewHandler(service)

	cleanup := func() {
		client.Disconnect(context.Background())
	}

	return handler, repo, blocklist, cleanup
}
