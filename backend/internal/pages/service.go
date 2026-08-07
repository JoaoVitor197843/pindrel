package pages

import (
	"context"
	"errors"

	"go.mongodb.org/mongo-driver/v2/bson"
)

var (
	ErrInvalidCursor = errors.New("malformed cursor")
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
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
			Shared:         len(p.SharedWith) > 0,
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
