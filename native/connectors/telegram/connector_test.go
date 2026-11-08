package telegram

import (
	"context"
	"encoding/base64"
	"errors"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gotd/td/tgerr"
)

type fakeBackend struct {
	authorized                                           bool
	passwordNeeded                                       bool
	codeError                                            error
	sendError                                            error
	syncCount                                            int
	sends                                                []string
	attachment                                           []byte
	phone, code, hash                                    string
	password                                             string
	recipient                                            string
	clientID                                             string
	replyTo                                              string
	reactionConversation, reactionMessage, reactionEmoji string
	loggedOut                                            bool
	start                                                chan struct{}
	blockReady                                           bool
	runError                                             error
}

func (f *fakeBackend) Run(ctx context.Context, ready func(bool, error)) error {
	if f.start != nil {
		close(f.start)
	}
	if !f.blockReady {
		ready(f.authorized, nil)
	}
	if f.runError != nil {
		return f.runError
	}
	<-ctx.Done()
	return ctx.Err()
}
func (f *fakeBackend) SendCode(_ context.Context, phone string) (string, error) {
	f.phone = phone
	return "private-code-hash", nil
}
func (f *fakeBackend) SignIn(_ context.Context, phone, code, hash string) error {
	f.phone, f.code, f.hash = phone, code, hash
	if f.codeError != nil {
		return f.codeError
	}
	if f.passwordNeeded {
		return errPasswordNeeded
	}
	return nil
}
func (f *fakeBackend) Password(_ context.Context, password string) error {
	f.password = password
	return nil
}
func (f *fakeBackend) Sync(context.Context) error                 { f.syncCount++; return nil }
func (f *fakeBackend) History(context.Context, string, int) error { return nil }
func (f *fakeBackend) Resolve(_ context.Context, recipient string) (any, error) {
	f.recipient = recipient
	return map[string]any{"id": "user:42", "title": "Fixture", "timestamp": int64(1700000000000)}, nil
}
func (f *fakeBackend) SendText(_ context.Context, conversationID, body, clientID, replyTo string) (any, error) {
	f.clientID = clientID
	f.replyTo = replyTo
	f.sends = append(f.sends, conversationID+" "+body)
	if f.sendError != nil {
		return nil, f.sendError
	}
	return map[string]any{"id": "user:42:15"}, nil
}
func (f *fakeBackend) SendAttachment(_ context.Context, _ string, data []byte, _, _, _, clientID, replyTo string) (any, error) {
	f.clientID = clientID
	f.replyTo = replyTo
	f.attachment = data
	return map[string]any{"id": "user:42:16"}, nil
}
func (f *fakeBackend) Download(context.Context, string) (any, error) {
	return map[string]any{"bytes": base64.StdEncoding.EncodeToString([]byte("fixture")), "mime_type": "text/plain"}, nil
}

func (f *fakeBackend) React(_ context.Context, conversationID, messageID, emoji string) (any, error) {
	f.reactionConversation, f.reactionMessage, f.reactionEmoji = conversationID, messageID, emoji
	return map[string]any{"applied": true}, f.sendError
}

func (f *fakeBackend) LogOut(context.Context) error {
	f.loggedOut = true
	return nil
}

func fixtureConnector(t *testing.T, f *fakeBackend) (*Connector, func() []string) {
	t.Helper()
	var mu sync.Mutex
	states := []string{}
	c, err := New("fixture-account", t.TempDir(), make([]byte, 32), func(event map[string]any) {
		if event["type"] == "login" {
			mu.Lock()
			states = append(states, event["state"].(string))
			mu.Unlock()
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	c.backend = f
	t.Cleanup(func() { c.Close() })
	return c, func() []string { mu.Lock(); defer mu.Unlock(); return append([]string(nil), states...) }
}

func fixtureConnect(t *testing.T, c *Connector) map[string]any {
	t.Helper()
	result, err := c.Handle(context.Background(), map[string]any{"op": "connect", "api_id": 12345, "api_hash": strings.Repeat("a", 32)})
	if err != nil {
		t.Fatal(err)
	}
	return result.(map[string]any)
}

func TestReactionAddAndRemoveReachTheConnectedBackend(t *testing.T) {
	f := &fakeBackend{authorized: true}
	c, _ := fixtureConnector(t, f)
	fixtureConnect(t, c)
	for _, emoji := range []string{"👍", ""} {
		result, err := c.Handle(context.Background(), map[string]any{"op": "react", "conversation_id": "user:42", "message_id": "user:42:7", "emoji": emoji})
		if err != nil || result.(map[string]any)["applied"] != true {
			t.Fatal("reaction command failed")
		}
		if f.reactionConversation != "user:42" || f.reactionMessage != "user:42:7" || f.reactionEmoji != emoji {
			t.Fatal("reaction command lost its target or removal")
		}
	}
}

func TestLogoutEndsTheAuthorizedSessionAndStopsTheConnection(t *testing.T) {
	f := &fakeBackend{authorized: true}
	c, states := fixtureConnector(t, f)
	fixtureConnect(t, c)
	result, err := c.Handle(context.Background(), map[string]any{"op": "logout"})
	if err != nil || result.(map[string]any)["logged_out"] != true || result.(map[string]any)["remote_session_revoked"] != true || !f.loggedOut {
		t.Fatal("logout did not reach the authorized session")
	}
	if got := states(); got[len(got)-1] != "disconnected" {
		t.Fatalf("logout left the connection %v", got)
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "user:42", "body": "after"}); err == nil {
		t.Fatal("a signed out account still sent")
	}
}

func TestReplyTargetReachesTextAndAttachmentBackend(t *testing.T) {
	f := &fakeBackend{authorized: true}
	c, _ := fixtureConnector(t, f)
	fixtureConnect(t, c)
	for _, op := range []string{"send_text", "send_attachment"} {
		_, err := c.Handle(context.Background(), map[string]any{"op": op, "conversation_id": "user:42", "body": "Reply", "id": "outgoing", "reply_to_message_id": "user:42:1", "bytes": base64.StdEncoding.EncodeToString([]byte("fixture"))})
		if err != nil {
			t.Fatal(err)
		}
		if f.replyTo != "user:42:1" || f.clientID != "outgoing" {
			t.Fatal("backend lost reply target or stable send identifier")
		}
	}
}

func TestPhoneCodePasswordLoginUsesRealStateTransitions(t *testing.T) {
	f := &fakeBackend{passwordNeeded: true}
	c, states := fixtureConnector(t, f)
	if result := fixtureConnect(t, c); result["state"] != "phone" {
		t.Fatalf("unexpected state: %v", result)
	}
	for _, request := range []map[string]any{
		{"op": "login_phone", "phone": "+12025550123"},
		{"op": "login_code", "code": "12345"},
		{"op": "login_password", "password": "fixture-password"},
	} {
		if _, err := c.Handle(context.Background(), request); err != nil {
			t.Fatal(err)
		}
	}
	if got, want := states(), []string{"connecting", "phone", "code", "password", "connected"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("states %v; want %v", got, want)
	}
	if f.phone != "+12025550123" || f.code != "12345" || f.hash != "private-code-hash" || f.password != "fixture-password" || f.syncCount != 1 {
		t.Fatal("login inputs were not passed through")
	}
	if c.phone != "" || c.codeHash != "" {
		t.Fatal("completed authentication retained temporary credentials")
	}
}

func TestUnauthenticatedSendAndWrongLoginStepAreRejected(t *testing.T) {
	f := &fakeBackend{}
	c, _ := fixtureConnector(t, f)
	if _, err := c.Handle(context.Background(), map[string]any{"op": "connect"}); err == nil || err.Error() != "telegram_api_credentials_required" {
		t.Fatalf("missing credentials accepted: %v", err)
	}
	fixtureConnect(t, c)
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "user:42", "body": "fixture"}); err == nil {
		t.Fatal("unauthenticated send accepted")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "login_code", "code": "12345"}); !errors.Is(err, errInvalidState) {
		t.Fatalf("wrong login step: %v", err)
	}
	if len(f.sends) != 0 {
		t.Fatal("unauthorized send reached backend")
	}
}

func TestAuthorizedSessionSendsBytesAndSanitizesRemoteFailures(t *testing.T) {
	f := &fakeBackend{authorized: true, sendError: errors.New("server returned private-body and auth token")}
	c, states := fixtureConnector(t, f)
	fixtureConnect(t, c)
	if got := states(); !reflect.DeepEqual(got, []string{"connecting", "connected"}) {
		t.Fatalf("states %v", got)
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "user:42", "body": "fixture", "id": "pending-send"}); err == nil || err.Error() != "telegram_request_failed" {
		t.Fatalf("unsafe error: %v", err)
	}
	if f.clientID != "pending-send" {
		t.Fatal("send lost the persisted client identifier")
	}
	data := []byte("fixture attachment")
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_attachment", "conversation_id": "user:42", "bytes": base64.StdEncoding.EncodeToString(data), "name": "fixture.txt"}); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(f.attachment, data) {
		t.Fatal("attachment bytes changed")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "send_attachment", "bytes": "invalid-base64"}); err == nil {
		t.Fatal("invalid attachment accepted")
	}
}

func TestInvalidCodeRetainsCodeStepForRetry(t *testing.T) {
	f := &fakeBackend{codeError: errors.New("private upstream failure")}
	c, states := fixtureConnector(t, f)
	fixtureConnect(t, c)
	c.Handle(context.Background(), map[string]any{"op": "login_phone", "phone": "+12025550123"})
	if _, err := c.Handle(context.Background(), map[string]any{"op": "login_code", "code": "bad"}); err == nil {
		t.Fatal("failed sign-in accepted")
	}
	if got := states(); !reflect.DeepEqual(got, []string{"connecting", "phone", "code"}) {
		t.Fatalf("states %v", got)
	}
	f.codeError = nil
	if _, err := c.Handle(context.Background(), map[string]any{"op": "login_code", "code": "12345"}); err != nil {
		t.Fatal(err)
	}
}

func TestStartConversationResolvesRecipientOnlyAfterAuthentication(t *testing.T) {
	f := &fakeBackend{authorized: true}
	c, _ := fixtureConnector(t, f)
	request := map[string]any{"op": "start_conversation", "recipient": "@fixture_user"}
	if _, err := c.Handle(context.Background(), request); err == nil || f.recipient != "" {
		t.Fatal("unauthorized resolution reached backend")
	}
	fixtureConnect(t, c)
	result, err := c.Handle(context.Background(), request)
	if err != nil || result.(map[string]any)["id"] != "user:42" || f.recipient != "@fixture_user" {
		t.Fatalf("recipient resolution failed: %v", err)
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "start_conversation", "recipient": " "}); err == nil {
		t.Fatal("empty recipient accepted")
	}
}

func TestCloseCancelsPendingConnectAndPreventsReuse(t *testing.T) {
	f := &fakeBackend{blockReady: true, start: make(chan struct{})}
	c, _ := fixtureConnector(t, f)
	finished := make(chan error, 1)
	go func() {
		_, err := c.Handle(context.Background(), map[string]any{"op": "connect", "api_id": 12345, "api_hash": strings.Repeat("a", 32)})
		finished <- err
	}()
	select {
	case <-f.start:
	case <-time.After(30 * time.Second):
		t.Fatal("connect did not start")
	}
	if err := c.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-finished:
		if err == nil {
			t.Fatal("closed connection succeeded")
		}
	case <-time.After(30 * time.Second):
		t.Fatal("close did not cancel connect")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "capabilities"}); !errors.Is(err, errClosed) {
		t.Fatalf("closed connector reused: %v", err)
	}
}

func TestSanitizerDoesNotTrustPrefixOfUpstreamError(t *testing.T) {
	if got := sanitizeError(errors.New("telegram_secret-token")); got.Error() != "telegram_request_failed" {
		t.Fatalf("unsafe error %v", got)
	}
}

func TestSendWithoutConclusiveAcknowledgmentHasUnknownOutcome(t *testing.T) {
	for _, upstream := range []error{context.DeadlineExceeded, context.Canceled,
		errors.New("private transport error"), tgerr.New(500, "INTERNAL")} {
		if got := sanitizeError(sendError(upstream)); !errors.Is(got, errSendOutcomeUnknown) {
			t.Fatalf("ambiguous result %v", got)
		}
	}
	if got := sendError(tgerr.New(420, "FLOOD_WAIT_30")); got.Error() != "telegram_rate_limited" {
		t.Fatalf("conclusive refusal: %v", got)
	}
}

func TestImmediateConnectionFailureCannotLeaveLoginAvailable(t *testing.T) {
	f := &fakeBackend{runError: errors.New("private failure")}
	c, _ := fixtureConnector(t, f)
	_, err := c.Handle(context.Background(), map[string]any{"op": "connect", "api_id": 12345, "api_hash": strings.Repeat("a", 32)})
	if err == nil {
		t.Fatal("failed connection was reported as ready")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "login_phone", "phone": "+12025550123"}); !errors.Is(err, errNotConnected) {
		t.Fatalf("login remained available: %v", err)
	}
}
