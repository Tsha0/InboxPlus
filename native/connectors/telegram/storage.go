package telegram

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/securedb"
	"github.com/gotd/td/session"
)

const sessionFilename = "session.enc"
const sessionFormat = "InboxPlus Telegram session v1\x00"

var errSessionStorage = errors.New("Telegram session storage failed")
var errSessionDecryption = errors.New("Telegram session could not be decrypted")

type sessionStorage struct {
	directory string
	aead      cipher.AEAD
	mu        sync.Mutex
}

func newSessionStorage(directory string, key []byte) (*sessionStorage, error) {
	if directory == "" || len(key) != 32 {
		return nil, errSessionStorage
	}
	if err := securedb.SecureDirectory(directory); err != nil {
		return nil, errSessionStorage
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, errSessionStorage
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, errSessionStorage
	}
	return &sessionStorage{directory: filepath.Clean(directory), aead: aead}, nil
}

func (s *sessionStorage) root() (*os.Root, error) {
	info, err := os.Lstat(s.directory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errSessionStorage
	}
	root, err := os.OpenRoot(s.directory)
	if err != nil {
		return nil, errSessionStorage
	}
	return root, nil
}

func (s *sessionStorage) LoadSession(ctx context.Context) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	root, err := s.root()
	if err != nil {
		return nil, err
	}
	defer root.Close()
	info, err := root.Lstat(sessionFilename)
	if errors.Is(err, os.ErrNotExist) {
		return nil, session.ErrNotFound
	}
	if err != nil || !info.Mode().IsRegular() {
		return nil, errSessionStorage
	}
	file, err := root.Open(sessionFilename)
	if err != nil {
		return nil, errSessionStorage
	}
	defer file.Close()
	if err := securedb.SecureFile(filepath.Join(s.directory, sessionFilename)); err != nil {
		return nil, errSessionStorage
	}
	data, err := io.ReadAll(file)
	if err != nil {
		return nil, errSessionStorage
	}
	if len(data) < len(sessionFormat)+s.aead.NonceSize()+s.aead.Overhead() || !bytes.HasPrefix(data, []byte(sessionFormat)) {
		return nil, errSessionDecryption
	}
	nonce := data[len(sessionFormat) : len(sessionFormat)+s.aead.NonceSize()]
	plaintext, err := s.aead.Open(nil, nonce, data[len(sessionFormat)+s.aead.NonceSize():], []byte(sessionFormat))
	if err != nil {
		return nil, errSessionDecryption
	}
	return plaintext, nil
}

func (s *sessionStorage) hasSession() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	root, err := s.root()
	if err != nil {
		return true
	}
	defer root.Close()
	_, err = root.Lstat(sessionFilename)
	return !errors.Is(err, os.ErrNotExist)
}

func (s *sessionStorage) StoreSession(ctx context.Context, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	root, err := s.root()
	if err != nil {
		return err
	}
	defer root.Close()
	if info, err := root.Lstat(sessionFilename); err == nil {
		if !info.Mode().IsRegular() {
			return errSessionStorage
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return errSessionStorage
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return errSessionStorage
	}
	ciphertext := make([]byte, 0, len(sessionFormat)+len(nonce)+len(data)+s.aead.Overhead())
	ciphertext = append(ciphertext, sessionFormat...)
	ciphertext = append(ciphertext, nonce...)
	ciphertext = s.aead.Seal(ciphertext, nonce, data, []byte(sessionFormat))
	temporaryName := ".session-" + hex.EncodeToString(nonce) + ".tmp"
	file, err := root.OpenFile(temporaryName, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return errSessionStorage
	}
	defer root.Remove(temporaryName)
	if err := securedb.SecureFile(filepath.Join(s.directory, temporaryName)); err != nil {
		file.Close()
		return errSessionStorage
	}
	if _, err := file.Write(ciphertext); err != nil {
		file.Close()
		return errSessionStorage
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return errSessionStorage
	}
	if err := file.Close(); err != nil {
		return errSessionStorage
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := securedb.ReplaceSnapshot(filepath.Join(s.directory, temporaryName), filepath.Join(s.directory, sessionFilename)); err != nil {
		return errSessionStorage
	}
	return nil
}
