package auth

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"plany/internal/api"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Email    string `json:"email"`
		Username string `json:"username"`
		Password string `json:"password"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		api.WriteError(w, 400, "invalid_input", "malformed request body")
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
