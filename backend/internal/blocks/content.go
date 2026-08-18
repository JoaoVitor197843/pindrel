package blocks

import (
	"encoding/json"
	"errors"

	"github.com/go-playground/validator/v10"
)

var (
	ErrInvalidBlockType = errors.New("this block type doesn't exist")
	ErrInvalidContent   = errors.New("this block doesn't accept this type of content")
)

var contentValidator = validator.New()

type TextContent struct {
	Text *string `json:"text" validate:"required"`
}

type HeadingContent struct {
	Text  *string `json:"text" validate:"required"`
	Level int     `json:"level" validate:"required,min=1,max=6"`
}

type ChecklistItem struct {
	Text    *string `json:"text" validate:"required"`
	Checked bool    `json:"checked"`
}

type ChecklistContent struct {
	Items []ChecklistItem `json:"items" validate:"dive"`
}

type CodeContent struct {
	Language *string `json:"language" validate:"required"`
	Code     *string `json:"code" validate:"required"`
}

type ImageContent struct {
	URL string `json:"url" validate:"required,url"`
	Alt string `json:"alt"`
}

type TableContent struct {
	Columns []string   `json:"columns" validate:"required"`
	Rows    [][]string `json:"rows"`
}

func validateTextContent(raw json.RawMessage) error {
	var content TextContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	return nil
}

func validateHeadingContent(raw json.RawMessage) error {
	var content HeadingContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	return nil
}

func validateCodeContent(raw json.RawMessage) error {
	var content CodeContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	return nil
}

func validateImageContent(raw json.RawMessage) error {
	var content ImageContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	return nil
}

func validateChecklistContent(raw json.RawMessage) error {
	var content ChecklistContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if content.Items == nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	return nil
}

func validateTableContent(raw json.RawMessage) error {
	var content TableContent
	err := json.Unmarshal(raw, &content)
	if err != nil {
		return ErrInvalidContent
	}
	if content.Rows == nil {
		return ErrInvalidContent
	}
	if err := contentValidator.Struct(content); err != nil {
		return ErrInvalidContent
	}
	for _, row := range content.Rows {
		if len(row) != len(content.Columns) {
			return ErrInvalidContent
		}
	}
	return nil
}

type ContentValidator func(raw json.RawMessage) error

var blockValidators = map[string]ContentValidator{
	"text":      validateTextContent,
	"heading":   validateHeadingContent,
	"checklist": validateChecklistContent,
	"code":      validateCodeContent,
	"image":     validateImageContent,
	"table":     validateTableContent,
}

func ValidateContent(blockType string, raw json.RawMessage) error {
	validateFn, ok := blockValidators[blockType]
	if !ok {
		return ErrInvalidBlockType
	}
	return validateFn(raw)
}
