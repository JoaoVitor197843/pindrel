package auth

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"plany/internal/api"
	"time"

	"github.com/go-playground/validator/v10"
)

type Handler struct {
	service   *Service
	validator *validator.Validate
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service, validator: validator.New()}
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Email    string `json:"email" validate:"required,email"`
		Username string `json:"username" validate:"required"`
		Password string `json:"password" validate:"required,min=8"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		api.WriteError(w, 400, "invalid_input", "malformed request body")
		return
	}
	if err := h.validator.Struct(input); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "validation failed")
		return
	}
	user, err := h.service.Register(r.Context(), input.Email, input.Username, input.Password)
	if err != nil {
		switch {
		case errors.Is(err, ErrRegistrationDisabled):
			api.WriteError(w, http.StatusForbidden, "registration_disabled", "Server registration is disabled")
		case errors.Is(err, ErrEmailAlreadyExists):
			api.WriteError(w, http.StatusConflict, "email_already_exists", "This email is already registered")
		default:
			log.Printf("register error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(RegisterResponse{
		User: UserSummary{
			ID:       user.ID.Hex(),
			Email:    user.Email,
			Username: user.Username,
		},
	})
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request, jwtSecret string, accessExpireAt, refreshExpireAt time.Duration) {
	var input struct {
		Email    string `json:"email" validate:"required,email"`
		Password string `json:"password" validate:"required,min=8"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		api.WriteError(w, 400, "invalid_input", "malformed request body")
		return
	}
	if err := h.validator.Struct(input); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "validation failed")
		return
	}
	tokens, err := h.service.Login(r.Context(), input.Email, input.Password, jwtSecret, accessExpireAt, refreshExpireAt)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidCredentials):
			api.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "Invalid email or password")
		default:
			log.Printf("register error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}
	w.Header().Set("Content-Type", "application/json")
	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    tokens.RefreshToken,
		HttpOnly: true,
		Secure:   false,
		SameSite: http.SameSiteLaxMode,
		Path:     "/",
		MaxAge:   int(refreshExpireAt.Seconds()),
	})
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(LoginResponse{
		AccessToken: tokens.AccessToken,
		ExpiresIn:   int(accessExpireAt.Seconds()),
	})
}
