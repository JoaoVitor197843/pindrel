// Package server exposes public information about this Plany instance.
package server

import (
	"net/http"

	"plany/internal/api"
	"plany/internal/api/dto"
)

type Handler struct {
	info *dto.ServerInfo
}

func NewHandler(name string, registrationEnabled bool) *Handler {
	return &Handler{info: &dto.ServerInfo{Name: name, RegistrationEnabled: registrationEnabled}}
}

// Info returns the server name and whether registration is open.
func (h *Handler) Info(w http.ResponseWriter, r *http.Request) {
	api.WriteResponse(w, http.StatusOK, h.info)
}
