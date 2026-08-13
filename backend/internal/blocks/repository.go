package blocks

import (
	"context"
	"errors"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type Repository struct {
	collection *mongo.Collection
}

func NewRepository(ctx context.Context, db mongo.Database) (*Repository, error) {
	collection := db.Collection("block")
	indexModel := []mongo.IndexModel{
		{Keys: bson.D{{Key: "page_id", Value: 1}, {Key: "page_position", Value: 1}}},
		{
			Keys:    bson.D{{Key: "expire_at", Value: 1}},
			Options: options.Index().SetExpireAfterSeconds(0),
		},
	}
	_, err := collection.Indexes().CreateMany(ctx, indexModel)
	if err != nil {
		return nil, err
	}
	return &Repository{collection: collection}, nil
}

func (r *Repository) Create(ctx context.Context, block *Block) error {
	result, err := r.collection.InsertOne(ctx, block)
	if err != nil {
		return err
	}
	block.ID = result.InsertedID.(bson.ObjectID)
	return nil
}

var (
	ErrBlockNotFound = errors.New("block not found")
)

func (r *Repository) FindBlocks(ctx context.Context, PageID bson.ObjectID) ([]Block, error) {
	filter := bson.M{"page_id": PageID}
	cursor, err := r.collection.Find(ctx, filter)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)
	var blocks []Block
	for cursor.Next(ctx) {
		var block Block
		if err := cursor.Decode(&block); err != nil {
			return nil, err
		}
		blocks = append(blocks, block)
	}
	return blocks, nil
}

func (r *Repository) DeleteBlock(ctx context.Context, pageID, blockID bson.ObjectID) error {
	result, err := r.collection.DeleteOne(ctx, bson.M{"_id": blockID, "page_id": pageID})
	if err != nil {
		return err
	}
	if result.DeletedCount == 0 {
		return ErrBlockNotFound
	}
	return nil
}

func (r *Repository) DeletePageBlocks(ctx context.Context, pageID bson.ObjectID) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"page_id": pageID})
	return err
}
