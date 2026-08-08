package pages

import (
	"context"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

type Repository struct {
	collection *mongo.Collection
}

func NewRepository(ctx context.Context, db *mongo.Database) (*Repository, error) {
	collection := db.Collection("pages")

    indexModels := []mongo.IndexModel{
        {Keys: bson.M{"owner_id": 1}},
        {Keys: bson.M{"shared_with": 1}},
    }

    _, err := collection.Indexes().CreateMany(ctx, indexModels)
    if err != nil {
        return nil, err
    }

    return &Repository{collection: collection}, nil
}

func (r *Repository) Create(ctx context.Context, page *Page) error {
	result, err := r.collection.InsertOne(ctx, page)
	if err != nil {
		return err
	}
	page.ID = result.InsertedID.(bson.ObjectID)
	return nil
}

func (r *Repository) FindPages(ctx context.Context, userID bson.ObjectID, cursor *bson.ObjectID, limit int64) ([]PageWithBlockCount, int64, error) {
	filter := bson.M{
		"$or": []bson.M{
			{"owner_id": userID},
			{"shared_with": userID},
		},
		"deleted_at": nil,
	}
	total, err := r.collection.CountDocuments(ctx, filter)
	if err != nil {
		return nil, 0, err
	}
	if cursor != nil {
		filter["_id"] = bson.M{"$gt": *cursor}
	}
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: filter}},
		{{Key: "$sort", Value: bson.M{"_id": 1}}},
		{{Key: "$limit", Value: limit}},
		{{Key: "$lookup", Value: bson.M{
			"from":         "blocks",
			"localField":   "_id",
			"foreignField": "page_id",
			"as":           "blocks",
		}}},
		{{Key: "$addFields", Value: bson.M{
			"number_of_blocks": bson.M{"$size": "$blocks"},
		}}},
		{{Key: "$project", Value: bson.M{
			"blocks": 0,
		}}},
	}
	cursorResult, err := r.collection.Aggregate(ctx, pipeline)
	if err != nil {
		return nil, 0, err
	}
	defer cursorResult.Close(ctx)

	var pages []PageWithBlockCount
	for cursorResult.Next(ctx) {
		var page PageWithBlockCount
		if err := cursorResult.Decode(&page); err != nil {
			return nil, 0, err
		}
		pages = append(pages, page)
	}
	return pages, total, cursorResult.Err()
}

func (r *Repository) Delete(ctx context.Context, id bson.ObjectID) error {
	_, err := r.collection.DeleteOne(ctx, bson.M{"_id": id})
	return err
}

func (r *Repository) FindByID(ctx context.Context, id bson.ObjectID) (*Page, error) {
	var page Page
	err := r.collection.FindOne(ctx, bson.M{"_id": id}).Decode(&page)
	if err != nil {
		return nil, err
	}
	return &page, nil
}
