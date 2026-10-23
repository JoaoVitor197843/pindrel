package validator

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"plany/internal/api/dto"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/go-ozzo/ozzo-validation/v4/is"
	"golang.org/x/text/unicode/norm"
)

// maxEmailLen is the RFC 5321 limit for an address.
const maxEmailLen = 254

// NormalizeUsername is the stored form of a username: no space at the ends and NFC, so "e"+accent
// and the precomposed "é" are the same name. Validation and storage must both use it.
func NormalizeUsername(s string) string {
	return norm.NFC.String(strings.TrimSpace(s))
}

// visibleUsername rejects names a person cannot see or that change how the text is drawn:
// control and format characters (zero-width space/joiner, BOM, bidi overrides, tags), exotic
// spaces and names made only of combining marks.
func visibleUsername(value interface{}) error {
	s, _ := value.(string)
	hasBase := false
	for _, r := range s {
		switch {
		case unicode.IsControl(r), unicode.Is(unicode.Cf, r), unicode.Is(unicode.Co, r):
			return validation.NewError("invalid_username", "username has invisible or control characters")
		case unicode.IsSpace(r) && r != ' ':
			return validation.NewError("invalid_username", "username has unusual spaces")
		case !unicode.IsMark(r) && r != ' ':
			hasBase = true
		}
	}
	if s != "" && !hasBase {
		return validation.NewError("invalid_username", "username needs visible characters")
	}
	if !utf8.ValidString(s) {
		return validation.NewError("invalid_username", "username is not valid text")
	}
	return nil
}

func ValidateLogin(input *dto.LoginInput) error {
	if input == nil {
		return validation.NewError("empty_payload", "payload cannot be empty")
	}

	return validation.Errors{
		"email":    validation.Validate(input.GetEmail(), validation.Required, validation.Length(1, maxEmailLen), is.EmailFormat),
		"password": validation.Validate(input.GetPassword(), validation.Required, validation.Length(8, 72)),
	}.Filter()
}

func ValidateRegister(input *dto.RegisterInput) error {
	if input == nil {
		return validation.NewError("empty_payload", "payload cannot be empty")
	}

	return validation.Errors{
		"email":    validation.Validate(input.GetEmail(), validation.Required, validation.Length(1, maxEmailLen), is.EmailFormat),
		"username": validation.Validate(NormalizeUsername(input.GetUsername()), validation.Required, validation.RuneLength(3, 32), validation.By(visibleUsername)),
		"password": validation.Validate(input.GetPassword(), validation.Required, validation.Length(8, 72)),
	}.Filter()
}
