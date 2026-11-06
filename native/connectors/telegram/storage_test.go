package telegram

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/gotd/td/session"
)

func TestSessionStoragePersistsOnlyCiphertext(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "telegram")
	key := bytes.Repeat([]byte{31}, 32)
	storage, err := newSessionStorage(directory, key)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := storage.LoadSession(context.Background()); !errors.Is(err, session.ErrNotFound) {
		t.Fatalf("missing session error = %v", err)
	}
	plaintext := []byte(`{"auth_key":"offline-test-secret","dc":2}`)
	if err := storage.StoreSession(context.Background(), plaintext); err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(filepath.Join(directory, sessionFilename))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(first, plaintext) || bytes.Contains(first, []byte("offline-test-secret")) {
		t.Fatal("session was persisted in plaintext")
	}
	if err := storage.StoreSession(context.Background(), plaintext); err != nil {
		t.Fatal(err)
	}
	second, err := os.ReadFile(filepath.Join(directory, sessionFilename))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(first, second) {
		t.Fatal("session writes reused the encryption nonce")
	}
	reopened, err := newSessionStorage(directory, key)
	if err != nil {
		t.Fatal(err)
	}
	got, err := reopened.LoadSession(context.Background())
	if err != nil || !bytes.Equal(got, plaintext) {
		t.Fatalf("reopened session = %q, error = %v", got, err)
	}
	entries, err := os.ReadDir(directory)
	if err != nil || len(entries) != 1 || entries[0].Name() != sessionFilename {
		t.Fatalf("unexpected storage files = %v, error = %v", entries, err)
	}
	if runtime.GOOS != "windows" {
		for path, want := range map[string]os.FileMode{directory: 0700, filepath.Join(directory, sessionFilename): 0600} {
			info, err := os.Stat(path)
			if err != nil || info.Mode().Perm() != want {
				t.Fatalf("storage permissions for %s = %v, error = %v", path, info, err)
			}
		}
	}
}

func TestSessionPresencePreservesAnyStoredAuthorizationMaterial(t *testing.T) {
	client, err := New("account", t.TempDir(), bytes.Repeat([]byte{25}, 32), func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	if client.HasSession() {
		t.Fatal("new empty session was reported as authorized material")
	}
	if err := client.storage.StoreSession(context.Background(), []byte("fixture-auth-key")); err != nil {
		t.Fatal(err)
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	if !client.HasSession() {
		t.Fatal("closing discarded stored authorization material")
	}
}

func TestSessionStorageRejectsWrongKeyAndCorruption(t *testing.T) {
	directory := t.TempDir()
	storage, err := newSessionStorage(directory, bytes.Repeat([]byte{1}, 32))
	if err != nil {
		t.Fatal(err)
	}
	if err := storage.StoreSession(context.Background(), []byte("session-data")); err != nil {
		t.Fatal(err)
	}
	wrongKey, err := newSessionStorage(directory, bytes.Repeat([]byte{2}, 32))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := wrongKey.LoadSession(context.Background()); !errors.Is(err, errSessionDecryption) || errors.Is(err, session.ErrNotFound) {
		t.Fatalf("wrong key error = %v", err)
	}
	path := filepath.Join(directory, sessionFilename)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, corrupted := range [][]byte{nil, []byte("unrecognized-version"), append([]byte(nil), data...)} {
		if len(corrupted) == len(data) {
			corrupted[len(corrupted)-1] ^= 1
		}
		if err := os.WriteFile(path, corrupted, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := storage.LoadSession(context.Background()); !errors.Is(err, errSessionDecryption) || errors.Is(err, session.ErrNotFound) {
			t.Fatalf("corrupt session error = %v", err)
		}
	}
}

func TestSessionStorageRejectsUnsafePaths(t *testing.T) {
	key := bytes.Repeat([]byte{1}, 32)
	if _, err := newSessionStorage(t.TempDir(), key[:31]); err == nil {
		t.Fatal("invalid key accepted")
	}
	directory := t.TempDir()
	target := filepath.Join(t.TempDir(), "target")
	if err := os.WriteFile(target, []byte("leave-unchanged"), 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(directory, sessionFilename)
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	storage, err := newSessionStorage(directory, key)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := storage.LoadSession(context.Background()); err == nil {
		t.Fatal("symlink session was read")
	}
	if err := storage.StoreSession(context.Background(), []byte("replacement")); err == nil {
		t.Fatal("symlink session was replaced")
	}
	got, err := os.ReadFile(target)
	if err != nil || string(got) != "leave-unchanged" {
		t.Fatalf("symlink target = %q, error = %v", got, err)
	}
	directoryLink := filepath.Join(t.TempDir(), "telegram")
	if err := os.Symlink(directory, directoryLink); err != nil {
		t.Fatal(err)
	}
	if _, err := newSessionStorage(directoryLink, key); err == nil {
		t.Fatal("symlink session directory accepted")
	}
}

func TestSessionStorageCancellationPreservesSession(t *testing.T) {
	storage, err := newSessionStorage(t.TempDir(), bytes.Repeat([]byte{1}, 32))
	if err != nil {
		t.Fatal(err)
	}
	if err := storage.StoreSession(context.Background(), []byte("original")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := storage.StoreSession(ctx, []byte("replacement")); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled store error = %v", err)
	}
	if _, err := storage.LoadSession(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled load error = %v", err)
	}
	got, err := storage.LoadSession(context.Background())
	if err != nil || string(got) != "original" {
		t.Fatalf("preserved session = %q, error = %v", got, err)
	}
}

func TestSessionStorageRepairsPermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix permission bits are not supported on Windows")
	}
	directory := t.TempDir()
	key := bytes.Repeat([]byte{1}, 32)
	storage, err := newSessionStorage(directory, key)
	if err != nil {
		t.Fatal(err)
	}
	if err := storage.StoreSession(context.Background(), []byte("session")); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, sessionFilename)
	if err := os.Chmod(directory, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	reopened, err := newSessionStorage(directory, key)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reopened.LoadSession(context.Background()); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]os.FileMode{directory: 0700, path: 0600} {
		info, err := os.Stat(path)
		if err != nil || info.Mode().Perm() != want {
			t.Fatalf("repaired storage permissions for %s = %v, error = %v", path, info, err)
		}
	}
}
