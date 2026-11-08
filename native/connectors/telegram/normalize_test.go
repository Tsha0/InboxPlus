package telegram

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/gotd/td/tg"
)

func TestReactionCountsPreserveOwnZeroOrderAndEmptySnapshots(t *testing.T) {
	chosen := tg.ReactionCount{Reaction: &tg.ReactionEmoji{Emoticon: "👍"}, Count: 3}
	chosen.SetChosenOrder(0)
	reactions := tg.MessageReactions{Results: []tg.ReactionCount{chosen, {Reaction: &tg.ReactionEmoji{Emoticon: "❤️"}, Count: 2}}}
	event := normalizeMessage("account", &tg.Message{ID: 7, PeerID: &tg.PeerUser{UserID: 42}, Reactions: reactions}, "")
	values := event["reactions"].([]map[string]any)
	if len(values) != 2 || values[0]["count"] != 3 || values[0]["includes_me"] != true || values[1]["includes_me"] != false {
		t.Fatal("reaction counts or ownership were lost")
	}
	var emitted []map[string]any
	b := &gotdBackend{accountID: "account", emit: func(event map[string]any) { emitted = append(emitted, event) }}
	if err := b.handleUpdates(context.Background(), &tg.UpdateShort{Update: &tg.UpdateMessageReactions{Peer: &tg.PeerUser{UserID: 42}, MsgID: 7}}); err != nil {
		t.Fatal(err)
	}
	if len(emitted) != 1 || emitted[0]["id"] != "user:42:7" || len(emitted[0]["reactions"].([]map[string]any)) != 0 {
		t.Fatal("empty reaction update did not clear its scoped message")
	}
}

func TestReplyIdentifiersAreScopedAndNormalized(t *testing.T) {
	message := &tg.Message{ID: 2, PeerID: &tg.PeerUser{UserID: 42}, ReplyTo: &tg.MessageReplyHeader{ReplyToMsgID: 1}}
	event := normalizeMessage("account", message, "")
	if event["reply_to_message_id"] != "user:42:1" {
		t.Fatal("incoming reply was not scoped")
	}
	message.ReplyTo = &tg.MessageReplyHeader{ReplyToMsgID: 1, ReplyToPeerID: &tg.PeerUser{UserID: 43}}
	if _, present := normalizeMessage("account", message, "")["reply_to_message_id"]; present {
		t.Fatal("external reply was assigned to this conversation")
	}
	if id, err := replyMessageID("user:42", "user:42:1"); err != nil || id != 1 {
		t.Fatal("valid reply target rejected")
	}
	for _, invalid := range []string{"user:43:1", "user:42:0", "user:42:-1", "user:42:2147483648", "1"} {
		if _, err := replyMessageID("user:42", invalid); err == nil {
			t.Fatal("invalid or cross-conversation reply was accepted")
		}
	}
}

func TestKnownRecipientResolutionAndBackfillEvents(t *testing.T) {
	events := []map[string]any{}
	b := &gotdBackend{
		accountID: "fixture", peers: map[string]tg.InputPeerClass{}, names: map[string]string{},
		attachments: map[string]attachmentReference{}, emit: func(event map[string]any) { events = append(events, event) },
	}
	b.remember([]tg.UserClass{&tg.User{ID: 42, AccessHash: 123, FirstName: "Fixture"}}, nil)
	result, err := b.Resolve(context.Background(), "user:42")
	if err != nil || result.(map[string]any)["id"] != "user:42" || events[0]["title"] != "Fixture" {
		t.Fatalf("known recipient unavailable: %v", err)
	}
	if _, err := b.Resolve(context.Background(), "user:43"); err == nil {
		t.Fatal("unknown peer was accepted without an access hash")
	}
	for _, historical := range []bool{true, false} {
		b.deliver(&tg.Message{ID: 1, PeerID: &tg.PeerUser{UserID: 42}}, historical)
		if events[len(events)-1]["historical"] != historical {
			t.Fatal("message lost backfill marker")
		}
	}
}

func TestDeletedMessagesKeepTheirKnownConversationScope(t *testing.T) {
	events := []map[string]any{}
	b := &gotdBackend{accountID: "account", names: map[string]string{}, attachments: map[string]attachmentReference{},
		emit: func(event map[string]any) { events = append(events, event) }}
	b.deliver(&tg.Message{ID: 7, PeerID: &tg.PeerUser{UserID: 41}}, true)
	b.deliver(&tg.Message{ID: 8, PeerID: &tg.PeerChat{ChatID: 42}}, true)
	b.deliver(&tg.Message{ID: 7, PeerID: &tg.PeerChannel{ChannelID: 43}}, true)
	events = nil
	if err := b.handleUpdates(context.Background(), &tg.Updates{Updates: []tg.UpdateClass{
		&tg.UpdateDeleteMessages{Messages: []int{7, 8, 99}},
		&tg.UpdateDeleteChannelMessages{ChannelID: 43, Messages: []int{7, 99}},
	}}); err != nil {
		t.Fatal(err)
	}
	if len(events) != 4 {
		t.Fatalf("expected four scoped deletions, got %d", len(events))
	}
	for index, route := range []string{"user:41", "chat:42", "channel:43", "channel:43"} {
		if events[index]["type"] != "message_delete" || events[index]["account_id"] != "account" || events[index]["conversation_id"] != route {
			t.Fatal("deleted message was assigned to the wrong conversation")
		}
	}
	if events[0]["id"] != "user:41:7" || events[1]["id"] != "chat:42:8" || events[3]["id"] != "channel:43:99" {
		t.Fatal("deletion lost the scoped message identifier")
	}
}

func TestNonChannelDeletionDoesNotGuessAnAmbiguousConversation(t *testing.T) {
	events := []map[string]any{}
	b := &gotdBackend{accountID: "account", names: map[string]string{}, attachments: map[string]attachmentReference{},
		emit: func(event map[string]any) { events = append(events, event) }}
	b.deliver(&tg.Message{ID: 7, PeerID: &tg.PeerUser{UserID: 41}}, true)
	b.deliver(&tg.Message{ID: 7, PeerID: &tg.PeerChat{ChatID: 42}}, true)
	events = nil
	if err := b.handleUpdates(context.Background(), &tg.UpdateShort{Update: &tg.UpdateDeleteMessages{Messages: []int{7}}}); err != nil {
		t.Fatal(err)
	}
	if len(events) != 0 {
		t.Fatal("ambiguous deletion removed an unrelated message")
	}
}

func TestMessageMetadataDistinguishesGroupFromDirectConversation(t *testing.T) {
	for _, fixture := range []struct {
		peer  tg.PeerClass
		group bool
	}{
		{&tg.PeerUser{UserID: 1}, false},
		{&tg.PeerChat{ChatID: 1}, true},
		{&tg.PeerChannel{ChannelID: 1}, true},
	} {
		event := normalizeMessage("account", &tg.Message{ID: 1, PeerID: fixture.peer}, "")
		if event["is_group"] != fixture.group {
			t.Fatal("message lacks its conversation kind")
		}
		_, hasIdentity := event["identity_id"]
		if hasIdentity == fixture.group {
			t.Fatal("group was presented as a contact identity")
		}
	}
}

func TestPersistedSendIdentifiersDeduplicateWithinAccountAndConversation(t *testing.T) {
	id := stableRequestID("account", "user:42", "pending-send")
	if id == 0 || stableRequestID("account", "user:42", "pending-send") != id {
		t.Fatal("retry generated a different Telegram random_id")
	}
	for _, other := range []int64{
		stableRequestID("other-account", "user:42", "pending-send"),
		stableRequestID("account", "user:43", "pending-send"),
		stableRequestID("account", "user:42", "other-send"),
	} {
		if other == id {
			t.Fatal("unrelated send reused a Telegram random_id")
		}
	}
	if stableRequestID("account", "user:42", "") != 0 {
		t.Fatal("unidentified sends must use the SDK random source")
	}
}

func TestNormalizeTextMessage(t *testing.T) {
	message := &tg.Message{
		ID: 42, PeerID: &tg.PeerChannel{ChannelID: 17}, FromID: &tg.PeerUser{UserID: 9},
		Date: 1700000000, Message: "Fixture message", Out: true,
	}
	event := normalizeMessage("local-account", message, "Fixture sender")
	for key, expected := range map[string]any{
		"type": "message", "account_id": "local-account", "conversation_id": "channel:17",
		"id": "channel:17:42", "body": "Fixture message", "timestamp": int64(1700000000000),
		"outgoing": true, "sender_id": "user:9", "sender_name": "Fixture sender", "kind": "text",
	} {
		if event[key] != expected {
			t.Fatalf("%s = %v, want %v", key, event[key], expected)
		}
	}
	if len(event["attachments"].([]map[string]any)) != 0 {
		t.Fatal("text message has attachments")
	}
	message.PeerID = &tg.PeerChat{ChatID: 17}
	if normalizeMessage("local-account", message, "")["id"] == event["id"] {
		t.Fatal("message IDs collide between peer types")
	}
}

func TestNormalizeDocumentMetadataKeepsLocationPrivate(t *testing.T) {
	document := &tg.Document{
		ID: 123, AccessHash: 456, FileReference: []byte("sensitive-file-reference"),
		Size: 12000, MimeType: "application/pdf", DCID: 3, Attributes: []tg.DocumentAttributeClass{
			&tg.DocumentAttributeFilename{FileName: "fixture.pdf"},
		},
	}
	media := &tg.MessageMediaDocument{Document: document}
	event := normalizeMessage("account", &tg.Message{ID: 6, PeerID: &tg.PeerUser{UserID: 2}, Media: media}, "")
	attachment := event["attachments"].([]map[string]any)[0]
	if event["kind"] != "file" || attachment["name"] != "fixture.pdf" || attachment["mime_type"] != "application/pdf" || attachment["size"] != int64(12000) || attachment["id"] != "user:2:6" {
		t.Fatalf("unexpected attachment metadata: %v", attachment)
	}
	encoded, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "sensitive-file-reference") || strings.Contains(string(encoded), "access_hash") {
		t.Fatal("attachment location leaked to event")
	}
	location, size, ok := mediaLocation(media)
	if !ok || size != 12000 || location.(*tg.InputDocumentFileLocation).AccessHash != 456 {
		t.Fatal("internal document location is unavailable")
	}
	if mediaDCID(media) != 3 {
		t.Fatal("document DCID is unavailable")
	}
}

func TestPhotoUsesLargestDownloadableSize(t *testing.T) {
	media := &tg.MessageMediaPhoto{Photo: &tg.Photo{
		ID: 10, AccessHash: 20, FileReference: []byte("reference"), DCID: 4,
		Sizes: []tg.PhotoSizeClass{
			&tg.PhotoSize{Type: "m", W: 100, H: 100, Size: 1000},
			&tg.PhotoSizeProgressive{Type: "y", W: 1000, H: 1000, Sizes: []int{500, 5000, 10000}},
			&tg.PhotoSize{Type: "s", W: 20, H: 20, Size: 100},
		},
	}}
	location, size, ok := mediaLocation(media)
	if !ok || size != 10000 || location.(*tg.InputPhotoFileLocation).ThumbSize != "y" {
		t.Fatal("largest photo size was not chosen")
	}
	if mediaDCID(media) != 4 {
		t.Fatal("photo DCID is unavailable")
	}
	event := normalizeMessage("account", &tg.Message{ID: 1, PeerID: &tg.PeerUser{UserID: 2}, Media: media}, "")
	if event["kind"] != "image" || event["attachments"].([]map[string]any)[0]["size"] != int64(10000) {
		t.Fatal("photo metadata does not describe downloaded size")
	}
}

func TestUnsupportedAndExpiredMediaRemainExplicit(t *testing.T) {
	for _, media := range []tg.MessageMediaClass{
		&tg.MessageMediaGeo{},
		&tg.MessageMediaPhoto{Photo: &tg.PhotoEmpty{ID: 1}},
		&tg.MessageMediaDocument{Document: &tg.Document{ID: 1}, TTLSeconds: 10},
		&tg.MessageMediaPhoto{Photo: &tg.Photo{ID: 1}, TTLSeconds: 10},
	} {
		event := normalizeMessage("account", &tg.Message{Media: media, Message: "caption"}, "")
		if event["kind"] != "unsupported" || event["body"] != "caption" || len(event["attachments"].([]map[string]any)) != 0 {
			t.Fatal("unsupported media was presented as downloadable")
		}
		if _, _, available := mediaLocation(media); available {
			t.Fatal("unsupported media has a download location")
		}
	}
}

func TestDocumentKinds(t *testing.T) {
	for _, test := range []struct {
		mime string
		kind string
	}{
		{"audio/ogg", "audio"}, {"video/mp4", "video"}, {"image/webp", "image"},
	} {
		event := normalizeMessage("account", &tg.Message{Media: &tg.MessageMediaDocument{Document: &tg.Document{MimeType: test.mime}}}, "")
		if event["kind"] != test.kind {
			t.Fatalf("MIME %s has kind %v, want %s", test.mime, event["kind"], test.kind)
		}
	}
}

func TestDialogSyncPaginatesAndRetainsEveryPeer(t *testing.T) {
	var events []map[string]any
	b := &gotdBackend{accountID: "fixture", peers: map[string]tg.InputPeerClass{}, names: map[string]string{}, attachments: map[string]attachmentReference{}, emit: func(event map[string]any) { events = append(events, event) }}
	calls := 0
	err := b.syncDialogs(context.Background(), func(ctx context.Context, request *tg.MessagesGetDialogsRequest) (tg.MessagesDialogsClass, error) {
		calls++
		first, end := 1, 100
		if calls == 1 {
			if request.OffsetID != 0 || request.Limit != 100 {
				t.Fatal("invalid first page")
			}
		} else {
			peer, ok := request.OffsetPeer.(*tg.InputPeerUser)
			if calls != 2 || !ok || peer.UserID != 100 || request.OffsetID != 7 || request.OffsetDate != 100 || !request.ExcludePinned {
				t.Fatal("offset did not advance to last dialog")
			}
			first, end = 101, 101
		}
		page := &tg.MessagesDialogsSlice{Count: 101}
		for i := first; i <= end; i++ {
			peer := &tg.PeerUser{UserID: int64(i)}
			page.Users = append(page.Users, &tg.User{ID: int64(i), AccessHash: int64(i + 1000), FirstName: "Fixture"})
			page.Dialogs = append(page.Dialogs, &tg.Dialog{Peer: peer, TopMessage: 7})
			page.Messages = append(page.Messages, &tg.Message{ID: 7, PeerID: peer, Date: i})
		}
		if calls == 2 {
			return &tg.MessagesDialogs{Users: page.Users, Dialogs: page.Dialogs, Messages: page.Messages}, nil
		}
		return page, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 || len(b.peers) != 101 {
		t.Fatalf("loaded %d peers in %d pages", len(b.peers), calls)
	}
	chats := 0
	for _, event := range events {
		if event["type"] == "chat" {
			chats++
		}
	}
	if chats != 101 {
		t.Fatalf("emitted %d chats", chats)
	}
	for i := 1; i <= 101; i++ {
		if _, err := b.peer(fmt.Sprintf("user:%d", i)); err != nil {
			t.Fatal("page peer was lost")
		}
	}
}

func TestDialogSyncPropagatesPageFailure(t *testing.T) {
	expected := errors.New("fixture failure")
	b := &gotdBackend{}
	if err := b.syncDialogs(context.Background(), func(context.Context, *tg.MessagesGetDialogsRequest) (tg.MessagesDialogsClass, error) {
		return nil, expected
	}); !errors.Is(err, expected) {
		t.Fatal("page failure was swallowed")
	}
}
