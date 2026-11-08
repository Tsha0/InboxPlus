package linkedin

import (
	"bytes"
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/direct"
	li "go.mau.fi/mautrix-linkedin/pkg/linkedingo"
)

type fakeClient struct {
	sends                           int
	conversation, body, transaction string
}

func (f *fakeClient) GetConversationsUpdatedBefore(context.Context, time.Time) (*li.CollectionResponse[li.ConversationCursorMetadata, li.Conversation], error) {
	return &li.CollectionResponse[li.ConversationCursorMetadata, li.Conversation]{}, nil
}
func (f *fakeClient) GetMessagesBefore(context.Context, li.URN, time.Time, int) (*li.CollectionResponse[li.MessageMetadata, li.Message], error) {
	return &li.CollectionResponse[li.MessageMetadata, li.Message]{}, nil
}
func (f *fakeClient) SendMessage(_ context.Context, conversation li.URN, body li.SendMessageBody, _ []li.SendRenderContent, transaction string) (*li.MessageSentResponse, error) {
	f.sends++
	f.conversation, f.body, f.transaction = conversation.String(), body.Text, transaction
	return &li.MessageSentResponse{Data: li.Message{EntityURN: li.NewURN("urn:li:msg_message:99"), ConversationURN: conversation, Body: li.AttributedText{Text: body.Text}}}, nil
}
func (f *fakeClient) RealtimeConnect(context.Context) error { return nil }
func (f *fakeClient) RealtimeDisconnect()                   {}

func TestLinkedInSendUsesPersonalSessionConversationAndStableTransaction(t *testing.T) {
	jar, err := li.NewJarFromCookieHeader(`li_at=private-session; JSESSIONID="ajax:fixture"`)
	if err != nil {
		t.Fatal(err)
	}
	var b *backend
	c, err := direct.New("linkedin-fixture", t.TempDir(), make([]byte, 32), Capabilities(), nil, func(c *direct.Connector) direct.Backend {
		b = &backend{c: c, saved: savedSession{Cookies: jar, UserID: "self"}, media: map[string]string{}}
		return b
	})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	client := &fakeClient{}
	b.client = client
	result, err := b.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "urn:li:msg_conversation:42", "body": "fixture reply", "id": "stable-send"})
	if err != nil || result.(map[string]any)["id"] != "urn:li:msg_message:99" || client.sends != 1 {
		t.Fatal("send was not confirmed exactly once")
	}
	if client.conversation != "urn:li:msg_conversation:42" || client.body != "fixture reply" || client.transaction != "stable-send" {
		t.Fatal("message target, body or stable transaction was lost")
	}
}

func TestLinkedInConversationAndAttachmentsDoNotExposeNetworkURLs(t *testing.T) {
	b := &backend{saved: savedSession{UserID: "self"}, media: map[string]string{}}
	conversation := li.Conversation{EntityURN: li.NewURN("urn:li:msg_conversation:42"), ConversationParticipants: []li.MessagingParticipant{{EntityURN: li.NewURN("urn:li:fsd_profile:self")}, {EntityURN: li.NewURN("urn:li:fsd_profile:friend"), ParticipantType: li.ParticipantType{Member: &li.MemberParticipantInfo{FirstName: li.AttributedText{Text: "Fixture"}, LastName: li.AttributedText{Text: "Friend"}}}}}}
	chat := b.chat(conversation)
	if chat["title"] != "Fixture Friend" || chat["identity_id"] != "urn:li:fsd_profile:friend" {
		t.Fatal("conversation title or remote identity was lost")
	}
	event := b.message(li.Message{EntityURN: li.NewURN("urn:li:msg_message:99"), ConversationURN: conversation.EntityURN, Sender: conversation.ConversationParticipants[1], RenderContent: []li.RenderContent{{File: &li.FileAttachment{Name: "fixture.pdf", MediaType: "application/pdf", URL: "https://media.licdn.com/attachment?token=private"}}}})
	encoded, _ := json.Marshal(event)
	if bytes.Contains(encoded, []byte("token=private")) || bytes.Contains(encoded, []byte("licdn.com")) || b.media["urn:li:msg_message:99/0"] == "" {
		t.Fatal("attachment URL escaped the connector")
	}
}

func TestLinkedInRejectsInvalidConversationBeforeNetwork(t *testing.T) {
	for _, id := range []string{"", "https://evil.test", "urn:li:fsd_profile:42"} {
		if _, err := conversationURN(map[string]any{"conversation_id": id}); err == nil {
			t.Fatal("invalid conversation accepted")
		}
	}
	c, err := New("linkedin-fixture", t.TempDir(), make([]byte, 32), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	result, err := c.Handle(context.Background(), map[string]any{"op": "connect"})
	if err != nil || result.(map[string]any)["state"] != "needs_login" || c.HasSession() {
		t.Fatal("empty account connected")
	}
}
