package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"pindrel/internal/database/db"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrTokenRevoked = errors.New("the token is revoked")
	// ErrInvalidToken covers every token that is not ours or no longer good: malformed, signed with another key or
	// algorithm, expired. A caller answers it with 401; any other error of ValidateToken is the server's (the database).
	ErrInvalidToken = errors.New("invalid token")
)

// IsTokenRefused says whether err means "this token is not accepted" (401), as opposed to a failure of the server.
func IsTokenRefused(err error) bool {
	return errors.Is(err, ErrInvalidToken) || errors.Is(err, ErrTokenRevoked)
}

type CustomClaim struct {
	UserID uuid.UUID `json:"user_id"`
	jwt.RegisteredClaims
}

func GenerateToken(userID uuid.UUID, secret string, expiry time.Duration) (string, error) {
	claims := CustomClaim{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiry)),
			ID:        uuid.NewString(),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
}

// ValidateToken checks the signature (HS256 only: a token that names another algorithm is refused before its key is
// looked at), the expiry and the revocation list. The repository is asked only about a token that passed the rest.
func ValidateToken(ctx context.Context, tokenString, secret string, repo *db.Queries) (*CustomClaim, error) {
	claims := &CustomClaim{}
	keyFunc := func(*jwt.Token) (any, error) { return []byte(secret), nil }
	if _, err := jwt.ParseWithClaims(tokenString, claims, keyFunc,
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithExpirationRequired()); err != nil {
		return nil, fmt.Errorf("%w: %w", ErrInvalidToken, err)
	}
	if claims.ID == "" || claims.UserID == uuid.Nil {
		return nil, fmt.Errorf("%w: missing jti or user_id", ErrInvalidToken)
	}
	revoked, err := repo.IsTokenRevoked(ctx, claims.ID)
	if err != nil {
		return nil, err
	}
	if revoked {
		return nil, ErrTokenRevoked
	}
	return claims, nil
}

func ExtractToken(r *http.Request) (string, error) {
	cookie, err := r.Cookie("refresh_token")
	if err != nil || cookie.Value == "" {
		return "", errors.New("no token found")
	}
	return cookie.Value, nil
}

func ExtractBearerToken(r *http.Request) (string, error) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		return "", errors.New("no bearer token found")
	}
	return token, nil
}
