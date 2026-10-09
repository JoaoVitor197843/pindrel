package auth

import (
	"context"
	"errors"
	"plany/internal/database/db"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	ErrRegistrationDisabled = errors.New("registration is disabled")
	ErrEmailAlreadyExists   = errors.New("email already exists")
	ErrInvalidCredentials   = errors.New("invalid credentials")
	ErrUserNotFound         = errors.New("user not found")
)

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
	_, err := s.repo.GetUserByEmail(ctx, email)
	if err == nil {
		return nil, ErrEmailAlreadyExists
	}
	hashedPassword, err := HashPassword(password)
	if err != nil {
		return nil, err
	}
	user_params := db.CreateUserParams{Email: email, Username: username, PasswordHash: hashedPassword}
	user, err := s.repo.CreateUser(ctx, user_params)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (s *Service) Login(ctx context.Context, email, password, secret string, accessExpireIn, refreshExpireIn time.Duration) (*LoginResult, error) {

	user, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
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

func (s *Service) Logout(ctx context.Context, refreshToken, accessToken, secret string) error {
	RefreshClaims, err := ValidateToken(ctx, refreshToken, secret, s.repo)
	if err != nil {
		return err
	}

	revoke_refresh_params := db.RevokeTokenParams{
		TokenID: RefreshClaims.ID,
		UserID:  RefreshClaims.UserID,
		ExpiresAt: pgtype.Timestamptz{
			Time:  RefreshClaims.ExpiresAt.Time,
			Valid: true,
		},
	}
	if err := s.repo.RevokeToken(ctx, revoke_refresh_params); err != nil {
		return err
	}

	if accessToken != "" {
		accessClaims, err := ValidateToken(ctx, accessToken, secret, s.repo)
		if err == nil {
			revoke_access_params := db.RevokeTokenParams{
				TokenID: accessClaims.ID,
				UserID:  accessClaims.UserID,
				ExpiresAt: pgtype.Timestamptz{
					Time:  accessClaims.ExpiresAt.Time,
					Valid: true,
				},
			}
			s.repo.RevokeToken(ctx, revoke_access_params)
		}
	}

	return nil
}

func (s *Service) Refresh(ctx context.Context, tokenString, secret string, accessExpireIn time.Duration) (string, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.repo)
	if err != nil {
		return "", err
	}

	_, err = s.repo.GetUserByID(ctx, claims.UserID)
	if err != nil {
		return "", err
	}
	accessToken, err := GenerateToken(claims.UserID, secret, accessExpireIn)
	if err != nil {
		return "", err
	}
	return accessToken, nil
}

func (s *Service) Me(ctx context.Context, tokenString, secret string) (*db.GetUserByIDRow, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.repo)
	if err != nil {
		return nil, err
	}
	user, err := s.repo.GetUserByID(ctx, claims.UserID)
	if err != nil {
		return nil, err
	}
	return &user, nil
}
