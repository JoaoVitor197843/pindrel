// Package api have WriteError logic
package api

import (
	"fmt"
	"log"
	"net/http"

	"pindrel/internal/api/dto"

	"google.golang.org/protobuf/proto"
)

func WriteError(w http.ResponseWriter, statusCode int, code, message string) {
	resp := &dto.ErrorHttp{
		Code:    code,
		Message: message,
	}
	bytes, err := proto.Marshal(resp)
	if err != nil {
		http.Error(w, fmt.Sprintf("serializing error, original message: %s", message), http.StatusInternalServerError)
		log.Printf("error on serializing proto response: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/x-protobuf")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(statusCode)
	_, _ = w.Write(bytes)
}

func WriteResponse(w http.ResponseWriter, statusCode int, body proto.Message) {
	bytes, err := proto.Marshal(body)
	if err != nil {
		WriteError(w, http.StatusInternalServerError, "internal_error", "serializing error")
		log.Printf("error on serializing proto response: %v", err)
		return
	}
	w.Header().Set("Content-Type", "application/x-protobuf")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(statusCode)
	_, _ = w.Write(bytes)
}
