//go:build !windows

package securedb

import (
	"os"
	"path/filepath"

	"golang.org/x/sys/unix"
)

func lockSnapshot(path string) (*os.File, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR|unix.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, ErrOpen
	}
	if SecureFile(path) != nil || unix.Flock(int(file.Fd()), unix.LOCK_EX|unix.LOCK_NB) != nil {
		_ = file.Close()
		return nil, ErrOpen
	}
	return file, nil
}

func makePrivate(path string, mode os.FileMode) error { return os.Chmod(path, mode) }

func replaceSnapshot(source, destination string) error {
	if err := os.Rename(source, destination); err != nil {
		return err
	}
	directory, err := os.Open(filepath.Dir(destination))
	if err != nil {
		return err
	}
	err = directory.Sync()
	closeErr := directory.Close()
	if err != nil {
		return err
	}
	return closeErr
}
