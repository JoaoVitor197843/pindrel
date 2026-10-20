package validator_test

import (
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
