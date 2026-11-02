package middleware_test

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"pindrel/internal/api/dto"
	"pindrel/internal/middleware"

	"google.golang.org/protobuf/proto"
)

func serve(h http.Handler, remote string, hdr map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/auth/login/", nil)
	req.RemoteAddr = remote
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func newHandler(burst int) (http.Handler, *int32) {
	var calls int32
	l := middleware.NewIPRateLimiter(0, burst) // rate 0: no refill, only the burst
	h := middleware.RateLimitMiddleware(l, nil)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
	}))
	return h, &calls
}

func TestRateLimit_BlocksAfterBurstWithProtobufError(t *testing.T) {
	h, calls := newHandler(2)
	for i := 0; i < 2; i++ {
		if rec := serve(h, "1.2.3.4:5000", nil); rec.Code != http.StatusOK {
			t.Fatalf("request %d: got %d", i, rec.Code)
		}
	}
	rec := serve(h, "1.2.3.4:5000", nil)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("got %d, want 429", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/x-protobuf" {
		t.Errorf("content-type = %q", ct)
	}
	var e dto.ErrorHttp
	if err := proto.Unmarshal(rec.Body.Bytes(), &e); err != nil || e.Code != "rate_limited" {
		t.Errorf("body = %v err=%v", &e, err)
	}
	if *calls != 2 {
		t.Errorf("next called %d times, want 2", *calls)
	}
}

// Stress: the limit is per IP, not per source port (a flood from many ports must share one bucket).
func TestRateLimit_SamePortChangeDoesNotEscape(t *testing.T) {
	h, _ := newHandler(1)
	serve(h, "1.2.3.4:1000", nil)
	for port := 1001; port < 1050; port++ {
		if rec := serve(h, fmt.Sprintf("1.2.3.4:%d", port), nil); rec.Code != http.StatusTooManyRequests {
			t.Fatalf("port %d escaped the limit: %d", port, rec.Code)
		}
	}
}

// Stress: a spoofed X-Forwarded-For must not give the client a fresh bucket (the middleware uses RemoteAddr).
func TestRateLimit_SpoofedForwardedForIsIgnored(t *testing.T) {
	h, _ := newHandler(1)
	serve(h, "1.2.3.4:1000", nil)
	for i := 0; i < 20; i++ {
		rec := serve(h, "1.2.3.4:1000", map[string]string{"X-Forwarded-For": fmt.Sprintf("9.9.9.%d", i), "X-Real-IP": "8.8.8.8"})
		if rec.Code != http.StatusTooManyRequests {
			t.Fatalf("spoofed header %d escaped the limit: %d", i, rec.Code)
		}
	}
}

func TestRateLimit_IPsAreIndependent(t *testing.T) {
	h, _ := newHandler(1)
	serve(h, "1.1.1.1:1", nil)
	if rec := serve(h, "1.1.1.1:1", nil); rec.Code != http.StatusTooManyRequests {
		t.Fatal("first IP should be blocked")
	}
	if rec := serve(h, "2.2.2.2:1", nil); rec.Code != http.StatusOK {
		t.Fatalf("second IP must not be affected by the first: %d", rec.Code)
	}
}

// RemoteAddr without a port (unusual) and IPv6 must not panic and must still be limited.
func TestRateLimit_OddRemoteAddrs(t *testing.T) {
	for _, addr := range []string{"1.2.3.4", "[2001:db8::1]:443", "", "not-an-address", "::1"} {
		h, _ := newHandler(1)
		serve(h, addr, nil)
		if rec := serve(h, addr, nil); rec.Code != http.StatusTooManyRequests {
			t.Errorf("addr %q: second request got %d, want 429", addr, rec.Code)
		}
	}
}

// Stress: many threads hitting one IP at once never let more than the burst through.
func TestRateLimit_ConcurrentFloodRespectsBurst(t *testing.T) {
	const burst = 5
	h, calls := newHandler(burst)
	var wg sync.WaitGroup
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			serve(h, "7.7.7.7:1", nil)
		}()
	}
	wg.Wait()
	if *calls != burst {
		t.Errorf("%d requests passed, want exactly %d", *calls, burst)
	}
}

// Stress: many different source addresses; the table must be cleaned so memory does not grow forever.
func TestCleanup_DropsOnlyIdleEntries(t *testing.T) {
	l := middleware.NewIPRateLimiter(1, 1)
	for i := 0; i < 1000; i++ {
		l.GetLimiter(fmt.Sprintf("10.0.%d.%d", i/250, i%250))
	}
	old := l.GetLimiter("old")
	time.Sleep(30 * time.Millisecond)
	fresh := l.GetLimiter("fresh")

	l.Cleanup(20 * time.Millisecond)

	if l.GetLimiter("fresh") != fresh {
		t.Error("recent entry was dropped (its bucket got reset)")
	}
	if l.GetLimiter("old") == old {
		t.Error("idle entry was kept")
	}
}

func TestCleanup_ConcurrentWithRequests(t *testing.T) {
	l := middleware.NewIPRateLimiter(1, 1)
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(2)
		go func(i int) { defer wg.Done(); l.GetLimiter(fmt.Sprintf("ip%d", i%7)) }(i)
		go func() { defer wg.Done(); l.Cleanup(0) }()
	}
	wg.Wait()
}
