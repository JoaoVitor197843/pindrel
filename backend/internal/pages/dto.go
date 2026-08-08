package pages

import "time"

type PageData struct {
	Data       []PageMetadata `json:"data"`
	NextCursor string         `json:"next_cursor"`
	Total      int64          `json:"total"`
}

type PageMetadata struct {
	ID             string     `json:"id"`
	Title          string     `json:"title"`
	Description    string     `json:"description"`
	Tags           []string   `json:"tags"`
	Shared         bool       `json:"shared"`
	NumberOfBlocks int        `json:"number_of_blocks"`
	TrashedAt      *time.Time `json:"trashed_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type PageCreateRequest struct {
	Title       string   `json:"title" validate:"required"`
	Description string   `json:"description"`
	Tags      []string `json:"tags"`
	SharedWith  []string `json:"shared_with"`
}

type PageCreateResponse struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Tags        []string  `json:"tags"`
	CreatedAt   time.Time `json:"created_at"`
}
