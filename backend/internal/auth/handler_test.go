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

func TestHandler_Register_InvalidEmail(t *testing.T) {
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

	body := `{"email":"emailinvalido","username":"teste","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_Register_EmptyUsername(t *testing.T) {
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

	body := `{"email":"teste@example.com","username":"","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_Login_Success(t *testing.T) {
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

    email := fmt.Sprintf("login-%d@example.com", time.Now().UnixNano())
    password := "senha_segura_123"

    registerBody := fmt.Sprintf(`{"email":"%s","username":"loginuser","password":"%s"}`, email, password)
    registerReq := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(registerBody))
    registerRec := httptest.NewRecorder()
    handler.Register(registerRec, registerReq)

    var registerResp auth.RegisterResponse
    json.NewDecoder(registerRec.Body).Decode(&registerResp)
    id, _ := bson.ObjectIDFromHex(registerResp.User.ID)
    defer repo.Delete(context.Background(), id)

    loginBody := fmt.Sprintf(`{"email":"%s","password":"%s"}`, email, password)
    loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(loginBody))
    loginRec := httptest.NewRecorder()
    handler.Login(loginRec, loginReq, "test-secret", 15*time.Minute, 720*time.Hour)

    if loginRec.Code != http.StatusOK {
        t.Fatalf("expected status 200, got %d", loginRec.Code)
    }

    var loginResp auth.LoginResponse
    json.NewDecoder(loginRec.Body).Decode(&loginResp)
    if loginResp.AccessToken == "" {
        t.Fatal("expected access_token to be present")
    }

    cookies := loginRec.Result().Cookies()
    found := false
    for _, c := range cookies {
        if c.Name == "refresh_token" && c.Value != "" {
            found = true
        }
    }
    if !found {
        t.Fatal("expected refresh_token cookie to be set")
    }
}