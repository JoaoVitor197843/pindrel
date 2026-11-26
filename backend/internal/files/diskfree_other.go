//go:build !(linux || darwin || freebsd || windows)

package files

import "math"

// freeBytes: on a platform where the free space cannot be read, the check is off.
func freeBytes(string) (uint64, error) { return math.MaxUint64, nil }
