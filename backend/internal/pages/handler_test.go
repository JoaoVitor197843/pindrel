package pages_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"plany/internal/pages"
	contextkeys "plany/pkg/context"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestHandler_GetPages_Success(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()
	userCheck := fakeUserChecker{count: 1}
	service := pages.NewService(repo, userCheck)
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
	userCheck := fakeUserChecker{count: 1}
	service := pages.NewService(repo, userCheck)
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

func TestHandler_CreatePage_Success(t *testing.T) {
	repo, cleanup := setupTest(t)
	defer cleanup()

	fakeUsers := fakeUserChecker{count: 1}
	service := pages.NewService(repo, fakeUsers)
	handler := pages.NewHandler(service)

	userID := bson.NewObjectID()
	sharedID := bson.NewObjectID()

	body := fmt.Sprintf(`{"title":"Minha página","description":"conteúdo","tags":["Trabalho","  urgente "],"shared_with":["%s"]}`, sharedID.Hex())
	req := httptest.NewRequest(http.MethodPost, "/pages", strings.NewReader(body))
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()

	handler.CreatePage(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var result pages.PageCreateResponse
	json.NewDecoder(rec.Body).Decode(&result)

	if result.ID == "" {
		t.Fatal("expected non-empty page ID")
	}
	defer repo.Delete(context.Background(), mustObjectID(result.ID))

	if len(result.Tags) != 2 || result.Tags[0] != "trabalho" || result.Tags[1] != "urgente" {
		t.Fatalf("expected normalized tags [trabalho urgente], got %v", result.Tags)
	}
}

func TestHandler_CreatePage_InvalidSharedUser(t *testing.T) {
    repo, cleanup := setupTest(t)
    defer cleanup()

    fakeUsers := fakeUserChecker{count: 0} // simula que nenhum usuário existe
    service := pages.NewService(repo, fakeUsers)
    handler := pages.NewHandler(service)

    userID := bson.NewObjectID()
    fakeSharedID := bson.NewObjectID()

    body := fmt.Sprintf(`{"title":"Teste","shared_with":["%s"]}`, fakeSharedID.Hex())
    req := httptest.NewRequest(http.MethodPost, "/pages", strings.NewReader(body))
    ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
    req = req.WithContext(ctx)
    rec := httptest.NewRecorder()

    handler.CreatePage(rec, req)

    if rec.Code != http.StatusBadRequest {
        t.Fatalf("expected status 400, got %d", rec.Code)
    }
}