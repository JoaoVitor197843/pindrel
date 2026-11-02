package route

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"pindrel/internal/auth"
	"pindrel/internal/clientip"
	"pindrel/internal/config"
	AuthMiddleware "pindrel/internal/middleware"
)

// infoFrom sends GET /server/info/ from `peer` with an X-Forwarded-For and returns the status.
func infoFrom(r http.Handler, peer, xff string) int {
	req := httptest.NewRequest(http.MethodGet, "/server/info/", nil)
	req.RemoteAddr = peer
	if xff != "" {
		req.Header.Set("X-Forwarded-For", xff)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec.Code
}

func statuses(n int, do func(i int) int) map[int]int {
	out := map[int]int{}
	for i := 0; i < n; i++ {
		out[do(i)]++
	}
	return out
}

func newRouter(t *testing.T, trusted string) http.Handler {
	t.Helper()
	cfg := &config.Config{InAppRateLimit: true}
	if trusted != "" {
		nets, err := clientip.ParseTrusted(trusted)
		if err != nil {
			t.Fatal(err)
		}
		res, err := clientip.New(nets, "X-Forwarded-For")
		if err != nil {
			t.Fatal(err)
		}
		cfg.ClientKey = res.Key
	}
	return SetupRouter(cfg, nil, &auth.Handler{}, AuthMiddleware.NewIPRateLimiter(0, 5), AuthMiddleware.NewIPRateLimiter(0, 5))
}

// The finding that started this: from a private address the global limit used the LEFTMOST X-Forwarded-For
// entry, which the client writes, so 130 requests with 130 different values all passed.
func TestRouter_GlobalLimitCannotBeDodgedWithForwardedFor(t *testing.T) {
	for _, peer := range []string{"127.0.0.1:5000", "192.168.1.20:5000", "10.0.0.7:5000", "[::1]:5000", "203.0.113.5:5000"} {
		r := newRouter(t, "")
		got := statuses(130, func(i int) int { return infoFrom(r, peer, fmt.Sprintf("198.51.100.%d", i+1)) })
		if got[http.StatusOK] != 100 || got[http.StatusTooManyRequests] != 30 {
			t.Errorf("peer %s: got %v, want 100 OK and 30 429", peer, got)
		}
	}
}

func TestRouter_BehindATrustedProxyEachClientHasItsOwnGlobalLimit(t *testing.T) {
	r := newRouter(t, "127.0.0.1")
	for _, client := range []string{"198.51.100.1", "198.51.100.2"} {
		got := statuses(130, func(int) int { return infoFrom(r, "127.0.0.1:5000", client) })
		if got[http.StatusOK] != 100 || got[http.StatusTooManyRequests] != 30 {
			t.Errorf("client %s: got %v", client, got)
		}
	}
	// what the client writes on the left is not its identity: the right-most address is
	r = newRouter(t, "127.0.0.1")
	got := statuses(130, func(i int) int { return infoFrom(r, "127.0.0.1:5000", fmt.Sprintf("10.9.9.%d, 198.51.100.7", i+1)) })
	if got[http.StatusOK] != 100 || got[http.StatusTooManyRequests] != 30 {
		t.Errorf("forged left side: got %v", got)
	}
	// and a client that is not behind the proxy cannot claim to be
	r = newRouter(t, "127.0.0.1")
	got = statuses(130, func(i int) int { return infoFrom(r, "203.0.113.5:5000", fmt.Sprintf("198.51.100.%d", i+1)) })
	if got[http.StatusOK] != 100 {
		t.Errorf("untrusted peer: got %v", got)
	}
}

func login(r http.Handler, peer, xff string) int {
	req := httptest.NewRequest(http.MethodPost, "/auth/login/", nil)
	req.RemoteAddr = peer
	if xff != "" {
		req.Header.Set("X-Forwarded-For", xff)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec.Code
}

// Login and register used the connection's address only: behind a tunnel everyone shared one bucket of 5.
func TestRouter_LoginLimitCountsEachClientBehindATrustedProxy(t *testing.T) {
	r := newRouter(t, "127.0.0.1")
	for _, client := range []string{"198.51.100.1", "198.51.100.2", "198.51.100.3"} {
		for i := 0; i < 5; i++ {
			if code := login(r, "127.0.0.1:5000", client); code == http.StatusTooManyRequests {
				t.Fatalf("client %s request %d was limited: the burst is 5 per client", client, i+1)
			}
		}
		if code := login(r, "127.0.0.1:5000", client); code != http.StatusTooManyRequests {
			t.Errorf("client %s: the 6th login got %d, want 429", client, code)
		}
	}
	// and without a trusted proxy the header is worthless: one connection, one bucket
	r = newRouter(t, "")
	limited := 0
	for i := 0; i < 10; i++ {
		if login(r, "192.168.1.20:5000", fmt.Sprintf("198.51.100.%d", i+1)) == http.StatusTooManyRequests {
			limited++
		}
	}
	if limited != 5 {
		t.Errorf("forged X-Forwarded-For on login: %d of 10 limited, want 5", limited)
	}
}
