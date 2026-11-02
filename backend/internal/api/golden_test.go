package api_test

import (
	"os"
	"testing"

	"pindrel/internal/api/dto"

	"github.com/google/go-cmp/cmp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/testing/protocmp"
)

// The Rust gateway encodes ErrorHttp and DiscoveredServers by hand. Its tests pin the bytes in
// gateway/tests/golden/*.bin; decoding the same files here with the generated code makes any drift
// from shared/protos fail a test on the Go side too.
func golden(t *testing.T, name string, into proto.Message) {
	t.Helper()
	raw, err := os.ReadFile("../../../gateway/tests/golden/" + name)
	if err != nil {
		t.Fatal(err)
	}
	if err := proto.Unmarshal(raw, into); err != nil {
		t.Fatalf("%s is not a valid message: %v", name, err)
	}
}

func TestGatewayGolden_RateLimited(t *testing.T) {
	var got dto.ErrorHttp
	golden(t, "rate_limited.bin", &got)
	// the API itself answers 429 with exactly this body (internal/middleware/ratelimit.go)
	want := &dto.ErrorHttp{Code: "rate_limited", Message: "too many requests, try again later"}
	if diff := cmp.Diff(want, &got, protocmp.Transform()); diff != "" {
		t.Errorf("mismatch (-want +got):\n%s", diff)
	}
}

func TestGatewayGolden_DiscoveredServers(t *testing.T) {
	var got dto.DiscoveredServers
	golden(t, "discovered.bin", &got)
	want := &dto.DiscoveredServers{Servers: []*dto.DiscoveredServer{
		{Name: "Casa do João", Host: "casa", Addresses: []string{"192.168.1.10", "10.0.0.5"}, Port: 8080, Id: "0123456789abcdef0123456789abcdef"},
		{Name: "Servidor", Host: "srv", Addresses: []string{"192.168.1.20"}, Port: 39215},
	}}
	if diff := cmp.Diff(want, &got, protocmp.Transform()); diff != "" {
		t.Errorf("mismatch (-want +got):\n%s", diff)
	}
}
