package meta

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"go.mau.fi/mautrix-meta/pkg/messagix/table"
)

func TestFacebookNormalizesOnlyPublicMessageFields(t *testing.T) {
	var emitted []map[string]any
	f := &fbAdapter{c: &Connector{accountID: "account", ownID: "101", emit: func(event map[string]any) { emitted = append(emitted, event) }}}
	f.handleTable(&table.LSTable{
		LSDeleteThenInsertThread:  []*table.LSDeleteThenInsertThread{{ThreadKey: 201, ThreadName: "Conversation", ThreadType: table.ONE_TO_ONE, LastActivityTimestampMs: 500}},
		LSDeleteThenInsertContact: []*table.LSDeleteThenInsertContact{{Id: 101, Name: "Sender", EmailAddress: "private@example.test"}},
		LSUpsertMessage:           []*table.LSUpsertMessage{{ThreadKey: 201, MessageId: "message", SenderId: 101, Text: "Hello", TimestampMs: 500, ReplySourceId: "original", ReplyMediaUrl: "https://example.test/private-token", Unrecognized: map[int]any{900: "session-secret"}}},
		LSInsertBlobAttachment:    []*table.LSInsertBlobAttachment{{MessageId: "message", AttachmentFbid: "attachment", Filename: "image.png", AttachmentMimeType: "image/png", Filesize: 20, PlayableUrl: "https://example.test/media-secret"}},
	}, false)
	if len(emitted) != 2 {
		t.Fatalf("expected chat and message, got %d events", len(emitted))
	}
	message := emitted[1]
	if message["reply_to_message_id"] != "original" {
		t.Fatal("incoming reply target was lost")
	}
	if message["body"] != "Hello" || message["outgoing"] != true || message["sender_name"] != "Sender" || message["timestamp"] != int64(500) {
		t.Fatalf("unexpected normalized message: %#v", message)
	}
	encoded, err := json.Marshal(emitted)
	if err != nil {
		t.Fatal(err)
	}
	for _, private := range []string{"private-token", "session-secret", "media-secret", "private@example.test"} {
		if strings.Contains(string(encoded), private) {
			t.Fatalf("normalized event exposed upstream private field %q", private)
		}
	}
}

func TestFacebookEncryptedChatCannotUsePlaintextSendOrHistory(t *testing.T) {
	var emitted []map[string]any
	f := &fbAdapter{c: &Connector{accountID: "account", emit: func(event map[string]any) { emitted = append(emitted, event) }}, ready: true}
	f.handleTable(&table.LSTable{LSDeleteThenInsertThread: []*table.LSDeleteThenInsertThread{{ThreadKey: 201, ThreadType: table.ENCRYPTED_OVER_WA_ONE_TO_ONE}}}, false)
	if emitted[0]["send_supported"] != false || emitted[0]["e2ee"] != true {
		t.Fatal("encrypted thread was not explicitly marked unavailable")
	}
	if _, err := f.sendText(context.Background(), "201", "Hello", "original"); err == nil || err.Error() != "messenger_encrypted_chats_unavailable" {
		t.Fatalf("encrypted send must fail before calling the network: %v", err)
	}
	if _, err := f.history(context.Background(), map[string]any{"conversation_id": "201"}); err == nil || err.Error() != "messenger_encrypted_chats_unavailable" {
		t.Fatalf("encrypted history must fail before calling the network: %v", err)
	}
}

func TestFacebookCutoverDisablesAnExistingOpenChat(t *testing.T) {
	f := &fbAdapter{c: &Connector{accountID: "account", emit: func(map[string]any) {}}, ready: true}
	f.handleTable(&table.LSTable{LSDeleteThenInsertThread: []*table.LSDeleteThenInsertThread{{ThreadKey: 201, ThreadType: table.ONE_TO_ONE}}}, false)
	if _, _, err := f.target("201"); err != nil {
		t.Fatal(err)
	}
	f.handleTable(&table.LSTable{LSCreateOpenToE2EEThreadLink: []*table.LSCreateOpenToE2EEThreadLink{{OpenThreadID: 201, ArmadilloThreadID: 202}}}, false)
	if _, _, err := f.target("201"); err == nil || err.Error() != "messenger_encrypted_chats_unavailable" {
		t.Fatalf("cutover must disable old plaintext chat: %v", err)
	}
}

func TestFacebookSendRequiresMatchingServerConfirmation(t *testing.T) {
	response := &table.LSTable{LSReplaceOptimsiticMessage: []*table.LSReplaceOptimsiticMessage{{OfflineThreadingId: "other", MessageId: "wrong"}, {OfflineThreadingId: "requested", MessageId: "confirmed"}}}
	if id := fbConfirmedMessageID(response, "requested"); id != "confirmed" {
		t.Fatalf("wrong message confirmation: %q", id)
	}
	if id := fbConfirmedMessageID(response, "missing"); id != "" {
		t.Fatalf("unconfirmed send was accepted: %q", id)
	}
}

func TestFacebookReactionConfirmationRequiresTheSameActorMessageAndThread(t *testing.T) {
	response := &table.LSTable{LSReplaceOptimisticReaction: []*table.LSReplaceOptimisticReaction{{ThreadKey: 201, ActorId: 101, MessageId: "message"}}}
	if !fbReactionConfirmed(response, 201, 101, "message", "👍") {
		t.Fatal("matching acknowledgement was rejected")
	}
	if fbReactionConfirmed(response, 202, 101, "message", "👍") || fbReactionConfirmed(response, 201, 102, "message", "👍") || fbReactionConfirmed(response, 201, 101, "other", "👍") {
		t.Fatal("unrelated reaction acknowledgement was accepted")
	}
	var events []map[string]any
	f := &fbAdapter{c: &Connector{accountID: "account", ownID: "101", emit: func(event map[string]any) { events = append(events, event) }}}
	f.handleTable(&table.LSTable{LSUpsertReaction: []*table.LSUpsertReaction{{ThreadKey: 201, MessageId: "message", ActorId: 101, Reaction: "👍", TimestampMs: 1700000000000}}}, false)
	f.handleTable(&table.LSTable{LSDeleteReaction: []*table.LSDeleteReaction{{ThreadKey: 201, MessageId: "message", ActorId: 101}}}, false)
	if len(events) != 2 || events[0]["type"] != "reaction" || events[0]["outgoing"] != true || events[1]["emoji"] != "" {
		t.Fatal("reaction state became a normal message or lost removal")
	}
}

func TestFacebookMediaUsesOpaqueReferences(t *testing.T) {
	c := &Connector{media: make(map[string]mediaReference)}
	f := &fbAdapter{c: c}
	attachment := f.attachment("message", "attachment", "image.png", "image/png", "https://scontent.example.fbcdn.net/image?token=secret", 20)
	if attachment["downloadable"] != true || attachment["id"] != "message/attachment" {
		t.Fatal("allowed attachment was not registered for download")
	}
	encoded, err := json.Marshal(attachment)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "secret") || strings.Contains(string(encoded), "fbcdn.net") {
		t.Fatal("attachment URL escaped the native connector")
	}
	blocked := f.attachment("message", "other", "image.png", "image/png", "https://unrelated.example/image", 20)
	if blocked["downloadable"] != false {
		t.Fatal("unrelated media host was accepted")
	}
}

func TestFacebookSeparatesHistoryFromLiveDelivery(t *testing.T) {
	var emitted []map[string]any
	f := &fbAdapter{c: &Connector{accountID: "account", emit: func(event map[string]any) { emitted = append(emitted, event) }}}
	data := &table.LSTable{LSUpsertMessage: []*table.LSUpsertMessage{{ThreadKey: 201, MessageId: "message", Text: "Hello", TimestampMs: 500}}}
	f.handleTable(data, true)
	f.handleTable(data, false)
	if len(emitted) != 2 || emitted[0]["historical"] != true || emitted[1]["historical"] != false {
		t.Fatal("loading history must not appear as a new live message")
	}
}

func TestFacebookConversationAndMessageKeepGroupClassification(t *testing.T) {
	for _, test := range []struct {
		threadType table.ThreadType
		isGroup    bool
	}{
		{table.ONE_TO_ONE, false},
		{table.GROUP_THREAD, true},
		{table.ENCRYPTED_OVER_WA_ONE_TO_ONE, false},
		{table.ENCRYPTED_OVER_WA_GROUP, true},
		{table.TINCAN_GROUP_DISAPPEARING, true},
		{table.COMMUNITY_SUB_THREAD, true},
	} {
		var emitted []map[string]any
		f := &fbAdapter{c: &Connector{accountID: "account", emit: func(event map[string]any) { emitted = append(emitted, event) }}}
		f.handleTable(&table.LSTable{
			LSDeleteThenInsertThread: []*table.LSDeleteThenInsertThread{{ThreadKey: 201, ThreadType: test.threadType}},
			LSInsertMessage:          []*table.LSInsertMessage{{ThreadKey: 201, MessageId: "message", SenderId: 301, Text: "Fixture"}},
		}, false)
		if len(emitted) != 2 {
			t.Fatalf("expected chat and message for thread type %d", test.threadType)
		}
		for _, event := range emitted {
			if event["is_group"] != test.isGroup {
				t.Fatalf("thread type %d lost group classification", test.threadType)
			}
			identity, hasIdentity := event["identity_id"]
			if test.isGroup && hasIdentity {
				t.Fatal("group was assigned a contact identity")
			}
			if !test.isGroup && identity != "201" {
				t.Fatal("direct conversation lost its peer identity")
			}
		}
	}
}

func TestFacebookMessageWithoutThreadMetadataDoesNotInventAContact(t *testing.T) {
	var emitted []map[string]any
	f := &fbAdapter{c: &Connector{accountID: "account", emit: func(event map[string]any) { emitted = append(emitted, event) }}}
	f.emitMessage(201, "message", 301, "Fixture", 1, false, false, nil, false, "")
	if len(emitted) != 1 {
		t.Fatal("message was dropped")
	}
	if _, ok := emitted[0]["is_group"]; ok {
		t.Fatal("unknown thread was classified as a direct chat")
	}
	if _, ok := emitted[0]["identity_id"]; ok {
		t.Fatal("unknown thread was assigned a person")
	}
}
