package middleware

import "net/http"

// SecurityHeaders adds the headers every answer should carry, whatever it is: no content sniffing, no referrer sent to
// other sites, no framing, and no access to the camera, microphone or location for anything this server serves.
// The Content-Security-Policy belongs to the web page only and is set where the page is served.
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")
		next.ServeHTTP(w, r)
	})
}
