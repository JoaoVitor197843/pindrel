package middleware

import (
	"net/http"
	"pindrel/internal/api"
	"pindrel/internal/clientip"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

type limiterEntry struct {
	limiter  *rate.Limiter
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

// RateLimitMiddleware limits per client. key says who the client is (clientip.Resolver.Key behind a trusted
// proxy); nil means the address that opened the connection.
func RateLimitMiddleware(limiter *IPRateLimiter, key func(*http.Request) string) func(http.Handler) http.Handler {
	if key == nil {
		key = clientip.PeerKey
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			l := limiter.GetLimiter(key(r))
			if !l.Allow() {
				api.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
