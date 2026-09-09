package blocks_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"plany/internal/blocks"
	contextkeys "plany/pkg/context"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func newRequest(body string, userID bson.ObjectID) (*http.Request, *httptest.ResponseRecorder) {
	req := httptest.NewRequest(http.MethodPost, "/blocks", strings.NewReader(body))
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
	req = req.WithContext(ctx)
	return req, httptest.NewRecorder()
}

func TestHandler_CreateBlock_Success(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"text","content":{"text":"hello"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var result blocks.CreateBlockResponse
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.PageID != pageID.Hex() {
		t.Fatalf("expected page_id %s, got %s", pageID.Hex(), result.PageID)
	}
	if result.Type != "text" {
		t.Fatalf("expected type 'text', got %q", result.Type)
	}
	if len(result.Warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", result.Warnings)
	}
}

func TestHandler_CreateBlock_PositionZero(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":0,"block_type":"text","content":{"text":"first block"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("position 0 should be valid (it's the first block of a page), got %d: %s",
			rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_NoUserInContext(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	req := httptest.NewRequest(http.MethodPost, "/blocks", strings.NewReader(`{}`))
	rec := httptest.NewRecorder()

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestHandler_CreateBlock_InvalidUserIDInContext(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	req := httptest.NewRequest(http.MethodPost, "/blocks", strings.NewReader(`{}`))
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, "not-a-valid-object-id")
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}

func TestHandler_CreateBlock_MalformedBody(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	req, rec := newRequest(`{"page_id": broken json`, bson.NewObjectID())

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_CreateBlock_MissingRequiredFields(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	req, rec := newRequest(`{"page_position":1}`, bson.NewObjectID())

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_CreateBlock_PageNotOwned(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	realOwner := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, realOwner)

	attacker := bson.NewObjectID()
	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"text","content":{"text":"x"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, attacker)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_ParentInOtherPage(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageA)
	cleanupPageBlocks(t, repo, pageB)

	parent := &blocks.Block{PageID: pageB, Type: "text", Content: bson.M{"text": "parent"}}
	if err := repo.Create(context.Background(), parent); err != nil {
		t.Fatalf("failed to create parent: %v", err)
	}

	body := fmt.Sprintf(
		`{"page_id":"%s","parent_block_id":"%s","page_position":1,"block_type":"text","content":{"text":"x"}}`,
		pageA.Hex(), parent.ID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_InvalidBlockType(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"carousel","content":{"text":"x"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_InvalidContentForType(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"code","content":{"text":"x"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_TableWithMismatchedRow(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"table","content":{"columns":["a","b"],"rows":[["1","2","3"]]}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestHandler_CreateBlock_WarningsInResponse(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	body := fmt.Sprintf(
		`{"page_id":"%s","children":["garbage"],"page_position":1,"block_type":"text","content":{"text":"x"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201 (child inválido é warning, não erro), got %d: %s",
			rec.Code, rec.Body.String())
	}

	var result blocks.CreateBlockResponse
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(result.Warnings) == 0 {
		t.Fatal("expected warnings in response body")
	}
}

func TestHandler_CreateBlock_ContentTypeHeader(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	handler := blocks.NewHandler(service)

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	body := fmt.Sprintf(
		`{"page_id":"%s","page_position":1,"block_type":"text","content":{"text":"x"}}`,
		pageID.Hex(),
	)
	req, rec := newRequest(body, ownerID)

	handler.CreateBlock(rec, req)

	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("expected Content-Type application/json, got %q", ct)
	}
}

func newGetBlocksRequest(pageIDString string, userID bson.ObjectID) (*http.Request, *httptest.ResponseRecorder) {
	req := httptest.NewRequest(http.MethodGet, "/pages/"+pageIDString+"/blocks", nil)
	req.SetPathValue("page_id", pageIDString)
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, userID.Hex())
	req = req.WithContext(ctx)
	return req, httptest.NewRecorder()
}
 
func TestHandler_GetBlocks_Success(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
 
	b1 := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	b2 := &blocks.Block{PageID: pageID, PagePosition: 1, Type: "text", Content: bson.M{"text": "two"}}
	if err := repo.Create(context.Background(), b1); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	if err := repo.Create(context.Background(), b2); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
 
	req, rec := newGetBlocksRequest(pageID.Hex(), ownerID)
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d: %s", rec.Code, rec.Body.String())
	}
 
	var result []blocks.Block
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 blocks, got %d", len(result))
	}
}
 
func TestHandler_GetBlocks_EmptyPage(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
 
	req, rec := newGetBlocksRequest(pageID.Hex(), ownerID)
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200 for a page with no blocks, got %d: %s", rec.Code, rec.Body.String())
	}
 
	var result []blocks.Block
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(result) != 0 {
		t.Fatalf("expected 0 blocks, got %d", len(result))
	}
}
 
func TestHandler_GetBlocks_NoUserInContext(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	req := httptest.NewRequest(http.MethodGet, "/pages/"+bson.NewObjectID().Hex()+"/blocks", nil)
	req.SetPathValue("page_id", bson.NewObjectID().Hex())
	rec := httptest.NewRecorder()
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}
 
func TestHandler_GetBlocks_InvalidUserIDInContext(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	req := httptest.NewRequest(http.MethodGet, "/pages/"+bson.NewObjectID().Hex()+"/blocks", nil)
	req.SetPathValue("page_id", bson.NewObjectID().Hex())
	ctx := context.WithValue(req.Context(), contextkeys.UserIDKey, "not-a-valid-object-id")
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d", rec.Code)
	}
}
 
func TestHandler_GetBlocks_InvalidPageID(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	req, rec := newGetBlocksRequest("not-a-valid-object-id", bson.NewObjectID())
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d: %s", rec.Code, rec.Body.String())
	}
}
 
func TestHandler_GetBlocks_EmptyPageIDInPath(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	req, rec := newGetBlocksRequest("", bson.NewObjectID())
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for empty page id, got %d: %s", rec.Code, rec.Body.String())
	}
}
 
func TestHandler_GetBlocks_PageNotOwned(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	realOwner := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, realOwner)
 
	attacker := bson.NewObjectID()
	req, rec := newGetBlocksRequest(pageID.Hex(), attacker)
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d: %s", rec.Code, rec.Body.String())
	}
}
 
func TestHandler_GetBlocks_NonExistentPage(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	req, rec := newGetBlocksRequest(bson.NewObjectID().Hex(), bson.NewObjectID())
 
	handler.GetBlocks(rec, req)
 
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d: %s", rec.Code, rec.Body.String())
	}
}
 
func TestHandler_GetBlocks_ContentTypeHeader(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	handler := blocks.NewHandler(service)
 
	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
 
	req, rec := newGetBlocksRequest(pageID.Hex(), ownerID)
 
	handler.GetBlocks(rec, req)
 
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("expected Content-Type application/json, got %q", ct)
	}
}
