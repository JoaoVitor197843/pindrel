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
	"go.mongodb.org/mongo-driver/v2/bson"
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
	repo, err := auth.NewRepository(t.Context(), db)
	if err != nil {
		t.Fatalf("collection creation failed: %v", err)
	}
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
	repo, err := auth.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("collection creation failed: %v", err)
	}

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
	repo, err := auth.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("collection creation failed: %v", err)
	}

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
	repo, err := auth.NewRepository(context.Background(), db)
	if err != nil {
		t.Fatalf("collection creation failed: %v", err)
	}
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

func TestRepository_FindByID_Found(t *testing.T) {
	_, repo, _, cleanup := setupTest(t, true)
	defer cleanup()

	email := fmt.Sprintf("findid-%d@example.com", time.Now().UnixNano())
	user := auth.User{Email: email, Username: "user1", PasswordHash: "hash", CreatedAt: time.Now()}
	if err := repo.Create(context.Background(), &user); err != nil {
		t.Fatalf("create failed: %v", err)
	}
	defer repo.Delete(context.Background(), user.ID)

	found, err := repo.FindByID(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("expected to find user, got error: %v", err)
	}
	if found.Email != email {
		t.Fatalf("expected email %s, got %s", email, found.Email)
	}
}

func TestRepository_FindByID_NotFound(t *testing.T) {
	_, repo, _, cleanup := setupTest(t, true)
	defer cleanup()

	fakeID := bson.NewObjectID()
	_, err := repo.FindByID(context.Background(), fakeID)
	if !errors.Is(err, mongo.ErrNoDocuments) {
		t.Fatalf("expected ErrNoDocuments, got: %v", err)
	}
}
