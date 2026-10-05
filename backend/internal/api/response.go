// Package api have WriteError logic
package api

import (
	"log"
	"net/http"

	"github.com/goccy/go-json"
)

type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type ErrorResponse struct {
	Error ErrorDetail `json:"error"`
}

func WriteError(w http.ResponseWriter, statusCode int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(ErrorResponse{
		Error: ErrorDetail{Code: code, Message: message},
	})
}

func WriteResponse[T any](w http.ResponseWriter, statusCode int, body T) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("erro ao enviar resposta JSON: %v", err)
	}
}
