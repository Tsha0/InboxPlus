package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"
)

func TestDispatcherAccountIsolationAndOfflineLifecycle(t *testing.T) {
	r := &runtime{accounts: map[string]*account{}}
	defer r.request([]byte(`{"op":"shutdown"}`))
	directory := t.TempDir()
	key := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	init := map[string]any{"op": "initialize", "account_id": "a", "platform": "whatsapp", "directory": filepath.Join(directory, "account"), "key": key}
	request := func(value map[string]any) map[string]any {
		t.Helper()
		encoded, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		var decoded map[string]any
		if json.Unmarshal(r.request(encoded), &decoded) != nil {
			t.Fatal("invalid response")
		}
		return decoded
	}
	if response := request(init); response["ok"] != true {
		t.Fatalf("initialize failed: %#v", response)
	}
	if response := request(init); response["ok"] != true {
		t.Fatal("repeated initialize failed")
	}
	init["account_id"] = "b"
	if response := request(init); response["ok"] != false {
		t.Fatal("two accounts accepted the same credential directory")
	}
	init["account_id"] = "a"
	init["key"] = base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{8}, 32))
	if response := request(init); response["ok"] != false {
		t.Fatal("an initialized account silently accepted a different key")
	}
	if response := request(map[string]any{"op": "send_text", "account_id": "a", "conversation_id": "15550000000@s.whatsapp.net", "body": "offline fixture"}); response["ok"] != false {
		t.Fatal("offline send was accepted")
	}
	if response := request(map[string]any{"op": "capabilities", "account_id": "a"}); response["ok"] != true {
		t.Fatal("account capabilities failed")
	}
	if response := request(map[string]any{"op": "close", "account_id": "a"}); response["ok"] != true {
		t.Fatal("close failed")
	} else if response["data"].(map[string]any)["has_session"] != false {
		t.Fatal("empty offline account was not reported as safe to discard")
	}
	if response := request(map[string]any{"op": "list_chats", "account_id": "a"}); response["ok"] != false {
		t.Fatal("closed account accepted a request")
	}
}

type blockingConnector struct {
	started chan struct{}
	closed  bool
}

type failingConnector struct{}

type retainingConnector struct{ closed bool }

func (c *retainingConnector) Handle(context.Context, map[string]any) (any, error) { return nil, nil }
func (c *retainingConnector) Close() error                                        { c.closed = true; return nil }
func (c *retainingConnector) HasSession() bool                                    { return c.closed }

func TestCloseReportsSessionPresenceAfterStoppingTheConnector(t *testing.T) {
	client := &retainingConnector{}
	r := &runtime{accounts: map[string]*account{"account": {connector: client}}}
	var response struct {
		OK   bool `json:"ok"`
		Data struct {
			Closed     bool `json:"closed"`
			HasSession bool `json:"has_session"`
		} `json:"data"`
	}
	if json.Unmarshal(r.request([]byte(`{"op":"close","account_id":"account"}`)), &response) != nil || !response.OK || !response.Data.Closed || !response.Data.HasSession {
		t.Fatal("close did not preserve a session finalized before shutdown")
	}
}

func (f *failingConnector) Handle(context.Context, map[string]any) (any, error) {
	return nil, errors.New("fixture-private-token-and-message-body")
}
func (f *failingConnector) Close() error     { return nil }
func (f *failingConnector) HasSession() bool { return false }

func TestDispatcherDoesNotExposeBackendErrors(t *testing.T) {
	r := &runtime{accounts: map[string]*account{"a": {connector: &failingConnector{}}}}
	response := r.request([]byte(`{"op":"send_text","account_id":"a"}`))
	if bytes.Contains(response, []byte("fixture-private")) || !bytes.Contains(response, []byte(`"code":"operation_failed"`)) {
		t.Fatal("backend error crossed the public response boundary")
	}
}

func (c *blockingConnector) Handle(ctx context.Context, req map[string]any) (any, error) {
	if req["op"] == "connect" {
		close(c.started)
		<-ctx.Done()
		return nil, ctx.Err()
	}
	return map[string]any{"available": true}, nil
}

func (c *blockingConnector) Close() error {
	c.closed = true
	return nil
}

func (c *blockingConnector) HasSession() bool { return false }

func TestBlockingAccountCanBeCancelledWithoutStallingOtherAccounts(t *testing.T) {
	a := &blockingConnector{started: make(chan struct{})}
	b := &blockingConnector{started: make(chan struct{})}
	r := &runtime{accounts: map[string]*account{"a": {connector: a}, "b": {connector: b}}}
	done := make(chan []byte, 1)
	go func() { done <- r.request([]byte(`{"op":"connect","account_id":"a"}`)) }()
	select {
	case <-a.started:
	case <-time.After(10 * time.Second):
		t.Fatal("request did not start")
	}
	other := make(chan []byte, 1)
	go func() { other <- r.request([]byte(`{"op":"capabilities","account_id":"b"}`)) }()
	select {
	case response := <-other:
		if !bytes.Contains(response, []byte(`"ok":true`)) {
			t.Fatal("other account failed")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("blocking account stalled other accounts")
	}
	if response := r.request([]byte(`{"op":"cancel","account_id":"a"}`)); !bytes.Contains(response, []byte(`"ok":true`)) {
		t.Fatal("cancel failed")
	}
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("active request did not cancel")
	}
	if response := r.request([]byte(`{"op":"shutdown"}`)); !bytes.Contains(response, []byte(`"ok":true`)) {
		t.Fatal("shutdown failed")
	}
	if len(r.accounts) != 0 || !a.closed || !b.closed {
		t.Fatal("shutdown left accounts open")
	}
}

func TestShutdownCancelsAnActiveRequestBeforeClosingItsConnector(t *testing.T) {
	client := &blockingConnector{started: make(chan struct{})}
	r := &runtime{accounts: map[string]*account{"a": {connector: client}}}
	requestDone := make(chan struct{})
	go func() { r.request([]byte(`{"op":"connect","account_id":"a"}`)); close(requestDone) }()
	select {
	case <-client.started:
	case <-time.After(10 * time.Second):
		t.Fatal("request did not start")
	}
	shutdownDone := make(chan []byte, 1)
	go func() { shutdownDone <- r.request([]byte(`{"op":"shutdown"}`)) }()
	select {
	case response := <-shutdownDone:
		if !bytes.Contains(response, []byte(`"ok":true`)) {
			t.Fatal("shutdown failed")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("shutdown did not cancel the active request")
	}
	select {
	case <-requestDone:
	case <-time.After(10 * time.Second):
		t.Fatal("active request did not return")
	}
	if !client.closed || len(r.accounts) != 0 {
		t.Fatal("shutdown did not close the connector")
	}
}

func TestDispatcherRejectsMalformedRequestsAndQueuesEvents(t *testing.T) {
	r := &runtime{accounts: map[string]*account{}}
	for _, request := range []string{`null`, `[]`, `{`, `{"op":"connect"}`} {
		var decoded map[string]any
		if json.Unmarshal(r.request([]byte(request)), &decoded) != nil || decoded["ok"] != false {
			t.Fatalf("malformed request accepted: %s", request)
		}
	}
	r.emit(map[string]any{"type": "connection", "account_id": "a", "state": "connected"})
	r.emit(map[string]any{"type": "connection", "account_id": "b", "state": "disconnected"})
	for _, id := range []string{"a", "b"} {
		var event map[string]any
		if json.Unmarshal(r.poll(), &event) != nil || event["account_id"] != id {
			t.Fatal("events lost account identity or ordering")
		}
	}
	if r.poll() != nil {
		t.Fatal("empty queue returned an event")
	}
}
