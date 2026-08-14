package blocks

import "net/http"

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) CreateBlock(w http.ResponseWriter, r *http.Request) {

}
