//go:build linux || darwin || freebsd

package files

import "syscall"

// freeBytes is the space an unprivileged process can still use on the disk that holds dir.
func freeBytes(dir string) (uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(dir, &st); err != nil {
		return 0, err
	}
	return uint64(st.Bavail) * uint64(st.Bsize), nil //nolint:unconvert // field types differ by platform
}
