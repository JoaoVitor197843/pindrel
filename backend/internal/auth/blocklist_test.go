package auth_test

import (
	"context"
	"fmt"
	"testing"
	"time"
)

func TestBlocklistRepository_RevokeAndCheck(t *testing.T) {
	_, _, blocklist, cleanup := setupTest(t, true)
	defer cleanup()

	jti := fmt.Sprintf("test-jti-%d", time.Now().UnixNano())
	expiresAt := time.Now().Add(1 * time.Hour)

	// antes de revogar, não deveria estar na blocklist
	revoked, err := blocklist.IsRevoked(context.Background(), jti)
	if err != nil {
		t.Fatalf("unexpected error checking revoked: %v", err)
	}
	if revoked {
		t.Fatal("expected token to not be revoked yet")
	}

	// revoga
	if err := blocklist.Revoke(context.Background(), jti, expiresAt); err != nil {
		t.Fatalf("failed to revoke: %v", err)
	}

	revoked, err = blocklist.IsRevoked(context.Background(), jti)
	if err != nil {
		t.Fatalf("unexpected error checking revoked: %v", err)
	}
	if !revoked {
		t.Fatal("expected token to be revoked")
	}
}
