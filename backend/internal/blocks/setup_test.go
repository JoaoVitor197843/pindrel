package blocks_test

import (
	"context"
	"os"
	"testing"
	"time"

	"plany/internal/blocks"
	"plany/internal/database"
	"plany/internal/pages"

	"github.com/joho/godotenv"
	"go.mongodb.org/mongo-driver/v2/bson"
)

func setupTest(t *testing.T) (*blocks.Repository, *blocks.Service, *pages.Repository, func()) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}

	db := client.Database(os.Getenv("MONGO_DB_NAME"))

	pageRepo, err := pages.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("failed to create pages repository: %v", err)
	}

	blockRepo, err := blocks.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("failed to create blocks repository: %v", err)
	}

	service := blocks.NewService(blockRepo, pageRepo)

	cleanup := func() {
		client.Disconnect(context.Background())
	}

	return blockRepo, service, pageRepo, cleanup
}

func createTestPage(t *testing.T, pageRepo *pages.Repository, ownerID bson.ObjectID) bson.ObjectID {
	page := &pages.Page{
		Title:     "test page",
		OwnerID:   ownerID,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if err := pageRepo.Create(context.Background(), page); err != nil {
		t.Fatalf("failed to create test page: %v", err)
	}

	t.Cleanup(func() {
		pageRepo.Delete(context.Background(), page.ID)
	})

	return page.ID
}

func cleanupPageBlocks(t *testing.T, repo *blocks.Repository, pageID bson.ObjectID) {
	t.Cleanup(func() {
		repo.DeletePageBlocks(context.Background(), pageID)
	})
}
