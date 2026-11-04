//go:build swagger

package route

import (
	"github.com/go-chi/chi/v5"
	httpSwagger "github.com/swaggo/http-swagger"
)

// mountSwagger serves the Swagger UI. It only exists in a binary built with `-tags swagger`: swaggo/files copies
// ~35 MB of UI files into an in-memory filesystem when it is imported (~9 MiB of live heap, measured), RAM that a
// release image never uses.
func mountSwagger(r chi.Router) {
	r.Get("/swagger/*", httpSwagger.WrapHandler)
}
