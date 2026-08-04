package database

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

func Connect(uri string, maxRetries int, retryDelay, timeout time.Duration) (*mongo.Client, error) {

	var client *mongo.Client
	var err error

	for attempt := 1; attempt < maxRetries; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		client, err = mongo.Connect(options.Client().ApplyURI(uri))
		if err == nil {
			err = client.Ping(ctx, nil)
		}
		cancel()
		if err == nil {
			log.Println("connected to MongoDB")
			return client, nil
		}
		log.Printf("Attempt %d/%d failed: %v - trying again in %s", attempt, maxRetries, err, retryDelay)
		time.Sleep(retryDelay)
	}
	return nil, fmt.Errorf("Cannot connect to MongoDB after %d tries: %w", maxRetries, err)
}

func DefaultConnect(uri string) (*mongo.Client, error) {
	return Connect(uri, 5, 3*time.Second, 5*time.Second)
}