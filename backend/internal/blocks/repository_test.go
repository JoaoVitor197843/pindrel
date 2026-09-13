package blocks_test

import (
	"context"
	"errors"
	"testing"
	"time"

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

	_, err := repo.FindByID(context.Background(), bson.NewObjectID(), bson.NewObjectID())
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

	found, err := repo.FindByID(context.Background(), block.ID, pageID)
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

func TestRepository_DeleteBlockPermanent_Success(t *testing.T) {
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
	if _, err := repo.FindByID(context.Background(), block.ID, pageID); err == nil {
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

func TestRepository_DeleteBlock_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	block := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	err := repo.DeleteBlock(context.Background(), pageID, block.ID)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	_, err = repo.FindByID(context.Background(), block.ID, pageID)
	if err == nil {
		t.Fatalf("expected block to be gone, but it was found")
	}
}

func TestRepository_DeleteBlock_NotFound(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	err := repo.DeleteBlock(context.Background(), pageID, bson.NewObjectID())
	if !errors.Is(err, blocks.ErrBlockNotFound) {
		t.Fatalf("expected ErrBlockNotFound, got: %v", err)
	}
}

func TestRepository_DeleteBlock_WrongPageID(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	otherPageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	cleanupPageBlocks(t, repo, otherPageID)

	block := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	// tenta deletar passando o pageID errado
	err := repo.DeleteBlock(context.Background(), otherPageID, block.ID)
	if !errors.Is(err, blocks.ErrBlockNotFound) {
		t.Fatalf("expected ErrBlockNotFound, got: %v", err)
	}

	// confirma que o bloco não foi afetado
	stillThere, err := repo.FindByID(context.Background(), block.ID, pageID)
	if err != nil {
		t.Fatalf("expected block to still exist, got err: %v", err)
	}
	if stillThere == nil {
		t.Fatalf("expected block to still exist")
	}
}

func TestRepository_UpdateFields_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	block := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	deletedAt := time.Now()
	expireAt := deletedAt.Add(24 * time.Hour)

	err := repo.UpdateFields(context.Background(), block.ID, pageID, bson.M{
		"deleted_at": deletedAt,
		"expire_at":  expireAt,
	})
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	found, err := repo.FindByIDs(context.Background(), []bson.ObjectID{block.ID})
	if err != nil {
		t.Fatalf("failed to fetch block: %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected 1 block, got %d", len(found))
	}
	if found[0].DeletedAt == nil {
		t.Fatalf("expected DeletedAt to be set")
	}
	if found[0].ExpireAt == nil {
		t.Fatalf("expected ExpireAt to be set")
	}
}

func TestRepository_UpdateFields_RejectsPagePosition(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	block := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	err := repo.UpdateFields(context.Background(), block.ID, pageID, bson.M{"page_position": 5})
	if !errors.Is(err, blocks.ErrCannotUpdatePagePosition) {
		t.Fatalf("expected ErrCannotUpdatePagePosition, got: %v", err)
	}

	// confirma que a posição não mudou
	found, err := repo.FindByID(context.Background(), block.ID, pageID)
	if err != nil {
		t.Fatalf("failed to fetch block: %v", err)
	}
	if found.PagePosition != 0 {
		t.Fatalf("expected PagePosition to remain 0, got %d", found.PagePosition)
	}
}

func TestRepository_UpdateFields_NotFound(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	err := repo.UpdateFields(context.Background(), bson.NewObjectID(), pageID, bson.M{"is_spoiler": true})
	if !errors.Is(err, blocks.ErrBlockNotFound) {
		t.Fatalf("expected ErrBlockNotFound, got: %v", err)
	}
}

func TestRepository_UpdateFields_WrongPageID(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	otherPageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	cleanupPageBlocks(t, repo, otherPageID)

	block := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "one"}}
	if err := repo.Create(context.Background(), block); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}

	err := repo.UpdateFields(context.Background(), block.ID, otherPageID, bson.M{"is_spoiler": true})
	if !errors.Is(err, blocks.ErrBlockNotFound) {
		t.Fatalf("expected ErrBlockNotFound, got: %v", err)
	}
}

func TestRepository_DecrementPositionsAfter_Success(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	b0 := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "zero"}}
	b1 := &blocks.Block{PageID: pageID, PagePosition: 1, Type: "text", Content: bson.M{"text": "one"}}
	b2 := &blocks.Block{PageID: pageID, PagePosition: 2, Type: "text", Content: bson.M{"text": "two"}}

	for _, b := range []*blocks.Block{b0, b1, b2} {
		if err := repo.Create(context.Background(), b); err != nil {
			t.Fatalf("failed to create block: %v", err)
		}
	}

	// simula que o bloco na posição 0 foi removido: decrementa quem vem depois
	err := repo.DecrementPositionsAfter(context.Background(), pageID, 0)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	got1, err := repo.FindByID(context.Background(), b1.ID, pageID)
	if err != nil {
		t.Fatalf("failed to fetch b1: %v", err)
	}
	if got1.PagePosition != 0 {
		t.Fatalf("expected b1.PagePosition to become 0, got %d", got1.PagePosition)
	}

	got2, err := repo.FindByID(context.Background(), b2.ID, pageID)
	if err != nil {
		t.Fatalf("failed to fetch b2: %v", err)
	}
	if got2.PagePosition != 1 {
		t.Fatalf("expected b2.PagePosition to become 1, got %d", got2.PagePosition)
	}
}

func TestRepository_DecrementPositionsAfter_DoesNotTouchEarlierPositions(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	b0 := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "zero"}}
	b1 := &blocks.Block{PageID: pageID, PagePosition: 1, Type: "text", Content: bson.M{"text": "one"}}

	for _, b := range []*blocks.Block{b0, b1} {
		if err := repo.Create(context.Background(), b); err != nil {
			t.Fatalf("failed to create block: %v", err)
		}
	}

	// remove o bloco na posição 1 (o último) — b0 não deveria ser afetado
	err := repo.DecrementPositionsAfter(context.Background(), pageID, 1)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	got0, err := repo.FindByID(context.Background(), b0.ID, pageID)
	if err != nil {
		t.Fatalf("failed to fetch b0: %v", err)
	}
	if got0.PagePosition != 0 {
		t.Fatalf("expected b0.PagePosition to remain 0, got %d", got0.PagePosition)
	}
}

func TestRepository_DecrementPositionsAfter_SkipsSoftDeletedBlocks(t *testing.T) {
	repo, _, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)

	b0 := &blocks.Block{PageID: pageID, PagePosition: 0, Type: "text", Content: bson.M{"text": "zero"}}
	b1 := &blocks.Block{PageID: pageID, PagePosition: 1, Type: "text", Content: bson.M{"text": "one"}}

	for _, b := range []*blocks.Block{b0, b1} {
		if err := repo.Create(context.Background(), b); err != nil {
			t.Fatalf("failed to create block: %v", err)
		}
	}

	// soft-deleta b1 manualmente, direto via UpdateFields
	deletedAt := time.Now()
	if err := repo.UpdateFields(context.Background(), b1.ID, pageID, bson.M{"deleted_at": deletedAt}); err != nil {
		t.Fatalf("failed to soft delete b1: %v", err)
	}

	// decrementa a partir da posição -1 (ou seja, todo mundo qualificaria por posição,
	// mas b1 já está soft-deletado e não deveria ser tocado)
	err := repo.DecrementPositionsAfter(context.Background(), pageID, -1)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	found, err := repo.FindByIDs(context.Background(), []bson.ObjectID{b1.ID})
	if err != nil {
		t.Fatalf("failed to fetch b1 raw: %v", err)
	}
	if len(found) != 1 {
		t.Fatalf("expected 1 block, got %d", len(found))
	}
	if found[0].PagePosition != 1 {
		t.Fatalf("expected soft-deleted b1.PagePosition to remain untouched at 1, got %d", found[0].PagePosition)
	}
}
