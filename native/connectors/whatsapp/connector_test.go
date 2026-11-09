package whatsapp

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waAdv"
	"go.mau.fi/whatsmeow/proto/waCommon"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"
)

type fixtureContacts struct {
	store.NoopStore
	values map[types.JID]types.ContactInfo
}

func TestPhonePairingNormalizesDisplayFormatsAndUsesAcceptedClientIdentity(t *testing.T) {
	c, err := New("pairing", t.TempDir(), bytes.Repeat([]byte{29}, 32), func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	ready := make(chan struct{})
	close(ready)
	c.pairingReady = ready
	c.pairingExpiresAt = time.Now().Add(time.Minute)
	var phone string
	c.pairPhone = func(_ context.Context, number string, notify bool, client whatsmeow.PairClientType, name string) (string, error) {
		phone = number
		if !notify || client != whatsmeow.PairClientChrome || name != "Chrome (Linux)" {
			t.Fatal("unsupported pairing client identity")
		}
		return "ABCD-EFGH", nil
	}
	for input, expected := range map[string]string{
		"+65 8123 4567":    "6581234567",
		"65 (8123)-4567":   "6581234567",
		"+39 02 1234 5678": "390212345678",
		"6581234567":       "6581234567",
	} {
		result, err := c.Handle(context.Background(), map[string]any{"op": "pair_phone", "phone": input})
		if err != nil || phone != expected {
			t.Fatalf("formatted pairing failed: %v", err)
		}
		if result.(map[string]any)["code"] != "ABCD-EFGH" || result.(map[string]any)["expires_at"] != c.pairingExpiresAt.UnixMilli() {
			t.Fatal("pairing lost its code or expiry")
		}
	}
	for _, invalid := range []string{"", "+65abc81234567", "++6581234567", "06581234567", "123456", "1234567890123456", "+65 ８１２３４５６７", "+65 8123 ext 5"} {
		if _, err := c.Handle(context.Background(), map[string]any{"op": "pair_phone", "phone": invalid}); !errors.Is(err, ErrInvalidPhone) {
			t.Fatal("invalid number was accepted")
		}
	}
	c.pairPhone = func(context.Context, string, bool, whatsmeow.PairClientType, string) (string, error) {
		return "", errors.New("private-network-response")
	}
	if _, err := c.Handle(context.Background(), map[string]any{"op": "pair_phone", "phone": "6581234567"}); !errors.Is(err, ErrPhonePairing) {
		t.Fatal("pairing error was not sanitized")
	}
}

func TestPhonePairingRequiresReadinessAndRejectsExpiredAttempts(t *testing.T) {
	c, err := New("pairing", t.TempDir(), bytes.Repeat([]byte{30}, 32), func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.pairPhone = func(context.Context, string, bool, whatsmeow.PairClientType, string) (string, error) {
		t.Fatal("pairing started before ready or after expiry")
		return "", nil
	}
	request := map[string]any{"op": "pair_phone", "phone": "+65 8123 4567"}
	if _, err := c.Handle(context.Background(), request); !errors.Is(err, ErrPairingNotReady) {
		t.Fatal("pairing did not wait for its first QR event")
	}
	c.pairingExpiresAt = time.Now().Add(-time.Second)
	if _, err := c.Handle(context.Background(), request); !errors.Is(err, ErrPairingExpired) {
		t.Fatal("expired pairing was accepted")
	}
}

func TestReactionUpdatesDoNotBecomeMessagesOrConversationActivity(t *testing.T) {
	var captured []map[string]any
	c, err := New("account", t.TempDir(), bytes.Repeat([]byte{35}, 32), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	chat := types.NewJID("group", types.GroupServer)
	sender := types.NewJID("15550000000", types.DefaultUserServer)
	reaction := &waE2E.ReactionMessage{Key: &waCommon.MessageKey{ID: proto.String("original"), RemoteJID: proto.String(chat.String())}, Text: proto.String("👍"), SenderTimestampMS: proto.Int64(1700000000000)}
	event := &events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: chat, Sender: sender}, ID: "reaction-envelope"}, Message: &waE2E.Message{ReactionMessage: reaction}}
	c.message(event)
	if len(captured) != 1 || captured[0]["type"] != "reaction" || captured[0]["id"] != "original" || captured[0]["sender_id"] != sender.String() || captured[0]["emoji"] != "👍" {
		t.Fatal("reaction was not normalized against the original scoped message")
	}
	reaction.Text = proto.String("")
	c.message(event)
	if captured[1]["emoji"] != "" {
		t.Fatal("reaction removal was lost")
	}
	reaction.Key.RemoteJID = proto.String("other@g.us")
	c.message(event)
	if len(captured) != 2 {
		t.Fatal("cross-conversation reaction was accepted")
	}
	chats, err := c.listChats(context.Background())
	if err != nil || len(chats.(map[string]any)["chats"].([]map[string]any)) != 0 {
		t.Fatal("a reaction created conversation activity")
	}
}

func TestRepliesCarryOriginalSenderForTextAndMedia(t *testing.T) {
	for _, message := range []*waE2E.Message{
		{Conversation: proto.String("Reply")},
		{ImageMessage: &waE2E.ImageMessage{}},
		{VideoMessage: &waE2E.VideoMessage{}},
		{AudioMessage: &waE2E.AudioMessage{}},
		{DocumentMessage: &waE2E.DocumentMessage{}},
	} {
		request := map[string]any{"reply_to_message_id": "original", "reply_to_sender_id": "15550000000@s.whatsapp.net", "reply_to_body": "Original"}
		if err := applyReply(message, request, nil); err != nil {
			t.Fatal(err)
		}
		context := messageContext(message)
		if context.GetStanzaID() != "original" || context.GetParticipant() != "15550000000@s.whatsapp.net" || context.GetQuotedMessage().GetConversation() != "Original" {
			t.Fatal("reply lost the target, author or quoted body")
		}
	}
	own := types.NewJID("15550000001", types.DefaultUserServer)
	message := &waE2E.Message{Conversation: proto.String("Reply to myself")}
	if err := applyReply(message, map[string]any{"reply_to_message_id": "own", "reply_to_outgoing": true}, &own); err != nil || messageContext(message).GetParticipant() != own.String() {
		t.Fatal("reply to own sent message did not use the paired identity")
	}
	if err := applyReply(message, map[string]any{"reply_to_message_id": "target", "reply_to_sender_id": "invalid"}, nil); err == nil {
		t.Fatal("reply accepted an unavailable sender")
	}
}

func TestIncomingReplyKeepsTheCurrentConversationScope(t *testing.T) {
	var captured []map[string]any
	client, err := New("account", t.TempDir(), bytes.Repeat([]byte{34}, 32), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	chat := types.NewJID("group", types.GroupServer)
	context := &waE2E.ContextInfo{StanzaID: proto.String("original")}
	message := &events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: chat}, ID: "reply", Timestamp: time.Now()},
		Message: &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{Text: proto.String("Reply"), ContextInfo: context}}}
	client.message(message)
	if captured[0]["reply_to_message_id"] != "original" {
		t.Fatal("incoming quote was lost")
	}
	context.RemoteJID = proto.String("other@g.us")
	client.message(message)
	if _, present := captured[1]["reply_to_message_id"]; present {
		t.Fatal("a quote from another chat was assigned to this conversation")
	}
}

func TestClosePreservesPairedSessionsWithoutRequiringAConnectionEvent(t *testing.T) {
	for _, paired := range []bool{false, true} {
		client, err := New("account", t.TempDir(), bytes.Repeat([]byte{24}, 32), func(map[string]any) {})
		if err != nil {
			t.Fatal(err)
		}
		if paired {
			jid := types.NewJID("15550000000", types.DefaultUserServer)
			client.client.Store.ID = &jid
			client.client.Store.Account = &waAdv.ADVSignedDeviceIdentity{Details: []byte{}, AccountSignature: make([]byte, 64), AccountSignatureKey: make([]byte, 32), DeviceSignature: make([]byte, 64)}
			if err := client.client.Store.Save(context.Background()); err != nil {
				t.Fatal(err)
			}
		}
		if err := client.Close(); err != nil {
			t.Fatal(err)
		}
		if client.HasSession() != paired {
			t.Fatal("closing lost the durable pairing status")
		}
	}
}

func (f *fixtureContacts) GetAllContacts(context.Context) (map[types.JID]types.ContactInfo, error) {
	return f.values, nil
}

func TestConversationListExcludesAddressBookOnlyContactsAndSurvivesReopen(t *testing.T) {
	directory := t.TempDir()
	key := bytes.Repeat([]byte{19}, 32)
	client, err := New("account", directory, key, func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	known := types.NewJID("15550000000", types.DefaultUserServer)
	addressBookOnly := types.NewJID("15550000001", types.DefaultUserServer)
	client.client.Store.Contacts = &fixtureContacts{values: map[types.JID]types.ContactInfo{known: {FullName: "Known person"}, addressBookOnly: {FullName: "Address book only"}}}
	if err := client.recordChat(known, "Stored title", 1700000000000, 2); err != nil {
		t.Fatal(err)
	}
	if err := client.recordChat(known, "", 1700000001000, -1); err != nil {
		t.Fatal(err)
	}
	value, err := client.listChats(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	chats := value.(map[string]any)["chats"].([]map[string]any)
	if len(chats) != 1 || chats[0]["id"] != known.String() || chats[0]["title"] != "Known person" || chats[0]["unread_count"] != 2 {
		t.Fatal("address book contacts were mistaken for conversations")
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := New("account", directory, key, func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	value, err = reopened.listChats(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	chats = value.(map[string]any)["chats"].([]map[string]any)
	if len(chats) != 1 || chats[0]["id"] != known.String() || chats[0]["title"] != "Stored title" || chats[0]["timestamp"] != int64(1700000001000) || chats[0]["unread_count"] != 2 {
		t.Fatal("conversation metadata did not survive reopening")
	}
}

func TestOfflineSessionAndNormalizedIncomingMessages(t *testing.T) {
	directory := t.TempDir()
	key := bytes.Repeat([]byte{42}, 32)
	var captured []map[string]any
	client, err := New("local-account", directory, key, func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	jid := types.NewJID("15550000000", types.DefaultUserServer)
	now := time.Unix(1700000000, 0)
	client.handleEvent(&events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: jid, Sender: jid}, ID: "fixture-1", PushName: "Fixture", Timestamp: now}, Message: &waE2E.Message{Conversation: proto.String("Fixture message")}})
	if len(captured) != 1 || captured[0]["account_id"] != "local-account" || captured[0]["conversation_id"] != jid.String() || captured[0]["body"] != "Fixture message" || captured[0]["timestamp"] != now.UnixMilli() || captured[0]["outgoing"] != false {
		t.Fatalf("unexpected normalized message: %#v", captured)
	}
	if _, err := client.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": jid.String(), "body": "Fixture outgoing"}); err == nil {
		t.Fatal("an offline connector accepted a send")
	}
	if _, err := client.Handle(context.Background(), map[string]any{"op": "pair_phone", "phone": "+1 unsafe"}); err == nil {
		t.Fatal("an invalid phone number was accepted")
	}
	if _, err := client.Handle(context.Background(), map[string]any{"op": "start_conversation", "recipient": "not a phone"}); err == nil {
		t.Fatal("an invalid new-conversation recipient was accepted")
	}
	if _, err := client.Handle(context.Background(), map[string]any{"op": "start_conversation", "recipient": "+15550000000"}); err == nil {
		t.Fatal("an offline connector accepted a recipient lookup")
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	client, err = New("local-account", directory, key, func(map[string]any) {})
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestHistoryMessagesAreMarkedForSilentBackfill(t *testing.T) {
	var captured []map[string]any
	client, err := New("account", t.TempDir(), bytes.Repeat([]byte{27}, 32), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	jid := types.NewJID("15550000000", types.DefaultUserServer)
	event := &events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: jid}, ID: "history-id", Timestamp: time.Now()}, Message: &waE2E.Message{Conversation: proto.String("fixture")}}
	client.emitMessage(event, true)
	client.message(event)
	if len(captured) != 2 || captured[0]["historical"] != true || captured[1]["historical"] != false {
		t.Fatal("history and live events were not distinguished")
	}
}

func TestRevokedMessageDeletesTheOriginalWithoutAPlaceholder(t *testing.T) {
	var captured []map[string]any
	client, err := New("account", t.TempDir(), bytes.Repeat([]byte{32}, 32), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	jid := types.NewJID("15550000000", types.DefaultUserServer)
	if _, err := client.db.Exec("INSERT INTO inboxplus_media(id,message) VALUES(?,?)", jid.String()+"/original-id", []byte("fixture")); err != nil {
		t.Fatal(err)
	}
	message := &events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: jid}, ID: "revoke-envelope", Timestamp: time.Now()},
		Message: &waE2E.Message{ProtocolMessage: &waE2E.ProtocolMessage{Type: waE2E.ProtocolMessage_REVOKE.Enum(),
			Key: &waCommon.MessageKey{ID: proto.String("original-id"), RemoteJID: proto.String(jid.String())}}}}
	client.message(message)
	if len(captured) != 1 || captured[0]["type"] != "message_delete" || captured[0]["account_id"] != "account" || captured[0]["conversation_id"] != jid.String() || captured[0]["id"] != "original-id" {
		t.Fatal("revoke did not remove the original scoped message")
	}
	var count int
	if err := client.db.QueryRow("SELECT COUNT(*) FROM inboxplus_media WHERE id=?", jid.String()+"/original-id").Scan(&count); err != nil || count != 0 {
		t.Fatal("revoked attachment remained downloadable")
	}
	captured = nil
	message.Message.ProtocolMessage.Key.RemoteJID = proto.String("different@g.us")
	client.message(message)
	if len(captured) != 0 {
		t.Fatal("cross-conversation revoke was accepted")
	}
}

func TestGroupMessageDoesNotCreateADirectContactIdentity(t *testing.T) {
	var captured []map[string]any
	client, err := New("account", t.TempDir(), bytes.Repeat([]byte{33}, 32), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	jid := types.NewJID("12345", types.GroupServer)
	client.message(&events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: jid, IsGroup: true}, ID: "message", Timestamp: time.Now()}, Message: &waE2E.Message{Conversation: proto.String("fixture")}})
	if len(captured) != 1 || captured[0]["is_group"] != true || captured[0]["identity_id"] != nil {
		t.Fatal("group message was presented as a direct contact")
	}
}

func TestAttachmentMetadataStaysInsideEncryptedSession(t *testing.T) {
	directory := t.TempDir()
	key := bytes.Repeat([]byte{17}, 32)
	var captured []map[string]any
	client, err := New("account", directory, key, func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	jid := types.NewJID("15550000000", types.DefaultUserServer)
	client.message(&events.Message{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: jid}, ID: "image-id", Timestamp: time.Now()}, Message: &waE2E.Message{ImageMessage: &waE2E.ImageMessage{URL: proto.String("https://private.invalid/private-attachment-token"), MediaKey: []byte("fixture-media-secret"), Mimetype: proto.String("image/jpeg"), FileLength: proto.Uint64(123)}}})
	if len(captured) != 1 || captured[0]["kind"] != "image" {
		t.Fatalf("unexpected media event: %#v", captured)
	}
	attachments := captured[0]["attachments"].([]map[string]any)
	if len(attachments) != 1 || attachments[0]["id"] != jid.String()+"/image-id" || attachments[0]["mime_type"] != "image/jpeg" {
		t.Fatalf("unexpected attachment: %#v", attachments)
	}
	var record []byte
	if err := client.db.QueryRow("SELECT message FROM inboxplus_media WHERE id=?", jid.String()+"/image-id").Scan(&record); err != nil {
		t.Fatal(err)
	}
	decoded := &waE2E.Message{}
	if proto.Unmarshal(record, decoded) != nil || decoded.GetImageMessage().GetURL() != "https://private.invalid/private-attachment-token" {
		t.Fatal("download metadata was not retained")
	}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	files, err := os.ReadDir(directory)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range files {
		if entry.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(directory, entry.Name()))
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Contains(data, []byte("private-attachment-token")) || bytes.Contains(data, []byte("fixture-media-secret")) {
			t.Fatal("attachment credentials were written as plaintext")
		}
	}
}

func TestPictureEventsUpdateAndRemoveConversationPhotos(t *testing.T) {
	var emitted []map[string]any
	c := &Connector{accountID: "fixture", emit: func(e map[string]any) { emitted = append(emitted, e) }}
	jid := types.NewJID("123", types.DefaultUserServer)
	c.handleEvent(&events.Picture{JID: jid, PictureID: "revision"})
	if emitted[0]["avatar_source"] != "avatar:"+jid.String()+"#revision" {
		t.Fatal("photo update missing")
	}
	c.handleEvent(&events.Picture{JID: jid, Remove: true})
	if emitted[1]["avatar_source"] != "" {
		t.Fatal("photo removal missing")
	}
}
