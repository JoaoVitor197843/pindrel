package api_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"pindrel/internal/api"
	"pindrel/internal/api/dto"

	"github.com/google/go-cmp/cmp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"
)

func TestWriteError_Headers(t *testing.T) {
	rec := httptest.NewRecorder()
	api.WriteError(rec, http.StatusTeapot, "boom", "mensagem")
	if rec.Code != http.StatusTeapot {
		t.Errorf("status = %d", rec.Code)
	}
	if rec.Header().Get("Content-Type") != "application/x-protobuf" || rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Errorf("headers = %v", rec.Header())
	}
	var got dto.ErrorHttp
	if err := proto.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if diff := cmp.Diff(&dto.ErrorHttp{Code: "boom", Message: "mensagem"}, &got, protocmp.Transform()); diff != "" {
		t.Error(diff)
	}
}

// Strange text must survive the round trip untouched (no escaping, no truncation, no panic).
func TestWriteError_StrangeText(t *testing.T) {
	for _, msg := range []string{"", "   ", "ação — çãõ 🚀", strings.Repeat("x", 100_000), "<script>alert(1)</script>", "a\x00b"} {
		rec := httptest.NewRecorder()
		api.WriteError(rec, http.StatusBadRequest, "c", msg)
		var got dto.ErrorHttp
		if err := proto.Unmarshal(rec.Body.Bytes(), &got); err != nil || got.Message != msg {
			t.Errorf("message of %d bytes lost: err=%v", len(msg), err)
		}
	}
}

// proto3 strings must be valid UTF-8: serialization fails and the caller still gets a 500, not a panic or empty 200.
func TestWriteError_InvalidUTF8_Falls_Back(t *testing.T) {
	rec := httptest.NewRecorder()
	api.WriteError(rec, http.StatusBadRequest, "c", "\xff\xfe")
	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want 500", rec.Code)
	}
}

func TestWriteResponse_Success(t *testing.T) {
	rec := httptest.NewRecorder()
	api.WriteResponse(rec, http.StatusCreated, &dto.ServerInfo{Name: "Casa"})
	if rec.Code != http.StatusCreated || rec.Header().Get("Content-Type") != "application/x-protobuf" {
		t.Fatalf("got %d %v", rec.Code, rec.Header())
	}
	var got dto.ServerInfo
	if err := proto.Unmarshal(rec.Body.Bytes(), &got); err != nil || got.Name != "Casa" {
		t.Errorf("body = %v err=%v", &got, err)
	}
}

// A failed serialization must produce exactly one response (an error), not an error followed by a second write.
func TestWriteResponse_SerializationFailure_SingleError(t *testing.T) {
	rec := httptest.NewRecorder()
	api.WriteResponse(rec, http.StatusOK, &dto.ServerInfo{Name: "\xff"})
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	var e dto.ErrorHttp
	if err := proto.Unmarshal(rec.Body.Bytes(), &e); err != nil || e.Code != "internal_error" {
		t.Errorf("body should be exactly one ErrorHttp: %v err=%v (%d bytes)", &e, err, rec.Body.Len())
	}
}
