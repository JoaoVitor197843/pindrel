package auth_test

import (
	"context"
	"plany/internal/auth"
	"plany/internal/database/db"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

func TestDB_JwtToken_TokenValidationPass_ReturnUserID(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	testSecret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	user_id := setupDummyUser(t, repo)
	token, err := auth.GenerateToken(user_id, testSecret, 1*time.Second)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}
	claim, err := auth.ValidateToken(context.Background(), token, testSecret, repo)
	if err != nil {
		t.Fatalf("Error on validating token: %v", err)
	}
	if claim.UserID != user_id {
		t.Fatalf("expected user_id %s, received: %s", user_id, claim.UserID)
	}
}

func TestDB_JwtToken_ExpiredToken_ReturnsError(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	secret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["

	user_id := setupDummyUser(t, repo)
	token, err := auth.GenerateToken(user_id, secret, -1*time.Second)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, secret, repo)
	if err == nil {
		t.Fatal("expected error validating expired token, got nil")
	}
}

func TestDB_JwtToken_WrongSecret_ReturnsError(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()
	correctSecret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	wrongSecret := "chave-diferente-errada"
	user_id := setupDummyUser(t, repo)

	token, err := auth.GenerateToken(user_id, correctSecret, 1*time.Second)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, wrongSecret, repo)
	if err == nil {
		t.Fatal("expected error validating with wrong secret, got nil")
	}
}

func TestDB_JwtToken_RevokedToken_ReturnsError(t *testing.T) {
	_, repo, cleanup := setupTest(t, true)
	defer cleanup()

	secret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	user_id := setupDummyUser(t, repo)
	token, err := auth.GenerateToken(user_id, secret, 1*time.Hour)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	claims, err := auth.ValidateToken(context.Background(), token, secret, repo)
	if err != nil {
		t.Fatalf("expected valid token before revoking, got: %v", err)
	}
	revoke_params := db.RevokeTokenParams{
		TokenID: claims.ID,
		UserID:  claims.UserID,
		ExpiresAt: pgtype.Timestamptz{
			Time:  claims.ExpiresAt.Time,
			Valid: true,
		},
	}
	if err := repo.RevokeToken(context.Background(), revoke_params); err != nil {
		t.Fatalf("failed to revoke: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, secret, repo)
	if err == nil {
		t.Fatal("expected validation to fail for revoked token, got nil error")
	}
}
