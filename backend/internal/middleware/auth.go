// Package middleware holds the HTTP middlewares of the API: session check, per-client rate limits and security headers.
package middleware

import (
	"context"
	"log"
	"net/http"
	"pindrel/internal/api"
	"pindrel/internal/auth"
	"pindrel/internal/database/db"
	contextkeys "pindrel/pkg/context"
)

// AuthMiddleware lets a request through only with a valid access token in the Authorization header, and puts the user's
// id in its context (contextkeys.UserIDKey).
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
				if auth.IsTokenRefused(err) {
					api.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
					return
				}
				// the database could not say whether the token was revoked: not the client's fault, and a 401 here would
				// make the clients throw the session away
				log.Printf("auth middleware: %v", err)
				api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
				return
			}
			ctx := context.WithValue(r.Context(), contextkeys.UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
