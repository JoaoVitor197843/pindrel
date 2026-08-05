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
)

type Service struct {
	repo                *Repository
	registrationEnabled bool
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
	err = s.repo.Create(ctx, user)
	if err != nil {
		return nil, err
	}
	return &user, nil
}
