package blocks

import "encoding/json"

type CreateBlockInput struct {
	PageID        string          `json:"page_id" validate:"required"`
	ParentBlockID *string         `json:"parent_block_id"`
	Children      []string        `json:"children"`
	PagePosition  int             `json:"page_position" validate:"required"`
	BlockType     string          `json:"block_type" validate:"required"`
	Content       json.RawMessage `json:"content"`
	IsSpoiler     bool            `json:"is_spoiler"`
	IsSecure      bool            `json:"is_secure"`
}

type CreateBlockResponse struct {
	PageID        string   `json:"page_id"`
	ParentBlockID string   `json:"parent_block_id"`
	Children      []string `json:"children"`
	PagePosition  int      `json:"page_position"`
	Type          string   `json:"type"`
	Content       string   `json:"content"`
	IsSpoiler     bool     `json:"is_spoiler"`
	IsSecure      bool     `json:"is_secure"`
	Warnings      []string `json:"warnings,omitempty"`
}
