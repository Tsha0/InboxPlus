package wechat

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/eatmoreapple/openwechat"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }

func TestWeChatDoesNotRetryUnconfirmedSend(t *testing.T) {
	bot := newBot(context.Background())
	defer bot.Exit()
	attempts := 0
	bot.Caller.Client.HTTPClient().Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
		attempts++
		return nil, errors.New("fixture acknowledgement lost")
	})
	_, err := bot.Caller.WebWxSendMsg(context.Background(), &openwechat.CallerWebWxSendMsgOptions{LoginInfo: &openwechat.LoginInfo{}, BaseRequest: &openwechat.BaseRequest{}, Message: openwechat.NewTextSendMessage("fixture", "@self", "@friend")})
	if err == nil || attempts != 1 {
		t.Fatal("uncertain message was retried")
	}
}

func TestWeChatNormalizesPrivateGroupAndOutgoingMessages(t *testing.T) {
	for _, test := range []struct {
		from, to, content, conversation, sender string
		outgoing                                bool
	}{
		{"@friend", "@self", "hello &amp; goodbye", "@friend", "@friend", false},
		{"@@group", "@self", "@friend:\nhello &amp; goodbye", "@@group", "@friend", false},
		{"@self", "@@group", "hello &amp; goodbye", "@@group", "@self", true},
	} {
		message := &openwechat.Message{MsgId: "message", MsgType: openwechat.MsgTypeText, FromUserName: test.from, ToUserName: test.to, Content: test.content, CreateTime: 1700000000, Raw: []byte("private-session-token")}
		event := normalize(message, "@self")
		if event["conversation_id"] != test.conversation || event["sender_id"] != test.sender || event["outgoing"] != test.outgoing || event["body"] != "hello & goodbye" || event["timestamp"] != int64(1700000000000) {
			t.Fatal("message lost its sender, target, text or timestamp")
		}
		encoded, _ := json.Marshal(event)
		if bytes.Contains(encoded, []byte("private-session-token")) {
			t.Fatal("unknown network fields leaked")
		}
	}
}

func TestWeChatAccountWithoutSessionNeverStartsQRInBackground(t *testing.T) {
	c, err := New("wechat-fixture", t.TempDir(), make([]byte, 32), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	result, err := c.Handle(context.Background(), map[string]any{"op": "connect"})
	if err != nil || result.(map[string]any)["state"] != "needs_login" || c.HasSession() {
		t.Fatal("background reconnect started an interactive sign-in")
	}
	if Capabilities()["history_sync"] != false || Capabilities()["send_attachment"] != false || Capabilities()["replies"] != false {
		t.Fatal("unsupported operations advertised")
	}
}

func TestWeChatContactTitlesAndGroupIdentityArePreserved(t *testing.T) {
	private := chat(&openwechat.User{UserName: "@friend", RemarkName: "Saved name", NickName: "Remote name"})
	group := chat(&openwechat.User{UserName: "@@group", NickName: "Group"})
	if private["title"] != "Saved name" || private["identity_id"] != "@friend" || group["is_group"] != true || group["identity_id"] != nil {
		t.Fatal("contact and group identities were mixed")
	}
}

func TestProfilePhotoReferencesChangeWithoutExposingSessionURLs(t *testing.T) {
	user := &openwechat.User{UserName: "@friend", HeadImgUrl: "/head?session=private-one"}
	first := chat(user)["avatar_source"]
	user.HeadImgUrl = "/head?session=private-two"
	second := chat(user)
	encoded, _ := json.Marshal(second)
	if first == second["avatar_source"] || bytes.Contains(encoded, []byte("private-")) {
		t.Fatal("photo update was lost or leaked a session URL")
	}
	user.HeadImgUrl = ""
	if chat(user)["avatar_source"] != "" {
		t.Fatal("photo removal was lost")
	}
}
