package auth_test

import (
	"context"
	"pindrel/internal/auth"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"pindrel/internal/database/db"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

func setupTest(t *testing.T, registrationEnabled bool) (*auth.Handler, *db.Queries, func()) {
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	repo := db.New(dbPool)
	service := auth.NewService(repo, registrationEnabled)
	handler := auth.NewHandler(service, "test-secret", 15*time.Minute, 720*time.Hour)

	cleanup := func() {
		dbPool.Close()
	}

	return handler, repo, cleanup
}

func setupDummyUser(t *testing.T, queries *db.Queries) uuid.UUID {
	t.Helper()
	ctx := context.Background()
	dummyEmail := uuid.New()
	hashPassword, err := auth.HashPassword("senha_valida_123")
	if err != nil {
		t.Fatalf("error on create dummy password: %v", err)
	}
	create_user_params := db.CreateUserParams{
		Email:        "test-" + dummyEmail.String() + "@test.com",
		PasswordHash: hashPassword,
	}
	user, err := queries.CreateUser(ctx, create_user_params)
	if err != nil {
		t.Fatalf("falha ao criar dummy user: %v", err)
	}

	t.Cleanup(func() {
		_ = queries.DeleteUser(ctx, user.ID)
	})

	return user.ID
}
