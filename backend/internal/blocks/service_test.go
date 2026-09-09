package blocks_test

import (
	"context"
	"encoding/json"
	"testing"

	"plany/internal/blocks"

	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestService_CreateBlock_Success(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"hello world"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.PageID != pageID.Hex() {
		t.Fatalf("expected page_id %s, got %s", pageID.Hex(), resp.PageID)
	}
	if resp.ParentBlockID != "" {
		t.Fatalf("expected empty parent_block_id, got %s", resp.ParentBlockID)
	}
	if len(resp.Warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", resp.Warnings)
	}
}

func TestService_CreateBlock_PageNotOwnedByCaller(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	realOwnerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, realOwnerID)

	attackerID := bson.NewObjectID()

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"hello"}`),
	}

	_, err := service.CreateBlock(context.Background(), attackerID, input)
	if err != blocks.ErrPageNotFound {
		t.Fatalf("expected ErrPageNotFound, got %v", err)
	}
}

func TestService_CreateBlock_InvalidPageID(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()

	input := blocks.CreateBlockInput{
		PageID:       "not-a-valid-object-id",
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"hello"}`),
	}

	_, err := service.CreateBlock(context.Background(), bson.NewObjectID(), input)
	if err == nil {
		t.Fatal("expected error for invalid page id, got nil")
	}
}

func TestService_CreateBlock_ParentInOtherPage(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)

	parentBlock := &blocks.Block{
		PageID:       pageB,
		PagePosition: 0,
		Type:         "text",
		Content:      bson.M{"text": "parent"},
	}
	if err := repo.Create(context.Background(), parentBlock); err != nil {
		t.Fatalf("failed to create parent block: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageB, parentBlock.ID)

	parentIDHex := parentBlock.ID.Hex()
	input := blocks.CreateBlockInput{
		PageID:        pageA.Hex(),
		ParentBlockID: &parentIDHex,
		PagePosition:  0,
		BlockType:     "text",
		Content:       json.RawMessage(`{"text":"child"}`),
	}

	_, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != blocks.ErrParentBlockInOtherPage {
		t.Fatalf("expected ErrParentBlockInOtherPage, got %v", err)
	}
}

func TestService_CreateBlock_InvalidChildIDGeneratesWarning(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		Children:     []string{"not-a-valid-id"},
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"hello"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error (invalid child should warn, not fail), got %v", err)
	}
	if len(resp.Warnings) == 0 {
		t.Fatal("expected at least one warning for invalid child id")
	}
	if len(resp.Children) != 0 {
		t.Fatalf("expected 0 children in response, got %d", len(resp.Children))
	}
}

func TestService_CreateBlock_NonExistentChildGeneratesWarning(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	nonExistentID := bson.NewObjectID().Hex()
	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		Children:     []string{nonExistentID},
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"hello"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(resp.Warnings) == 0 {
		t.Fatal("expected a warning for non-existent child id")
	}
	if len(resp.Children) != 0 {
		t.Fatalf("expected 0 children in response, got %d", len(resp.Children))
	}
}

func TestService_CreateBlock_InvalidContentJSON(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{not valid json`),
	}

	_, err := service.CreateBlock(context.Background(), ownerID, input)
	if err == nil {
		t.Fatal("expected error for malformed content JSON, got nil")
	}
}

func TestService_CreateBlock_WithValidParent(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	parent := &blocks.Block{PageID: pageID, Type: "text", Content: bson.M{"text": "parent"}}
	if err := repo.Create(context.Background(), parent); err != nil {
		t.Fatalf("failed to create parent: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, parent.ID)

	parentHex := parent.ID.Hex()
	input := blocks.CreateBlockInput{
		PageID:        pageID.Hex(),
		ParentBlockID: &parentHex,
		PagePosition:  1,
		BlockType:     "text",
		Content:       json.RawMessage(`{"text":"child"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if resp.ParentBlockID != parentHex {
		t.Fatalf("expected parent_block_id %s, got %s", parentHex, resp.ParentBlockID)
	}
	if len(resp.Warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", resp.Warnings)
	}
}

func TestService_CreateBlock_InvalidParentHex(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	badParent := "definitely-not-hex"
	input := blocks.CreateBlockInput{
		PageID:        pageID.Hex(),
		ParentBlockID: &badParent,
		PagePosition:  0,
		BlockType:     "text",
		Content:       json.RawMessage(`{"text":"x"}`),
	}

	if _, err := service.CreateBlock(context.Background(), ownerID, input); err == nil {
		t.Fatal("expected error for malformed parent id, got nil")
	}
}

func TestService_CreateBlock_NonExistentParent(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	ghostParent := bson.NewObjectID().Hex()
	input := blocks.CreateBlockInput{
		PageID:        pageID.Hex(),
		ParentBlockID: &ghostParent,
		PagePosition:  0,
		BlockType:     "text",
		Content:       json.RawMessage(`{"text":"x"}`),
	}

	if _, err := service.CreateBlock(context.Background(), ownerID, input); err == nil {
		t.Fatal("expected error for non-existent parent, got nil")
	}
}

func TestService_CreateBlock_WithValidChildren(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	var childHexes []string
	for i := range 2 {
		c := &blocks.Block{PageID: pageID, PagePosition: i, Type: "text", Content: bson.M{"text": "c"}}
		if err := repo.Create(context.Background(), c); err != nil {
			t.Fatalf("failed to create child: %v", err)
		}
		defer repo.DeleteBlock(context.Background(), pageID, c.ID)
		childHexes = append(childHexes, c.ID.Hex())
	}

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		Children:     childHexes,
		PagePosition: 5,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"parent of two"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(resp.Warnings) != 0 {
		t.Fatalf("expected no warnings, got %v", resp.Warnings)
	}
	if len(resp.Children) != 2 {
		t.Fatalf("expected 2 children, got %d", len(resp.Children))
	}
}

func TestService_CreateBlock_ChildFromOtherPageGeneratesWarning(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageA)
	cleanupPageBlocks(t, repo, pageB)
	foreign := &blocks.Block{PageID: pageB, Type: "text", Content: bson.M{"text": "foreign"}}
	if err := repo.Create(context.Background(), foreign); err != nil {
		t.Fatalf("failed to create foreign child: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageB, foreign.ID)

	input := blocks.CreateBlockInput{
		PageID:       pageA.Hex(),
		Children:     []string{foreign.ID.Hex()},
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"x"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(resp.Warnings) == 0 {
		t.Fatal("expected warning for child from another page")
	}
	if len(resp.Children) != 0 {
		t.Fatalf("expected child from other page to be rejected, got %d children", len(resp.Children))
	}
}

func TestService_CreateBlock_MixedValidAndInvalidChildren(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	good := &blocks.Block{PageID: pageID, Type: "text", Content: bson.M{"text": "good"}}
	if err := repo.Create(context.Background(), good); err != nil {
		t.Fatalf("failed to create child: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, good.ID)

	input := blocks.CreateBlockInput{
		PageID: pageID.Hex(),
		Children: []string{
			good.ID.Hex(),
			"garbage",
			bson.NewObjectID().Hex(),
		},
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"x"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(resp.Children) != 1 {
		t.Fatalf("expected only the 1 valid child, got %d", len(resp.Children))
	}
	if resp.Children[0] != good.ID.Hex() {
		t.Fatalf("expected child %s, got %s", good.ID.Hex(), resp.Children[0])
	}
	if len(resp.Warnings) != 2 {
		t.Fatalf("expected 2 warnings (invalid hex + not found), got %d: %v", len(resp.Warnings), resp.Warnings)
	}
}

func TestService_CreateBlock_PersistsFilteredChildren(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	good := &blocks.Block{PageID: pageID, Type: "text", Content: bson.M{"text": "good"}}
	if err := repo.Create(context.Background(), good); err != nil {
		t.Fatalf("failed to create child: %v", err)
	}
	defer repo.DeleteBlock(context.Background(), pageID, good.ID)

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		Children:     []string{good.ID.Hex(), bson.NewObjectID().Hex()},
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`{"text":"parent"}`),
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	all, err := repo.FindBlocks(context.Background(), pageID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	var created *blocks.Block
	for i := range all {
		if all[i].ID != good.ID {
			created = &all[i]
		}
	}
	if created == nil {
		t.Fatal("could not find the created block in the database")
	}
	defer repo.DeleteBlock(context.Background(), pageID, created.ID)

	if len(created.Children) != len(resp.Children) {
		t.Fatalf("db has %d children but response reported %d — inconsistent",
			len(created.Children), len(resp.Children))
	}
	if len(created.Children) != 1 || created.Children[0] != good.ID {
		t.Fatalf("expected only the valid child persisted, got %v", created.Children)
	}
}

func TestService_CreateBlock_PersistsFlagsAndContent(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageID)
	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 3,
		BlockType:    "code",
		Content:      json.RawMessage(`{"language":"go","code":"fmt.Println()"}`),
		IsSecure:     true,
		IsSpoiler:    true,
	}

	resp, err := service.CreateBlock(context.Background(), ownerID, input)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if !resp.IsSecure || !resp.IsSpoiler {
		t.Fatalf("expected flags to be true in response, got %v/%v", resp.IsSecure, resp.IsSpoiler)
	}
	if resp.Type != "code" {
		t.Fatalf("expected type 'code', got %q", resp.Type)
	}

	all, err := repo.FindBlocks(context.Background(), pageID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(all) != 1 {
		t.Fatalf("expected 1 block in db, got %d", len(all))
	}
	defer repo.DeleteBlock(context.Background(), pageID, all[0].ID)

	if !all[0].IsSecure || !all[0].IsSpoiler {
		t.Fatal("flags did not persist to the database")
	}
	if all[0].Content["language"] != "go" {
		t.Fatalf("expected content.language 'go' in db, got %v", all[0].Content["language"])
	}
	if all[0].PagePosition != 3 {
		t.Fatalf("expected page_position 3, got %d", all[0].PagePosition)
	}
	if all[0].IsDeleted {
		t.Fatal("expected IsDeleted false on a newly created block")
	}
}

func TestService_CreateBlock_MissingContent(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 0,
		BlockType:    "text",
	}

	if _, err := service.CreateBlock(context.Background(), ownerID, input); err == nil {
		t.Fatal("expected error for missing content, got nil")
	}
}

func TestService_CreateBlock_ContentNotAnObject(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()

	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)

	input := blocks.CreateBlockInput{
		PageID:       pageID.Hex(),
		PagePosition: 0,
		BlockType:    "text",
		Content:      json.RawMessage(`["not","an","object"]`),
	}

	if _, err := service.CreateBlock(context.Background(), ownerID, input); err == nil {
		t.Fatal("expected error when content is not a JSON object, got nil")
	}
}

func TestService_GetBlocks_Success(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
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
 
	result, err := service.GetBlocks(context.Background(), ownerID, pageID)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 blocks, got %d", len(result))
	}
}
 
func TestService_GetBlocks_EmptyPage(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	ownerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, ownerID)
 
	result, err := service.GetBlocks(context.Background(), ownerID, pageID)
	if err != nil {
		t.Fatalf("expected no error for a page with no blocks, got %v", err)
	}
	if len(result) != 0 {
		t.Fatalf("expected 0 blocks, got %d", len(result))
	}
}
 
func TestService_GetBlocks_PageNotOwnedByCaller(t *testing.T) {
	_, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	realOwnerID := bson.NewObjectID()
	pageID := createTestPage(t, pageRepo, realOwnerID)
 
	attackerID := bson.NewObjectID()
 
	_, err := service.GetBlocks(context.Background(), attackerID, pageID)
	if err != blocks.ErrPageNotFound {
		t.Fatalf("expected ErrPageNotFound, got %v", err)
	}
}
 
func TestService_GetBlocks_NonExistentPage(t *testing.T) {
	_, service, _, cleanup := setupTest(t)
	defer cleanup()
 
	callerID := bson.NewObjectID()
	ghostPageID := bson.NewObjectID()
 
	_, err := service.GetBlocks(context.Background(), callerID, ghostPageID)
	if err != blocks.ErrPageNotFound {
		t.Fatalf("expected ErrPageNotFound, got %v", err)
	}
}
 
func TestService_GetBlocks_OnlyReturnsBlocksForGivenPage(t *testing.T) {
	repo, service, pageRepo, cleanup := setupTest(t)
	defer cleanup()
 
	ownerID := bson.NewObjectID()
	pageA := createTestPage(t, pageRepo, ownerID)
	pageB := createTestPage(t, pageRepo, ownerID)
	cleanupPageBlocks(t, repo, pageA)
	cleanupPageBlocks(t, repo, pageB)
 
	inA := &blocks.Block{PageID: pageA, Type: "text", Content: bson.M{"text": "in a"}}
	inB := &blocks.Block{PageID: pageB, Type: "text", Content: bson.M{"text": "in b"}}
	if err := repo.Create(context.Background(), inA); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
	if err := repo.Create(context.Background(), inB); err != nil {
		t.Fatalf("failed to create block: %v", err)
	}
 
	result, err := service.GetBlocks(context.Background(), ownerID, pageA)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 block scoped to pageA, got %d", len(result))
	}
	if result[0].ID != inA.ID {
		t.Fatalf("expected block %s, got %s", inA.ID.Hex(), result[0].ID.Hex())
	}
}
