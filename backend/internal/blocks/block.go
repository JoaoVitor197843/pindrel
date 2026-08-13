// Package blocks define os blocos de conteúdo das páginas do Plany.
package blocks

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

type Block struct {
	ID            bson.ObjectID   `bson:"_id,omitempty"`
	PageID        bson.ObjectID   `bson:"page_id"`
	ParentBlockID *bson.ObjectID  `bson:"parent_block_id"`
	PagePosition  int             `bson:"page_position"`
	Children      []bson.ObjectID `bson:"children"`
	Type          string          `bson:"type"`
	Content       bson.M          `bson:"content"`
	IsSecure      bool            `bson:"is_secure"`
	IsSpoiler     bool            `bson:"is_spoiler"`
	IsDeleted     bool            `bson:"is_deleted"`
	DeletedAt     *time.Time      `bson:"deleted_at, omitempty"`
	ExpireAt      *time.Time      `bson:"expire_at"`
}
