package server_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"pindrel/internal/api/dto"
	"pindrel/internal/server"

	"github.com/google/go-cmp/cmp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"
)

func TestHandler_Info(t *testing.T) {
	for _, reg := range []bool{true, false} {
		rec := httptest.NewRecorder()
		server.NewHandler("Casa", reg).Info(rec, httptest.NewRequest(http.MethodGet, "/server/info/", nil))

		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		if ct := rec.Header().Get("Content-Type"); ct != "application/x-protobuf" {
			t.Errorf("content-type = %q", ct)
		}
		var got dto.ServerInfo
		if err := proto.Unmarshal(rec.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		want := &dto.ServerInfo{Name: "Casa", RegistrationEnabled: reg}
		if diff := cmp.Diff(want, &got, protocmp.Transform()); diff != "" {
			t.Errorf("mismatch (-want +got):\n%s", diff)
		}
	}
}
