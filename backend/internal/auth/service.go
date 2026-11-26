package auth

import (
	"context"
	"errors"
	"pindrel/internal/database/db"
	"pindrel/internal/validator"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrRegistrationDisabled = errors.New("registration is disabled")
	ErrEmailAlreadyExists   = errors.New("email already exists")
	ErrInvalidCredentials   = errors.New("invalid credentials")
	ErrUserNotFound         = errors.New("user not found")
)

const pgUniqueViolation = "23505"

// dummyHash is verified when the e-mail does not exist so that login takes the same time (one
// Argon2) whether or not the account exists. Computed once, on first use, to keep startup cheap.
var dummyHash = sync.OnceValue(func() string {
	h, err := HashPassword("pindrel-dummy-password-for-timing")
	if err != nil {
		panic(err)
	}
	return h
})

type Service struct {
	repo                *db.Queries
	registrationEnabled bool
}

func NewService(repo *db.Queries, registrationEnabled bool) *Service {
	return &Service{repo: repo, registrationEnabled: registrationEnabled}
}

func (s *Service) Register(ctx context.Context, email, username, password string) (*db.CreateUserRow, error) {
	if !s.registrationEnabled {
		return nil, ErrRegistrationDisabled
	}
	// a shortcut that spares an Argon2 run; the UNIQUE constraint below is the real guard
	if _, err := s.repo.GetUserByEmail(ctx, email); err == nil {
		return nil, ErrEmailAlreadyExists
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	hashedPassword, err := HashPassword(password)
	if err != nil {
		return nil, err
	}
	user, err := s.repo.CreateUser(ctx, db.CreateUserParams{Email: email, Username: validator.NormalizeUsername(username), PasswordHash: hashedPassword})
	if err != nil {
		// two registrations of the same e-mail at once
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgUniqueViolation {
			return nil, ErrEmailAlreadyExists
		}
		return nil, err
	}
	return &user, nil
}

func (s *Service) Login(ctx context.Context, email, password, secret string, accessExpireIn, refreshExpireIn time.Duration) (*LoginResult, error) {
	user, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			_, _ = VerifyPassword(dummyHash(), password)
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}
	passed, err := VerifyPassword(user.PasswordHash, password)
	if err != nil {
		return nil, err
	}
	if !passed {
		return nil, ErrInvalidCredentials
	}
	accessToken, err := GenerateToken(user.ID, secret, accessExpireIn)
	if err != nil {
		return nil, err
	}
	refreshToken, err := GenerateToken(user.ID, secret, refreshExpireIn)
	if err != nil {
		return nil, err
	}
	return &LoginResult{RefreshToken: refreshToken, AccessToken: accessToken}, nil
}

// revoke puts a token on the revocation list until it would have expired anyway.
func (s *Service) revoke(ctx context.Context, c *CustomClaim) error {
	return s.repo.RevokeToken(ctx, db.RevokeTokenParams{
		TokenID:   c.ID,
		UserID:    c.UserID,
		ExpiresAt: pgtype.Timestamptz{Time: c.ExpiresAt.Time, Valid: true},
	})
}

// Logout revokes the refresh token and, when the client sent it, the access token too.
func (s *Service) Logout(ctx context.Context, refreshToken, accessToken, secret string) error {
	refreshClaims, err := ValidateToken(ctx, refreshToken, secret, s.repo)
	if err != nil {
		return err
	}
	if err := s.revoke(ctx, refreshClaims); err != nil {
		return err
	}
	if accessToken == "" {
		return nil
	}
	// an access token that is already invalid has nothing left to revoke
	accessClaims, err := ValidateToken(ctx, accessToken, secret, s.repo)
	if IsTokenRefused(err) {
		return nil
	}
	if err != nil {
		return err
	}
	return s.revoke(ctx, accessClaims)
}

// user loads the account a token names; an account deleted since the token was made is ErrUserNotFound.
func (s *Service) user(ctx context.Context, id uuid.UUID) (*db.GetUserByIDRow, error) {
	user, err := s.repo.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (s *Service) Refresh(ctx context.Context, tokenString, secret string, accessExpireIn time.Duration) (string, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.repo)
	if err != nil {
		return "", err
	}
	if _, err := s.user(ctx, claims.UserID); err != nil {
		return "", err
	}
	return GenerateToken(claims.UserID, secret, accessExpireIn)
}

func (s *Service) Me(ctx context.Context, tokenString, secret string) (*db.GetUserByIDRow, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.repo)
	if err != nil {
		return nil, err
	}
	return s.user(ctx, claims.UserID)
}

// PruneRevokedTokens forgets revoked tokens that have expired by now: an expired token is refused anyway, so its row
// only takes space. Safe on every replica at once (one DELETE).
func (s *Service) PruneRevokedTokens(ctx context.Context) error {
	return s.repo.DeleteExpiredTokens(ctx)
}
