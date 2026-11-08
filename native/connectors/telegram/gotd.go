package telegram

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	gotd "github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/downloader"
	"github.com/gotd/td/telegram/message"
	"github.com/gotd/td/telegram/message/styling"
	"github.com/gotd/td/telegram/updates"
	"github.com/gotd/td/telegram/updates/hook"
	"github.com/gotd/td/telegram/uploader"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

const maxAttachmentBytes = 32 * 1024 * 1024

type attachmentReference struct {
	location tg.InputFileLocationClass
	dc       int
	size     int64
	name     string
	mime     string
}

type gotdBackend struct {
	accountID     string
	client        *gotd.Client
	updates       *updates.Manager
	emit          func(map[string]any)
	authorized    chan int64
	mu            sync.Mutex
	selfID        int64
	peers         map[string]tg.InputPeerClass
	names         map[string]string
	attachments   map[string]attachmentReference
	messageRoutes map[int]map[string]struct{}
}

func newGotdBackend(accountID string, apiID int, apiHash string, storage *sessionStorage, emit func(map[string]any)) *gotdBackend {
	b := &gotdBackend{accountID: accountID, emit: emit, authorized: make(chan int64, 1),
		peers: make(map[string]tg.InputPeerClass), names: make(map[string]string),
		attachments: make(map[string]attachmentReference)}
	b.updates = updates.New(updates.Config{Handler: gotd.UpdateHandlerFunc(b.handleUpdates), MaxChannelDifferenceConcurrency: 2})
	b.client = gotd.NewClient(apiID, apiHash, gotd.Options{
		SessionStorage: storage,
		UpdateHandler:  b.updates,
		Middlewares:    []gotd.Middleware{hook.UpdateHook(b.updates.Handle)},
		Device:         gotd.DeviceConfig{DeviceModel: "Inbox+", SystemVersion: "Inbox+", AppVersion: "1.0.0"},
	})
	return b
}

func (b *gotdBackend) Run(ctx context.Context, ready func(bool, error)) error {
	return b.client.Run(ctx, func(runCtx context.Context) error {
		status, err := b.client.Auth().Status(runCtx)
		if err != nil {
			ready(false, err)
			return err
		}
		var userID int64
		if status.Authorized {
			userID = status.User.ID
			b.remember([]tg.UserClass{status.User}, nil)
			b.mu.Lock()
			b.selfID = userID
			b.mu.Unlock()
			ready(true, nil)
		} else {
			ready(false, nil)
			select {
			case userID = <-b.authorized:
			case <-runCtx.Done():
				return runCtx.Err()
			}
		}
		return b.updates.Run(runCtx, b.client.API(), userID, updates.AuthOptions{})
	})
}

func (b *gotdBackend) SendCode(ctx context.Context, phone string) (string, error) {
	ctx, cancel := requestContext(ctx)
	defer cancel()
	result, err := b.client.Auth().SendCode(ctx, phone, auth.SendCodeOptions{})
	if err != nil {
		return "", err
	}
	if code, ok := result.(*tg.AuthSentCode); ok {
		return code.PhoneCodeHash, nil
	}
	return "", errors.New("telegram_login_method_unsupported")
}

func (b *gotdBackend) SignIn(ctx context.Context, phone, code, hash string) error {
	ctx, cancel := requestContext(ctx)
	defer cancel()
	result, err := b.client.Auth().SignIn(ctx, phone, code, hash)
	if errors.Is(err, auth.ErrPasswordAuthNeeded) {
		return errPasswordNeeded
	}
	if err != nil {
		return err
	}
	return b.acceptAuthorization(result)
}

func (b *gotdBackend) Password(ctx context.Context, password string) error {
	ctx, cancel := requestContext(ctx)
	defer cancel()
	result, err := b.client.Auth().Password(ctx, password)
	if err != nil {
		return err
	}
	return b.acceptAuthorization(result)
}

func (b *gotdBackend) acceptAuthorization(result *tg.AuthAuthorization) error {
	user, ok := result.User.(*tg.User)
	if !ok {
		return errors.New("telegram_authorization_failed")
	}
	b.remember([]tg.UserClass{user}, nil)
	b.mu.Lock()
	b.selfID = user.ID
	b.mu.Unlock()
	select {
	case b.authorized <- user.ID:
	default:
	}
	return nil
}

func (b *gotdBackend) LogOut(ctx context.Context) error {
	ctx, cancel := requestContext(ctx)
	defer cancel()
	_, err := b.client.API().AuthLogOut(ctx)
	return err
}

func (b *gotdBackend) Sync(ctx context.Context) error {
	ctx, cancel := requestContext(ctx)
	defer cancel()
	return b.syncDialogs(ctx, b.client.API().MessagesGetDialogs)
}

func (b *gotdBackend) syncDialogs(ctx context.Context, fetch func(context.Context, *tg.MessagesGetDialogsRequest) (tg.MessagesDialogsClass, error)) error {
	request := &tg.MessagesGetDialogsRequest{OffsetPeer: &tg.InputPeerEmpty{}, Limit: 100}
	previousPeer := ""
	for {
		result, err := fetch(ctx, request)
		if err != nil {
			return err
		}
		dialogs, ok := result.AsModified()
		if !ok {
			return nil
		}
		b.remember(dialogs.GetUsers(), dialogs.GetChats())
		latest := make(map[string]int64)
		dates := make(map[string]int)
		for _, item := range dialogs.GetMessages() {
			if m, ok := item.AsNotEmpty(); ok {
				id := peerKey(m.GetPeerID())
				latest[id] = int64(m.GetDate()) * 1000
				dates[id+":"+strconv.Itoa(m.GetID())] = m.GetDate()
			}
		}
		for _, item := range dialogs.GetDialogs() {
			dialog, ok := item.(*tg.Dialog)
			if !ok {
				continue
			}
			id := peerKey(dialog.Peer)
			if id == "" {
				continue
			}
			b.mu.Lock()
			title := b.names[id]
			b.mu.Unlock()
			if title == "" {
				title = "Telegram conversation"
			}
			chat := map[string]any{"type": "chat", "account_id": b.accountID, "id": id, "title": title,
				"timestamp": latest[id], "unread_count": dialog.UnreadCount, "is_group": !strings.HasPrefix(id, "user:")}
			if strings.HasPrefix(id, "user:") {
				chat["identity_id"] = id
			}
			b.emit(chat)
		}
		for _, item := range dialogs.GetMessages() {
			if m, ok := item.(*tg.Message); ok {
				b.deliver(m, true)
			}
		}

		items := dialogs.GetDialogs()
		if _, complete := result.(*tg.MessagesDialogs); complete || len(items) == 0 {
			return nil
		}
		last, ok := items[len(items)-1].(*tg.Dialog)
		if !ok {
			return errors.New("telegram_dialog_pagination_failed")
		}
		id := peerKey(last.Peer)
		peer, err := b.peer(id)
		if err != nil {
			return err
		}
		date := dates[id+":"+strconv.Itoa(last.TopMessage)]
		if date == 0 || (previousPeer == id && request.OffsetID == last.TopMessage && request.OffsetDate == date) {
			return errors.New("telegram_dialog_pagination_failed")
		}
		previousPeer = id
		request = &tg.MessagesGetDialogsRequest{ExcludePinned: true, OffsetPeer: peer, OffsetID: last.TopMessage, OffsetDate: date, Limit: 100}
	}
}

func (b *gotdBackend) History(ctx context.Context, conversationID string, limit int) error {
	peer, err := b.peer(conversationID)
	if err != nil {
		return err
	}
	ctx, cancel := requestContext(ctx)
	defer cancel()
	result, err := b.client.API().MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{Peer: peer, Limit: limit})
	if err != nil {
		return err
	}
	history, ok := result.AsModified()
	if !ok {
		return nil
	}
	b.remember(history.GetUsers(), history.GetChats())
	items := history.GetMessages()
	for i := len(items) - 1; i >= 0; i-- {
		if m, ok := items[i].(*tg.Message); ok {
			b.deliver(m, true)
		}
	}
	return nil
}

func (b *gotdBackend) Resolve(ctx context.Context, recipient string) (any, error) {
	recipient = strings.TrimSpace(recipient)
	var id string
	if strings.Contains(recipient, ":") {
		if _, err := b.peer(recipient); err != nil {
			return nil, err
		}
		id = recipient
	} else {
		ctx, cancel := requestContext(ctx)
		defer cancel()
		var resolved *tg.ContactsResolvedPeer
		var err error
		if validPhone(recipient) {
			resolved, err = b.client.API().ContactsResolvePhone(ctx, recipient)
		} else {
			username := strings.TrimPrefix(recipient, "@")
			if !validUsername(username) {
				return nil, errors.New("telegram_invalid_recipient")
			}
			resolved, err = b.client.API().ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{Username: username})
		}
		if err != nil {
			return nil, err
		}
		b.remember(resolved.Users, resolved.Chats)
		id = peerKey(resolved.Peer)
		if _, err := b.peer(id); err != nil {
			return nil, err
		}
	}
	b.mu.Lock()
	title := b.names[id]
	b.mu.Unlock()
	if title == "" {
		title = "Telegram conversation"
	}
	chat := map[string]any{"type": "chat", "account_id": b.accountID, "id": id, "title": title,
		"timestamp": time.Now().UnixMilli(), "is_group": !strings.HasPrefix(id, "user:")}
	if strings.HasPrefix(id, "user:") {
		chat["identity_id"] = id
	}
	b.emit(chat)
	return chat, nil
}

func validUsername(username string) bool {
	if len(username) < 1 || len(username) > 32 {
		return false
	}
	for _, r := range username {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_') {
			return false
		}
	}
	return true
}

func (b *gotdBackend) SendText(ctx context.Context, conversationID, body, clientID, replyTo string) (any, error) {
	replyID, err := replyMessageID(conversationID, replyTo)
	if err != nil {
		return nil, err
	}
	peer, err := b.peer(conversationID)
	if err != nil {
		return nil, err
	}
	ctx, cancel := requestContext(ctx)
	defer cancel()
	builder := message.NewSender(b.client.API()).To(peer).RandomID(stableRequestID(b.accountID, conversationID, clientID))
	if replyID != 0 {
		builder.Reply(replyID)
	}
	result, err := builder.Text(ctx, body)
	if err != nil {
		return nil, sendError(err)
	}
	return b.sent(result, conversationID, body), nil
}

func (b *gotdBackend) SendAttachment(ctx context.Context, conversationID string, data []byte, name, mime, caption, clientID, replyTo string) (any, error) {
	replyID, err := replyMessageID(conversationID, replyTo)
	if err != nil {
		return nil, err
	}
	peer, err := b.peer(conversationID)
	if err != nil {
		return nil, err
	}
	if len(data) > maxAttachmentBytes || len(data) == 0 {
		return nil, errors.New("telegram_attachment_size_unsupported")
	}
	ctx, cancel := requestContext(ctx)
	defer cancel()
	name = filepath.Base(name)
	if name == "." || name == "" {
		name = "attachment"
	}
	input, err := uploader.NewUploader(b.client.API()).FromBytes(ctx, name, data)
	if err != nil {
		return nil, err
	}
	if mime == "" {
		mime = "application/octet-stream"
	}
	media := message.UploadedDocument(input, styling.Plain(caption)).Filename(name).MIME(mime)
	builder := message.NewSender(b.client.API()).To(peer).RandomID(stableRequestID(b.accountID, conversationID, clientID))
	if replyID != 0 {
		builder.Reply(replyID)
	}
	result, err := builder.Media(ctx, media)
	if err != nil {
		return nil, sendError(err)
	}
	return b.sent(result, conversationID, caption), nil
}

func stableRequestID(accountID, conversationID, clientID string) int64 {
	if clientID == "" {
		return 0
	}
	hash := sha256.Sum256([]byte(accountID + "\x00" + conversationID + "\x00" + clientID))
	id := int64(binary.LittleEndian.Uint64(hash[:8]))
	if id == 0 {
		return 1
	}
	return id
}

func (b *gotdBackend) React(ctx context.Context, conversationID, messageID, emoji string) (any, error) {
	id, err := replyMessageID(conversationID, messageID)
	if err != nil || id == 0 {
		return nil, errors.New("telegram_invalid_reaction_target")
	}
	peer, err := b.peer(conversationID)
	if err != nil {
		return nil, err
	}
	ctx, cancel := requestContext(ctx)
	defer cancel()
	request := &tg.MessagesSendReactionRequest{Peer: peer, MsgID: id}
	values := []tg.ReactionClass{}
	if emoji != "" {
		values = append(values, &tg.ReactionEmoji{Emoticon: emoji})
	}
	request.SetReaction(values)
	updates, err := b.client.API().MessagesSendReaction(ctx, request)
	if err != nil {
		return nil, err
	}
	if err := b.handleUpdates(ctx, updates); err != nil {
		return nil, err
	}
	current, err := b.client.API().MessagesGetMessagesReactions(ctx, &tg.MessagesGetMessagesReactionsRequest{Peer: peer, ID: []int{id}})
	if err != nil {
		return nil, err
	}
	if err := b.handleUpdates(ctx, current); err != nil {
		return nil, err
	}
	for _, item := range updateItems(current) {
		if reaction, ok := item.(*tg.UpdateMessageReactions); ok && reaction.MsgID == id && peerKey(reaction.Peer) == conversationID {
			result := reactionEvent(b.accountID, conversationID, id, &reaction.Reactions)
			result["applied"] = true
			return result, nil
		}
	}
	return nil, errors.New("telegram_reaction_unconfirmed")
}

func (b *gotdBackend) Download(ctx context.Context, attachmentID string) (any, error) {
	b.mu.Lock()
	reference, ok := b.attachments[attachmentID]
	b.mu.Unlock()
	if !ok {
		return nil, errors.New("telegram_attachment_unavailable")
	}
	if reference.size <= 0 || reference.size > maxAttachmentBytes {
		return nil, errors.New("telegram_attachment_size_unsupported")
	}
	ctx, cancel := requestContext(ctx)
	defer cancel()
	pool, err := b.client.DC(ctx, reference.dc, 1)
	if err != nil {
		return nil, err
	}
	defer pool.Close()
	output := limitedBuffer{limit: maxAttachmentBytes}
	if _, err := downloader.NewDownloader().Download(tg.NewClient(pool), reference.location).Stream(ctx, &output); err != nil {
		return nil, err
	}
	return map[string]any{"id": attachmentID, "bytes": base64.StdEncoding.EncodeToString(output.Bytes()), "name": reference.name, "mime_type": reference.mime}, nil
}

type limitedBuffer struct {
	bytes.Buffer
	limit int
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if len(p) > b.limit-b.Len() {
		return 0, errors.New("telegram_attachment_size_unsupported")
	}
	return b.Buffer.Write(p)
}

func (b *gotdBackend) peer(id string) (tg.InputPeerClass, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	peer, ok := b.peers[id]
	if !ok {
		return nil, errors.New("telegram_conversation_unavailable")
	}
	return peer, nil
}

func (b *gotdBackend) remember(users []tg.UserClass, chats []tg.ChatClass) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, item := range users {
		user, ok := item.(*tg.User)
		if !ok {
			continue
		}
		id := "user:" + strconv.FormatInt(user.ID, 10)
		b.names[id] = strings.TrimSpace(user.FirstName + " " + user.LastName)
		if user.Self {
			b.peers[id] = &tg.InputPeerSelf{}
		} else if !user.Min && user.AccessHash != 0 {
			b.peers[id] = &tg.InputPeerUser{UserID: user.ID, AccessHash: user.AccessHash}
		}
	}
	for _, item := range chats {
		switch chat := item.(type) {
		case *tg.Chat:
			id := "chat:" + strconv.FormatInt(chat.ID, 10)
			b.peers[id], b.names[id] = &tg.InputPeerChat{ChatID: chat.ID}, chat.Title
		case *tg.Channel:
			id := "channel:" + strconv.FormatInt(chat.ID, 10)
			b.names[id] = chat.Title
			if !chat.Min && chat.AccessHash != 0 {
				b.peers[id] = &tg.InputPeerChannel{ChannelID: chat.ID, AccessHash: chat.AccessHash}
			}
		}
	}
}

func (b *gotdBackend) handleUpdates(ctx context.Context, update tg.UpdatesClass) error {
	items := updateItems(update)
	switch value := update.(type) {
	case *tg.Updates:
		b.remember(value.Users, value.Chats)
	case *tg.UpdatesCombined:
		b.remember(value.Users, value.Chats)
	case *tg.UpdateShortMessage:
		b.mu.Lock()
		selfID := b.selfID
		b.mu.Unlock()
		sender := value.UserID
		if value.Out {
			sender = selfID
		}
		b.deliver(&tg.Message{ID: value.ID, Out: value.Out, PeerID: &tg.PeerUser{UserID: value.UserID},
			FromID: &tg.PeerUser{UserID: sender}, Date: value.Date, Message: value.Message}, false)
	case *tg.UpdateShortChatMessage:
		b.deliver(&tg.Message{ID: value.ID, Out: value.Out, PeerID: &tg.PeerChat{ChatID: value.ChatID},
			FromID: &tg.PeerUser{UserID: value.FromID}, Date: value.Date, Message: value.Message}, false)
	}
	for _, item := range items {
		switch value := item.(type) {
		case *tg.UpdateMessageReactions:
			b.emit(reactionEvent(b.accountID, peerKey(value.Peer), value.MsgID, &value.Reactions))
		case *tg.UpdateNewMessage:
			if m, ok := value.Message.(*tg.Message); ok {
				b.deliver(m, false)
			}
		case *tg.UpdateNewChannelMessage:
			if m, ok := value.Message.(*tg.Message); ok {
				b.deliver(m, false)
			}
		case *tg.UpdateEditMessage:
			if m, ok := value.Message.(*tg.Message); ok {
				b.deliver(m, false)
			}
		case *tg.UpdateEditChannelMessage:
			if m, ok := value.Message.(*tg.Message); ok {
				b.deliver(m, false)
			}
		case *tg.UpdateDeleteMessages:
			for _, id := range value.Messages {
				b.deleteKnownMessage(id)
			}
		case *tg.UpdateDeleteChannelMessages:
			for _, id := range value.Messages {
				b.deleteMessage("channel:"+strconv.FormatInt(value.ChannelID, 10), id)
			}
		}
	}
	return nil
}

func updateItems(update tg.UpdatesClass) []tg.UpdateClass {
	switch value := update.(type) {
	case *tg.Updates:
		return value.Updates
	case *tg.UpdatesCombined:
		return value.Updates
	case *tg.UpdateShort:
		return []tg.UpdateClass{value.Update}
	default:
		return nil
	}
}

func (b *gotdBackend) deliver(m *tg.Message, historical bool) {
	b.mu.Lock()
	conversationID := peerKey(m.PeerID)
	if conversationID != "" && !strings.HasPrefix(conversationID, "channel:") {
		if b.messageRoutes == nil {
			b.messageRoutes = make(map[int]map[string]struct{})
		}
		if b.messageRoutes[m.ID] == nil {
			b.messageRoutes[m.ID] = make(map[string]struct{})
		}
		b.messageRoutes[m.ID][conversationID] = struct{}{}
	}
	if m.FromID == nil && m.Out {
		m.FromID = &tg.PeerUser{UserID: b.selfID}
	}
	name := b.names[peerKey(m.FromID)]
	b.mu.Unlock()
	event := normalizeMessage(b.accountID, m, name)
	event["historical"] = historical
	if location, size, ok := mediaLocation(m.Media); ok {
		attachments, _ := event["attachments"].([]map[string]any)
		if len(attachments) > 0 {
			item := attachments[0]
			name, _ := item["name"].(string)
			mime, _ := item["mime_type"].(string)
			id, _ := item["id"].(string)
			b.mu.Lock()
			b.attachments[id] = attachmentReference{location: location, dc: mediaDCID(m.Media), size: size, name: name, mime: mime}
			b.mu.Unlock()
		}
	}
	b.emit(event)
}

func (b *gotdBackend) deleteKnownMessage(id int) {
	b.mu.Lock()
	routes := b.messageRoutes[id]
	var conversationID string
	if len(routes) == 1 {
		for route := range routes {
			conversationID = route
		}
		delete(b.messageRoutes, id)
	}
	b.mu.Unlock()
	if conversationID != "" {
		b.deleteMessage(conversationID, id)
	}
}

func (b *gotdBackend) deleteMessage(conversationID string, id int) {
	messageID := conversationID + ":" + strconv.Itoa(id)
	b.mu.Lock()
	delete(b.attachments, messageID)
	b.mu.Unlock()
	b.emit(map[string]any{"type": "message_delete", "account_id": b.accountID,
		"conversation_id": conversationID, "id": messageID})
}

func (b *gotdBackend) sent(result tg.UpdatesClass, conversationID, body string) any {
	if short, ok := result.(*tg.UpdateShortSentMessage); ok {
		b.mu.Lock()
		selfID := b.selfID
		b.mu.Unlock()
		id := conversationID + ":" + strconv.Itoa(short.ID)
		var peer tg.PeerClass
		kind, number, _ := strings.Cut(conversationID, ":")
		peerID, _ := strconv.ParseInt(number, 10, 64)
		switch kind {
		case "user":
			peer = &tg.PeerUser{UserID: peerID}
		case "chat":
			peer = &tg.PeerChat{ChatID: peerID}
		case "channel":
			peer = &tg.PeerChannel{ChannelID: peerID}
		}
		b.deliver(&tg.Message{ID: short.ID, PeerID: peer, FromID: &tg.PeerUser{UserID: selfID}, Out: true,
			Date: short.Date, Message: body, Media: short.Media}, false)
		return map[string]any{"id": id, "timestamp": int64(short.Date) * 1000}
	}
	var items []tg.UpdateClass
	var timestamp int64
	switch result := result.(type) {
	case *tg.Updates:
		items = result.Updates
		timestamp = int64(result.Date) * 1000
	case *tg.UpdatesCombined:
		items = result.Updates
		timestamp = int64(result.Date) * 1000
	case *tg.UpdateShort:
		items = []tg.UpdateClass{result.Update}
		timestamp = int64(result.Date) * 1000
	}
	for _, item := range items {
		switch item := item.(type) {
		case *tg.UpdateMessageID:
			return map[string]any{"id": conversationID + ":" + strconv.Itoa(item.ID), "timestamp": timestamp}
		case *tg.UpdateNewMessage:
			if m, ok := item.Message.(*tg.Message); ok {
				return map[string]any{"id": peerKey(m.PeerID) + ":" + strconv.Itoa(m.ID), "timestamp": int64(m.Date) * 1000}
			}
		case *tg.UpdateNewChannelMessage:
			if m, ok := item.Message.(*tg.Message); ok {
				return map[string]any{"id": peerKey(m.PeerID) + ":" + strconv.Itoa(m.ID), "timestamp": int64(m.Date) * 1000}
			}
		}
	}
	return map[string]any{"accepted": true}
}

func sanitizeError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, errPasswordNeeded) {
		return errPasswordNeeded
	}
	if errors.Is(err, errSendOutcomeUnknown) {
		return errSendOutcomeUnknown
	}
	if errors.Is(err, auth.ErrPasswordInvalid) {
		return errors.New("telegram_invalid_password")
	}
	var signup *auth.SignUpRequired
	if errors.As(err, &signup) {
		return errors.New("telegram_signup_required")
	}
	for _, code := range []string{"PHONE_NUMBER_INVALID", "PHONE_CODE_INVALID", "PHONE_CODE_EXPIRED", "API_ID_INVALID", "API_ID_PUBLISHED_FLOOD", "AUTH_KEY_UNREGISTERED", "SESSION_REVOKED", "SESSION_EXPIRED", "PHONE_NUMBER_BANNED"} {
		if tgerr.Is(err, code) {
			return errors.New("telegram_" + strings.ToLower(code))
		}
	}
	if _, ok := tgerr.AsFloodWait(err); ok {
		return errors.New("telegram_rate_limited")
	}
	if errors.Is(err, context.Canceled) {
		return errors.New("telegram_request_cancelled")
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return errors.New("telegram_request_timed_out")
	}
	switch err.Error() {
	case "telegram_login_method_unsupported", "telegram_authorization_failed", "telegram_attachment_unavailable",
		"telegram_attachment_size_unsupported", "telegram_conversation_unavailable", "telegram_invalid_recipient":
		return err
	}
	return errors.New("telegram_request_failed")
}

func sendError(err error) error {
	if rpc, ok := tgerr.As(err); ok && rpc.Code < 500 {
		return sanitizeError(err)
	}
	return errSendOutcomeUnknown
}
