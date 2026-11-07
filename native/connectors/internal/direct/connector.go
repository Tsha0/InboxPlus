package direct

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"maps"
	"strings"
	"sync"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/securedb"
)

type Backend interface {
	Connect(context.Context, map[string]any) (string, error)
	Handle(context.Context, map[string]any) (any, error)
	Close() error
}

type Connector struct {
	backend    Backend
	db         *sql.DB
	accountID  string
	features   map[string]any
	emit       func(map[string]any)
	opMu       sync.Mutex
	mu         sync.Mutex
	connected  bool
	closed     bool
	failed     bool
	hasSession bool
}

func New(accountID, directory string, key []byte, features map[string]any, emit func(map[string]any), factory func(*Connector) Backend) (*Connector, error) {
	db, err := securedb.Open(directory, key)
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec("CREATE TABLE IF NOT EXISTS session (id INTEGER PRIMARY KEY CHECK(id=1), data BLOB NOT NULL)"); err != nil {
		db.Close()
		return nil, securedb.ErrDatabase
	}
	if emit == nil {
		emit = func(map[string]any) {}
	}
	c := &Connector{db: db, accountID: accountID, features: maps.Clone(features), emit: emit}
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM session").Scan(&count); err != nil {
		db.Close()
		return nil, securedb.ErrDatabase
	}
	c.hasSession = count != 0
	c.backend = factory(c)
	return c, nil
}

func (c *Connector) Load(value any) (bool, error) {
	var data []byte
	err := c.db.QueryRow("SELECT data FROM session WHERE id=1").Scan(&data)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil || json.Unmarshal(data, value) != nil {
		return false, securedb.ErrDatabase
	}
	return true, nil
}

func (c *Connector) Save(value any) error {
	data, err := json.Marshal(value)
	if err == nil {
		_, err = c.db.Exec("INSERT INTO session (id,data) VALUES (1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data", data)
	}
	if err != nil {
		c.mu.Lock()
		c.failed, c.connected = true, false
		c.mu.Unlock()
		c.Event(map[string]any{"type": "connection", "state": "error"})
		c.Event(map[string]any{"type": "error", "code": "storage_failed", "message": "The account session could not be saved securely. Reopen the account before reconnecting."})
		return securedb.ErrPersistence
	}
	c.mu.Lock()
	c.hasSession = true
	c.mu.Unlock()
	return nil
}

func (c *Connector) Event(event map[string]any) {
	event = maps.Clone(event)
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	if c.failed && event["type"] != "error" && !(event["type"] == "connection" && event["state"] != "connected") {
		c.mu.Unlock()
		return
	}
	if event["type"] == "connection" {
		c.connected = event["state"] == "connected" && !c.failed
	}
	c.mu.Unlock()
	event["account_id"] = c.accountID
	c.emit(event)
}

func (c *Connector) Handle(ctx context.Context, req map[string]any) (any, error) {
	c.opMu.Lock()
	defer c.opMu.Unlock()
	op := Text(req, "op")
	c.mu.Lock()
	closed, failed, connected := c.closed, c.failed, c.connected
	c.mu.Unlock()
	if closed {
		return nil, errors.New("account_closed")
	}
	if op == "capabilities" {
		return maps.Clone(c.features), nil
	}
	if failed && op != "disconnect" && op != "logout" {
		return nil, securedb.ErrPersistence
	}
	switch op {
	case "connect", "login", "login_code", "login_password", "login_wait":
		if connected {
			return map[string]any{"state": "connected"}, nil
		}
		c.Event(map[string]any{"type": "connection", "state": "connecting"})
		state, err := c.backend.Connect(ctx, req)
		c.mu.Lock()
		failed = c.failed
		c.mu.Unlock()
		if failed {
			err = securedb.ErrPersistence
		}
		if err != nil {
			_ = c.backend.Close()
			c.Event(map[string]any{"type": "connection", "state": "disconnected"})
			return nil, errors.New("sign_in_failed")
		}
		c.Event(map[string]any{"type": "connection", "state": state})
		return map[string]any{"state": state}, nil
	case "disconnect":
		err := c.backend.Close()
		c.Event(map[string]any{"type": "connection", "state": "disconnected"})
		return map[string]any{"state": "disconnected"}, err
	case "logout":
		if err := c.backend.Close(); err != nil {
			return nil, err
		}
		if _, err := c.db.Exec("DELETE FROM session"); err != nil {
			return nil, securedb.ErrPersistence
		}
		c.mu.Lock()
		c.hasSession = false
		c.mu.Unlock()
		c.Event(map[string]any{"type": "connection", "state": "logged_out"})
		return map[string]any{"logged_out": true, "remote_session_revoked": false}, nil
	default:
		if !connected {
			return nil, errors.New("account_not_connected")
		}
		if op == "send_text" && (Text(req, "conversation_id") == "" || strings.TrimSpace(Text(req, "body")) == "") {
			return nil, errors.New("message_target_and_text_required")
		}
		result, err := c.backend.Handle(ctx, req)
		c.mu.Lock()
		failed = c.failed
		c.mu.Unlock()
		if failed {
			_ = c.backend.Close()
			return nil, securedb.ErrPersistence
		}
		return result, err
	}
}

func (c *Connector) HasSession() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.hasSession
}

func (c *Connector) Close() error {
	c.opMu.Lock()
	defer c.opMu.Unlock()
	if err := c.backend.Close(); err != nil {
		return err
	}
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed, c.connected = true, false
	c.mu.Unlock()
	return c.db.Close()
}

func Text(req map[string]any, key string) string { value, _ := req[key].(string); return value }

func Limit(req map[string]any) int {
	value, _ := req["limit"].(float64)
	if value < 1 || value > 100 {
		return 50
	}
	return int(value)
}
