package auth

import (
	"context"
	"errors"
	"time"

	"go.mongodb.org/mongo-driver/v2/mongo"
)

var (
	ErrRegistrationDisabled = errors.New("registration is disabled")
	ErrEmailAlreadyExists   = errors.New("email already exists")
	ErrInvalidCredentials = errors.New("invalid credentials")
)

type Service struct {
	repo                *Repository
	registrationEnabled bool
}

type LoginResult struct {
	RefreshToken string
	AccessToken string
}

func NewService(repo *Repository, registrationEnabled bool) *Service {
	return &Service{repo: repo, registrationEnabled: registrationEnabled}
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