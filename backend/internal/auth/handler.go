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
		case errors.Is(err, ErrShortPassword), errors.Is(err, ErrCommonPassword):
			api.WriteError(w, http.StatusBadRequest, "invalid_input", "password does not meet requirements")
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
	json.NewEncoder(w).Encode(LoginRefreshResponse{
		AccessToken: tokens.AccessToken,
		ExpiresIn:   int(accessExpireAt.Seconds()),
	})
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request, jwtSecret string) {
	refreshToken, err := ExtractToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}

	accessToken, _ := extractBearerToken(r)
	if err := h.service.Logout(r.Context(), refreshToken, accessToken, jwtSecret); err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    "",
		HttpOnly: true,
		Secure:   false,
		SameSite: http.SameSiteLaxMode,
		Path:     "/",
		MaxAge:   -1,
	})
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request, jwtSecret string, accessExpireAt time.Duration) {
	tokenString, err := ExtractToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "no valid token found")
		return
	}
	accessToken, err := h.service.Refresh(r.Context(), tokenString, jwtSecret, accessExpireAt)
	if err != nil {
		switch {
		case errors.Is(err, ErrUserNotFound):
			api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "user no longer exists")
		default:
			api.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "no valid token found")
		}
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(LoginRefreshResponse{
		AccessToken: accessToken,
		ExpiresIn:   int(accessExpireAt.Seconds()),
	})
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request, jwtSecret string) {
	tokenString, err := extractBearerToken(r)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	user, err := h.service.Me(r.Context(), tokenString, jwtSecret)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "no valid token found")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(UserSummary{
		ID:       user.ID.Hex(),
		Email:    user.Email,
		Username: user.Username,
	})
}
