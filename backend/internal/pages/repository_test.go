package pages_test

import (
	"context"
	"fmt"
	"plany/internal/pages"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestRepository_FindPages_Basic(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	userID := bson.NewObjectID()
	var createdIDs []bson.ObjectID

	for i := range 3 {
		page := pages.Page{
			Title:     fmt.Sprintf("Página %d", i),
			OwnerID:   userID,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if err := repo.Create(context.Background(), &page); err != nil {
			t.Fatalf("create failed: %v", err)
		}
		createdIDs = append(createdIDs, page.ID)
	}
	defer func() {
		for _, id := range createdIDs {
			repo.Delete(context.Background(), id)
		}
	}()

	result, total, err := repo.FindPages(context.Background(), userID, nil, 10)
	if err != nil {
		t.Fatalf("find pages failed: %v", err)
	}

	if total != 3 {
		t.Fatalf("expected total 3, got %d", total)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 pages returned, got %d", len(result))
	}
}

func TestRepository_FindPages_Pagination(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	userID := bson.NewObjectID()
	var createdIDs []bson.ObjectID

	for i := range 5 {
		page := pages.Page{
			Title:     fmt.Sprintf("Página %d", i),
			OwnerID:   userID,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if err := repo.Create(context.Background(), &page); err != nil {
			t.Fatalf("create failed: %v", err)
		}
		createdIDs = append(createdIDs, page.ID)
	}
	defer func() {
		for _, id := range createdIDs {
			repo.Delete(context.Background(), id)
		}
	}()

	firstBatch, total, err := repo.FindPages(context.Background(), userID, nil, 2)
	if err != nil {
		t.Fatalf("first batch failed: %v", err)
	}
	if total != 5 {
		t.Fatalf("expected total 5, got %d", total)
	}
	if len(firstBatch) != 2 {
		t.Fatalf("expected 2 pages in first batch, got %d", len(firstBatch))
	}

	lastID := firstBatch[len(firstBatch)-1].ID
	secondBatch, _, err := repo.FindPages(context.Background(), userID, &lastID, 2)
	if err != nil {
		t.Fatalf("second batch failed: %v", err)
	}
	if len(secondBatch) != 2 {
		t.Fatalf("expected 2 pages in second batch, got %d", len(secondBatch))
	}

	for _, first := range firstBatch {
		for _, second := range secondBatch {
			if first.ID == second.ID {
				t.Fatalf("found duplicate page ID %s between batches", first.ID.Hex())
			}
		}
	}
}
