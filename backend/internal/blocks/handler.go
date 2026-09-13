package blocks

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"plany/internal/api"
	contextkeys "plany/pkg/context"
	"time"

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

func (h *Handler) CreateBlock(w http.ResponseWriter, r *http.Request) {
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
	var input CreateBlockInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		api.WriteError(w, 400, "invalid_input", "malformed request body")
		return
	}
	if err := h.validator.Struct(input); err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_input", "validation failed")
		return
	}
	block, err := h.service.CreateBlock(r.Context(), userID, input)
	if err != nil {
		switch {
		case errors.Is(err, ErrPageNotFound):
			api.WriteError(w, http.StatusNotFound, "page_not_found", "block page not found")
		case errors.Is(err, ErrParentBlockInOtherPage):
			api.WriteError(w, http.StatusBadRequest, "unauthorized", "parent block in other page")
		case errors.Is(err, ErrInvalidBlockType):
			api.WriteError(w, http.StatusBadRequest, "invalid_block_type", "this blockType doesn't exist")
		case errors.Is(err, ErrInvalidContent):
			api.WriteError(w, http.StatusBadRequest, "invalid_content", "this block doesn't accept this type of content")
		default:
			log.Printf("create block error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(block)
}

func (h *Handler) GetBlocks(w http.ResponseWriter, r *http.Request) {
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
	pageIDString := r.PathValue("page_id")

	pageID, err := bson.ObjectIDFromHex(pageIDString)
	if err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid page id")
		return
	}
	blocks, err := h.service.GetBlocks(r.Context(), userID, pageID)
	if err != nil {
		switch {
		case errors.Is(err, ErrPageNotFound):
			api.WriteError(w, http.StatusNotFound, "page_not_found", "page not found")
		default:
			log.Printf("get blocks error: %v", err)
			api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
		}
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(blocks)
}

func (h *Handler) DeleteBlock(w http.ResponseWriter, r *http.Request) {
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
	pageIDString := r.PathValue("page_id")
	pageID, err := bson.ObjectIDFromHex(pageIDString)
	if err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid page id")
		return
	}
	blockIDString := r.PathValue("block_id")
	blockID, err := bson.ObjectIDFromHex(blockIDString)
	if err != nil {
		api.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid block id")
		return
	}
	var deleteIn *time.Duration
	if retentionString := r.URL.Query().Get("retention"); retentionString != "" {
		d, err := time.ParseDuration(retentionString)
		if err != nil {
			api.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid retantion format")
			return
		}
		deleteIn = &d
	}
	err = h.service.DeleteBlock(r.Context(), blockID, userID, pageID, deleteIn)
	if err != nil {
		switch {
			case errors.Is(err, ErrPageNotFound), errors.Is(err, ErrBlockNotFound):
            	api.WriteError(w, http.StatusNotFound, "page_not_found", "page not found")
			default:
				log.Printf("get blocks error: %v", err)
				api.WriteError(w, http.StatusInternalServerError, "internal_error", "something went wrong")
			}
			return
	}
	w.WriteHeader(http.StatusNoContent)
}