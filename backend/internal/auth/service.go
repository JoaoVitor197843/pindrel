package auth

import (
	"context"
	"errors"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

var (
	ErrRegistrationDisabled = errors.New("registration is disabled")
	ErrEmailAlreadyExists   = errors.New("email already exists")
	ErrInvalidCredentials   = errors.New("invalid credentials")
	ErrUserNotFound         = errors.New("user not found")
)

type Service struct {
	repo                *Repository
	blocklist           *BlocklistRepository
	registrationEnabled bool
}

type LoginResult struct {
	RefreshToken string
	AccessToken  string
}

func NewService(repo *Repository, blocklist *BlocklistRepository, registrationEnabled bool) *Service {
	return &Service{repo: repo, blocklist: blocklist, registrationEnabled: registrationEnabled}
}

func (s *Service) Register(ctx context.Context, email, username, password string) (*User, error) {
	if !s.registrationEnabled {
		return nil, ErrRegistrationDisabled
	}
	_, err := s.repo.FindByEmail(ctx, email)
	if err == nil {
		return nil, ErrEmailAlreadyExists
	}
	if !errors.Is(err, mongo.ErrNoDocuments) {
		return nil, err
	}
	hashedPassword, err := HashPassword(password)
	if err != nil {
		return nil, err
	}
	user := User{Username: username, Email: email, PasswordHash: hashedPassword, CreatedAt: time.Now()}
	err = s.repo.Create(ctx, &user)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (s *Service) Login(ctx context.Context, email, password, secret string, accessExpireAt, refreshExpireAt time.Duration) (*LoginResult, error) {

	user, err := s.repo.FindByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
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
	accessToken, err := GenerateToken(user.ID.Hex(), secret, accessExpireAt)
	if err != nil {
		return nil, err
	}
	refreshToken, err := GenerateToken(user.ID.Hex(), secret, refreshExpireAt)
	if err != nil {
		return nil, err
	}
	return &LoginResult{RefreshToken: refreshToken, AccessToken: accessToken}, nil
}

func (s *Service) Logout(ctx context.Context, refreshToken, accessToken, secret string) error {
	RefreshClaims, err := ValidateToken(ctx, refreshToken, secret, s.blocklist)
	if err != nil {
		return err
	}
	if err := s.blocklist.Revoke(ctx, RefreshClaims.ID, RefreshClaims.ExpiresAt.Time); err != nil {
		return err
	}

	if accessToken != "" {
		accessClaims, err := ValidateToken(ctx, accessToken, secret, s.blocklist)
		if err == nil {
			s.blocklist.Revoke(ctx, accessClaims.ID, accessClaims.ExpiresAt.Time)
		}
	}

	return nil
}

func (s *Service) Refresh(ctx context.Context, tokenString, secret string, accessExpireAt time.Duration) (string, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.blocklist)
	if err != nil {
		return "", err
	}
	id, err := bson.ObjectIDFromHex(claims.UserID)
	if err != nil {
		return "", err
	}

	_, err = s.repo.FindByID(ctx, id)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return "", ErrUserNotFound
		}
		return "", err
	}
	accessToken, err := GenerateToken(claims.UserID, secret, accessExpireAt)
	if err != nil {
		return "", err
	}
	return accessToken, nil
}

func (s *Service) Me(ctx context.Context, tokenString, secret string) (*User, error) {
	claims, err := ValidateToken(ctx, tokenString, secret, s.blocklist)
	if err != nil {
		return nil, err
	}
	id, err := bson.ObjectIDFromHex(claims.UserID)
	if err != nil {
		return nil, err
	}
	user, err := s.repo.FindByID(ctx, id)
	if err != nil {
		return nil, err
	}
	return user, nil
}
