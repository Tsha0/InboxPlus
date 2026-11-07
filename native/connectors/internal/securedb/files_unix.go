//go:build !windows

package securedb

import (
	"os"
	"path/filepath"
)

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
