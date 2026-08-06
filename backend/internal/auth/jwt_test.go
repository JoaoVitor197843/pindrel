package auth_test

import (
	"context"
	"plany/internal/auth"
	"testing"
	"time"
)

func TestJwtToken_TokenValidationPass_ReturnUserID(t *testing.T) {
	_, _, blocklist, cleanup := setupTest(t, true)
	defer cleanup()
	test_secret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	token, err := auth.GenerateToken("1", test_secret, 1*time.Second)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}
	claim, err := auth.ValidateToken(context.Background(), token, test_secret, blocklist)
	if err != nil {
		t.Fatalf("Error on validating token: %v", err)
	}
	if claim.UserID != "1" {
		t.Fatalf("expected user_id 1, received: %s", claim.UserID)
	}
}

func TestJwtToken_ExpiredToken_ReturnsError(t *testing.T) {
	_, _, blocklist, cleanup := setupTest(t, true)
	defer cleanup()
	secret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	token, err := auth.GenerateToken("1", secret, -1*time.Second) // já expirado
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, secret, blocklist)
	if err == nil {
		t.Fatal("expected error validating expired token, got nil")
	}
}

func TestJwtToken_WrongSecret_ReturnsError(t *testing.T) {
	_, _, blocklist, cleanup := setupTest(t, true)
	defer cleanup()
	correctSecret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	wrongSecret := "chave-diferente-errada"

	token, err := auth.GenerateToken("1", correctSecret, 1*time.Second)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, wrongSecret, blocklist)
	if err == nil {
		t.Fatal("expected error validating with wrong secret, got nil")
	}
}

func TestJwtToken_RevokedToken_ReturnsError(t *testing.T) {
	_, _, blocklist, cleanup := setupTest(t, true)
	defer cleanup()

	secret := "OMd8Hc+t8£G0}9&l?oN?l%RDqh+l9.["
	token, err := auth.GenerateToken("1", secret, 1*time.Hour)
	if err != nil {
		t.Fatalf("Error on generating token: %v", err)
	}

	claims, err := auth.ValidateToken(context.Background(), token, secret, blocklist)
	if err != nil {
		t.Fatalf("expected valid token before revoking, got: %v", err)
	}

	if err := blocklist.Revoke(context.Background(), claims.ID, claims.ExpiresAt.Time); err != nil {
		t.Fatalf("failed to revoke: %v", err)
	}

	_, err = auth.ValidateToken(context.Background(), token, secret, blocklist)
	if err == nil {
		t.Fatal("expected validation to fail for revoked token, got nil error")
	}
}
