// Package middleware have all middlewares
package middleware

import (
	"context"
	"net/http"
	"plany/internal/api"
	"plany/internal/auth"
	"plany/internal/database/db"
	contextkeys "plany/pkg/context"
)

func AuthMiddleware(secret string, repo *db.Queries) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tokenString, err := auth.ExtractBearerToken(r)
			if err != nil {
				api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
				return
			}

			claims, err := auth.ValidateToken(r.Context(), tokenString, secret, repo)
			if err != nil {
				api.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}

			ctx := context.WithValue(r.Context(), contextkeys.UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
