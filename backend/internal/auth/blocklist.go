package auth

import (
	"context"
	"errors"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type RevokedToken struct {
	JTI       string    `bson:"jti"`
	ExpiresAt time.Time `bson:"expires_at"`
}

type BlocklistRepository struct {
	collection *mongo.Collection
}

func NewBlocklistRepository(ctx context.Context, db *mongo.Database) (*BlocklistRepository, error) {
	collection := db.Collection("revoked_tokens")

	indexModel := mongo.IndexModel{
		Keys: bson.M{"expires_at": 1},
		Options: options.Index().SetExpireAfterSeconds(0),
	}

	_, err := collection.Indexes().CreateOne(ctx, indexModel)
	if err != nil {
		return nil, err
	}
	return &BlocklistRepository{collection: collection}, nil
}

func (b *BlocklistRepository) Revoke(ctx context.Context, jti string, expiresAt time.Time) error {
	_, err := b.collection.InsertOne(ctx, RevokedToken{JTI: jti, ExpiresAt: expiresAt})
	return err
}
func (b *BlocklistRepository) IsRevoked(ctx context.Context, jti string) (bool, error) {
	var revoked RevokedToken
	err := b.collection.FindOne(ctx, bson.M{"jti": jti}).Decode(&revoked)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}