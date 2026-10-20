package validator

import (
	"plany/internal/api/dto"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/go-ozzo/ozzo-validation/v4/is"
)

func ValidateLogin(input *dto.LoginInput) error {
	if input == nil {
		return validation.NewError("empty_payload", "payload cannot be empty")
	}

	return validation.Errors{
		"email":    validation.Validate(input.GetEmail(), validation.Required, is.EmailFormat),
		"password": validation.Validate(input.GetPassword(), validation.Required, validation.Length(8, 72)),
	}.Filter()
}

func ValidateRegister(input *dto.RegisterInput) error {
	if input == nil {
		return validation.NewError("empty_payload", "payload cannot be empty")
	}

	return validation.Errors{
		"email":    validation.Validate(input.GetEmail(), validation.Required, is.EmailFormat),
		"username": validation.Validate(input.GetUsername(), validation.Required, validation.Length(3, 32)),
		"password": validation.Validate(input.GetPassword(), validation.Required, validation.Length(8, 72)),
	}.Filter()
}
