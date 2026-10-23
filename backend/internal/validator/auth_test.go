package validator_test

import (
	"strings"
	"testing"

	"plany/internal/api/dto"
	"plany/internal/validator"
)

func TestValidateLogin_EmailSyntaxOnly(t *testing.T) {
	cases := map[string]bool{
		"ana@exemplo.com":                    true,
		"ana@t.com":                          true, // domain never resolved: no DNS lookup
		"ana@dominio-que-nao-existe.invalid": true,
		"ana@localhost.local":                true,
		"sem-arroba":                         false,
		"ana@":                               false,
		"":                                   false,
	}
	for email, ok := range cases {
		err := validator.ValidateLogin(&dto.LoginInput{Email: email, Password: "senha_valida_123"})
		if (err == nil) != ok {
			t.Errorf("email %q: valid=%v, err=%v", email, ok, err)
		}
	}
}

func TestValidateRegister_EmailSyntaxOnly(t *testing.T) {
	good := &dto.RegisterInput{Email: "ana@t.com", Username: "ana", Password: "senha_valida_123"}
	if err := validator.ValidateRegister(good); err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	bad := &dto.RegisterInput{Email: "ana", Username: "ana", Password: "senha_valida_123"}
	if err := validator.ValidateRegister(bad); err == nil {
		t.Error("expected error for malformed email")
	}
}

func TestValidate_NilInput(t *testing.T) {
	if validator.ValidateLogin(nil) == nil || validator.ValidateRegister(nil) == nil {
		t.Error("nil payload must be rejected")
	}
}

func TestValidate_PasswordLengthBoundaries(t *testing.T) {
	cases := map[int]bool{0: false, 7: false, 8: true, 72: true, 73: false, 100_000: false}
	for n, ok := range cases {
		pw := strings.Repeat("a", n)
		if err := validator.ValidateLogin(&dto.LoginInput{Email: "a@b.com", Password: pw}); (err == nil) != ok {
			t.Errorf("login password len %d: err=%v", n, err)
		}
		if err := validator.ValidateRegister(&dto.RegisterInput{Email: "a@b.com", Username: "ana", Password: pw}); (err == nil) != ok {
			t.Errorf("register password len %d: err=%v", n, err)
		}
	}
}

func TestValidateRegister_UsernameBoundaries(t *testing.T) {
	cases := map[string]bool{
		"": false, "ab": false, "abc": true, strings.Repeat("a", 32): true, strings.Repeat("a", 33): false,
		"   ": false, // 3 spaces: should not count as a name
	}
	for u, ok := range cases {
		err := validator.ValidateRegister(&dto.RegisterInput{Email: "a@b.com", Username: u, Password: "senha_valida_123"})
		if (err == nil) != ok {
			t.Errorf("username %q: err=%v, want valid=%v", u, err, ok)
		}
	}
}

// Careless/unusual text in the e-mail field.
func TestValidateLogin_StrangeEmails(t *testing.T) {
	for _, e := range []string{" ", "ana@b.com\n", "a b@c.com", "'; DROP TABLE users;--@x.com", strings.Repeat("a", 5000) + "@x.com", "ana@@x.com", "\x00@x.com"} {
		if err := validator.ValidateLogin(&dto.LoginInput{Email: e, Password: "senha_valida_123"}); err == nil {
			t.Errorf("email %.30q accepted", e)
		}
	}
}
