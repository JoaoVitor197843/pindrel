package auth_test

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"plany/internal/api/dto"
	"plany/internal/auth"
	"plany/internal/database/db"

	"github.com/google/go-cmp/cmp"
	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"
)

const (
	contentTypeProto = "application/x-protobuf"
	testPassword     = "senha_segura_123"
	testAccessTTL    = 15 * time.Minute // mesmo valor usado no setupTest
)

// Corpo truncado de verdade: campo 1 (string) declara 16 bytes, mas só vem 1.
// Bytes aleatórios nem sempre falham no proto.Unmarshal, esse sempre falha.
var truncatedProto = []byte{0x0a, 0x10, 0x61}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type testUser struct {
	ID       uuid.UUID
	Email    string
	Password string
}

func rawRequest(method, path string, body []byte) *http.Request {
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	req.Header.Set("Content-Type", contentTypeProto)
	return req
}

func protoRequest(t *testing.T, method, path string, msg proto.Message) *http.Request {
	t.Helper()
	body, err := proto.Marshal(msg)
	if err != nil {
		t.Fatalf("failed to marshal request: %v", err)
	}
	return rawRequest(method, path, body)
}

func decodeBody(t *testing.T, rec *httptest.ResponseRecorder, msg proto.Message) {
	t.Helper()
	if err := proto.Unmarshal(rec.Body.Bytes(), msg); err != nil {
		t.Fatalf("response body is not valid protobuf: %v (body: %q)", err, rec.Body.String())
	}
}

func requireStatus(t *testing.T, rec *httptest.ResponseRecorder, want int) {
	t.Helper()
	if rec.Code != want {
		t.Fatalf("expected status %d, got %d (body: %q)", want, rec.Code, rec.Body.String())
	}
}

// requireError confere o status e o código do ErrorHttp devolvido no corpo.
func requireError(t *testing.T, rec *httptest.ResponseRecorder, wantStatus int, wantCode string) {
	t.Helper()
	requireStatus(t, rec, wantStatus)
	var e dto.ErrorHttp
	decodeBody(t, rec, &e)
	if e.GetCode() != wantCode {
		t.Fatalf("expected error code %q, got %q", wantCode, e.GetCode())
	}
}

func findCookie(rec *httptest.ResponseRecorder, name string) *http.Cookie {
	for _, c := range rec.Result().Cookies() {
		if c.Name == name {
			return c
		}
	}
	return nil
}

func uniqueEmail(prefix string) string {
	return fmt.Sprintf("%s-%d@example.com", prefix, time.Now().UnixNano())
}

// registerUser cria um usuário pelo handler e agenda a remoção dele no fim do teste.
func registerUser(t *testing.T, h *auth.Handler, repo *db.Queries, prefix string) testUser {
	t.Helper()
	email := uniqueEmail(prefix)

	rec := httptest.NewRecorder()
	h.Register(rec, protoRequest(t, http.MethodPost, "/auth/register", &dto.RegisterInput{
		Email:    email,
		Username: prefix + "user",
		Password: testPassword,
	}))
	requireStatus(t, rec, http.StatusCreated)

	var resp dto.RegisterResponse
	decodeBody(t, rec, &resp)
	id, err := uuid.Parse(resp.GetUser().GetId())
	if err != nil {
		t.Fatalf("register returned an invalid user id %q: %v", resp.GetUser().GetId(), err)
	}
	t.Cleanup(func() { _ = repo.DeleteUser(context.Background(), id) })

	return testUser{ID: id, Email: email, Password: testPassword}
}

// loginUser faz login e devolve o access token e o cookie de refresh.
func loginUser(t *testing.T, h *auth.Handler, u testUser) (string, *http.Cookie) {
	t.Helper()

	rec := httptest.NewRecorder()
	h.Login(rec, protoRequest(t, http.MethodPost, "/auth/login", &dto.LoginInput{
		Email:    u.Email,
		Password: u.Password,
	}))
	requireStatus(t, rec, http.StatusOK)

	var resp dto.LoginRefreshResponse
	decodeBody(t, rec, &resp)

	cookie := findCookie(rec, "refresh_token")
	if cookie == nil || cookie.Value == "" {
		t.Fatal("expected refresh_token cookie from login")
	}
	return resp.GetAccessToken(), cookie
}

// ---------------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------------

func TestHandler_Register_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	email := uniqueEmail("teste")
	rec := httptest.NewRecorder()
	handler.Register(rec, protoRequest(t, http.MethodPost, "/auth/register", &dto.RegisterInput{
		Email:    email,
		Username: "teste",
		Password: testPassword,
	}))

	var resp dto.RegisterResponse
	if rec.Code == http.StatusCreated {
		decodeBody(t, rec, &resp)
		if id, err := uuid.Parse(resp.GetUser().GetId()); err == nil {
			t.Cleanup(func() { _ = repo.DeleteUser(context.Background(), id) })
		}
	}

	requireStatus(t, rec, http.StatusCreated)
	if _, err := uuid.Parse(resp.GetUser().GetId()); err != nil {
		t.Fatalf("expected a valid uuid in user.id, got %q", resp.GetUser().GetId())
	}
	if resp.GetUser().GetEmail() != email {
		t.Fatalf("expected email %q, got %q", email, resp.GetUser().GetEmail())
	}
	if resp.GetUser().GetUsername() != "teste" {
		t.Fatalf("expected username %q, got %q", "teste", resp.GetUser().GetUsername())
	}
}

func TestHandler_Register_EmailAlreadyExists(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "dup")

	rec := httptest.NewRecorder()
	handler.Register(rec, protoRequest(t, http.MethodPost, "/auth/register", &dto.RegisterInput{
		Email:    u.Email,
		Username: "outro",
		Password: testPassword,
	}))

	requireError(t, rec, http.StatusConflict, "email_already_exists")
}

func TestHandler_Register_RegistrationDisabled(t *testing.T) {
	handler, _, cleanup := setupTest(t, false)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Register(rec, protoRequest(t, http.MethodPost, "/auth/register", &dto.RegisterInput{
		Email:    "teste@example.com",
		Username: "teste",
		Password: testPassword,
	}))

	requireError(t, rec, http.StatusForbidden, "registration_disabled")
}

func TestHandler_Register_ValidationErrors(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	cases := []struct {
		name  string
		input *dto.RegisterInput
	}{
		{"invalid email", &dto.RegisterInput{Email: "emailinvalido", Username: "teste", Password: testPassword}},
		{"empty username", &dto.RegisterInput{Email: "teste@example.com", Username: "", Password: testPassword}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			handler.Register(rec, protoRequest(t, http.MethodPost, "/auth/register", tc.input))
			requireError(t, rec, http.StatusUnprocessableEntity, "validation_failed")
		})
	}
}

// Corpo vazio é um protobuf válido (todos os campos no valor zero),
// então quem barra é a validação e não o Unmarshal.
func TestHandler_Register_EmptyBody(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Register(rec, rawRequest(http.MethodPost, "/auth/register", nil))

	requireError(t, rec, http.StatusUnprocessableEntity, "validation_failed")
}

func TestHandler_Register_MalformedBody(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Register(rec, rawRequest(http.MethodPost, "/auth/register", truncatedProto))

	requireError(t, rec, http.StatusBadRequest, "invalid_input")
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

func TestHandler_Login_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "login")

	rec := httptest.NewRecorder()
	handler.Login(rec, protoRequest(t, http.MethodPost, "/auth/login", &dto.LoginInput{
		Email:    u.Email,
		Password: u.Password,
	}))
	requireStatus(t, rec, http.StatusOK)

	var resp dto.LoginRefreshResponse
	decodeBody(t, rec, &resp)
	if resp.GetAccessToken() == "" {
		t.Fatal("expected access_token to be present")
	}
	if want := int32(testAccessTTL.Seconds()); resp.GetExpiresIn() != want {
		t.Fatalf("expected expires_in %d, got %d", want, resp.GetExpiresIn())
	}

	cookie := findCookie(rec, "refresh_token")
	if cookie == nil || cookie.Value == "" {
		t.Fatal("expected refresh_token cookie to be set")
	}
	if !cookie.HttpOnly {
		t.Fatal("expected refresh_token cookie to be HttpOnly")
	}
}

func TestHandler_Login_InvalidCredentials(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "badlogin")

	cases := []struct {
		name  string
		input *dto.LoginInput
	}{
		{"wrong password", &dto.LoginInput{Email: u.Email, Password: "senha_errada_123"}},
		{"unknown email", &dto.LoginInput{Email: uniqueEmail("naoexiste"), Password: testPassword}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			handler.Login(rec, protoRequest(t, http.MethodPost, "/auth/login", tc.input))
			requireError(t, rec, http.StatusUnauthorized, "invalid_credentials")
			if findCookie(rec, "refresh_token") != nil {
				t.Fatal("refresh_token cookie must not be set on failed login")
			}
		})
	}
}

func TestHandler_Login_EmptyBody(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Login(rec, rawRequest(http.MethodPost, "/auth/login", nil))

	requireError(t, rec, http.StatusUnprocessableEntity, "validation_failed")
}

func TestHandler_Login_MalformedBody(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Login(rec, rawRequest(http.MethodPost, "/auth/login", truncatedProto))

	requireError(t, rec, http.StatusBadRequest, "invalid_input")
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

func TestHandler_Logout_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "logout")
	_, refresh := loginUser(t, handler, u)

	req := httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
	req.AddCookie(refresh)
	rec := httptest.NewRecorder()
	handler.Logout(rec, req)

	requireStatus(t, rec, http.StatusNoContent)
	if c := findCookie(rec, "refresh_token"); c == nil || c.MaxAge >= 0 {
		t.Fatal("expected refresh_token cookie to be cleared")
	}

	// o mesmo refresh token, já revogado, não pode funcionar de novo
	req2 := httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
	req2.AddCookie(refresh)
	rec2 := httptest.NewRecorder()
	handler.Logout(rec2, req2)

	requireError(t, rec2, http.StatusUnauthorized, "unauthorized")
}

func TestHandler_Logout_NoToken(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Logout(rec, httptest.NewRequest(http.MethodPost, "/auth/logout", nil))

	requireError(t, rec, http.StatusUnauthorized, "unauthorized")
}

// ---------------------------------------------------------------------------
// Refresh
// ---------------------------------------------------------------------------

func TestHandler_Refresh_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "refresh")
	_, refresh := loginUser(t, handler, u)

	req := httptest.NewRequest(http.MethodPost, "/auth/refresh", nil)
	req.AddCookie(refresh)
	rec := httptest.NewRecorder()
	handler.Refresh(rec, req)

	requireStatus(t, rec, http.StatusOK)
	var resp dto.LoginRefreshResponse
	decodeBody(t, rec, &resp)
	if resp.GetAccessToken() == "" {
		t.Fatal("expected new access_token to be present")
	}
	if want := int32(testAccessTTL.Seconds()); resp.GetExpiresIn() != want {
		t.Fatalf("expected expires_in %d, got %d", want, resp.GetExpiresIn())
	}
}

func TestHandler_Refresh_NoToken(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	rec := httptest.NewRecorder()
	handler.Refresh(rec, httptest.NewRequest(http.MethodPost, "/auth/refresh", nil))

	requireError(t, rec, http.StatusUnauthorized, "invalid_refresh_token")
}

// ---------------------------------------------------------------------------
// Me
// ---------------------------------------------------------------------------

func TestHandler_Me_Success(t *testing.T) {
	handler, repo, cleanup := setupTest(t, true)
	defer cleanup()

	u := registerUser(t, handler, repo, "me")
	access, _ := loginUser(t, handler, u)

	req := httptest.NewRequest(http.MethodGet, "/auth/me", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	rec := httptest.NewRecorder()
	handler.Me(rec, req)

	requireStatus(t, rec, http.StatusOK)
	var got dto.UserSummary
	decodeBody(t, rec, &got)

	want := &dto.UserSummary{Id: u.ID.String(), Email: u.Email, Username: "meuser"} // registerUser usa prefix + "user"
	if diff := cmp.Diff(want, &got, protocmp.Transform()); diff != "" {
		t.Fatalf("unexpected user (-want +got):\n%s", diff)
	}
}

func TestHandler_Me_Unauthorized(t *testing.T) {
	handler, _, cleanup := setupTest(t, true)
	defer cleanup()

	cases := []struct {
		name   string
		header string
	}{
		{"missing token", ""},
		{"invalid token", "Bearer token.invalido.aqui"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/auth/me", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			handler.Me(rec, req)

			requireError(t, rec, http.StatusUnauthorized, "unauthorized")
		})
	}
}
