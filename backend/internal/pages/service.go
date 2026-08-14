package pages

import (
	"context"
	"errors"
	"slices"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

var (
	ErrInvalidCursor       = errors.New("malformed cursor")
	ErrInvalidSharedUserID = errors.New("invalid user shared id")
)

type UserExistenceChecker interface {
	CountByIDs(ctx context.Context, ids []bson.ObjectID) (int64, error)
}

type Service struct {
	repo  *Repository
	users UserExistenceChecker
}

func NewService(repo *Repository, users UserExistenceChecker) *Service {
	return &Service{repo: repo, users: users}
}

func (s *Service) GetPages(ctx context.Context, userID bson.ObjectID, cursorString string, limit int64) (*PageData, error) {
	var cursor *bson.ObjectID
	if cursorString != "" {
		parsed, err := bson.ObjectIDFromHex(cursorString)
		if err != nil {
			return nil, ErrInvalidCursor
		}
		cursor = &parsed
	}

	pages, total, err := s.repo.FindPages(ctx, userID, cursor, limit)
	if err != nil {
		return nil, err
	}

	metadata := make([]PageMetadata, len(pages))
	for i, p := range pages {
		metadata[i] = PageMetadata{
			ID:             p.ID.Hex(),
			Title:          p.Title,
			Description:    p.Description,
			Tags:           p.Tags,
			Shared:         slices.Contains(p.SharedWith, userID),
			NumberOfBlocks: p.NumberOfBlocks,
			TrashedAt:      p.DeletedAt,
			CreatedAt:      p.CreatedAt,
			UpdatedAt:      p.UpdatedAt,
		}
	}
	var nextCursor string
	if int64(len(pages)) == limit {
		nextCursor = pages[len(pages)-1].ID.Hex()
	}
	return &PageData{Data: metadata, NextCursor: nextCursor, Total: total}, nil
}

func (s *Service) CreatePage(ctx context.Context, ownerID bson.ObjectID, input PageCreateRequest) (*PageCreateResponse, error) {
	normalizedTags := make([]string, 0, len(input.Tags))
	for _, tag := range input.Tags {
		normalized := strings.ToLower(strings.TrimSpace(tag))
		if normalized != "" {
			normalizedTags = append(normalizedTags, normalized)
		}
	}
	seen := make(map[bson.ObjectID]bool)
	sharedWith := make([]bson.ObjectID, 0)
	for _, idStr := range input.SharedWith {
		id, err := bson.ObjectIDFromHex(idStr)
		if err != nil {
			return nil, ErrInvalidSharedUserID
		}
		if id == ownerID || seen[id] {
			continue
		}
		seen[id] = true
		sharedWith = append(sharedWith, id)
	}
	if len(sharedWith) > 0 {
		count, err := s.users.CountByIDs(ctx, sharedWith)
		if err != nil {
			return nil, err
		}
		if count != int64(len(sharedWith)) {
			return nil, ErrInvalidSharedUserID
		}
	}
	now := time.Now()
	page := Page{
		Title:       input.Title,
		Description: input.Description,
		OwnerID:     ownerID,
		SharedWith:  sharedWith,
		Tags:        normalizedTags,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if err := s.repo.Create(ctx, &page); err != nil {
		return nil, err
	}
	return &PageCreateResponse{
		ID:          page.ID.Hex(),
		Title:       page.Title,
		Description: page.Description,
		Tags:        page.Tags,
		CreatedAt:   page.CreatedAt,
	}, nil
}

