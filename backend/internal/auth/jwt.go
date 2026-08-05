package auth

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
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
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", err
	}
	return signedToken, nil
}

func ValidateToken(tokenString, secret string) (*CustomClaim, error) {
	claims := &CustomClaim{}
	keyFunc := func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	}
	_, err := jwt.ParseWithClaims(tokenString, claims, keyFunc)
	if err != nil {
		return nil, err
	}

	return claims, nil
}
