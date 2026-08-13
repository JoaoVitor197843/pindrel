// Package pages defines all pages logic
package pages

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

type Page struct {
	ID          bson.ObjectID   `bson:"_id,omitempty"`
	Title       string          `bson:"title"`
	Description string          `bson:"description"`
	OwnerID     bson.ObjectID   `bson:"owner_id"`
	SharedWith  []bson.ObjectID `bson:"shared_with"`
	Tags        []string        `bson:"tags"`
	DeletedAt   *time.Time      `bson:"deleted_at,omitempty"`
	CreatedAt   time.Time       `bson:"created_at"`
	UpdatedAt   time.Time       `bson:"updated_at"`
}

type PageWithBlockCount struct {
	Page           `bson:",inline"`
	NumberOfBlocks int `bson:"number_of_blocks"`
}

