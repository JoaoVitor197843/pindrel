package pages_test

import (
	"context"
	"os"
	"plany/internal/database"
	"plany/internal/pages"
	"testing"

	"github.com/joho/godotenv"
)

func setupTest(t *testing.T) (*pages.Repository, func()) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo, err := pages.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("Error on creating repository")
	}
	cleanup := func() {
		client.Disconnect(context.Background())
	}

	return repo, cleanup
}
