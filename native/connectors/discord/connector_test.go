package discord

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	dc "github.com/diamondburned/arikawa/v3/discord"
	"github.com/diamondburned/arikawa/v3/session"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }
func response(body string) *http.Response {
	return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": {"application/json"}}, Body: io.NopCloser(strings.NewReader(body))}
}

func TestDiscordPasswordLoginRequiresAuthenticatorBeforeSavingSession(t *testing.T) {
	original := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = original })
	http.DefaultTransport = roundTripFunc(func(req *http.Request) (*http.Response, error) {
		if req.URL.Host != "discord.com" || !strings.HasSuffix(req.URL.Path, "/auth/login") {
			t.Fatal("unexpected request during incomplete login")
		}
		var fields map[string]string
		json.NewDecoder(req.Body).Decode(&fields)
		if fields["login"] != "fixture@example.test" || fields["password"] != "fixture-password" {
			t.Fatal("credentials did not reach authentication endpoint")
		}
		return response(`{"mfa":true,"totp":true,"ticket":"private-ticket","login_instance_id":"private-instance"}`), nil
	})
	events := []map[string]any{}
	c, err := New("discord-fixture", t.TempDir(), make([]byte, 32), func(event map[string]any) { events = append(events, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	result, err := c.Handle(context.Background(), map[string]any{"op": "login", "username": "fixture@example.test", "password": "fixture-password"})
	if err != nil || result.(map[string]any)["state"] != "code" || c.HasSession() {
		t.Fatal("incomplete authentication was saved as a session")
	}
	encoded, _ := json.Marshal(events)
	if bytes.Contains(encoded, []byte("private-ticket")) || bytes.Contains(encoded, []byte("fixture-password")) {
		t.Fatal("authentication credentials leaked to events")
	}
}

func TestDiscordReplyAndAttachmentUseCorrectConversationAndFileName(t *testing.T) {
	original := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = original })
	requestCount := 0
	http.DefaultTransport = roundTripFunc(func(req *http.Request) (*http.Response, error) {
		requestCount++
		if req.URL.Host != "discord.com" || !strings.HasSuffix(req.URL.Path, "/channels/42/messages") || req.Method != "POST" {
			t.Fatal("send used the wrong target")
		}
		if req.Header.Get("Authorization") != "fixture-token" {
			t.Fatal("session token did not reach network client")
		}
		var fields map[string]any
		if strings.HasPrefix(req.Header.Get("Content-Type"), "multipart/") {
			if err := req.ParseMultipartForm(1 << 20); err != nil {
				t.Fatal(err)
			}
			file, header, err := req.FormFile("file0")
			if err != nil {
				t.Fatal(err)
			}
			defer file.Close()
			data, _ := io.ReadAll(file)
			if header.Filename != "fixture.txt" || string(data) != "file bytes" {
				t.Fatal("attachment filename or contents changed")
			}
			json.Unmarshal([]byte(req.FormValue("payload_json")), &fields)
		} else {
			json.NewDecoder(req.Body).Decode(&fields)
		}
		if fields["message_reference"].(map[string]any)["message_id"] != "7" || fields["content"] != "fixture reply" {
			t.Fatal("reply text or target was lost")
		}
		return response(`{"id":"99","channel_id":"42","content":"fixture reply","author":{"id":"1","username":"Me"},"timestamp":"2026-11-06T10:00:00Z"}`), nil
	})
	b := &backend{client: session.New("fixture-token"), ownID: 1, channels: map[dc.ChannelID]dc.Channel{42: {ID: 42, Type: dc.DirectMessage}}, media: map[string]string{}}
	for _, op := range []string{"send_text", "send_attachment"} {
		result, err := b.Handle(context.Background(), map[string]any{"op": op, "conversation_id": "42", "reply_to_message_id": "7", "id": "stable-send-id", "body": "fixture reply", "name": "fixture.txt", "bytes": base64.StdEncoding.EncodeToString([]byte("file bytes"))})
		if err != nil || result.(map[string]any)["id"] != "99" {
			t.Fatal("network confirmation was lost")
		}
	}
	if requestCount != 2 {
		t.Fatal("send performed an unexpected retry")
	}
}

func TestDiscordNormalizedAttachmentsKeepSignedURLsPrivate(t *testing.T) {
	b := &backend{ownID: 1, media: map[string]string{}}
	event := b.message(&dc.Message{ID: 7, ChannelID: 42, Author: dc.User{ID: 1, Username: "Me"}, Timestamp: dc.NewTimestamp(time.UnixMilli(1700000000000)), Attachments: []dc.Attachment{{ID: 8, Filename: "fixture.png", ContentType: "image/png", URL: "https://cdn.discordapp.com/file?token=private"}}})
	encoded, _ := json.Marshal(event)
	if bytes.Contains(encoded, []byte("token=private")) || event["outgoing"] != true || b.media["7/8"] == "" {
		t.Fatal("attachment normalization lost the reference or exposed the URL")
	}
	if normalizeChannel(dc.Channel{ID: 42, Type: dc.GroupDM, Name: "Group"})["is_group"] != true {
		t.Fatal("group DM was not identified")
	}
}

func TestDiscordDoesNotRetryUnconfirmedSend(t *testing.T) {
	original := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = original })
	attempts := 0
	http.DefaultTransport = roundTripFunc(func(*http.Request) (*http.Response, error) {
		attempts++
		return nil, errors.New("fixture acknowledgement lost")
	})
	b := &backend{client: session.New("fixture-token"), channels: map[dc.ChannelID]dc.Channel{42: {ID: 42, Type: dc.DirectMessage}}}
	_, err := b.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "42", "body": "fixture"})
	if err == nil || attempts != 1 {
		t.Fatal("uncertain message was retried")
	}
}
