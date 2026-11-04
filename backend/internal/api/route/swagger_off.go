//go:build !swagger

package route

import (
	"log"

	"github.com/go-chi/chi/v5"
)

// mountSwagger is a no-op without `-tags swagger` (see swagger_on.go); it says so, so DEBUG_MODE=true does not
// look broken.
func mountSwagger(_ chi.Router) {
	log.Println("DEBUG_MODE: Swagger is not in this build (compile with -tags swagger)")
}
