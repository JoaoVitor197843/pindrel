package auth_test

import (
	"context"
	"errors"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"testing"

	"github.com/joho/godotenv"
)

func TestService_Register_RegistrationDisabled(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	service := auth.NewService(repo, false) // registro desabilitado

	_, err = service.Register(context.Background(), "email@teste.com", "user", "senha_valida_123")

	if !errors.Is(err, auth.ErrRegistrationDisabled) {
		t.Fatalf("expected ErrRegistrationDisabled, got: %v", err)
	}
}

func TestService_Register_DuplicateEmail(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	service := auth.NewService(repo, true)

	_, err = service.Register(context.Background(), "duplicado@teste.com", "user1", "senha_valida_123")
	if err != nil {
		t.Fatalf("first register should succeed, got: %v", err)
	}

	_, err = service.Register(context.Background(), "duplicado@teste.com", "user2", "senha_valida_123")
	if !errors.Is(err, auth.ErrEmailAlreadyExists) {
		t.Fatalf("expected ErrEmailAlreadyExists, got: %v", err)
	}
}
