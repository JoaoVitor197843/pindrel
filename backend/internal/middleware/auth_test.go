package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/auth"
	"pindrel/internal/middleware"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
)

// These cases are rejected before the database is consulted, so a nil *db.Queries is enough:
// reaching the database would panic, which would itself prove the bypass.
func TestAuthMiddleware_RejectsBadCredentialsWithoutTouchingDB(t *testing.T) {
	const secret = "segredo-de-teste"
	good, err := auth.GenerateToken(uuid.New(), secret, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	expired, _ := auth.GenerateToken(uuid.New(), secret, -time.Minute)
	otherKey, _ := auth.GenerateToken(uuid.New(), "outro-segredo", time.Minute)

	// alg=none token with a valid-looking payload
	none := "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0." +
		"eyJ1c2VyX2lkIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAwIiwianRpIjoieCJ9."

	// good token with the signature chopped / payload tampered
	parts := strings.Split(good, ".")
	noSig := parts[0] + "." + parts[1] + "."
	badSig := parts[0] + "." + parts[1] + ".AAAA"

	cases := map[string]string{
		"no header":        "",
		"basic scheme":     "Basic abc",
		"lowercase bearer": "bearer " + good,
		"only scheme":      "Bearer",
		"empty bearer":     "Bearer ",
		"garbage":          "Bearer lixo",
		"many dots":        "Bearer a.b.c.d.e",
		"expired":          "Bearer " + expired,
		"other secret":     "Bearer " + otherKey,
		"alg none":         "Bearer " + none,
		"stripped sig":     "Bearer " + noSig,
		"forged sig":       "Bearer " + badSig,
		"huge":             "Bearer " + strings.Repeat("A", 1<<20),
	}

	reached := false
	h := middleware.AuthMiddleware(secret, nil, false)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached = true
	}))
	for name, hdr := range cases {
		req := httptest.NewRequest(http.MethodGet, "/x", nil)
		if hdr != "" {
			req.Header.Set("Authorization", hdr)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s: got %d, want 401", name, rec.Code)
		}
		var e dto.ErrorHttp
		if err := proto.Unmarshal(rec.Body.Bytes(), &e); err != nil || e.Code != "unauthorized" {
			t.Errorf("%s: body %v err=%v", name, &e, err)
		}
	}
	if reached {
		t.Fatal("a protected handler ran with invalid credentials")
	}
}

// The refresh cookie is not an access credential: only the Authorization header is accepted.
func TestAuthMiddleware_IgnoresRefreshCookie(t *testing.T) {
	const secret = "segredo-de-teste"
	tok, _ := auth.GenerateToken(uuid.New(), secret, time.Minute)
	h := middleware.AuthMiddleware(secret, nil, false)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler reached using only a cookie")
	}))
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.AddCookie(&http.Cookie{Name: "refresh_token", Value: tok})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", rec.Code)
	}
}
