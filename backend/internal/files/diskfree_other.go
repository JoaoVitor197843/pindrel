//go:build !(linux || darwin || freebsd)

package files

import "math"

// freeBytes: on a platform where the free space cannot be read, the check is off (the server image is Linux).
func freeBytes(string) (uint64, error) { return math.MaxUint64, nil }
