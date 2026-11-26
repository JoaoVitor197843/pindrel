//go:build windows

package files

import "golang.org/x/sys/windows"

// freeBytes is the space this user can still use on the disk that holds dir (quotas included).
func freeBytes(dir string) (uint64, error) {
	p, err := windows.UTF16PtrFromString(dir)
	if err != nil {
		return 0, err
	}
	var free uint64
	if err := windows.GetDiskFreeSpaceEx(p, &free, nil, nil); err != nil {
		return 0, err
	}
	return free, nil
}
