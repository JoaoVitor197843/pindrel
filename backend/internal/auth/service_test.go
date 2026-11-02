package auth_test

import (
	"context"
	"errors"
	"fmt"
	"pindrel/internal/auth"
	"pindrel/internal/config"
	"pindrel/internal/database"
	"pindrel/internal/database/db"
	"testing"
	"time"

	"github.com/joho/godotenv"
)

func TestDB_Service_Register_RegistrationDisabled(t *testing.T) {
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		t.Fatalf("failed to connect to postgres: %v", err)
	}
	defer dbPool.Close()
	repo := db.New(dbPool)

	service := auth.NewService(repo, false)

	_, err = service.Register(context.Background(), "email@teste.com", "user", "senha_valida_123")

	if !errors.Is(err, auth.ErrRegistrationDisabled) {
		t.Fatalf("expected ErrRegistrationDisabled, got: %v", err)
	}
}

func TestDB_Service_Register_DuplicateEmail(t *testing.T) {
	godotenv.Load("../../.env")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("error on creating configuration: %v", err)
	}
	dbPool, err := database.NewConnection(context.Background(), cfg.Database)
	if err != nil {
		t.Fatalf("failed to connect to postgres: %v", err)
	}
	defer dbPool.Close()
	repo := db.New(dbPool)

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("dup-%d@teste.com", time.Now().UnixNano())

	user, err := service.Register(context.Background(), email, "user1", "senha_valida_123")
	if err != nil {
		t.Fatalf("first register should succeed, got: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	_, err = service.Register(context.Background(), email, "user2", "senha_valida_123")
	if !errors.Is(err, auth.ErrEmailAlreadyExists) {
		t.Fatalf("expected ErrEmailAlreadyExists, got: %v", err)
	}
}

func TestDB_Service_Login_Success(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svclogin-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("expected login to succeed, got: %v", err)
	}
	if tokens.AccessToken == "" || tokens.RefreshToken == "" {
		t.Fatal("expected both tokens to be non-empty")
	}
}

func TestDB_Service_Login_WrongPassword(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svclogin-wrong-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	_, err = service.Login(context.Background(), email, "senha_errada", "test-secret", 15*time.Minute, 720*time.Hour)
	if !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("expected ErrInvalidCredentials, got: %v", err)
	}
}

func TestDB_Service_Logout_RevokesToken(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svclogout-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("login should succeed: %v", err)
	}

	if err := service.Logout(context.Background(), tokens.RefreshToken, tokens.AccessToken, "test-secret"); err != nil {
		t.Fatalf("logout should succeed: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), tokens.RefreshToken, "test-secret", repo)
	if err == nil {
		t.Fatal("expected validation to fail for revoked token, got nil error")
	}
}

func TestDB_Service_Refresh_Success(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svcrefresh-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("login should succeed: %v", err)
	}

	newAccessToken, err := service.Refresh(context.Background(), tokens.RefreshToken, "test-secret", 15*time.Minute)
	if err != nil {
		t.Fatalf("refresh should succeed: %v", err)
	}
	if newAccessToken == "" {
		t.Fatal("expected new access token to be non-empty")
	}
}

func TestDB_Service_Refresh_RevokedToken(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svcrefresh-revoked-%d@example.com", time.Now().UnixNano())
	password := "secure_password_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("login should succeed: %v", err)
	}

	if err := service.Logout(context.Background(), tokens.RefreshToken, tokens.AccessToken, "test-secret"); err != nil {
		t.Fatalf("logout should succeed: %v", err)
	}

	_, err = service.Refresh(context.Background(), tokens.RefreshToken, "test-secret", 15*time.Minute)
	if err == nil {
		t.Fatal("expected refresh to fail with revoked token, got nil error")
	}
}

func TestDB_Service_Me_Success(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svcme-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("login should succeed: %v", err)
	}

	found, err := service.Me(context.Background(), tokens.AccessToken, "test-secret")
	if err != nil {
		t.Fatalf("expected me to succeed, got: %v", err)
	}
	if found.Email != email {
		t.Fatalf("expected email %s, got %s", email, found.Email)
	}
}

func TestDB_Service_Me_RevokedToken(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	service := auth.NewService(repo, true)
	email := fmt.Sprintf("svcme-revoked-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	user, err := service.Register(context.Background(), email, "user1", password)
	if err != nil {
		t.Fatalf("register should succeed: %v", err)
	}
	defer repo.DeleteUser(context.Background(), user.ID)

	tokens, err := service.Login(context.Background(), email, password, "test-secret", 15*time.Minute, 720*time.Hour)
	if err != nil {
		t.Fatalf("login should succeed: %v", err)
	}

	if err := service.Logout(context.Background(), tokens.RefreshToken, tokens.AccessToken, "test-secret"); err != nil {
		t.Fatalf("logout should succeed: %v", err)
	}
	_, err = service.Me(context.Background(), tokens.AccessToken, "test-secret")
	if err == nil {
		t.Fatal("expected me to fail with revoked token, got nil error")
	}
}
