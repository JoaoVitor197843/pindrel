package pages_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"plany/internal/pages"
	contextkeys "plany/pkg/context"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestHandler_GetPages_Success(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	service := pages.NewService(repo)
	handler := pages.NewHandler(service)

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

	req := httptest.NewRequest(http.MethodGet, "/pages", nil)
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()

	handler.GetPages(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var result pages.PageData
	json.NewDecoder(rec.Body).Decode(&result)
	if result.Total != 3 {
		t.Fatalf("expected total 3, got %d", result.Total)
	}
}

func TestHandler_GetPages_InvalidCursor(t *testing.T) {
    repo, cleanup := setupTest(t)
    defer cleanup()

    service := pages.NewService(repo)
    handler := pages.NewHandler(service)

    userID := bson.NewObjectID()

    req := httptest.NewRequest(http.MethodGet, "/pages?cursor=isso-nao-eh-um-objectid-valido", nil)
    ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
    req = req.WithContext(ctx)
    rec := httptest.NewRecorder()

    handler.GetPages(rec, req)

    if rec.Code != http.StatusBadRequest {
        t.Fatalf("expected status 400, got %d", rec.Code)
    }
}