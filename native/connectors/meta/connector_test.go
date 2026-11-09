package meta

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"go.mau.fi/mautrix-meta/pkg/instameow/slidetypes"
	"go.mau.fi/mautrix-meta/pkg/messagix/cookies"
	"go.mau.fi/mautrix-meta/pkg/messagix/responses"
	"go.mau.fi/util/jsontime"
)

func TestClosingReportsCookiesEvenBeforeTransportConnects(t *testing.T) {
	client, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	if client.HasSession() {
		t.Fatal("empty setup contains a session")
	}
	client.state.Cookies = map[cookies.MetaCookieName]string{cookies.IGCookieSessionID: "fixture-private-session"}
	if err := client.Close(); err != nil {
		t.Fatal(err)
	}
	if !client.HasSession() {
		t.Fatal("closed setup lost captured authentication")
	}
}

func TestInstagramReactionSnapshotsAndLiveRemovalKeepActorOwnership(t *testing.T) {
	var captured []map[string]any
	c, err := New(accountRequest(t.TempDir()), func(event map[string]any) { captured = append(captured, event) })
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.ownID = "101"
	reaction := slidetypes.Reaction{SenderFBID: 101, Reaction: "❤️", ReactionTimestampMS: jsontime.UnixMilliString{Time: time.UnixMilli(1700000000000)}}
	snapshot := c.instagramMessage("thread", &slidetypes.Message{ID: "message", TextBody: "Fixture", Reactions: []*slidetypes.Reaction{&reaction}})
	values := snapshot["reactions"].([]map[string]any)
	if len(values) != 1 || values[0]["sender_id"] != "101" || values[0]["includes_me"] != true {
		t.Fatal("snapshot lost reaction actor or ownership")
	}
	for _, removed := range []bool{false, true} {
		c.emitInstagramReaction("thread", "message", reaction, removed)
	}
	if len(captured) != 2 || captured[0]["emoji"] != "❤️" || captured[1]["emoji"] != "" || captured[1]["outgoing"] != true || captured[1]["id"] != "message" {
		t.Fatal("live reaction add/remove was not scoped to its original message")
	}
}

func accountRequest(directory string) map[string]any {
	return map[string]any{"account_id": "account", "platform": "instagram", "directory": directory,
		"key": base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))}
}

func TestEncryptedSessionRoundTripAndAccountBinding(t *testing.T) {
	directory := t.TempDir()
	c, err := New(accountRequest(directory), nil)
	if err != nil {
		t.Fatal(err)
	}
	c.state = sessionState{Cookies: map[cookies.MetaCookieName]string{cookies.IGCookieSessionID: "private-session"},
		SeqID: 42, SeqTime: time.Unix(1700000000, 0), Reconnect: json.RawMessage(`{"secret":"reconnect-token"}`)}
	if err = c.saveState(); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "meta-session.enc")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, secret := range []string{"private-session", "reconnect-token", "sessionid"} {
		if bytes.Contains(data, []byte(secret)) {
			t.Fatalf("session file exposed %q", secret)
		}
	}
	for target, mode := range map[string]os.FileMode{directory: 0700, path: 0600} {
		info, statErr := os.Stat(target)
		if statErr != nil || (runtime.GOOS != "windows" && info.Mode().Perm() != mode) {
			t.Fatalf("storage permissions do not match %o", mode)
		}
	}
	restored, err := New(accountRequest(directory), nil)
	if err != nil || restored.state.SeqID != 42 || restored.state.Cookies[cookies.IGCookieSessionID] != "private-session" {
		t.Fatal("encrypted session did not restore")
	}
	other := accountRequest(directory)
	other["account_id"] = "other-account"
	if _, err = New(other, nil); err == nil {
		t.Fatal("session must be bound to its account")
	}
	other = accountRequest(directory)
	other["key"] = base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{8}, 32))
	if _, err = New(other, nil); err == nil {
		t.Fatal("wrong encryption key must fail")
	}
	data[len(data)-1] ^= 1
	if err = os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = New(accountRequest(directory), nil); err == nil {
		t.Fatal("tampered session must fail")
	}
}

func TestLoginRejectsMissingOrInjectedCookiesBeforeNetwork(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, values := range []map[string]any{
		{"sessionid": "private-session", "ds_user_id": "101"},
		{"sessionid": "private-session\r\ninjection", "csrftoken": "private-csrf", "ds_user_id": "101"},
		{"sessionid": "private-session", "csrftoken": "private-csrf", "ds_user_id": "not-a-number"},
	} {
		_, err = c.Handle(context.Background(), map[string]any{"op": "login", "cookies": values})
		if err == nil {
			t.Fatal("invalid cookies reached the network")
		}
		if strings.Contains(err.Error(), "private-") {
			t.Fatal("login error exposed credentials")
		}
	}
}

func TestInstagramReelRepliesKeepTheirDistinctTargets(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"mountain", "cafe"} {
		original := c.instagramMessage("thread", &slidetypes.Message{
			ID: id,
			Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentXMA{
				XMA: &slidetypes.XMAContent{TargetURL: "https://www.instagram.com/reel/" + id + "/"},
			}},
		})
		attachments := original["attachments"].([]any)
		if original["body"] != "" || len(attachments) != 1 {
			t.Fatal("media-only Reel did not retain its attachment")
		}
		attachment := attachments[0].(map[string]any)
		if attachment["kind"] != "reel" || attachment["deep_link"] != "https://www.instagram.com/reel/"+id+"/" {
			t.Fatal("Reel identity was lost")
		}
		reply := c.instagramMessage("thread", &slidetypes.Message{
			ID: "reply-" + id, RepliedToMessageID: id,
			Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentText{TextBody: "Response"}},
		})
		if reply["reply_to_message_id"] != original["id"] {
			t.Fatal("reply was associated with the wrong Reel")
		}
	}
}

func TestInstagramNormalizesMessageWithoutCredentialOrUnknownFields(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	c.ownID = "101"
	message := &slidetypes.Message{ID: "message", SenderFBID: 101, RepliedToMessageID: "original", Sender: &slidetypes.MessageSender{Name: "Sender"},
		TimestampMS:  jsontime.UnixMilliString{Time: time.UnixMilli(123456)},
		Content:      slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentText{TextBody: "Hello"}},
		Unrecognized: map[string]any{"token": "session-secret"}}
	event := c.instagramMessage("thread", message)
	if event["reply_to_message_id"] != "original" {
		t.Fatal("incoming reply target was lost")
	}
	if event["id"] != "message" || event["body"] != "Hello" || event["timestamp"] != int64(123456) || event["outgoing"] != true || event["sender_name"] != "Sender" {
		t.Fatalf("unexpected normalized fields: %#v", event)
	}
	encoded, err := json.Marshal(event)
	if err != nil || bytes.Contains(encoded, []byte("session-secret")) {
		t.Fatal("normalized event exposed unknown fields")
	}
}

func TestInstagramAttachmentURLsRemainBehindOpaqueIdentifiers(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	message := &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentImage{Attachments: []*slidetypes.Attachment{
		{AttachmentFBID: "photo", AttachmentCDNURL: "https://scontent.cdninstagram.com/image.jpg?token=private"},
	}}}}
	event := c.instagramMessage("thread", message)
	encoded, err := json.Marshal(event)
	if err != nil || bytes.Contains(encoded, []byte("token=private")) || bytes.Contains(encoded, []byte("cdninstagram.com")) {
		t.Fatal("normalized event exposed attachment URL")
	}
	attachments := event["attachments"].([]any)
	if len(attachments) != 1 || attachments[0].(map[string]any)["id"] != "message/photo" {
		t.Fatal("missing opaque attachment identifier")
	}
	if c.media["message/photo"].URL == "" {
		t.Fatal("attachment could not be resolved locally")
	}
}

func TestDisappearingInstagramMediaIsExplicitlyUnavailable(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	message := &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentRavenImage{
		Attachment: &slidetypes.Attachment{AttachmentFBID: "photo", AttachmentCDNURL: "https://scontent.cdninstagram.com/private"},
	}}}
	event := c.instagramMessage("thread", message)
	if event["kind"] != "unsupported" || len(event["attachments"].([]any)) != 0 || len(c.media) != 0 {
		t.Fatal("disappearing media must not be downloaded or represented as supported")
	}
}

func TestOnlyHTTPSMetaMediaAndOwnedInstagramLinksAreAccepted(t *testing.T) {
	for _, raw := range []string{"http://cdninstagram.com/file", "https://cdninstagram.com.evil.test/file", "https://user@cdninstagram.com/file", "https://cdninstagram.com:444/file", "file:///private/file"} {
		if allowedMediaURL(raw) {
			t.Fatalf("accepted unsafe media URL %q", raw)
		}
	}
	if !allowedMediaURL("https://scontent.fbcdn.net/file") || !validInstagramLink("https://www.instagram.com/reel/example/") {
		t.Fatal("valid upstream URL was rejected")
	}
	if validInstagramLink("https://instagram.com.evil.test/reel/example/") {
		t.Fatal("external deep link was accepted")
	}
}

func TestMetaCapabilitiesMatchActualOperations(t *testing.T) {
	for _, platform := range []string{"instagram", "messenger"} {
		req := accountRequest(t.TempDir())
		req["platform"] = platform
		c, err := New(req, nil)
		if err != nil {
			t.Fatal(err)
		}
		result, err := c.Handle(context.Background(), map[string]any{"op": "capabilities"})
		if err != nil {
			t.Fatal(err)
		}
		capabilities := result.(map[string]any)
		if capabilities["reactions"] != true || capabilities["replies"] != true || capabilities["send_attachment"] != (platform == "instagram") || capabilities["max_attachment_bytes"] != 32<<20 || capabilities["encrypted_chats"] != false {
			t.Fatalf("incorrect capabilities for %s: %#v", platform, capabilities)
		}
		if _, err = c.Handle(context.Background(), map[string]any{"op": "send_text", "conversation_id": "thread", "body": "Hello"}); err == nil {
			t.Fatal("disconnected account attempted to send")
		}
	}
}

func TestSessionWriteFailureStopsFurtherNetworkOperations(t *testing.T) {
	var emitted []map[string]any
	c, err := New(accountRequest(t.TempDir()), func(event map[string]any) { emitted = append(emitted, event) })
	if err != nil {
		t.Fatal(err)
	}
	c.directory = filepath.Join(c.directory, "unavailable")
	if err = c.saveState(); err == nil {
		t.Fatal("session write unexpectedly succeeded")
	}
	if len(emitted) != 1 || emitted[0]["state"] != "error" {
		t.Fatal("session write failure was not reported")
	}
	if _, err = c.Handle(context.Background(), map[string]any{"op": "connect"}); err == nil || !strings.Contains(err.Error(), "reopen the account") {
		t.Fatal("connector did not stop after its encrypted session could not be saved")
	}
}

func TestInitialMailboxDoesNotPublishIncompleteMessageStubs(t *testing.T) {
	var emitted []map[string]any
	c, err := New(accountRequest(t.TempDir()), func(event map[string]any) { emitted = append(emitted, event) })
	if err != nil {
		t.Fatal(err)
	}
	thread := &slidetypes.ThreadInfo{ID: "thread", ThreadTitle: "Conversation", SlideMessages: &slidetypes.SlideMessages{
		Edges: []slidetypes.Node[*slidetypes.Message]{{Node: &slidetypes.Message{ID: "stub"}}},
	}}
	c.emitMailbox(&slidetypes.Mailbox{ThreadsByFolder: slidetypes.Edged[slidetypes.Node[slidetypes.WrappedThreadInfo]]{
		Edges: []slidetypes.Node[slidetypes.WrappedThreadInfo]{{Node: slidetypes.WrappedThreadInfo{AsIGDirectThread: thread}}},
	}})
	if len(emitted) != 1 || emitted[0]["type"] != "chat" {
		t.Fatal("mailbox stubs were incorrectly treated as complete messages")
	}
}

func TestInstagramMultimediaWithoutUpstreamIDsHasDistinctOpaqueReferences(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	message := &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentMultiMedia{
		Attachments: []*slidetypes.Attachment{
			{AttachmentCDNURL: "https://scontent.cdninstagram.com/first"},
			{AttachmentCDNURL: "https://scontent.cdninstagram.com/second", AttachmentType: 2},
		},
	}}}
	attachments := c.instagramMessage("thread", message)["attachments"].([]any)
	if len(attachments) != 2 || attachments[0].(map[string]any)["id"] == attachments[1].(map[string]any)["id"] || len(c.media) != 2 {
		t.Fatal("multiple media items overwrote the same opaque reference")
	}
}

func TestUpdatedCookiesArePersistedWithoutRewritingUnchangedState(t *testing.T) {
	directory := t.TempDir()
	c, err := New(accountRequest(directory), nil)
	if err != nil {
		t.Fatal(err)
	}
	jar := &cookies.Cookies{}
	jar.UpdateValues(map[cookies.MetaCookieName]string{cookies.IGCookieSessionID: "rotated-session"})
	if err = c.updateCookies(jar); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "meta-session.enc")
	first, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = c.updateCookies(jar); err != nil {
		t.Fatal(err)
	}
	second, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(first, second) {
		t.Fatal("unchanged cookies unnecessarily rewrote the encrypted session")
	}
	restored, err := New(accountRequest(directory), nil)
	if err != nil || restored.state.Cookies[cookies.IGCookieSessionID] != "rotated-session" {
		t.Fatal("updated session cookies were not restored")
	}
}

func TestLogoutRemovesCredentialsAndOpaqueMedia(t *testing.T) {
	directory := t.TempDir()
	c, err := New(accountRequest(directory), nil)
	if err != nil {
		t.Fatal(err)
	}
	c.state.Cookies = map[cookies.MetaCookieName]string{cookies.IGCookieSessionID: "private-session"}
	if err = c.saveState(); err != nil {
		t.Fatal(err)
	}
	c.rememberMedia("opaque", "https://scontent.cdninstagram.com/private", "image/jpeg", "image")
	result, err := c.Handle(context.Background(), map[string]any{"op": "logout"})
	if err != nil {
		t.Fatal(err)
	}
	if result.(map[string]any)["remote_session_revoked"] != false {
		t.Fatal("local logout claimed to revoke the remote session")
	}
	if _, err = os.Stat(filepath.Join(directory, "meta-session.enc")); !os.IsNotExist(err) || len(c.media) != 0 || len(c.state.Cookies) != 0 {
		t.Fatal("logout retained local credentials or attachment URLs")
	}
	restored, err := New(accountRequest(directory), nil)
	if err != nil || len(restored.state.Cookies) != 0 {
		t.Fatal("logged-out session unexpectedly restored credentials")
	}
}

func TestInstagramSeparatesHistoricalMessagesAndNormalizesUnreadChat(t *testing.T) {
	var emitted []map[string]any
	c, err := New(accountRequest(t.TempDir()), func(event map[string]any) { emitted = append(emitted, event) })
	if err != nil {
		t.Fatal(err)
	}
	c.emitInstagramThread(&slidetypes.ThreadInfo{ID: "thread", MarkedAsUnread: true, IsGroup: true})
	message := &slidetypes.Message{ID: "message", TextBody: "Hello"}
	c.emitInstagramMessage("thread", message, true)
	c.emitInstagramMessage("thread", message, false)
	if emitted[0]["unread_count"] != 1 || emitted[0]["is_group"] != true || emitted[1]["is_group"] != true || emitted[2]["is_group"] != true || emitted[1]["historical"] != true || emitted[2]["historical"] != false {
		t.Fatal("history and live delivery metadata were not distinguished")
	}
	for _, event := range emitted {
		if _, ok := event["identity_id"]; ok {
			t.Fatal("group was assigned a contact identity")
		}
	}
}

func TestInstagramDirectPeerMetadataIsSharedByChatsAndMessages(t *testing.T) {
	var emitted []map[string]any
	c, err := New(accountRequest(t.TempDir()), func(event map[string]any) { emitted = append(emitted, event) })
	if err != nil {
		t.Fatal(err)
	}
	c.ownID = "101"
	c.emitInstagramThread(&slidetypes.ThreadInfo{ID: "thread", IsGroup: false, Users: []*slidetypes.User{{InteropMessagingUserFBID: 101}, {InteropMessagingUserFBID: 201}}})
	c.emitInstagramMessage("thread", &slidetypes.Message{ID: "message", TextBody: "Fixture"}, false)
	if len(emitted) != 2 {
		t.Fatal("expected chat and message")
	}
	for _, event := range emitted {
		if event["is_group"] != false || event["identity_id"] != "201" {
			t.Fatal("direct conversation lost the other person's identity")
		}
	}
	unknown := c.instagramMessage("unknown", &slidetypes.Message{ID: "unknown-message", TextBody: "Fixture"})
	if _, ok := unknown["is_group"]; ok {
		t.Fatal("unknown conversation was guessed to be direct")
	}
	if _, ok := unknown["identity_id"]; ok {
		t.Fatal("unknown conversation was assigned a person")
	}
}

func TestRepeatedConnectReportsTheExistingTransportState(t *testing.T) {
	for _, platform := range []string{"instagram", "messenger"} {
		req := accountRequest(t.TempDir())
		req["platform"] = platform
		c, err := New(req, nil)
		if err != nil {
			t.Fatal(err)
		}
		c.ready = true
		c.transportReady.Store(true)
		if c.fb != nil {
			c.fb.ready = true
		}
		result, err := c.Handle(context.Background(), map[string]any{"op": "connect"})
		if err != nil || result.(map[string]any)["state"] != "connected" {
			t.Fatal("repeated connect incorrectly made a connected account appear offline")
		}
	}
}

func TestInstagramSharedPostKeepsPreviewAndShowsCaptionOnce(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	message := &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentXMA{XMA: &slidetypes.XMAContent{
		TitleText: "Fixture caption", HeaderTitleText: "fixture.author", TargetURL: "https://www.instagram.com/p/fixture/",
		PreviewImage: &slidetypes.XMAPreviewImage{URL: "https://scontent.cdninstagram.com/preview.jpg?token=private"},
	}}}}
	event := c.instagramMessage("thread", message)
	attachment := event["attachments"].([]any)[0].(map[string]any)
	if event["body"] != "Fixture caption" || attachment["name"] != "fixture.author" || attachment["kind"] != "link" || attachment["downloadable"] != false {
		t.Fatalf("unexpected shared post: %#v", event)
	}
	if attachment["preview_id"] != "message/preview" || c.media["message/preview"].URL == "" {
		t.Fatal("shared post preview was not kept")
	}
	encoded, _ := json.Marshal(event)
	if bytes.Contains(encoded, []byte("token=private")) {
		t.Fatal("normalized event exposed the preview URL")
	}
}

func TestInstagramSharedReelResolvesPlayableVideoOnDownload(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	video := []byte("fixture video")
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/720.mp4" {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(video)
	}))
	defer server.Close()
	served, _ := url.Parse(server.URL)
	transport := server.Client().Transport.(*http.Transport).Clone()
	transport.TLSClientConfig.InsecureSkipVerify = true
	transport.DialContext = func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, served.Host)
	}
	previous := http.DefaultTransport
	http.DefaultTransport = transport
	defer func() { http.DefaultTransport = previous }()
	var requested []string
	c.fetchMedia = func(_ context.Context, mediaID, shortcode string) (*responses.FetchMediaResponse, error) {
		requested = append(requested, mediaID, shortcode)
		return &responses.FetchMediaResponse{Items: []*responses.Items{{VideoVersions: []responses.VideoVersions{
			{Width: 1080, URL: "https://scontent.cdninstagram.com/1080.mp4"},
			{Width: 720, URL: "https://scontent.cdninstagram.com/720.mp4"},
			{Width: 480, URL: "https://scontent.cdninstagram.com/480.mp4"},
		}}}}, nil
	}
	message := &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentXMA{XMA: &slidetypes.XMAContent{
		TargetID: "123", TargetURL: "https://www.instagram.com/reel/Fixture_1/",
		PreviewImage: &slidetypes.XMAPreviewImage{URL: "https://scontent.cdninstagram.com/preview.jpg"},
	}}}}
	event := c.instagramMessage("thread", message)
	attachment := event["attachments"].([]any)[0].(map[string]any)
	if attachment["kind"] != "reel" || attachment["downloadable"] != true || attachment["mime_type"] != "video/mp4" || attachment["preview_id"] != "message/preview" {
		t.Fatalf("reel is not playable: %#v", attachment)
	}
	if len(requested) != 0 {
		t.Fatal("reel video was fetched before the user asked to play it")
	}
	result, err := c.download(context.Background(), "message/link")
	if err != nil {
		t.Fatal(err)
	}
	downloaded := result.(map[string]any)
	if downloaded["mime_type"] != "video/mp4" || downloaded["bytes"] != base64.StdEncoding.EncodeToString(video) {
		t.Fatalf("unexpected reel download: %#v", downloaded)
	}
	if strings.Join(requested, ",") != "123,Fixture_1" {
		t.Fatalf("unexpected media lookup: %v", requested)
	}
}

func TestInstagramReelWithoutPlayableVideoReportsUnavailable(t *testing.T) {
	c, err := New(accountRequest(t.TempDir()), nil)
	if err != nil {
		t.Fatal(err)
	}
	c.fetchMedia = func(context.Context, string, string) (*responses.FetchMediaResponse, error) {
		return &responses.FetchMediaResponse{Items: []*responses.Items{{VideoVersions: []responses.VideoVersions{{Width: 720, URL: "http://evil.test/video.mp4"}}}}}, nil
	}
	c.instagramMessage("thread", &slidetypes.Message{ID: "message", Content: slidetypes.MessageContentWrapper{Content: &slidetypes.MessageContentXMA{XMA: &slidetypes.XMAContent{
		TargetID: "123", TargetURL: "https://www.instagram.com/reel/fixture/",
	}}}})
	if _, err := c.download(context.Background(), "message/link"); err == nil || !strings.Contains(err.Error(), "open it in Instagram") {
		t.Fatalf("unexpected error: %v", err)
	}
}
