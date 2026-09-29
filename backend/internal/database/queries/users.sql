-- name: CreateUser :one
INSERT INTO users (
    email,
    password_hash,
    profile
) VALUES (
    $1, $2, $3
)
RETURNING id, email, profile, created_at, updated_at;

-- name: GetUserByEmail :one
SELECT id, email, password_hash, profile, created_at, updated_at
FROM users
WHERE email = $1 LIMIT 1;

-- name: GetUserByID :one
SELECT id, email, profile, created_at, updated_at
FROM users
WHERE id = $1 LIMIT 1;

-- name: RevokeToken :exec
INSERT INTO revoked_tokens (
    token_id,
    user_id,
    expires_at
) VALUES (
    $1, $2, $3
);

-- name: IsTokenRevoked :one
SELECT EXISTS (
    SELECT 1 FROM revoked_tokens
    WHERE token_id = $1 AND expires_at > now()
);

-- name: DeleteExpiredTokens :exec
DELETE FROM revoked_tokens
WHERE expires_at <= now();

-- name: DeleteUser :exec
DELETE FROM users
WHERE id = $1;