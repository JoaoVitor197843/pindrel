package auth_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"plany/internal/auth"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)


func TestHandler_Register_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()
	email := fmt.Sprintf("teste-%d@example.com", time.Now().UnixNano())
	body := fmt.Sprintf(`{"email":"%s","username":"teste","password":"senha_segura_123"}`, email)
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)
	var response auth.RegisterResponse
	json.NewDecoder(rec.Body).Decode(&response)

	id, _ := uuid.Parse(response.User.ID)
	defer repo.DeleteUser(context.Background(), id)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d", rec.Code)
	}
}

func TestHandler_Register_EmailAlreadyExists(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()
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

	id, _ := uuid.Parse(response.User.ID)
	defer repo.DeleteUser(context.Background(), id)
	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected status 409, got %d", rec2.Code)
	}
}

func TestHandler_Register_RegistrationDisabled(t *testing.T) {
	handler, _, cleanup := setupTest(t, false)
	defer cleanup()
	body := `{"email":"teste@example.com","username":"teste","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected status 403, got %d", rec.Code)
	}
}

func TestHandler_Register_InvalidEmail(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	body := `{"email":"emailinvalido","username":"teste","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_Register_EmptyUsername(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	body := `{"email":"teste@example.com","username":"","password":"senha_segura_123"}`
	req := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(body))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestHandler_Login_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	email := fmt.Sprintf("login-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	registerBody := fmt.Sprintf(`{"email":"%s","username":"loginuser","password":"%s"}`, email, password)
	registerReq := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(registerBody))
	registerRec := httptest.NewRecorder()
	handler.Register(registerRec, registerReq)

	var registerResp auth.RegisterResponse
	json.NewDecoder(registerRec.Body).Decode(&registerResp)
	id, _ := uuid.Parse(registerResp.User.ID)
	defer repo.DeleteUser(context.Background(), id)

	loginBody := fmt.Sprintf(`{"email":"%s","password":"%s"}`, email, password)
	loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(loginBody))
	loginRec := httptest.NewRecorder()
	handler.Login(loginRec, loginReq, "test-secret", 15*time.Minute, 720*time.Hour)

	if loginRec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", loginRec.Code)
	}

	var loginResp auth.LoginRefreshResponse
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

func TestHandler_Logout_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	email := fmt.Sprintf("logout-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	registerBody := fmt.Sprintf(`{"email":"%s","username":"logoutuser","password":"%s"}`, email, password)
	registerReq := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(registerBody))
	registerRec := httptest.NewRecorder()
	handler.Register(registerRec, registerReq)

	var registerResp auth.RegisterResponse
	json.NewDecoder(registerRec.Body).Decode(&registerResp)
	id, _ := uuid.Parse(registerResp.User.ID)
	defer repo.DeleteUser(context.Background(), id)

	loginBody := fmt.Sprintf(`{"email":"%s","password":"%s"}`, email, password)
	loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(loginBody))
	loginRec := httptest.NewRecorder()
	handler.Login(loginRec, loginReq, "test-secret", 15*time.Minute, 720*time.Hour)

	var refreshToken string
	for _, c := range loginRec.Result().Cookies() {
		if c.Name == "refresh_token" {
			refreshToken = c.Value
		}
	}
	if refreshToken == "" {
		t.Fatal("expected refresh_token cookie from login")
	}

	logoutReq := httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
	logoutReq.AddCookie(&http.Cookie{Name: "refresh_token", Value: refreshToken})
	logoutRec := httptest.NewRecorder()
	handler.Logout(logoutRec, logoutReq, "test-secret")

	if logoutRec.Code != http.StatusNoContent {
		t.Fatalf("expected status 204, got %d", logoutRec.Code)
	}

	secondLogoutReq := httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
	secondLogoutReq.AddCookie(&http.Cookie{Name: "refresh_token", Value: refreshToken})
	secondLogoutRec := httptest.NewRecorder()
	handler.Logout(secondLogoutRec, secondLogoutReq, "test-secret")

	if secondLogoutRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401 on second logout with revoked token, got %d", secondLogoutRec.Code)
	}
}

func TestHandler_Refresh_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	email := fmt.Sprintf("refresh-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	registerBody := fmt.Sprintf(`{"email":"%s","username":"refreshuser","password":"%s"}`, email, password)
	registerReq := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(registerBody))
	registerRec := httptest.NewRecorder()
	handler.Register(registerRec, registerReq)

	var registerResp auth.RegisterResponse
	json.NewDecoder(registerRec.Body).Decode(&registerResp)
	id, _ := uuid.Parse(registerResp.User.ID)
	defer repo.DeleteUser(context.Background(), id)

	loginBody := fmt.Sprintf(`{"email":"%s","password":"%s"}`, email, password)
	loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(loginBody))
	loginRec := httptest.NewRecorder()
	handler.Login(loginRec, loginReq, "test-secret", 15*time.Minute, 720*time.Hour)

	var refreshToken string
	for _, c := range loginRec.Result().Cookies() {
		if c.Name == "refresh_token" {
			refreshToken = c.Value
		}
	}
	if refreshToken == "" {
		t.Fatal("expected refresh_token cookie from login")
	}

	refreshReq := httptest.NewRequest(http.MethodPost, "/auth/refresh", nil)
	refreshReq.AddCookie(&http.Cookie{Name: "refresh_token", Value: refreshToken})
	refreshRec := httptest.NewRecorder()
	handler.Refresh(refreshRec, refreshReq, "test-secret", 15*time.Minute)

	if refreshRec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", refreshRec.Code)
	}

	var refreshResp auth.LoginRefreshResponse
	json.NewDecoder(refreshRec.Body).Decode(&refreshResp)
	if refreshResp.AccessToken == "" {
		t.Fatal("expected new access_token to be present")
	}
}

func TestHandler_Me_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	email := fmt.Sprintf("me-%d@example.com", time.Now().UnixNano())
	password := "senha_segura_123"

	registerBody := fmt.Sprintf(`{"email":"%s","username":"meuser","password":"%s"}`, email, password)
	registerReq := httptest.NewRequest(http.MethodPost, "/auth/register", strings.NewReader(registerBody))
	registerRec := httptest.NewRecorder()
	handler.Register(registerRec, registerReq)

	var registerResp auth.RegisterResponse
	json.NewDecoder(registerRec.Body).Decode(&registerResp)
	id, _ := uuid.Parse(registerResp.User.ID)
	defer repo.DeleteUser(context.Background(), id)

	loginBody := fmt.Sprintf(`{"email":"%s","password":"%s"}`, email, password)
	loginReq := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(loginBody))
	loginRec := httptest.NewRecorder()
	handler.Login(loginRec, loginReq, "test-secret", 15*time.Minute, 720*time.Hour)

	var loginResp auth.LoginRefreshResponse
	json.NewDecoder(loginRec.Body).Decode(&loginResp)

	meReq := httptest.NewRequest(http.MethodGet, "/auth/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+loginResp.AccessToken)
	meRec := httptest.NewRecorder()
	handler.Me(meRec, meReq, "test-secret")

	if meRec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", meRec.Code)
	}

	var meResp auth.UserSummary
	json.NewDecoder(meRec.Body).Decode(&meResp)
	if meResp.Email != email {
		t.Fatalf("expected email %s, got %s", email, meResp.Email)
	}
}
