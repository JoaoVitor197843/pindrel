package auth_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"plany/internal/auth"
	"plany/internal/database"
	"strings"
	"testing"
	"time"

	"github.com/joho/godotenv"
	"go.mongodb.org/mongo-driver/v2/bson"
)

func TestHandler_Register_Success(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	service := auth.NewService(repo, true)
	handler := auth.NewHandler(service)
	email := fmt.Sprintf("teste-%d@example.com", time.Now().UnixNano())
	body := fmt.Sprintf(`{"email":"%s","username":"teste","password":"senha_segura_123"}`, email)
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)
	var response auth.RegisterResponse
	json.NewDecoder(rec.Body).Decode(&response)

	id, _ := bson.ObjectIDFromHex(response.User.ID)
	defer repo.Delete(context.Background(), id)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d", rec.Code)
	}
}

func TestHandler_Register_EmailAlreadyExists(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	service := auth.NewService(repo, true)
	handler := auth.NewHandler(service)
	email := fmt.Sprintf("dup-%d@example.com", time.Now().UnixNano())
	body := fmt.Sprintf(`{"email":"%s","username":"user1","password":"senha_segura_123"}`, email)

	req1 := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec1 := httptest.NewRecorder()
	handler.Register(rec1, req1)

	req2 := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec2 := httptest.NewRecorder()
	handler.Register(rec2, req2)
	var response auth.RegisterResponse
	json.NewDecoder(rec1.Body).Decode(&response)

	id, _ := bson.ObjectIDFromHex(response.User.ID)
	defer repo.Delete(context.Background(), id)

	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected status 409, got %d", rec2.Code)
	}
}

func TestHandler_Register_RegistrationDisabled(t *testing.T) {
	godotenv.Load("../../.env")

	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
	if err != nil {
		t.Fatalf("failed to connect to mongo: %v", err)
	}
	defer client.Disconnect(context.Background())

	db := client.Database(os.Getenv("MONGO_DB_NAME"))
	repo := auth.NewRepository(db)
	service := auth.NewService(repo, false)
	handler := auth.NewHandler(service)
	body := `{"email":"teste@example.com","username":"teste","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected status 403, got %d", rec.Code)
	}
}
