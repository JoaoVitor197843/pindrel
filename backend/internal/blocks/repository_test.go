package blocks_test

import (
	"context"
	"testing"

	"plany/internal/blocks"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestRepository_Create_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "hello"},
	}

	err := repo.Create(context.Background(), block)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if block.ID.IsZero() {
		t.Fatal("expected block.ID to be set after Create")
	}

	defer repo.DeleteBlock(context.Background(), pageID, block.ID)
}

func TestRepository_FindBlocks_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "hello"},
	}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, block.ID)

	found, err := repo.FindBlocks(context.Background(), pageID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected 1 block, got %d", len(found))
	}
	if found[0].ID != block.ID {
		t.Fatalf("expected block ID %v, got %v", block.ID, found[0].ID)
	}
}

func TestRepository_FindByID_NotFound(t *testing.T) {
	repo, _, _, cleanup := setupTest(t)
	defer cleanup()

	_, err := repo.FindByID(context.Background(), bson.NewObjectID())
	if err == nil {
		t.Fatal("expected error for non-existent block, got nil")
	}
}

func TestRepository_FindByIDs_PartialMatch(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "hello"},
	}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, block.ID)

	// Pede o ID real + um ID que não existe no banco.
	ids := []bson.ObjectID{block.ID, bson.NewObjectID()}
	found, err := repo.FindByIDs(context.Background(), ids)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected 1 block found (the real one), got %d", len(found))
	}
}

func TestRepository_DeleteBlock_WrongPage(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	otherPageID := bson.NewObjectID()

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "hello"},
	}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, block.ID)

	err := repo.DeleteBlock(context.Background(), otherPageID, block.ID)
	if err != blocks.ErrBlockNotFound {
		t.Fatalf("expected ErrBlockNotFound, got %v", err)
	}
}

func TestRepository_DeletePageBlocks_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	for i := range 3 {
		block := &blocks.Block{
			PageID:       pageID,
			PagePosition: i,
			Type:         "text",
			Content:      bson.M{"text": "hello"},
		}
		if err := repo.Create(context.Background(), block); err != nil {
			t.Fatalf("failed to create block: %v", err)
		}
	}

	if err := repo.DeletePageBlocks(context.Background(), pageID); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	found, err := repo.FindBlocks(context.Background(), pageID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 0 {
		t.Fatalf("expected 0 blocks after DeletePageBlocks, got %d", len(found))
	}
}

func TestRepository_FindByID_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "code",
		Content:      bson.M{"language": "go", "code": "package main"},
		IsSecure:     true,
		IsSpoiler:    true,
	}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, block.ID)

	found, err := repo.FindByID(context.Background(), block.ID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if found.ID != block.ID {
		t.Fatalf("expected id %v, got %v", block.ID, found.ID)
	}
	if found.PageID != pageID {
		t.Fatalf("expected page_id %v, got %v", pageID, found.PageID)
	}
	if found.Type != "code" {
		t.Fatalf("expected type 'code', got %q", found.Type)
	}

	if !found.IsSecure || !found.IsSpoiler {
		t.Fatalf("expected IsSecure and IsSpoiler true, got %v/%v", found.IsSecure, found.IsSpoiler)
	}
	if found.Content["language"] != "go" {
		t.Fatalf("expected content.language 'go', got %v", found.Content["language"])
	}
}

func TestRepository_DeleteBlock_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	block := &blocks.Block{
		PageID:       pageID,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "delete me"},
	}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	if err := repo.DeleteBlock(context.Background(), pageID, block.ID); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	// Confirma que sumiu de verdade.
	if _, err := repo.FindByID(context.Background(), block.ID); err == nil {
		t.Fatal("expected block to be gone after delete")
	}
}

func TestRepository_DeleteBlock_NonExistent(t *testing.T) {
	repo, _, _, cleanup := setupTest(t)
	defer cleanup()

	err := repo.DeleteBlock(context.Background(), bson.NewObjectID(), bson.NewObjectID())
	if err != blocks.ErrBlockNotFound {
		t.Fatalf("expected ErrBlockNotFound, got %v", err)
	}
}

func TestRepository_FindBlocks_EmptyPage(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	found, err := repo.FindBlocks(context.Background(), pageID)
	if err != nil {
		t.Fatalf("expected no error for empty page, got %v", err)
	}
	if len(found) != 0 {
		t.Fatalf("expected 0 blocks, got %d", len(found))
	}
}

func TestRepository_FindBlocks_OnlyOwnPage(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)

	blockA := &blocks.Block{PageID: pageA, Type: "text", Content: bson.M{"text": "a"}}
	blockB := &blocks.Block{PageID: pageB, Type: "text", Content: bson.M{"text": "b"}}
	if err := repo.Create(context.Background(), blockA); err != nil {
		t.Fatalf("failed to create blockA: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageA, blockA.ID)
	if err := repo.Create(context.Background(), blockB); err != nil {
		t.Fatalf("failed to create blockB: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageB, blockB.ID)

	found, err := repo.FindBlocks(context.Background(), pageA)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected 1 block for pageA, got %d", len(found))
	}
	if found[0].ID != blockA.ID {
		t.Fatal("FindBlocks returned a block from the wrong page")
	}
}

func TestRepository_FindByIDs_EmptyInput(t *testing.T) {
	repo, _, _, cleanup := setupTest(t)
	defer cleanup()

	found, err := repo.FindByIDs(context.Background(), nil)
	if err != nil {
		t.Fatalf("expected no error for empty ids, got %v", err)
	}
	if len(found) != 0 {
		t.Fatalf("expected 0 blocks, got %d", len(found))
	}
}

func TestRepository_FindByIDs_AllFound(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	var ids []bson.ObjectID
	for i := range 3 {
		b := &blocks.Block{PageID: pageID, PagePosition: i, Type: "text", Content: bson.M{"text": "x"}}
		if err := repo.Create(context.Background(), b); err != nil {
			t.Fatalf("failed to create block: %v", err)
		}
		defer repo.DeleteBlock(context.Background(), pageID, b.ID)
		ids = append(ids, b.ID)
	}

	found, err := repo.FindByIDs(context.Background(), ids)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 3 {
		t.Fatalf("expected 3 blocks, got %d", len(found))
	}
}

func TestRepository_DeletePageBlocks_EmptyPage(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	if err := repo.DeletePageBlocks(context.Background(), pageID); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestRepository_DeletePageBlocks_DoesNotTouchOtherPages(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)

	blockA := &blocks.Block{PageID: pageA, Type: "text", Content: bson.M{"text": "a"}}
	blockB := &blocks.Block{PageID: pageB, Type: "text", Content: bson.M{"text": "b"}}
	if err := repo.Create(context.Background(), blockA); err != nil {
		t.Fatalf("failed to create blockA: %v", err)
	}
	if err := repo.Create(context.Background(), blockB); err != nil {
		t.Fatalf("failed to create blockB: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageB, blockB.ID)

	if err := repo.DeletePageBlocks(context.Background(), pageA); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	found, err := repo.FindBlocks(context.Background(), pageB)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected pageB to still have 1 block, got %d", len(found))
	}
}

