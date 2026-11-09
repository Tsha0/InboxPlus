package wechat

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"html"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/direct"
	"github.com/eatmoreapple/openwechat"
)

func Capabilities() map[string]any {
	return map[string]any{"platform": "wechat", "qr_login": true, "send_text": true, "send_attachment": false, "download_attachment": true, "history_sync": false, "replies": false, "reactions": false, "start_conversation": true}
}

func New(id, directory string, key []byte, emit func(map[string]any)) (*direct.Connector, error) {
	return direct.New(id, directory, key, Capabilities(), emit, func(c *direct.Connector) direct.Backend {
		return &backend{c: c, media: map[string]*openwechat.Message{}}
	})
}

type backend struct {
	c     *direct.Connector
	bot   *openwechat.Bot
	self  *openwechat.Self
	mu    sync.Mutex
	media map[string]*openwechat.Message
	stop  context.CancelFunc
}

type reloadStorage struct {
	reader *bytes.Reader
	c      *direct.Connector
}

func newBot(ctx context.Context) *openwechat.Bot {
	bot := openwechat.NewBot(ctx)
	openwechat.Desktop.Prepare(bot)
	// Retrying after a lost acknowledgement can send the same message twice.
	bot.Caller.Client.MaxRetryTimes = 1
	return bot
}

func (s *reloadStorage) Read(p []byte) (int, error) { return s.reader.Read(p) }
func (s *reloadStorage) Write(p []byte) (int, error) {
	if err := s.c.Save(json.RawMessage(p)); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (b *backend) Connect(ctx context.Context, req map[string]any) (string, error) {
	_ = b.Close()
	var saved json.RawMessage
	hasSession, err := b.c.Load(&saved)
	if err != nil {
		return "", err
	}
	if !hasSession && req["interactive"] != true {
		return "needs_login", nil
	}
	lifetime, stop := context.WithCancel(context.Background())
	b.stop = stop
	bot := newBot(lifetime)
	b.bot = bot
	bot.UUIDCallback = func(uuid string) {
		request, err := http.NewRequestWithContext(lifetime, http.MethodGet, openwechat.GetQrcodeUrl(uuid), nil)
		if err != nil {
			stop()
			return
		}
		client := &http.Client{Timeout: 20 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 || !direct.MediaURL(req.URL.String(), "weixin.qq.com") {
				return errors.New("wechat_qr_redirect_rejected")
			}
			return nil
		}}
		response, err := client.Do(request)
		if err != nil {
			stop()
			return
		}
		defer response.Body.Close()
		data, err := io.ReadAll(io.LimitReader(response.Body, 512*1024+1))
		if err != nil || response.StatusCode != http.StatusOK || len(data) > 512*1024 {
			stop()
			return
		}
		config, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || config.Width > 1024 || config.Height > 1024 {
			stop()
			return
		}
		b.c.Event(map[string]any{"type": "qr", "image": base64.StdEncoding.EncodeToString(data)})
	}
	bot.MessageErrorHandler = func(err error) error { return err }
	bot.LogoutCallBack = func(*openwechat.Bot) {
		if lifetime.Err() == nil {
			b.c.Event(map[string]any{"type": "connection", "state": "disconnected"})
		}
	}
	storage := &reloadStorage{reader: bytes.NewReader(saved), c: b.c}
	bot.SyncCheckCallback = func(openwechat.SyncCheckResponse) {
		if bot.DumpTo(storage) != nil {
			stop()
		}
	}
	bot.MessageHandler = func(message *openwechat.Message) {
		if lifetime.Err() == nil {
			b.receive(bot, message)
		}
	}
	cancelLogin := context.AfterFunc(ctx, stop)
	if hasSession {
		options := []openwechat.BotLoginOption{}
		if req["interactive"] == true {
			options = append(options, openwechat.NewRetryLoginOption())
		}
		err = bot.HotLogin(storage, options...)
	} else {
		err = bot.Login()
	}
	cancelLogin()
	if err != nil {
		stop()
		return "", errors.New("wechat_login_failed")
	}
	b.self, err = bot.GetCurrentUser()
	if err != nil {
		stop()
		return "", errors.New("wechat_login_failed")
	}
	if err := bot.DumpTo(storage); err != nil {
		stop()
		return "", err
	}
	return "connected", nil
}

func (b *backend) Handle(ctx context.Context, req map[string]any) (any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if b.self == nil {
		return nil, errors.New("wechat_not_connected")
	}
	switch direct.Text(req, "op") {
	case "list_chats":
		members, err := b.self.Members()
		if err != nil {
			return nil, errors.New("wechat_contacts_failed")
		}
		chats := []any{}
		for _, user := range members {
			if !user.IsFriend() && !user.IsGroup() {
				continue
			}
			chats = append(chats, chat(user))
		}
		return map[string]any{"chats": chats}, nil
	case "start_conversation", "send_text":
		members, err := b.self.Members()
		if err != nil {
			return nil, errors.New("wechat_contacts_failed")
		}
		target := direct.Text(req, "conversation_id")
		if direct.Text(req, "op") == "start_conversation" {
			target = direct.Text(req, "recipient")
		}
		user, ok := members.GetByUserName(target)
		if !ok {
			return nil, errors.New("wechat_contact_not_found")
		}
		if direct.Text(req, "op") == "start_conversation" {
			result := chat(user)
			b.c.Event(result)
			return result, nil
		}
		message := openwechat.NewTextSendMessage(direct.Text(req, "body"), b.self.UserName, target)
		sent, err := b.bot.Caller.WebWxSendMsg(ctx, &openwechat.CallerWebWxSendMsgOptions{LoginInfo: b.bot.Storage.LoginInfo, BaseRequest: b.bot.Storage.Request, Message: message})
		if err != nil || sent == nil || sent.MsgId == "" {
			return nil, errors.New("wechat_send_unconfirmed")
		}
		return map[string]any{"id": sent.MsgId, "timestamp": time.Now().UnixMilli()}, nil
	case "download_attachment":
		if reference, ok := strings.CutPrefix(direct.Text(req, "id"), "avatar:"); ok {
			username, _, _ := strings.Cut(reference, "#")
			members, err := b.self.Members()
			if err != nil {
				return nil, errors.New("avatar_unavailable")
			}
			user, ok := members.GetByUserName(username)
			if !ok {
				return nil, errors.New("avatar_unavailable")
			}
			response, err := b.bot.Caller.Client.WebWxGetHeadImg(ctx, user)
			if err != nil {
				return nil, errors.New("avatar_unavailable")
			}
			defer response.Body.Close()
			data, err := io.ReadAll(io.LimitReader(response.Body, (2<<20)+1))
			if err != nil || response.StatusCode != http.StatusOK || len(data) > 2<<20 {
				return nil, errors.New("avatar_unavailable")
			}
			return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data)}, nil
		}
		b.mu.Lock()
		message := b.media[direct.Text(req, "id")]
		b.mu.Unlock()
		if message == nil {
			return nil, errors.New("wechat_attachment_unavailable")
		}
		message.WithContext(ctx)
		response, err := message.GetFile()
		if err != nil {
			return nil, errors.New("wechat_download_failed")
		}
		defer response.Body.Close()
		data, err := io.ReadAll(io.LimitReader(response.Body, (32<<20)+1))
		if err != nil || response.StatusCode != http.StatusOK || len(data) > 32<<20 {
			return nil, errors.New("wechat_download_failed")
		}
		return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data)}, nil
	default:
		return nil, errors.New("wechat_operation_unavailable")
	}
}

func chat(user *openwechat.User) map[string]any {
	title := user.RemarkName
	if title == "" {
		title = user.NickName
	}
	if title == "" {
		title = user.UserName
	}
	source := ""
	if user.HeadImgUrl != "" {
		source = "avatar:" + user.UserName + "#" + strings.TrimPrefix(direct.AvatarID(user.HeadImgUrl), "avatar:")
	}
	result := map[string]any{"avatar_source": source, "type": "chat", "id": user.UserName, "title": html.UnescapeString(title), "is_group": user.IsGroup()}
	if !user.IsGroup() {
		result["identity_id"] = user.UserName
	}
	return result
}

func normalize(message *openwechat.Message, ownID string) map[string]any {
	outgoing := message.FromUserName == ownID
	conversation := message.FromUserName
	if outgoing {
		conversation = message.ToUserName
	}
	body := html.UnescapeString(message.Content)
	sender := message.FromUserName
	if strings.HasPrefix(conversation, "@@") && !outgoing {
		if id, text, ok := strings.Cut(body, ":\n"); ok && strings.HasPrefix(id, "@") {
			sender, body = id, text
		}
	}
	kind := "text"
	if !message.IsText() {
		kind, body = "unsupported", "This message type is unavailable in Inbox+."
	}
	return map[string]any{"type": "message", "conversation_id": conversation, "id": message.MsgId, "body": body, "kind": kind, "timestamp": message.CreateTime * 1000, "sender_id": sender, "outgoing": outgoing}
}

func (b *backend) receive(bot *openwechat.Bot, message *openwechat.Message) {
	self, err := bot.GetCurrentUser()
	if err != nil || message.MsgId == "" || message.IsSystem() || message.IsNotify() {
		return
	}
	event := normalize(message, self.UserName)
	if message.IsSendByGroup() && event["outgoing"] != true {
		if sender, err := message.SenderInGroup(); err == nil {
			event["sender_id"], event["sender_name"] = sender.UserName, sender.NickName
		}
	}
	conversation := event["conversation_id"].(string)
	if members, err := self.Members(); err == nil {
		if user, ok := members.GetByUserName(conversation); ok {
			value := chat(user)
			value["timestamp"] = event["timestamp"]
			b.c.Event(value)
		}
		if sender, ok := members.GetByUserName(event["sender_id"].(string)); ok {
			event["sender_name"] = sender.NickName
		}
	}
	if message.HasFile() {
		mime, kind, name := "application/octet-stream", "file", message.FileName
		if message.IsPicture() {
			mime, kind = "image/jpeg", "image"
		}
		if message.IsVoice() {
			mime, kind = "audio/mpeg", "audio"
		}
		if message.IsVideo() {
			mime, kind = "video/mp4", "video"
		}
		if name == "" {
			name = "WeChat attachment"
		}
		b.mu.Lock()
		b.media[message.MsgId] = message
		b.mu.Unlock()
		event["body"], event["kind"] = "", kind
		event["attachments"] = []any{map[string]any{"id": message.MsgId, "name": name, "mime_type": mime}}
	}
	b.c.Event(event)
}

func (b *backend) Close() error {
	if b.stop != nil {
		b.stop()
		b.stop = nil
	}
	b.self = nil
	b.mu.Lock()
	b.media = map[string]*openwechat.Message{}
	b.mu.Unlock()
	return nil
}
