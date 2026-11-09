package direct

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeBackend struct {
	c         *Connector
	block     chan struct{}
	sendCount int
	closed    bool
}

func (b *fakeBackend) Connect(ctx context.Context, req map[string]any) (string, error) {
	if b.block != nil {
		close(b.block)
		<-ctx.Done()
		return "", ctx.Err()
	}
	if Text(req, "token") == "" {
		return "needs_login", nil
	}
	return "connected", b.c.Save(map[string]string{"token": Text(req, "token")})
}
func (b *fakeBackend) Handle(context.Context, map[string]any) (any, error) {
	b.sendCount++
	return map[string]any{"id": "confirmed"}, nil
}
func (b *fakeBackend) Close() error { b.closed = true; return nil }

func fixture(t *testing.T, directory string, key []byte, events *[]map[string]any) (*Connector, *fakeBackend) {
	t.Helper()
	var b *fakeBackend
	c, err := New("fixture", directory, key, map[string]any{"send_text": true}, func(event map[string]any) {
		if events != nil {
			*events = append(*events, event)
		}
	}, func(c *Connector) Backend { b = &fakeBackend{c: c}; return b })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return c, b
}

func TestSessionRestoresWithOriginalKeyAndNeverWritesPlaintext(t *testing.T) {
	directory, key := t.TempDir(), bytes.Repeat([]byte{19}, 32)
	c, _ := fixture(t, directory, key, nil)
	if _, err := c.Handle(context.Background(), map[string]any{"op": "connect", "token": "private-session-fixture"}); err != nil {
		t.Fatal(err)
	}
	if err := c.Close(); err != nil {
		t.Fatal(err)
	}
	if !c.HasSession() {
		t.Fatal("closing lost the saved session indication")
	}
	data, err := os.ReadFile(filepath.Join(directory, "credentials.db.enc"))
	if err != nil || bytes.Contains(data, []byte("private-session-fixture")) {
		t.Fatal("credentials were not encrypted")
	}
	restored, _ := fixture(t, directory, key, nil)
	var saved map[string]string
	if exists, err := restored.Load(&saved); err != nil || !exists || saved["token"] != "private-session-fixture" {
		t.Fatal("session did not restore")
	}
	restored.Close()
	if wrong, err := New("fixture", directory, bytes.Repeat([]byte{20}, 32), nil, nil, func(*Connector) Backend { return &fakeBackend{} }); err == nil {
		wrong.Close()
		t.Fatal("wrong key replaced an existing session")
	}
}

func TestUnauthenticatedAndDisconnectedSendsNeverReachNetwork(t *testing.T) {
	c, b := fixture(t, t.TempDir(), make([]byte, 32), nil)
	request := map[string]any{"op": "send_text", "conversation_id": "chat", "body": "fixture"}
	if _, err := c.Handle(context.Background(), request); err == nil {
		t.Fatal("unauthenticated send accepted")
	}
	result, err := c.Handle(context.Background(), map[string]any{"op": "connect"})
	if err != nil || result.(map[string]any)["state"] != "needs_login" || c.HasSession() {
		t.Fatal("empty account attempted to become connected")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "connect", "token": "fixture-token"}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Handle(context.Background(), request); err != nil || b.sendCount != 1 {
		t.Fatal("connected send did not reach backend")
	}
	c.Event(map[string]any{"type": "connection", "state": "disconnected"})
	if _, err := c.Handle(context.Background(), request); err == nil || b.sendCount != 1 {
		t.Fatal("disconnected send reached network")
	}
}

func TestCancelledLoginStopsBackendWithoutSavingCredentials(t *testing.T) {
	c, b := fixture(t, t.TempDir(), make([]byte, 32), nil)
	b.block = make(chan struct{})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { _, err := c.Handle(ctx, map[string]any{"op": "connect"}); done <- err }()
	select {
	case <-b.block:
	case <-time.After(10 * time.Second):
		t.Fatal("login did not start")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled login succeeded")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("login did not cancel")
	}
	if !b.closed || c.HasSession() {
		t.Fatal("cancelled login retained an active session")
	}
}

func TestEventsRemainAccountScopedAndStopAfterClose(t *testing.T) {
	events := []map[string]any{}
	c, _ := fixture(t, t.TempDir(), make([]byte, 32), &events)
	c.Event(map[string]any{"type": "message", "account_id": "other", "id": "message"})
	if len(events) != 1 || events[0]["account_id"] != "fixture" {
		t.Fatal("event escaped its account")
	}
	c.Close()
	c.Event(map[string]any{"type": "message", "id": "late"})
	if len(events) != 1 {
		t.Fatal("closed connector emitted an event")
	}
}

func TestFailedPersistenceDisablesConnectionAndKeepsOriginalSession(t *testing.T) {
	events := []map[string]any{}
	c, b := fixture(t, t.TempDir(), make([]byte, 32), &events)
	if err := c.Save(map[string]string{"token": "original"}); err != nil {
		t.Fatal(err)
	}
	if err := c.Save(make(chan int)); err == nil {
		t.Fatal("invalid storage update accepted")
	}
	c.Event(map[string]any{"type": "connection", "state": "connected"})
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "chat", "body": "private"}); err == nil || b.sendCount != 0 {
		t.Fatal("storage failure allowed a network write")
	}
	var saved map[string]string
	if _, err := c.Load(&saved); err != nil || saved["token"] != "original" {
		t.Fatal("failed update discarded the original session")
	}
	for _, event := range events {
		encoded, _ := json.Marshal(event)
		if bytes.Contains(encoded, []byte("original")) || event["state"] == "connected" {
			t.Fatal("failed session emitted secrets or a connected state")
		}
	}
}

func TestLogoutClearsOnlyLocalSessionAndReportsRemoteSessionRetained(t *testing.T) {
	c, _ := fixture(t, t.TempDir(), make([]byte, 32), nil)
	c.Save(map[string]string{"token": "fixture-token"})
	result, err := c.Handle(context.Background(), map[string]any{"op": "logout"})
	if err != nil || c.HasSession() || result.(map[string]any)["remote_session_revoked"] != false {
		t.Fatal("local logout misrepresented remote revocation")
	}
	c.Close()
	if c.HasSession() {
		t.Fatal("logout left credentials behind")
	}
}

func TestMediaHostsRejectExternalTargetsAndDowngrade(t *testing.T) {
	for _, raw := range []string{"http://cdn.discordapp.com/file", "https://cdn.discordapp.com.evil.test/file", "https://user@cdn.discordapp.com/file", "https://cdn.discordapp.com:444/file", "https://127.0.0.1/file", "file:///private/file"} {
		if MediaURL(raw, "discordapp.com") {
			t.Fatal("untrusted attachment target accepted")
		}
	}
	if !MediaURL("https://cdn.discordapp.com/file?private=fixture", "discordapp.com") {
		t.Fatal("network attachment rejected")
	}
}

type avatarTransport func(*http.Request) (*http.Response, error)

func (f avatarTransport) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }

func TestAvatarDownloadsEnforceHostRedirectAndStreamingLimits(t *testing.T) {
	original := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = original })
	calls := 0
	http.DefaultTransport = avatarTransport(func(req *http.Request) (*http.Response, error) {
		calls++
		if req.URL.Path == "/redirect" {
			return &http.Response{StatusCode: http.StatusFound, Header: http.Header{"Location": []string{"https://untrusted.example/avatar"}}, Body: io.NopCloser(strings.NewReader("")), Request: req}, nil
		}
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(strings.Repeat("x", (2<<20)+1))), ContentLength: -1, Request: req}, nil
	})
	if _, err := DownloadAvatar(context.Background(), "https://untrusted.example/avatar", "example.test"); err == nil || calls != 0 {
		t.Fatal("untrusted host was fetched")
	}
	if _, err := DownloadAvatar(context.Background(), "https://example.test/redirect", "example.test"); err == nil || calls != 1 {
		t.Fatal("redirect escaped host validation")
	}
	if _, err := DownloadAvatar(context.Background(), "https://example.test/large", "example.test"); err == nil {
		t.Fatal("oversized streaming avatar accepted")
	}
}
