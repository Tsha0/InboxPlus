package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	discordconnector "github.com/Tsha0/InboxPlus/native/connectors/discord"
	"github.com/Tsha0/InboxPlus/native/connectors/internal/securedb"
	"github.com/Tsha0/InboxPlus/native/connectors/linkedin"
	metaconnector "github.com/Tsha0/InboxPlus/native/connectors/meta"
	"github.com/Tsha0/InboxPlus/native/connectors/telegram"
	"github.com/Tsha0/InboxPlus/native/connectors/wechat"
	"github.com/Tsha0/InboxPlus/native/connectors/whatsapp"
)

type connector interface {
	Handle(context.Context, map[string]any) (any, error)
	Close() error
	HasSession() bool
}

type account struct {
	opMu      sync.Mutex
	cancelMu  sync.Mutex
	cancel    context.CancelFunc
	closing   bool
	connector connector
	directory string
	platform  string
	keyDigest [32]byte
}

type runtime struct {
	mu       sync.Mutex
	accounts map[string]*account
	eventMu  sync.Mutex
	events   [][]byte
	head     int
}

var embedded = &runtime{accounts: map[string]*account{}}

//export inboxplus_request
func inboxplus_request(input *C.char) *C.char {
	if input == nil {
		return C.CString(string(failure("invalid_request", "A JSON request is required")))
	}
	return C.CString(string(embedded.request([]byte(C.GoString(input)))))
}

//export inboxplus_poll_event
func inboxplus_poll_event() *C.char {
	if event := embedded.poll(); event != nil {
		return C.CString(string(event))
	}
	return nil
}

//export inboxplus_free
func inboxplus_free(pointer unsafe.Pointer) {
	C.free(pointer)
}

func (r *runtime) request(encoded []byte) (response []byte) {
	defer func() {
		if recover() != nil {
			response = failure("internal_error", "The connector could not complete this request")
		}
	}()
	if len(encoded) > 48*1024*1024 {
		return failure("invalid_request", "The request exceeds the size limit")
	}
	var req map[string]any
	if json.Unmarshal(encoded, &req) != nil || req == nil {
		return failure("invalid_request", "The request must be a JSON object")
	}
	op, _ := req["op"].(string)
	if op == "secure_directory" {
		directory, _ := req["directory"].(string)
		if err := securedb.SecureDirectory(directory); err != nil {
			return failure("storage_failed", "The private storage directory could not be secured")
		}
		return success(map[string]any{"secured": true})
	}
	if op == "capabilities" && req["account_id"] == nil {
		return success(map[string]any{"abi_version": 1, "platforms": []string{"whatsapp", "telegram", "instagram", "messenger", "wechat", "discord", "linkedIn"}, "max_attachment_bytes": 32 * 1024 * 1024, "features": map[string]any{
			"whatsapp":  whatsapp.Capabilities(),
			"telegram":  telegram.Capabilities(),
			"instagram": metaconnector.Capabilities("instagram"),
			"messenger": metaconnector.Capabilities("messenger"),
			"wechat":    wechat.Capabilities(),
			"discord":   discordconnector.Capabilities(),
			"linkedIn":  linkedin.Capabilities(),
		}})
	}
	if op == "shutdown" {
		r.mu.Lock()
		entries := make(map[string]*account, len(r.accounts))
		for id, entry := range r.accounts {
			entries[id] = entry
			entry.cancelActive(true)
		}
		r.mu.Unlock()
		var failed bool
		for id, entry := range entries {
			failed = r.closeAccount(id, entry) != nil || failed
		}
		if failed {
			return failure("storage_failed", "Some sessions could not close cleanly")
		}
		return success(map[string]any{"closed": true})
	}
	if op == "cancel" && req["account_id"] == nil {
		r.mu.Lock()
		for _, entry := range r.accounts {
			entry.cancelActive(false)
		}
		r.mu.Unlock()
		return success(map[string]any{"cancelled": true})
	}
	id, _ := req["account_id"].(string)
	if id == "" || len(id) > 128 {
		return failure("invalid_request", "An account identifier is required")
	}
	if op == "initialize" {
		r.mu.Lock()
		defer r.mu.Unlock()
		directory, _ := req["directory"].(string)
		if !filepath.IsAbs(directory) {
			return failure("invalid_request", "An absolute private account directory is required")
		}
		directory = filepath.Clean(directory)
		keyText, _ := req["key"].(string)
		key, err := base64.StdEncoding.DecodeString(keyText)
		if err != nil || len(key) != 32 {
			return failure("invalid_request", "A base64 encoded 32 byte account key is required")
		}
		if err := securedb.SecureDirectory(directory); err != nil {
			return failure("storage_failed", "The private account directory could not be secured")
		}
		directory, err = filepath.EvalSymlinks(directory)
		if err != nil {
			return failure("storage_failed", "The private account directory could not be resolved")
		}
		req["directory"] = directory
		for accountID, entry := range r.accounts {
			if accountID != id && entry.directory == directory {
				return failure("invalid_request", "Each account requires a separate private directory")
			}
		}
		platform, _ := req["platform"].(string)
		if entry, exists := r.accounts[id]; exists {
			if entry.directory != directory || entry.platform != platform || entry.keyDigest != sha256.Sum256(key) {
				return failure("invalid_request", "Close the existing account before changing its session configuration")
			}
			return success(map[string]any{"initialized": true})
		}
		var client connector
		switch platform {
		case "whatsapp":
			client, err = whatsapp.New(id, directory, key, r.emit)
		case "telegram":
			client, err = telegram.New(id, directory, key, r.emit)
		case "instagram", "messenger":
			client, err = metaconnector.New(req, r.emit)
		case "wechat":
			client, err = wechat.New(id, directory, key, r.emit)
		case "discord":
			client, err = discordconnector.New(id, directory, key, r.emit)
		case "linkedIn":
			client, err = linkedin.New(id, directory, key, r.emit)
		default:
			err = errors.New("This messaging platform is unavailable")
		}
		if err != nil {
			return failure("initialization_failed", "The account session could not be opened securely")
		}
		r.accounts[id] = &account{connector: client, directory: directory, platform: platform, keyDigest: sha256.Sum256(key)}
		return success(map[string]any{"initialized": true})
	}
	r.mu.Lock()
	entry, exists := r.accounts[id]
	r.mu.Unlock()
	if !exists {
		return failure("account_not_initialized", "Initialize this account before using it")
	}
	if op == "close" {
		entry.cancelActive(true)
		if err := r.closeAccount(id, entry); err != nil {
			return failure("storage_failed", "The account could not close cleanly")
		}
		return success(map[string]any{"closed": true, "has_session": entry.connector.HasSession()})
	}
	if op == "cancel" {
		entry.cancelActive(false)
		return success(map[string]any{"cancelled": true})
	}
	if op == "disconnect" || op == "logout" {
		entry.cancelActive(false)
	}
	entry.opMu.Lock()
	defer entry.opMu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	entry.cancelMu.Lock()
	if entry.closing {
		entry.cancelMu.Unlock()
		return failure("account_closed", "This account is closing")
	}
	entry.cancel = cancel
	entry.cancelMu.Unlock()
	defer func() {
		entry.cancelMu.Lock()
		entry.cancel = nil
		entry.cancelMu.Unlock()
	}()
	data, err := entry.connector.Handle(ctx, req)
	if err != nil {
		switch {
		case errors.Is(err, whatsapp.ErrInvalidPhone):
			return failure("whatsapp_invalid_phone", "Enter a valid international phone number")
		case errors.Is(err, whatsapp.ErrPairingNotReady):
			return failure("whatsapp_pairing_not_ready", "Wait for WhatsApp pairing to be ready")
		case errors.Is(err, whatsapp.ErrPairingExpired):
			return failure("whatsapp_pairing_expired", "Start a new WhatsApp pairing attempt")
		case errors.Is(err, whatsapp.ErrPhonePairing):
			return failure("whatsapp_phone_pairing_failed", "WhatsApp could not create a linking code")
		}
		return failure("operation_failed", "The messaging operation could not be completed")
	}
	return success(data)
}

func (a *account) cancelActive(closing bool) {
	a.cancelMu.Lock()
	defer a.cancelMu.Unlock()
	a.closing = a.closing || closing
	if a.cancel != nil {
		a.cancel()
	}
}

func (r *runtime) closeAccount(id string, entry *account) error {
	entry.opMu.Lock()
	defer entry.opMu.Unlock()
	err := entry.connector.Close()
	if err != nil {
		return err
	}
	r.mu.Lock()
	if r.accounts[id] == entry {
		delete(r.accounts, id)
	}
	r.mu.Unlock()
	return nil
}

func (r *runtime) emit(event map[string]any) {
	encoded, err := json.Marshal(event)
	if err != nil {
		return
	}
	r.eventMu.Lock()
	r.events = append(r.events, encoded)
	r.eventMu.Unlock()
}

func (r *runtime) poll() []byte {
	r.eventMu.Lock()
	defer r.eventMu.Unlock()
	if r.head == len(r.events) {
		return nil
	}
	event := r.events[r.head]
	r.events[r.head] = nil
	r.head++
	if r.head == len(r.events) {
		r.events = nil
		r.head = 0
	}
	return event
}

func success(data any) []byte {
	encoded, err := json.Marshal(map[string]any{"ok": true, "data": data})
	if err != nil {
		return failure("internal_error", "The connector response could not be encoded")
	}
	return encoded
}

func failure(code, message string) []byte {
	encoded, _ := json.Marshal(map[string]any{"ok": false, "error": map[string]any{"code": code, "message": message}})
	return encoded
}

func main() {}
