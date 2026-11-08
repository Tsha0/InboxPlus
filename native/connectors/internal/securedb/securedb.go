package securedb

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"database/sql"
	"database/sql/driver"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/mattn/go-sqlite3"
)

var (
	ErrOpen        = errors.New("Secure session storage could not be opened.")
	ErrDatabase    = errors.New("Secure session database operation failed.")
	ErrPersistence = errors.New("Secure session changes could not be saved. Reopen the account before reconnecting.")
)

var header = []byte("INBOXPLUS-SESSION\x01")

type storage struct {
	mu          sync.Mutex
	lock        *os.File
	closed      bool
	connections int
	path        string
	aead        cipher.AEAD
	failed      atomic.Bool
	onFailure   func()
}

type connector struct{ storage *storage }
type sqliteDriver struct{ storage *storage }

func SecureDirectory(directory string) error {
	if !filepath.IsAbs(directory) {
		return ErrOpen
	}
	if err := rejectLinkedAncestors(directory); err != nil {
		return err
	}
	if err := os.MkdirAll(directory, 0700); err != nil {
		return ErrOpen
	}
	info, err := os.Lstat(directory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return ErrOpen
	}
	if err := makePrivate(directory, 0700); err != nil {
		return ErrOpen
	}
	return nil
}

func Open(directory string, key []byte) (*sql.DB, error) {
	return OpenWithFailure(directory, key, nil)
}

func OpenWithFailure(directory string, key []byte, onFailure func()) (*sql.DB, error) {
	if len(key) != 32 {
		return nil, ErrOpen
	}
	if err := SecureDirectory(directory); err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, ErrOpen
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, ErrOpen
	}
	s := &storage{path: filepath.Join(directory, "credentials.db.enc"), aead: aead, onFailure: onFailure}
	s.lock, err = lockSnapshot(filepath.Join(directory, ".credentials.lock"))
	if err != nil {
		return nil, ErrOpen
	}
	db := sql.OpenDB(&connector{storage: s})
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, ErrOpen
	}
	return db, nil
}

func SecureFile(path string) error {
	if !filepath.IsAbs(path) || rejectLinkedAncestors(filepath.Dir(path)) != nil {
		return ErrOpen
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() {
		return ErrOpen
	}
	if err := makePrivate(path, 0600); err != nil {
		return ErrOpen
	}
	return nil
}

func ReplaceSnapshot(source, destination string) error {
	if !filepath.IsAbs(source) || filepath.Dir(source) != filepath.Dir(destination) || SecureFile(source) != nil {
		return ErrPersistence
	}
	if info, err := os.Lstat(destination); err == nil && !info.Mode().IsRegular() {
		return ErrPersistence
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return ErrPersistence
	}
	if err := replaceSnapshot(source, destination); err != nil {
		return ErrPersistence
	}
	return nil
}

func rejectLinkedAncestors(path string) error {
	path = filepath.Clean(path)
	if runtime.GOOS == "darwin" {
		for _, prefix := range []string{"/var", "/tmp", "/etc"} {
			if path == prefix || strings.HasPrefix(path, prefix+"/") {
				path = "/private" + path
				break
			}
		}
	}
	for {
		info, err := os.Lstat(path)
		if err == nil && (!info.IsDir() || info.Mode()&os.ModeSymlink != 0) {
			return ErrOpen
		}
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return ErrOpen
		}
		parent := filepath.Dir(path)
		if parent == path {
			return nil
		}
		path = parent
	}
}

func (c *connector) Connect(context.Context) (driver.Conn, error) { return c.storage.open() }
func (c *connector) Driver() driver.Driver                        { return &sqliteDriver{storage: c.storage} }
func (d *sqliteDriver) Open(string) (driver.Conn, error)          { return d.storage.open() }

func (c *connector) Close() error {
	s := c.storage
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
	return s.releaseLock()
}

func (s *storage) releaseLock() error {
	if s.closed && s.connections == 0 && s.lock != nil {
		err := s.lock.Close()
		s.lock = nil
		return err
	}
	return nil
}

func (s *storage) open() (driver.Conn, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return nil, ErrOpen
	}
	if s.failed.Load() {
		return nil, ErrPersistence
	}
	raw, err := (&sqlite3.SQLiteDriver{}).Open(":memory:?_foreign_keys=on&_journal_mode=MEMORY")
	if err != nil {
		return nil, ErrOpen
	}
	native := raw.(*sqlite3.SQLiteConn)
	if _, err := native.Exec("PRAGMA temp_store = MEMORY", nil); err != nil {
		_ = native.Close()
		return nil, ErrOpen
	}
	plain, err := s.load()
	if err == nil && plain != nil {
		err = restore(native, plain)
		clear(plain)
	}
	if err != nil {
		_ = native.Close()
		return nil, ErrOpen
	}
	c := &connection{native: native, storage: s}
	s.connections++
	// The hook detects commits from every SQL path, including schema migrations and RETURNING.
	native.RegisterCommitHook(func() int { c.pending = true; return 0 })
	return c, nil
}

func (s *storage) load() ([]byte, error) {
	info, err := os.Lstat(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil || !info.Mode().IsRegular() {
		return nil, ErrOpen
	}
	if err := makePrivate(s.path, 0600); err != nil {
		return nil, ErrOpen
	}
	sealed, err := os.ReadFile(s.path)
	if err != nil || len(sealed) < len(header)+s.aead.NonceSize()+s.aead.Overhead() || string(sealed[:len(header)]) != string(header) {
		return nil, ErrOpen
	}
	nonce := sealed[len(header) : len(header)+s.aead.NonceSize()]
	plain, err := s.aead.Open(nil, nonce, sealed[len(header)+s.aead.NonceSize():], header)
	if err != nil {
		return nil, ErrOpen
	}
	return plain, nil
}

func restore(destination *sqlite3.SQLiteConn, plain []byte) error {
	raw, err := (&sqlite3.SQLiteDriver{}).Open(":memory:")
	if err != nil {
		return err
	}
	source := raw.(*sqlite3.SQLiteConn)
	defer source.Close()
	if err := source.Deserialize(plain, "main"); err != nil {
		return err
	}
	// Backup makes the restored database growable; Deserialize's allocation is fixed in this driver.
	backup, err := destination.Backup("main", source, "main")
	if err != nil {
		return err
	}
	done, err := backup.Step(-1)
	finishErr := backup.Finish()
	if err != nil {
		return err
	}
	if !done || finishErr != nil {
		return ErrOpen
	}
	return nil
}

func (s *storage) save(plain []byte) error {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return ErrPersistence
	}
	sealed := append(append([]byte(nil), header...), nonce...)
	sealed = s.aead.Seal(sealed, nonce, plain, header)
	file, err := os.CreateTemp(filepath.Dir(s.path), ".credentials-*.enc")
	if err != nil {
		return ErrPersistence
	}
	name := file.Name()
	defer os.Remove(name)
	if err := makePrivate(name, 0600); err != nil {
		_ = file.Close()
		return ErrPersistence
	}
	if _, err = file.Write(sealed); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil || closeErr != nil {
		return ErrPersistence
	}
	if err := replaceSnapshot(name, s.path); err != nil {
		return ErrPersistence
	}
	return nil
}

type connection struct {
	native  *sqlite3.SQLiteConn
	storage *storage
	pending bool
}

func (c *connection) check() error {
	if c.storage.failed.Load() {
		return ErrPersistence
	}
	return nil
}

func (c *connection) persist() error {
	if err := c.check(); err != nil {
		return err
	}
	if !c.pending || !c.native.AutoCommit() {
		return nil
	}
	plain, err := c.native.Serialize("main")
	if err == nil {
		err = c.storage.save(plain)
		clear(plain)
	}
	if err != nil {
		if c.storage.failed.CompareAndSwap(false, true) && c.storage.onFailure != nil {
			c.storage.onFailure()
		}
		return ErrPersistence
	}
	c.pending = false
	return nil
}

func (c *connection) Close() error {
	err := c.native.Close()
	c.storage.mu.Lock()
	defer c.storage.mu.Unlock()
	c.storage.connections--
	lockErr := c.storage.releaseLock()
	if err != nil {
		return err
	}
	return lockErr
}
func (c *connection) Ping(context.Context) error { return c.check() }
func (c *connection) Prepare(query string) (driver.Stmt, error) {
	return c.PrepareContext(context.Background(), query)
}
func (c *connection) PrepareContext(ctx context.Context, query string) (driver.Stmt, error) {
	if err := c.check(); err != nil {
		return nil, err
	}
	s, err := c.native.PrepareContext(ctx, query)
	if err != nil {
		return nil, ErrDatabase
	}
	return &statement{native: s.(*sqlite3.SQLiteStmt), connection: c}, nil
}
func (c *connection) Begin() (driver.Tx, error) {
	return c.BeginTx(context.Background(), driver.TxOptions{})
}
func (c *connection) BeginTx(ctx context.Context, opts driver.TxOptions) (driver.Tx, error) {
	if err := c.check(); err != nil {
		return nil, err
	}
	tx, err := c.native.BeginTx(ctx, opts)
	if err != nil {
		return nil, ErrDatabase
	}
	return &transaction{native: tx, connection: c}, nil
}
func (c *connection) ExecContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Result, error) {
	if err := c.check(); err != nil {
		return nil, err
	}
	result, err := c.native.ExecContext(ctx, query, args)
	if saveErr := c.persist(); saveErr != nil {
		return nil, saveErr
	}
	if err != nil {
		return nil, ErrDatabase
	}
	return result, nil
}
func (c *connection) QueryContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Rows, error) {
	if err := c.check(); err != nil {
		return nil, err
	}
	r, err := c.native.QueryContext(ctx, query, args)
	if err != nil {
		if saveErr := c.persist(); saveErr != nil {
			return nil, saveErr
		}
		return nil, ErrDatabase
	}
	return &rows{native: r, connection: c}, nil
}

type statement struct {
	native     *sqlite3.SQLiteStmt
	connection *connection
}

func (s *statement) Close() error  { return s.native.Close() }
func (s *statement) NumInput() int { return s.native.NumInput() }
func (s *statement) Exec(args []driver.Value) (driver.Result, error) {
	if err := s.connection.check(); err != nil {
		return nil, err
	}
	result, err := s.native.Exec(args)
	if saveErr := s.connection.persist(); saveErr != nil {
		return nil, saveErr
	}
	if err != nil {
		return nil, ErrDatabase
	}
	return result, nil
}
func (s *statement) Query(args []driver.Value) (driver.Rows, error) {
	if err := s.connection.check(); err != nil {
		return nil, err
	}
	r, err := s.native.Query(args)
	if err != nil {
		if saveErr := s.connection.persist(); saveErr != nil {
			return nil, saveErr
		}
		return nil, ErrDatabase
	}
	return &rows{native: r, connection: s.connection}, nil
}
func (s *statement) ExecContext(ctx context.Context, args []driver.NamedValue) (driver.Result, error) {
	if err := s.connection.check(); err != nil {
		return nil, err
	}
	result, err := s.native.ExecContext(ctx, args)
	if saveErr := s.connection.persist(); saveErr != nil {
		return nil, saveErr
	}
	if err != nil {
		return nil, ErrDatabase
	}
	return result, nil
}
func (s *statement) QueryContext(ctx context.Context, args []driver.NamedValue) (driver.Rows, error) {
	if err := s.connection.check(); err != nil {
		return nil, err
	}
	r, err := s.native.QueryContext(ctx, args)
	if err != nil {
		if saveErr := s.connection.persist(); saveErr != nil {
			return nil, saveErr
		}
		return nil, ErrDatabase
	}
	return &rows{native: r, connection: s.connection}, nil
}

type transaction struct {
	native     driver.Tx
	connection *connection
}

func (t *transaction) Commit() error {
	if err := t.connection.check(); err != nil {
		return err
	}
	err := t.native.Commit()
	if saveErr := t.connection.persist(); saveErr != nil {
		return saveErr
	}
	if err != nil {
		return ErrDatabase
	}
	return nil
}
func (t *transaction) Rollback() error {
	if err := t.native.Rollback(); err != nil {
		return ErrDatabase
	}
	return t.connection.persist()
}

type rows struct {
	native     driver.Rows
	connection *connection
	closed     bool
}

func (r *rows) Columns() []string { return r.native.Columns() }
func (r *rows) Close() error {
	if r.closed {
		return nil
	}
	r.closed = true
	err := r.native.Close()
	if saveErr := r.connection.persist(); saveErr != nil {
		return saveErr
	}
	if err != nil {
		return ErrDatabase
	}
	return nil
}
func (r *rows) Next(dest []driver.Value) error {
	if err := r.connection.check(); err != nil {
		return err
	}
	err := r.native.Next(dest)
	if err == io.EOF {
		return err
	}
	if err != nil {
		return ErrDatabase
	}
	return nil
}
