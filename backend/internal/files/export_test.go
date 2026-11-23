package files

import "math"

// Sample is the first bytes of real formats, shared with the external tests.
var Sample = sample

// CleanName is exported for the external tests.
var CleanName = cleanName

// FreeSpaceIsReadable says whether this platform can read the free space of the disk that holds dir. Where it cannot
// (diskfree_other.go: anything but Linux, macOS and FreeBSD) the "server is out of space" check is off by design, and the
// tests of that check have nothing to test.
func FreeSpaceIsReadable(dir string) bool {
	free, err := freeBytes(dir)
	return err == nil && free != math.MaxUint64
}
