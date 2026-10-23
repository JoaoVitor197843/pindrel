package auth_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"plany/internal/auth"
)

// Stress: a corrupted/malformed hash string must return an error, never panic the request goroutine.
func TestVerifyPassword_MalformedHash_NoPanic(t *testing.T) {
	hashes := []string{
		"", "abc", "1$2", "1$2$3$4$5", "a$b$c$d$e$f", "19456$2$1$32$!!$!!",
		"19456$2$1$32$$", "$$$$$", "-1$2$1$32$AAAA$AAAA", "99999999999$2$1$32$AAAA$AAAA",
		"19456$2$300$32$AAAA$AAAA", "19456$0$1$32$AAAA$AAAA", "19456$2$0$32$AAAA$AAAA", "0$2$1$32$AAAA$AAAA", "19456$2$1$0$AAAA$AAAA", strings.Repeat("$", 1000),
	}
	for _, h := range hashes {
		func() {
			defer func() {
				if r := recover(); r != nil {
					t.Errorf("hash %q panicked: %v", h, r)
				}
			}()
			ok, _ := auth.VerifyPassword(h, "senha_qualquer_123")
			if ok {
				t.Errorf("hash %q verified as correct", h)
			}
		}()
	}
}

func TestHashPassword_BoundaryLengths(t *testing.T) {
	if _, err := auth.HashPassword("1234567"); err != auth.ErrShortPassword {
		t.Errorf("7 chars: err = %v", err)
	}
	if _, err := auth.HashPassword("xK9#mQ2$"); err != nil {
		t.Errorf("8 chars should be accepted: %v", err)
	}
	if _, err := auth.HashPassword(""); err != auth.ErrShortPassword {
		t.Errorf("empty: err = %v", err)
	}
}

// Two hashes of the same password differ (random salt) and both verify.
func TestHashPassword_UniqueSalt(t *testing.T) {
	a, err := auth.HashPassword("xK9#mQ2$vL")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := auth.HashPassword("xK9#mQ2$vL")
	if a == b {
		t.Error("same hash twice: salt is not random")
	}
	for _, h := range []string{a, b} {
		if ok, err := auth.VerifyPassword(h, "xK9#mQ2$vL"); !ok || err != nil {
			t.Errorf("verify failed: %v %v", ok, err)
		}
	}
}

func TestVerifyPassword_StrangeInputs(t *testing.T) {
	h, _ := auth.HashPassword("xK9#mQ2$vL")
	for _, p := range []string{"", " ", "xK9#mQ2$vL ", " xK9#mQ2$vL", "XK9#MQ2$VL", strings.Repeat("a", 100_000), "\x00"} {
		if ok, _ := auth.VerifyPassword(h, p); ok {
			t.Errorf("password %.20q accepted", p)
		}
	}
}

func TestIsCommonPassword_ExactMatchOnly(t *testing.T) {
	if !auth.IsCommonPassword("password") {
		t.Skip("blocklist does not contain 'password'")
	}
	if auth.IsCommonPassword("") {
		t.Error("the empty string must not count as common (trailing newline in the data file)")
	}
	if auth.IsCommonPassword("password-muito-longa-e-unica-9X!") {
		t.Error("prefix match")
	}
}

func TestExtractBearerToken(t *testing.T) {
	cases := map[string]struct {
		hdr  string
		want string
		ok   bool
	}{
		"ok":        {"Bearer abc", "abc", true},
		"no space":  {"Bearerabc", "", false},
		"lowercase": {"bearer abc", "", false},
		"empty":     {"", "", false},
		"basic":     {"Basic abc", "", false},
	}
	for name, c := range cases {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		if c.hdr != "" {
			r.Header.Set("Authorization", c.hdr)
		}
		got, err := auth.ExtractBearerToken(r)
		if (err == nil) != c.ok || got != c.want {
			t.Errorf("%s: got %q err=%v", name, got, err)
		}
	}
}

func TestExtractToken_Cookie(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/", nil)
	if _, err := auth.ExtractToken(r); err == nil {
		t.Error("expected error without cookie")
	}
	r.AddCookie(&http.Cookie{Name: "refresh_token", Value: "xyz"})
	if got, err := auth.ExtractToken(r); err != nil || got != "xyz" {
		t.Errorf("got %q %v", got, err)
	}
	// a cookie with another name must not be accepted
	r2 := httptest.NewRequest(http.MethodPost, "/", nil)
	r2.AddCookie(&http.Cookie{Name: "access_token", Value: "xyz"})
	if _, err := auth.ExtractToken(r2); err == nil {
		t.Error("wrong cookie name accepted")
	}
}
