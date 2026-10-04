package middleware

import (
	"net"
	"net/http"
	"plany/internal/api"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

type limiterEntry struct {
	limiter *rate.Limiter
	lastSeen time.Time
}
type IPRateLimiter struct {
	limiters map[string]*limiterEntry
	mu       sync.Mutex
	r        rate.Limit
	b        int
}

func NewIPRateLimiter(r rate.Limit, b int) *IPRateLimiter {
	return &IPRateLimiter{
		limiters: make(map[string]*limiterEntry),
		r:        r,
		b:        b,
	}
}

func (i *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	i.mu.Lock()
	defer i.mu.Unlock()

	entry, exists := i.limiters[ip]
	if !exists {
		entry = &limiterEntry{limiter: rate.NewLimiter(i.r, i.b)}
		i.limiters[ip] = entry
	}
	entry.lastSeen = time.Now()
	return entry.limiter
}

func (i *IPRateLimiter) Cleanup(maxAge time.Duration) {
	i.mu.Lock()
	defer i.mu.Unlock()

	for ip, entry := range i.limiters {
		if time.Since(entry.lastSeen) > maxAge {
			delete(i.limiters, ip)
		}
	}
}

func RateLimitMiddleware(limiter *IPRateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				ip = r.RemoteAddr
			}

			l := limiter.GetLimiter(ip)
			if !l.Allow() {
				api.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}