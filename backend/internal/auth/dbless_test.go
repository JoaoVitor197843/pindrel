package auth_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/auth"
	"pindrel/internal/database/db"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const dblessSecret = "test-secret"

// dblessHandler is a handler whose checks all run before the database: reaching it would be a nil pointer, which would
// itself show that a check was skipped.
func dblessHandler(registrationEnabled bool) *auth.Handler {
	return auth.NewHandler(auth.NewService(nil, registrationEnabled), dblessSecret, testAccessTTL, 720*time.Hour)
}

// downDB stands for a database that is not answering (restarting, the disk full, the network gone).
type downDB struct{}

var errDown = errors.New("connection refused")

func (downDB) Exec(context.Context, string, ...any) (pgconn.CommandTag, error) {
	return pgconn.CommandTag{}, errDown
}
func (downDB) Query(context.Context, string, ...any) (pgx.Rows, error) { return nil, errDown }
func (downDB) QueryRow(context.Context, string, ...any) pgx.Row        { return downRow{} }

type downRow struct{}

func (downRow) Scan(...any) error { return errDown }

func downHandler() *auth.Handler {
	return auth.NewHandler(auth.NewService(db.New(downDB{}), true), dblessSecret, testAccessTTL, 720*time.Hour)
}

// The clients take a 401 on a renewal as "the session is over" and forget it, so a database that is down for a moment
// must answer 500, never 401: otherwise restarting Postgres would sign every device out.
func TestHandler_DatabaseDownIsA500NotA401(t *testing.T) {
	token, err := auth.GenerateToken(uuid.New(), dblessSecret, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	h := downHandler()

	me := httptest.NewRequest(http.MethodGet, "/auth/me/", nil)
	me.Header.Set("Authorization", "Bearer "+token)
	refresh := httptest.NewRequest(http.MethodPost, "/auth/refresh/", nil)
	refresh.AddCookie(&http.Cookie{Name: "refresh_token", Value: token})
	logout := httptest.NewRequest(http.MethodPost, "/auth/logout/", nil)
	logout.AddCookie(&http.Cookie{Name: "refresh_token", Value: token})

	for name, c := range map[string]struct {
		run func(http.ResponseWriter, *http.Request)
		req *http.Request
	}{
		"me": {h.Me, me}, "refresh": {h.Refresh, refresh}, "logout": {h.Logout, logout},
	} {
		rec := httptest.NewRecorder()
		c.run(rec, c.req)
		requireError(t, rec, http.StatusInternalServerError, "internal_error")
		if name == "logout" && findCookie(rec, "refresh_token") != nil {
			t.Error("logout cleared the cookie although the token was not revoked")
		}
	}
}

// A login or a sign-up while the database is down is a 500 too, and never runs Argon2 for nothing.
func TestHandler_LoginAndRegisterWithTheDatabaseDown(t *testing.T) {
	h := downHandler()
	rec := httptest.NewRecorder()
	h.Login(rec, protoRequest(t, http.MethodPost, "/auth/login/", &dto.LoginInput{Email: "a@b.com", Password: testPassword}))
	requireError(t, rec, http.StatusInternalServerError, "internal_error")

	svc := auth.NewService(db.New(downDB{}), true)
	start := time.Now()
	if _, err := svc.Register(context.Background(), "a@b.com", "ana", testPassword); !errors.Is(err, errDown) {
		t.Fatalf("register: %v, want the database error", err)
	}
	if time.Since(start) > 500*time.Millisecond {
		t.Errorf("register took %v: it hashed the password before seeing that the database is down", time.Since(start))
	}
}

// A cookie that is no longer good (expired, revoked, garbage) is dropped on logout even though the answer is 401: the
// person asked to leave and the browser should not keep sending it.
func TestHandler_Logout_RefusedCookieIsClearedAnyway(t *testing.T) {
	expired, _ := auth.GenerateToken(uuid.New(), dblessSecret, -time.Minute)
	for _, value := range []string{"lixo", expired} {
		req := httptest.NewRequest(http.MethodPost, "/auth/logout/", nil)
		req.AddCookie(&http.Cookie{Name: "refresh_token", Value: value})
		rec := httptest.NewRecorder()
		dblessHandler(true).Logout(rec, req)
		requireError(t, rec, http.StatusUnauthorized, "unauthorized")
		if c := findCookie(rec, "refresh_token"); c == nil || c.MaxAge >= 0 {
			t.Errorf("cookie %.10q was not cleared: %+v", value, c)
		}
	}
}

func TestService_Register_RegistrationDisabled(t *testing.T) {
	_, err := auth.NewService(nil, false).Register(context.Background(), "email@teste.com", "user", "senha_valida_123")
	if !errors.Is(err, auth.ErrRegistrationDisabled) {
		t.Fatalf("expected ErrRegistrationDisabled, got: %v", err)
	}
}

func signWith(t *testing.T, method jwt.SigningMethod, key any, claims jwt.Claims) string {
	t.Helper()
	s, err := jwt.NewWithClaims(method, claims).SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// Every token that is not exactly ours is refused before the revocation list is asked (the nil repository would panic):
// another key, another algorithm (even an HMAC one with the right key), no signature, no expiry, no id.
func TestValidateToken_RefusesWhatIsNotOurs(t *testing.T) {
	user := uuid.New()
	exp := jwt.NewNumericDate(time.Now().Add(time.Hour))
	good := auth.CustomClaim{UserID: user, RegisteredClaims: jwt.RegisteredClaims{ExpiresAt: exp, ID: "x"}}
	expired, _ := auth.GenerateToken(user, dblessSecret, -time.Second)
	otherKey, _ := auth.GenerateToken(user, "chave-diferente-errada", time.Hour)

	cases := map[string]string{
		"expired":     expired,
		"other key":   otherKey,
		"HS512":       signWith(t, jwt.SigningMethodHS512, []byte(dblessSecret), good),
		"HS384":       signWith(t, jwt.SigningMethodHS384, []byte(dblessSecret), good),
		"alg none":    signWith(t, jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType, good),
		"no expiry":   signWith(t, jwt.SigningMethodHS256, []byte(dblessSecret), auth.CustomClaim{UserID: user, RegisteredClaims: jwt.RegisteredClaims{ID: "x"}}),
		"no jti":      signWith(t, jwt.SigningMethodHS256, []byte(dblessSecret), auth.CustomClaim{UserID: user, RegisteredClaims: jwt.RegisteredClaims{ExpiresAt: exp}}),
		"no user":     signWith(t, jwt.SigningMethodHS256, []byte(dblessSecret), auth.CustomClaim{RegisteredClaims: jwt.RegisteredClaims{ExpiresAt: exp, ID: "x"}}),
		"empty":       "",
		"garbage":     "a.b.c",
		"huge":        strings.Repeat("A", 1<<20),
		"three dots":  "...",
		"only header": strings.SplitN(otherKey, ".", 2)[0],
	}
	for name, tok := range cases {
		_, err := auth.ValidateToken(context.Background(), tok, dblessSecret, nil)
		if !auth.IsTokenRefused(err) {
			t.Errorf("%s: err = %v, want a refused token", name, err)
		}
	}
}

func TestIsTokenRefused(t *testing.T) {
	if auth.IsTokenRefused(nil) || auth.IsTokenRefused(errDown) {
		t.Error("a database error or no error is not a refused token")
	}
	if !auth.IsTokenRefused(auth.ErrTokenRevoked) || !auth.IsTokenRefused(auth.ErrInvalidToken) {
		t.Error("revoked and invalid tokens are refused")
	}
}

// noAccountDB answers every lookup with "no such row": an e-mail nobody registered.
type noAccountDB struct{ downDB }

func (noAccountDB) QueryRow(context.Context, string, ...any) pgx.Row { return noRow{} }

type noRow struct{}

func (noRow) Scan(...any) error { return pgx.ErrNoRows }

// An unknown e-mail while every Argon2 slot is busy answers busy, as a real account would, and the next attempt works:
// a quick 401 there would tell which accounts exist, and the old lazily computed dummy hash panicked for good.
func TestService_Login_UnknownEmailWhileBusyIsBusyToo(t *testing.T) {
	resetArgon(t)
	auth.SetArgonLimits(1, 20*time.Millisecond)
	svc := auth.NewService(db.New(noAccountDB{}), true)
	release := auth.HoldArgonSlots()
	for range 2 {
		if _, err := svc.Login(context.Background(), "ninguem@casa.local", testPassword, dblessSecret, time.Minute, time.Hour); !errors.Is(err, auth.ErrServerBusy) {
			release()
			t.Fatalf("busy: err = %v, want ErrServerBusy", err)
		}
	}
	release()
	if _, err := svc.Login(context.Background(), "ninguem@casa.local", testPassword, dblessSecret, time.Minute, time.Hour); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("after the slots are free: err = %v, want ErrInvalidCredentials", err)
	}
}

// The constant dummy hash must cost what a real one costs today: same parameters as a fresh HashPassword.
func TestDummyHashUsesTodaysParameters(t *testing.T) {
	fresh, err := auth.HashPassword("xK9#mQ2$vL-qualquer")
	if err != nil {
		t.Fatal(err)
	}
	params := func(h string) string { p := strings.Split(h, "$"); return strings.Join(p[:4], "$") }
	if params(auth.DummyHash) != params(fresh) {
		t.Fatalf("dummy hash parameters %s, a real hash has %s: regenerate it with HashPassword", params(auth.DummyHash), params(fresh))
	}
	if ok, err := auth.VerifyPassword(auth.DummyHash, "pindrel-dummy-password-for-timing"); !ok || err != nil {
		t.Fatalf("dummy hash does not verify: ok=%v err=%v", ok, err)
	}
}
