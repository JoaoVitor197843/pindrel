package auth_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"testing"
	"time"

	"github.com/joho/godotenv"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

func TestRepository_Create_SetsID(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	user := auth.User{Email: "...", Username: "...", PasswordHash: "...", CreatedAt: time.Now()}
	err = repo.Create(context.Background(), &user)
	if err != nil {
		t.Fatalf("create failed: %v", err)
	}
	if user.ID.IsZero() {
		t.Fatal("expected user.ID to be set after Create, got zero value")
	}
	defer repo.Delete(context.Background(), user.ID)
}

func TestRepository_FindByEmail_Found(t *testing.T) {
	godotenv.Load("../../.env")
	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)

	email := fmt.Sprintf("find-%d@teste.com", time.Now().UnixNano())
	user := auth.User{Email: email, Username: "user1", PasswordHash: "hash", CreatedAt: time.Now()}
	if err := repo.Create(context.Background(), &user); err != nil {
		t.Fatalf("create failed: %v", err)
	}
	defer repo.Delete(context.Background(), user.ID)

	found, err := repo.FindByEmail(context.Background(), email)
	if err != nil {
		t.Fatalf("expected to find user, got error: %v", err)
	}
	if found.Email != email {
		t.Fatalf("expected email %s, got %s", email, found.Email)
	}
}

func TestRepository_FindByEmail_NotFound(t *testing.T) {
	godotenv.Load("../../.env")
	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)

	email := fmt.Sprintf("naoexiste-%d@teste.com", time.Now().UnixNano())
	_, err = repo.FindByEmail(context.Background(), email)
	if !errors.Is(err, mongo.ErrNoDocuments) {
		t.Fatalf("expected ErrNoDocuments, got: %v", err)
	}
}

func TestRepository_Delete_RemovesUser(t *testing.T) {
	godotenv.Load("../../.env")
	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)

	email := fmt.Sprintf("delete-%d@teste.com", time.Now().UnixNano())
	user := auth.User{Email: email, Username: "user1", PasswordHash: "hash", CreatedAt: time.Now()}
	if err := repo.Create(context.Background(), &user); err != nil {
		t.Fatalf("create failed: %v", err)
	}

	if err := repo.Delete(context.Background(), user.ID); err != nil {
		t.Fatalf("delete failed: %v", err)
	}

	_, err = repo.FindByEmail(context.Background(), email)
	if !errors.Is(err, mongo.ErrNoDocuments) {
		t.Fatalf("expected ErrNoDocuments after delete, got: %v", err)
	}
}
