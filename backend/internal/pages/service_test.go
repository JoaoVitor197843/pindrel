package pages_test

import (
	"context"
	"fmt"
	"plany/internal/pages"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestService_GetPages_Basic(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	service := pages.NewService(repo)
	userID := bson.NewObjectID()
	var createdIDs []bson.ObjectID

	for i := 0; i < 3; i++ {
		page := pages.Page{
			Title:       fmt.Sprintf("Página %d", i),
			Description: "conteúdo de teste",
			OwnerID:     userID,
			CreatedAt:   time.Now(),
			UpdatedAt:   time.Now(),
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

	result, err := service.GetPages(context.Background(), userID, "", 10)
	if err != nil {
		t.Fatalf("get pages failed: %v", err)
	}

	if result.Total != 3 {
		t.Fatalf("expected total 3, got %d", result.Total)
	}
	if len(result.Data) != 3 {
		t.Fatalf("expected 3 items, got %d", len(result.Data))
	}
	if result.NextCursor != "" {
		t.Fatalf("expected empty next_cursor when all results fit, got %s", result.NextCursor)
	}
	if result.Data[0].Description != "conteúdo de teste" {
		t.Fatalf("expected description to be mapped correctly")
	}
}

func TestService_GetPages_NextCursor(t *testing.T) {
    repo, cleanup := setupTest(t)
    defer cleanup()

    service := pages.NewService(repo)
    userID := bson.NewObjectID()
    var createdIDs []bson.ObjectID

    for i := 0; i < 5; i++ {
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

    // pede só 2, mas existem 5 — deve vir com next_cursor preenchido
    firstResult, err := service.GetPages(context.Background(), userID, "", 2)
    if err != nil {
        t.Fatalf("get pages failed: %v", err)
    }
    if firstResult.NextCursor == "" {
        t.Fatal("expected non-empty next_cursor when more results exist")
    }

    // usa o cursor pra buscar o próximo lote
    secondResult, err := service.GetPages(context.Background(), userID, firstResult.NextCursor, 2)
    if err != nil {
        t.Fatalf("get pages with cursor failed: %v", err)
    }
    if len(secondResult.Data) != 2 {
        t.Fatalf("expected 2 items in second batch, got %d", len(secondResult.Data))
    }

    // confirma que não há repetição entre os lotes
    for _, first := range firstResult.Data {
        for _, second := range secondResult.Data {
            if first.ID == second.ID {
                t.Fatalf("found duplicate page ID %s between batches", first.ID)
            }
        }
    }
}
