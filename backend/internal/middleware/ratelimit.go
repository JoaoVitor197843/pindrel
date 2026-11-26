package middleware

import (
	"math"
	"net/http"
	"pindrel/internal/api"
	"pindrel/internal/clientip"
	"strconv"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// MaxClients caps the table of one limiter, like the gateway's (16 384 entries per limit): a flood from many addresses
// must not grow it without end between two clean-ups (each entry is ~200 bytes; a million spoofed IPv4 sources would be
// ~200 MB, past the RAM ceiling).
const MaxClients = 16384

type limiterEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

type IPRateLimiter struct {
	limiters map[string]*limiterEntry
	mu       sync.Mutex
	r        rate.Limit
	b        int
	max      int
	// full is a limiter that refuses everything, handed to new clients while the table is full of active ones
	full      *rate.Limiter
	lastPrune time.Time
}

func NewIPRateLimiter(r rate.Limit, b int) *IPRateLimiter {
	return &IPRateLimiter{limiters: make(map[string]*limiterEntry), r: r, b: b, max: MaxClients, full: rate.NewLimiter(0, 0)}
}

// SetMaxClients changes the cap of the table (the tests use a small one).
func (i *IPRateLimiter) SetMaxClients(n int) {
	i.mu.Lock()
	defer i.mu.Unlock()
	i.max = max(1, n)
}

func (i *IPRateLimiter) GetLimiter(ip string) *rate.Limiter {
	i.mu.Lock()
	defer i.mu.Unlock()

	now := time.Now()
	entry, exists := i.limiters[ip]
	if !exists {
		if len(i.limiters) >= i.max && !i.pruneFullLocked(now) {
			// every entry is a client still being limited: a newcomer waits, the memory does not grow
			return i.full
		}
		entry = &limiterEntry{limiter: rate.NewLimiter(i.r, i.b)}
		i.limiters[ip] = entry
	}
	entry.lastSeen = now
	return entry.limiter
}

// pruneFullLocked drops the entries whose bucket is full again: a fresh entry would be the same, so nothing is forgotten.
// It runs at most once a second, so a flood that keeps the table full does not make every request walk it.
func (i *IPRateLimiter) pruneFullLocked(now time.Time) bool {
	if now.Sub(i.lastPrune) < time.Second {
		return false
	}
	i.lastPrune = now
	for ip, e := range i.limiters {
		if e.limiter.TokensAt(now) >= float64(i.b) {
			delete(i.limiters, ip)
		}
	}
	return len(i.limiters) < i.max
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

// Len is the number of clients in the table.
func (i *IPRateLimiter) Len() int {
	i.mu.Lock()
	defer i.mu.Unlock()
	return len(i.limiters)
}

// retryAfter is how many whole seconds a new token takes (1 to 60): what a refused client should wait before trying again.
func retryAfter(r rate.Limit) int {
	if r <= 0 {
		return 60
	}
	return min(60, max(1, int(math.Ceil(1/float64(r)))))
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
				w.Header().Set("Retry-After", strconv.Itoa(retryAfter(l.Limit())))
				api.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
