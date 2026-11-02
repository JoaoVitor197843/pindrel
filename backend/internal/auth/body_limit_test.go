package auth_test

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/auth"

	"google.golang.org/protobuf/proto"
)

// The body checks run before the service is used, so a handler without service/database is enough:
// reaching the service would panic, which would itself show the limit was bypassed.
func bareHandler() *auth.Handler {
	return auth.NewHandler(nil, "s", time.Minute, time.Hour)
}

// endless produces bytes forever and counts how many were pulled, like a client that never stops sending.
type endless struct{ read int64 }

func (e *endless) Read(p []byte) (int, error) {
	e.read += int64(len(p))
	return len(p), nil
}

type failingBody struct{}

func (failingBody) Read([]byte) (int, error) { return 0, errors.New("connection reset by peer") }

var endpoints = map[string]func(*auth.Handler) http.HandlerFunc{
	"register": func(h *auth.Handler) http.HandlerFunc { return h.Register },
	"login":    func(h *auth.Handler) http.HandlerFunc { return h.Login },
}

// Stress: a gigantic body is refused with 413 without being read in full.
func TestHandlers_HugeBody_Returns413(t *testing.T) {
	for name, endpoint := range endpoints {
		t.Run(name, func(t *testing.T) {
			src := &endless{}
			req := httptest.NewRequest(http.MethodPost, "/", io.LimitReader(src, 10<<30)) // "10 GiB"
			rec := httptest.NewRecorder()
			endpoint(bareHandler())(rec, req)

			requireError(t, rec, http.StatusRequestEntityTooLarge, "payload_too_large")
			if src.read > 1<<20 {
				t.Errorf("handler pulled %d bytes before refusing; the cap should stop it near 16 KiB", src.read)
			}
		})
	}
}

// Stress: a valid-looking message padded with a huge unknown field (proto ignores unknown fields).
func TestHandlers_PaddedProto_Returns413(t *testing.T) {
	good, _ := proto.Marshal(&dto.LoginInput{Email: "a@b.com", Password: "senha_valida_123"})
	padded := append(good, bytes.Repeat([]byte{0x00}, 1<<20)...)
	for name, endpoint := range endpoints {
		rec := httptest.NewRecorder()
		endpoint(bareHandler())(rec, rawRequest(http.MethodPost, "/", padded))
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Errorf("%s: got %d, want 413", name, rec.Code)
		}
	}
}

// Boundary: exactly at the cap the body is read (and then rejected as malformed, not as too large);
// one byte over is 413.
func TestHandlers_BodyCapBoundary(t *testing.T) {
	const limit = 16 << 10
	for name, endpoint := range endpoints {
		rec := httptest.NewRecorder()
		endpoint(bareHandler())(rec, rawRequest(http.MethodPost, "/", bytes.Repeat([]byte{0xff}, limit)))
		if rec.Code == http.StatusRequestEntityTooLarge {
			t.Errorf("%s: body of exactly %d bytes refused as too large", name, limit)
		}
		rec = httptest.NewRecorder()
		endpoint(bareHandler())(rec, rawRequest(http.MethodPost, "/", bytes.Repeat([]byte{0xff}, limit+1)))
		if rec.Code != http.StatusRequestEntityTooLarge {
			t.Errorf("%s: %d bytes got %d, want 413", name, limit+1, rec.Code)
		}
	}
}

// A dropped connection while the body is being sent is the client's problem: 400, not 500.
func TestHandlers_BrokenBody_Returns400(t *testing.T) {
	for name, endpoint := range endpoints {
		req := httptest.NewRequest(http.MethodPost, "/", failingBody{})
		rec := httptest.NewRecorder()
		endpoint(bareHandler())(rec, req)
		requireError(t, rec, http.StatusBadRequest, "invalid_input")
		_ = name
	}
}

// Careless use: empty body and a nil body still answer 4xx and never panic.
func TestHandlers_EmptyAndNilBody(t *testing.T) {
	for name, endpoint := range endpoints {
		for _, body := range []io.Reader{nil, bytes.NewReader(nil)} {
			rec := httptest.NewRecorder()
			endpoint(bareHandler())(rec, httptest.NewRequest(http.MethodPost, "/", body))
			if rec.Code < 400 || rec.Code >= 500 {
				t.Errorf("%s: got %d, want 4xx", name, rec.Code)
			}
		}
	}
}
