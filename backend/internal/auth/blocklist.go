package auth

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type RevokedToken struct {
	JTI       string    `db:"jti"`
	ExpiresAt time.Time `db:"expires_at"`
}

type BlocklistRepository struct {
	pool *pgxpool.Pool
}

func NewBlocklistRepository(pool *pgxpool.Pool) *BlocklistRepository {
	return &BlocklistRepository{pool: pool}
}

func (b *BlocklistRepository) Revoke(ctx context.Context, jti string, expiresAt time.Time) error {
	query := `
			INSERT INTO revoked_tokens (token_id, expires_at)
			VALUES ($1, $2)
			ON CONFLICT (token_id) DO NOTHING
	`
	_, err := b.pool.Exec(ctx, query, jti, expiresAt)
	return err
}
func (b *BlocklistRepository) IsRevoked(ctx context.Context, jti string) (bool, error) {
	query := `
			SELECT EXISTS(
				SELECT 1 FROM revoked_tokens
				WHERE token_id = $1
			)
	`
	var revoked bool
	err := b.pool.QueryRow(ctx, query, jti).Scan(&revoked)
	if err != nil {
		return false, err
	}
	return revoked, nil
}
