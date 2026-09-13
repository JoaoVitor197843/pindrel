package blocks

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"plany/internal/pages"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

type Service struct {
	repo     *Repository
	pageRepo *pages.Repository
	client   *mongo.Client
}

var (
	ErrPageNotFound             = errors.New("invalid pageID")
	ErrParentBlockInOtherPage   = errors.New("parent block have other page id")
	ErrCannotUpdatePagePosition = errors.New("can't update page position in this method")
)

func NewService(repo *Repository, pageRepo *pages.Repository) *Service {
	return &Service{repo: repo, pageRepo: pageRepo}
}

func (s *Service) CreateBlock(
	ctx context.Context,
	ownerID bson.ObjectID,
	input CreateBlockInput) (*CreateBlockResponse, error) {
	pageID, err := bson.ObjectIDFromHex(input.PageID)
	if err != nil {
		return nil, err
	}
	if err := ValidateContent(input.BlockType, input.Content); err != nil {
		return nil, err
	}
	ok, err := s.pageRepo.CheckPageOwner(ctx, pageID, ownerID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrPageNotFound
	}
	var parentBlockID *bson.ObjectID
	if input.ParentBlockID != nil {
		id, err := bson.ObjectIDFromHex(*input.ParentBlockID)
		if err != nil {
			return nil, err
		}
		parentBlock, err := s.repo.FindByID(ctx, id, pageID)
		if err != nil {
			return nil, err
		}
		if parentBlock.PageID != pageID {
			return nil, ErrParentBlockInOtherPage
		}
		parentBlockID = &id
	}

	var childrens []bson.ObjectID
	var warnings []string
	for _, c := range input.Children {
		child, err := bson.ObjectIDFromHex(c)
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("invalid child id ignored: %s", c))
			continue
		}
		childrens = append(childrens, child)
	}
	childs, err := s.repo.FindByIDs(ctx, childrens)
	if err != nil {
		return nil, err
	}
	seen := make(map[bson.ObjectID]bool)
	for _, c := range childs {
		if c.PageID == pageID {
			seen[c.ID] = true
		} else {
			warnings = append(warnings, fmt.Sprintf("other page child id, ignoring: %s", c.ID.Hex()))
		}
	}
	for _, requested := range childrens {
		if !seen[requested] {
			warnings = append(warnings, fmt.Sprintf("child id not found: %s", requested.Hex()))
		}
	}
	var childrenHex []string
	var validChildren []bson.ObjectID
	for _, c := range childrens {
		if seen[c] {
			childrenHex = append(childrenHex, c.Hex())
			validChildren = append(validChildren, c)
		}
	}
	var content bson.M
	err = json.Unmarshal(input.Content, &content)
	if err != nil {
		return nil, err
	}

	block := &Block{
		PageID:        pageID,
		ParentBlockID: parentBlockID,
		Children:      validChildren,
		PagePosition:  input.PagePosition,
		Type:          input.BlockType,
		Content:       content,
		IsSpoiler:     input.IsSpoiler,
		IsSecure:      input.IsSecure,
	}

	if err := s.repo.Create(ctx, block); err != nil {
		return nil, err
	}
	var parentBlockIDStr string
	if block.ParentBlockID != nil {
		parentBlockIDStr = block.ParentBlockID.Hex()
	}
	contentJSON, err := json.Marshal(block.Content)
	if err != nil {
		return nil, err
	}
	return &CreateBlockResponse{
		PageID:        block.PageID.Hex(),
		ParentBlockID: parentBlockIDStr,
		Children:      childrenHex,
		PagePosition:  block.PagePosition,
		Type:          block.Type,
		Content:       string(contentJSON),
		IsSpoiler:     block.IsSpoiler,
		IsSecure:      block.IsSecure,
		Warnings:      warnings,
	}, nil
}

func (s *Service) GetBlocks(ctx context.Context, ownerID, pageID bson.ObjectID) ([]Block, error) {
	ok, err := s.pageRepo.CheckPageOwner(ctx, pageID, ownerID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrPageNotFound
	}
	blocks, err := s.repo.FindBlocks(ctx, pageID)
	if err != nil {
		return nil, err
	}
	return blocks, nil
}

func (s *Service) DeleteBlock(ctx context.Context, blockID, ownerID, pageID bson.ObjectID, deleteIn *time.Duration) error {
	ok, err := s.pageRepo.CheckPageOwner(ctx, pageID, ownerID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrPageNotFound
	}
	session, err := s.client.StartSession()
	if err != nil {
		return err
	}
	defer session.EndSession(ctx)
	_, err = session.WithTransaction(ctx, func(sessCtx context.Context) (interface{}, error) {
		block, err := s.repo.FindByID(sessCtx, blockID, pageID)
		if err != nil {
			return nil, err
		}

		if deleteIn == nil {
			err = s.repo.DeleteBlock(sessCtx, pageID, blockID)
		} else {
			err = s.repo.UpdateFields(sessCtx, blockID, pageID, bson.M{
				"deleted_at": time.Now(),
				"expire_at": time.Now().Add(*deleteIn),
			})
		}
		if err != nil {
			return nil, err
		}
		err = s.repo.DecrementPositionsAfter(sessCtx, pageID, block.PagePosition)
		if err != nil {
			return nil, err
		}
		return nil, nil
	})
	
	return err
}
