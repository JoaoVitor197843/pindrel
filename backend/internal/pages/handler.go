package pages

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"plany/internal/api"
	contextkeys "plany/pkg/context"
	"strconv"

	"github.com/go-playground/validator/v10"
	"go.mongodb.org/mongo-driver/v2/bson"
)

type Handler struct {
	service   *Service
	validator *validator.Validate
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service, validator: validator.New()}
}

// GetPages godoc
// @Summary List user pages
// @Description List proprietary and shared pages, paged by cursor. Don't return bin items.
// @Tags pages
// @Produce json
// @Security BearerAuth
// @Param limit query int false "Number of items per page" default(20)
// @Param cursor query string false "Opaque cursor for the next page of results"
// @Success 200 {object} PageData
// @Failure 400 {object} api.ErrorResponse
// @Failure 401 {object} api.ErrorResponse
// @Router /pages [get]
func (h *Handler) GetPages(w http.ResponseWriter, r *http.Request) {
	userIDString, ok := r.Context().Value(contextkeys.UserIDKey).(string)
	if !ok {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "user not found in context")
		return
	}

	userID, err := bson.ObjectIDFromHex(userIDString)
	if err != nil {
		api.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid user id")
		return
	}

	limit := int64(20)
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		parsed, err := strconv.ParseInt(limitParam, 10, 64)
		if err == nil {
			limit = parsed
		}
	}
	cursor := r.URL.Query().Get("cursor")

	result, err := h.service.GetPages(r.Context(), userID, cursor, limit)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidCursor):
			api.WriteError(w, http.StatusBadRequest, "invalid_input", "malformed cursor")
		default:
			log.Printf("get pages error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(result)
}
