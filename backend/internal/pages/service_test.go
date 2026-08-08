package pages_test

import (
	"context"
	"errors"
	"fmt"
	"plany/internal/pages"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestService_GetPages_Basic(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()
	userCheck := fakeUserChecker{count: 1}
	service := pages.NewService(repo, userCheck)
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
	userCheck := fakeUserChecker{count: 1}
	service := pages.NewService(repo, userCheck)
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

	firstResult, err := service.GetPages(context.Background(), userID, "", 2)
	if err != nil {
		t.Fatalf("get pages failed: %v", err)
	}
	if firstResult.NextCursor == "" {
		t.Fatal("expected non-empty next_cursor when more results exist")
	}

	secondResult, err := service.GetPages(context.Background(), userID, firstResult.NextCursor, 2)
	if err != nil {
		t.Fatalf("get pages with cursor failed: %v", err)
	}
	if len(secondResult.Data) != 2 {
		t.Fatalf("expected 2 items in second batch, got %d", len(secondResult.Data))
	}

	for _, first := range firstResult.Data {
		for _, second := range secondResult.Data {
			if first.ID == second.ID {
				t.Fatalf("found duplicate page ID %s between batches", first.ID)
			}
		}
	}
}

func TestService_CreatePage_NormalizesTags(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	fakeUsers := fakeUserChecker{count: 0}
	service := pages.NewService(repo, fakeUsers)
	userID := bson.NewObjectID()

	input := pages.PageCreateRequest{
		Title: "Teste",
		Tags:  []string{"Trabalho", "  URGENTE  ", ""},
	}

	result, err := service.CreatePage(context.Background(), userID, input)
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}
	defer repo.Delete(context.Background(), mustObjectID(result.ID))

	if len(result.Tags) != 2 {
		t.Fatalf("expected 2 tags after normalization (empty discarded), got %d: %v", len(result.Tags), result.Tags)
	}
	if result.Tags[0] != "trabalho" || result.Tags[1] != "urgente" {
		t.Fatalf("expected [trabalho urgente], got %v", result.Tags)
	}
}

func TestService_CreatePage_InvalidSharedUser(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	fakeUsers := fakeUserChecker{count: 0} // simula que nenhum usuário existe
	service := pages.NewService(repo, fakeUsers)
	userID := bson.NewObjectID()
	fakeSharedID := bson.NewObjectID()

	input := pages.PageCreateRequest{
		Title:      "Teste",
		SharedWith: []string{fakeSharedID.Hex()},
	}

	_, err := service.CreatePage(context.Background(), userID, input)
	if !errors.Is(err, pages.ErrInvalidSharedUserID) {
		t.Fatalf("expected ErrInvalidSharedUserID, got: %v", err)
	}
}

func TestService_CreatePage_DeduplicatesAndRemovesOwner(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	fakeUsers := fakeUserChecker{count: 1} // só 1 usuário válido esperado após dedup/remoção
	service := pages.NewService(repo, fakeUsers)
	userID := bson.NewObjectID()
	sharedID := bson.NewObjectID()

	input := pages.PageCreateRequest{
		Title: "Teste",
		SharedWith: []string{
			sharedID.Hex(),
			sharedID.Hex(), // duplicado
			userID.Hex(),   // o próprio owner
		},
	}

	result, err := service.CreatePage(context.Background(), userID, input)
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}
	defer repo.Delete(context.Background(), mustObjectID(result.ID))

	page, err := repo.FindByID(context.Background(), mustObjectID(result.ID))
	if err != nil {
		t.Fatalf("failed to fetch created page: %v", err)
	}

	if len(page.SharedWith) != 1 {
		t.Fatalf("expected 1 shared user after dedup/owner removal, got %d: %v", len(page.SharedWith), page.SharedWith)
	}
	if page.SharedWith[0] != sharedID {
		t.Fatalf("expected shared user to be %s, got %s", sharedID.Hex(), page.SharedWith[0].Hex())
	}
}
