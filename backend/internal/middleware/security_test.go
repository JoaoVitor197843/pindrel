package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"pindrel/internal/middleware"
)

func TestSecurityHeaders_AreOnEveryAnswerWhateverTheStatusOrMethod(t *testing.T) {
	for _, status := range []int{http.StatusOK, http.StatusNotFound, http.StatusInternalServerError, http.StatusNoContent} {
		for _, method := range []string{http.MethodGet, http.MethodPost, http.MethodOptions} {
			h := middleware.SecurityHeaders(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(status) }))
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(method, "/x", nil))
			want := map[string]string{
				"X-Content-Type-Options": "nosniff",
				"Referrer-Policy":        "no-referrer",
				"X-Frame-Options":        "DENY",
				"Permissions-Policy":     "camera=(), microphone=(), geolocation=(), payment=()",
			}
			for k, v := range want {
				if got := rec.Header().Get(k); got != v {
					t.Errorf("%s %d %s: %q, want %q", method, status, k, got, v)
				}
			}
		}
	}
}

func TestSecurityHeaders_TheHandlerCanStillSetItsOwn(t *testing.T) {
	h := middleware.SecurityHeaders(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Frame-Options", "SAMEORIGIN")
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if got := rec.Header().Get("X-Frame-Options"); got != "SAMEORIGIN" {
		t.Fatalf("a handler could not override: %q", got)
	}
}
