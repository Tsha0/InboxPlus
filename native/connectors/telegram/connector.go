package telegram

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	errPasswordNeeded     = errors.New("telegram_password_required")
	errNotConnected       = errors.New("telegram_not_connected")
	errInvalidState       = errors.New("telegram_invalid_login_state")
	errClosed             = errors.New("telegram_closed")
	errSendOutcomeUnknown = errors.New("telegram_send_outcome_unknown")
)

type backend interface {
	Run(context.Context, func(bool, error)) error
	SendCode(context.Context, string) (string, error)
	SignIn(context.Context, string, string, string) error
	Password(context.Context, string) error
	Sync(context.Context) error
	History(context.Context, string, int) error
	Resolve(context.Context, string) (any, error)
	SendText(context.Context, string, string, string, string) (any, error)
	SendAttachment(context.Context, string, []byte, string, string, string, string, string) (any, error)
	Download(context.Context, string) (any, error)
	React(context.Context, string, string, string) (any, error)
	LogOut(context.Context) error
}

type Connector struct {
	operations sync.Mutex
	mu         sync.Mutex
	accountID  string
	storage    *sessionStorage
	emit       func(map[string]any)
	backend    backend
	cancel     context.CancelFunc
	done       chan struct{}
	state      string
	phone      string
	codeHash   string
	closed     bool
	running    bool
}

func New(accountID, directory string, key []byte, emit func(map[string]any)) (*Connector, error) {
	if strings.TrimSpace(accountID) == "" || emit == nil {
		return nil, errors.New("telegram_invalid_configuration")
	}
	storage, err := newSessionStorage(directory, key)
	if err != nil {
		return nil, err
	}
	return &Connector{accountID: accountID, storage: storage, emit: emit, state: "disconnected"}, nil
}

func (c *Connector) Handle(ctx context.Context, request map[string]any) (any, error) {
	c.operations.Lock()
	defer c.operations.Unlock()
	c.mu.Lock()
	closed := c.closed
	c.mu.Unlock()
	if closed {
		return nil, errClosed
	}
	op, _ := request["op"].(string)
	if op == "capabilities" {
		return Capabilities(), nil
	}
	if op == "connect" {
		return c.connect(ctx, request)
	}
	if op == "disconnect" {
		c.stop()
		c.setState("disconnected")
		return map[string]any{"state": "disconnected"}, nil
	}
	c.mu.Lock()
	b, state := c.backend, c.state
	c.mu.Unlock()
	if b == nil || state == "disconnected" || state == "connecting" {
		return nil, errNotConnected
	}
	switch op {
	case "login_phone":
		if state != "phone" && state != "code" {
			return nil, errInvalidState
		}
		phone := stringValue(request, "phone")
		if !validPhone(phone) {
			return nil, errors.New("telegram_invalid_phone")
		}
		hash, err := b.SendCode(ctx, phone)
		if err != nil {
			return nil, sanitizeError(err)
		}
		c.phone, c.codeHash = phone, hash
		if !c.setState("code") {
			return nil, errNotConnected
		}
		return map[string]any{"state": "code"}, nil
	case "login_code":
		if state != "code" {
			return nil, errInvalidState
		}
		code := stringValue(request, "code")
		if code == "" {
			return nil, errors.New("telegram_invalid_code")
		}
		if err := b.SignIn(ctx, c.phone, code, c.codeHash); err != nil {
			if errors.Is(err, errPasswordNeeded) {
				if !c.setState("password") {
					return nil, errNotConnected
				}
				return map[string]any{"state": "password"}, nil
			}
			return nil, sanitizeError(err)
		}
		return c.finishLogin(ctx, b)
	case "login_password":
		if state != "password" {
			return nil, errInvalidState
		}
		password := stringValue(request, "password")
		if password == "" {
			return nil, errors.New("telegram_invalid_password")
		}
		if err := b.Password(ctx, password); err != nil {
			return nil, sanitizeError(err)
		}
		return c.finishLogin(ctx, b)
	}
	if state != "connected" {
		return nil, errors.New("telegram_authentication_required")
	}
	switch op {
	case "logout":
		if err := b.LogOut(ctx); err != nil {
			return nil, sanitizeError(err)
		}
		c.stop()
		c.setState("disconnected")
		return map[string]any{"logged_out": true, "remote_session_revoked": true}, nil
	case "react":
		emoji := stringValue(request, "emoji")
		if len(emoji) > 256 {
			return nil, errors.New("telegram_invalid_reaction")
		}
		result, err := b.React(ctx, stringValue(request, "conversation_id"), stringValue(request, "message_id"), emoji)
		return result, sanitizeError(err)
	case "start_conversation":
		recipient := strings.TrimSpace(stringValue(request, "recipient"))
		if recipient == "" {
			return nil, errors.New("telegram_invalid_recipient")
		}
		result, err := b.Resolve(ctx, recipient)
		return result, sanitizeError(err)
	case "sync":
		if err := b.Sync(ctx); err != nil {
			return nil, sanitizeError(err)
		}
		return map[string]any{"state": "connected"}, nil
	case "history":
		limit := 50
		if value, ok := request["limit"].(float64); ok && value >= 1 && value <= 100 {
			limit = int(value)
		}
		if err := b.History(ctx, stringValue(request, "conversation_id"), limit); err != nil {
			return nil, sanitizeError(err)
		}
		return map[string]any{"state": "connected"}, nil
	case "send_text":
		body := stringValue(request, "body")
		if strings.TrimSpace(body) == "" {
			return nil, errors.New("telegram_empty_message")
		}
		result, err := b.SendText(ctx, stringValue(request, "conversation_id"), body, stringValue(request, "id"), stringValue(request, "reply_to_message_id"))
		return result, sanitizeError(err)
	case "send_attachment":
		encoded := stringValue(request, "bytes")
		if len(encoded) > base64.StdEncoding.EncodedLen(maxAttachmentBytes) {
			return nil, errors.New("telegram_attachment_size_unsupported")
		}
		data, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil || len(data) == 0 {
			return nil, errors.New("telegram_invalid_attachment")
		}
		result, err := b.SendAttachment(ctx, stringValue(request, "conversation_id"), data, stringValue(request, "name"),
			stringValue(request, "mime_type"), stringValue(request, "body"), stringValue(request, "id"), stringValue(request, "reply_to_message_id"))
		return result, sanitizeError(err)
	case "download_attachment":
		result, err := b.Download(ctx, stringValue(request, "id"))
		return result, sanitizeError(err)
	default:
		return nil, errors.New("telegram_unsupported_operation")
	}
}

func Capabilities() map[string]any {
	return map[string]any{
		"platform": "telegram", "direct": true, "phone_login": true,
		"password_login": true, "send_text": true, "send_attachment": true,
		"download_attachment": true, "history": true, "secret_chats": false,
		"start_conversation": true, "replies": true, "reactions": true,
		"stable_send_ids": true, "requires_api_credentials": true, "max_attachment_bytes": maxAttachmentBytes,
	}
}

func (c *Connector) connect(ctx context.Context, request map[string]any) (any, error) {
	ctx, cancelRequest := requestContext(ctx)
	defer cancelRequest()
	c.mu.Lock()
	if c.cancel != nil {
		state := c.state
		c.mu.Unlock()
		if state != "disconnected" {
			return map[string]any{"state": state}, nil
		}
		c.stop()
	} else {
		c.mu.Unlock()
	}
	apiID, err := strconv.Atoi(valueString(request["api_id"]))
	apiHash := stringValue(request, "api_hash")
	decodedHash, hashErr := hex.DecodeString(apiHash)
	if err != nil || apiID < 1 || hashErr != nil || len(decodedHash) != 16 {
		return nil, errors.New("telegram_api_credentials_required")
	}
	b := c.backend
	if b == nil {
		b = newGotdBackend(c.accountID, apiID, apiHash, c.storage, c.emit)
	}
	runCtx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	c.mu.Lock()
	c.backend, c.cancel, c.done, c.running = b, cancel, done, true
	c.mu.Unlock()
	c.setState("connecting")
	type connectionResult struct {
		authorized bool
		err        error
	}
	ready := make(chan connectionResult, 1)
	var once sync.Once
	connected := func(authorized bool, err error) {
		once.Do(func() { ready <- connectionResult{authorized, err} })
	}
	go func() {
		defer close(done)
		err := b.Run(runCtx, connected)
		c.mu.Lock()
		c.running = false
		c.mu.Unlock()
		connected(false, err)
		if runCtx.Err() == nil {
			c.setState("disconnected")
			c.emit(map[string]any{"type": "error", "account_id": c.accountID, "code": "telegram_connection_lost"})
		}
	}()
	select {
	case result := <-ready:
		if result.err != nil {
			c.stop()
			c.setState("disconnected")
			return nil, sanitizeError(result.err)
		}
		if result.authorized {
			return c.finishLogin(ctx, b)
		}
		if !c.setState("phone") {
			c.stop()
			return nil, errNotConnected
		}
		return map[string]any{"state": "phone"}, nil
	case <-ctx.Done():
		c.stop()
		c.setState("disconnected")
		return nil, errors.New("telegram_connection_cancelled")
	}
}

func (c *Connector) finishLogin(ctx context.Context, b backend) (any, error) {
	c.phone, c.codeHash = "", ""
	if !c.setState("connected") {
		return nil, errNotConnected
	}
	if err := b.Sync(ctx); err != nil {
		c.emit(map[string]any{"type": "error", "account_id": c.accountID, "code": "telegram_sync_failed"})
		c.mu.Lock()
		connected := c.state == "connected" && c.running && !c.closed
		c.mu.Unlock()
		if !connected {
			return nil, errNotConnected
		}
		return map[string]any{"state": "connected", "sync_pending": true}, nil
	}
	return map[string]any{"state": "connected"}, nil
}

func (c *Connector) setState(state string) bool {
	c.mu.Lock()
	if state != "disconnected" && (!c.running || c.closed) {
		c.mu.Unlock()
		return false
	}
	c.state = state
	c.mu.Unlock()
	c.emit(map[string]any{"type": "login", "account_id": c.accountID, "state": state})
	if state == "connected" || state == "connecting" || state == "disconnected" {
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": state})
	}
	return true
}

func (c *Connector) stop() {
	c.mu.Lock()
	cancel, done := c.cancel, c.done
	c.cancel, c.done, c.running = nil, nil, false
	c.mu.Unlock()
	if cancel != nil {
		cancel()
		<-done
	}
	c.mu.Lock()
	c.backend = nil
	c.mu.Unlock()
	c.phone, c.codeHash = "", ""
}

func (c *Connector) Close() error {
	c.mu.Lock()
	c.closed = true
	cancel := c.cancel
	c.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	c.operations.Lock()
	defer c.operations.Unlock()
	c.stop()
	return nil
}

func (c *Connector) HasSession() bool { return c.storage.hasSession() }

func stringValue(request map[string]any, name string) string {
	value, _ := request[name].(string)
	return value
}

func valueString(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case float64:
		if v == float64(int(v)) {
			return strconv.Itoa(int(v))
		}
	case int:
		return strconv.Itoa(v)
	}
	return ""
}

func validPhone(phone string) bool {
	if len(phone) < 7 || len(phone) > 16 || phone[0] != '+' {
		return false
	}
	for _, r := range phone[1:] {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func requestContext(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, 60*time.Second)
}
