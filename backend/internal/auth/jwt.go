package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrTokenRevoked = errors.New("the token is revoked")
)

type CustomClaim struct {
	UserID string `json:"user_id"`
	jwt.RegisteredClaims
}

func GenerateToken(UserID, secret string, expiry time.Duration) (string, error) {

	claims := CustomClaim{
		UserID: UserID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiry)),
			ID:        uuid.NewString(),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", err
	}
	return signedToken, nil
}

func ValidateToken(ctx context.Context, tokenString, secret string, blocklist *BlocklistRepository) (*CustomClaim, error) {
	claims := &CustomClaim{}
	keyFunc := func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	}
	_, err := jwt.ParseWithClaims(tokenString, claims, keyFunc)
	if err != nil {
		return nil, err
	}

	revoked, err := blocklist.IsRevoked(ctx, claims.ID)
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
	if err != nil {
		return "", errors.New("no token found")
	}
	return cookie.Value, nil
}

func ExtractBearerToken(r *http.Request) (string, error) {
	authHeader := r.Header.Get("Authorization")
	if strings.HasPrefix(authHeader, "Bearer ") {
		return strings.TrimPrefix(authHeader, "Bearer "), nil
	}
	return "", errors.New("no bearer token found")
}
