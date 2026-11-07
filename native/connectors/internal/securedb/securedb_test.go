package securedb

import (
	"bytes"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

var testKey = bytes.Repeat([]byte{0x47}, 32)

func openTestDB(t *testing.T, directory string) *sql.DB {
	t.Helper()
	db, err := Open(directory, testKey)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func execTest(t *testing.T, db *sql.DB, query string, args ...any) {
	t.Helper()
	if _, err := db.Exec(query, args...); err != nil {
		t.Fatal(err)
	}
}

func valueTest(t *testing.T, db *sql.DB) string {
	t.Helper()
	var value string
	if err := db.QueryRow("SELECT value FROM credentials WHERE id=1").Scan(&value); err != nil {
		t.Fatal(err)
	}
	return value
}

func TestEverySuccessfulWriteIsEncryptedAndDurableBeforeClose(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT)")
	execTest(t, db, "INSERT INTO credentials VALUES (1, ?)", "private-session-secret")
	if got := valueTest(t, openTestDB(t, directory)); got != "private-session-secret" {
		t.Fatalf("restored %q", got)
	}
	sealed, err := os.ReadFile(filepath.Join(directory, "credentials.db.enc"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(sealed, []byte("private-session-secret")) || bytes.Contains(sealed, []byte("SQLite format")) {
		t.Fatal("plaintext persisted")
	}
	if runtime.GOOS != "windows" {
		for path, mode := range map[string]os.FileMode{directory: 0700, filepath.Join(directory, "credentials.db.enc"): 0600} {
			info, err := os.Stat(path)
			if err != nil {
				t.Fatal(err)
			}
			if got := info.Mode().Perm(); got != mode {
				t.Fatalf("%s mode %o", path, got)
			}
		}
	}
	execTest(t, db, "UPDATE credentials SET value=? WHERE id=1", "next-ratchet")
	if got := valueTest(t, openTestDB(t, directory)); got != "next-ratchet" {
		t.Fatalf("update lost: %q", got)
	}
}

func TestTransactionCommitsAndRollbacks(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT); INSERT INTO credentials VALUES (1, 'initial')")
	before, err := os.ReadFile(filepath.Join(directory, "credentials.db.enc"))
	if err != nil {
		t.Fatal(err)
	}
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec("UPDATE credentials SET value='uncommitted' WHERE id=1"); err != nil {
		t.Fatal(err)
	}
	during, err := os.ReadFile(filepath.Join(directory, "credentials.db.enc"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, during) {
		t.Fatal("uncommitted transaction persisted")
	}
	if err := tx.Rollback(); err != nil {
		t.Fatal(err)
	}
	if got := valueTest(t, openTestDB(t, directory)); got != "initial" {
		t.Fatalf("rollback persisted %q", got)
	}
	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec("UPDATE credentials SET value='committed' WHERE id=1"); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if got := valueTest(t, openTestDB(t, directory)); got != "committed" {
		t.Fatalf("commit lost: %q", got)
	}
}

func TestPreparedStatementsAndReturningPersist(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT)")
	stmt, err := db.Prepare("INSERT INTO credentials VALUES (1, ?)")
	if err != nil {
		t.Fatal(err)
	}
	defer stmt.Close()
	if _, err := stmt.Exec("prepared-secret"); err != nil {
		t.Fatal(err)
	}
	if got := valueTest(t, openTestDB(t, directory)); got != "prepared-secret" {
		t.Fatalf("prepared write lost: %q", got)
	}
	var value string
	if err := db.QueryRow("UPDATE credentials SET value='returning-secret' WHERE id=1 RETURNING value").Scan(&value); err != nil {
		t.Fatal(err)
	}
	if got := valueTest(t, openTestDB(t, directory)); got != "returning-secret" {
		t.Fatalf("RETURNING write lost: %q", got)
	}
	query, err := db.Prepare("UPDATE credentials SET value=? WHERE id=1 RETURNING value")
	if err != nil {
		t.Fatal(err)
	}
	defer query.Close()
	if err := query.QueryRow("prepared-returning").Scan(&value); err != nil {
		t.Fatal(err)
	}
	if got := valueTest(t, openTestDB(t, directory)); got != "prepared-returning" {
		t.Fatalf("prepared RETURNING write lost: %q", got)
	}
}

func TestRestoredDatabaseCanGrow(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT)")
	execTest(t, db, "INSERT INTO credentials VALUES (1, 'small')")
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	restored := openTestDB(t, directory)
	large := string(bytes.Repeat([]byte("secret"), 10000))
	execTest(t, restored, "UPDATE credentials SET value=? WHERE id=1", large)
	if got := valueTest(t, openTestDB(t, directory)); got != large {
		t.Fatal("restored database did not grow")
	}
}

func TestWrongKeyAndCorruptionNeverResetExistingStore(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT); INSERT INTO credentials VALUES (1, 'secret')")
	path := filepath.Join(directory, "credentials.db.enc")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Open(directory, bytes.Repeat([]byte{0x99}, 32)); !errors.Is(err, ErrOpen) {
		t.Fatalf("wrong key error: %v", err)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("wrong key changed the store")
	}
	corrupt := append([]byte(nil), before...)
	corrupt[len(corrupt)-1] ^= 0x80
	if err := os.WriteFile(path, corrupt, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(directory, testKey); !errors.Is(err, ErrOpen) {
		t.Fatalf("corruption error: %v", err)
	}
	after, err = os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(corrupt, after) {
		t.Fatal("corrupt store was reset")
	}
}

func TestFailedPersistencePoisonsConnection(t *testing.T) {
	directory := t.TempDir()
	failures := 0
	db, err := OpenWithFailure(directory, testKey, func() { failures++ })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT); INSERT INTO credentials VALUES (1, 'last-durable')")
	path := filepath.Join(directory, "credentials.db.enc")
	previous, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	moved := directory + "-moved"
	if err := os.Rename(directory, moved); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(moved) })
	if _, err := db.Exec("UPDATE credentials SET value='must-fail' WHERE id=1"); !errors.Is(err, ErrPersistence) {
		t.Fatalf("write error: %v", err)
	}
	if _, err := db.Exec("UPDATE credentials SET value='must-stay-poisoned' WHERE id=1"); !errors.Is(err, ErrPersistence) {
		t.Fatalf("later write error: %v", err)
	}
	if failures != 1 {
		t.Fatalf("persistence failure callback ran %d times", failures)
	}
	after, err := os.ReadFile(filepath.Join(moved, "credentials.db.enc"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(previous, after) {
		t.Fatal("last durable snapshot changed")
	}
	if got := valueTest(t, openTestDB(t, moved)); got != "last-durable" {
		t.Fatalf("failed mutation persisted %q", got)
	}
}

func TestLinkedDirectoriesAndSnapshotFilesAreRejected(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows symlink creation requires developer mode or administrator rights")
	}
	root := t.TempDir()
	outside := t.TempDir()
	linked := filepath.Join(root, "linked")
	if err := os.Symlink(outside, linked); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(filepath.Join(linked, "child"), testKey); !errors.Is(err, ErrOpen) {
		t.Fatal("linked ancestor accepted")
	}
	if _, err := os.Stat(filepath.Join(outside, "child")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("linked ancestor was followed before validation")
	}
	directory := filepath.Join(root, "account")
	if err := SecureDirectory(directory); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(outside, "secret")
	if err := os.WriteFile(file, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(file, filepath.Join(directory, "credentials.db.enc")); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(directory, testKey); !errors.Is(err, ErrOpen) {
		t.Fatal("linked encrypted snapshot accepted")
	}
	if err := SecureFile(filepath.Join(directory, "credentials.db.enc")); !errors.Is(err, ErrOpen) {
		t.Fatal("linked file accepted for permission change")
	}
}

func TestReadsDoNotRewriteEncryptedSnapshot(t *testing.T) {
	directory := t.TempDir()
	db := openTestDB(t, directory)
	execTest(t, db, "CREATE TABLE credentials (id INTEGER PRIMARY KEY, value TEXT); INSERT INTO credentials VALUES (1, 'secret')")
	path := filepath.Join(directory, "credentials.db.enc")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	_ = valueTest(t, db)
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("read rewrote snapshot")
	}
}
