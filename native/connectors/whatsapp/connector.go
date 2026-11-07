package whatsapp

import (
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/securedb"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

const maxAttachmentBytes = 32 * 1024 * 1024

var (
	ErrInvalidPhone    = errors.New("invalid WhatsApp phone number")
	ErrPairingNotReady = errors.New("WhatsApp pairing is not ready")
	ErrPairingExpired  = errors.New("WhatsApp pairing expired")
	ErrPhonePairing    = errors.New("WhatsApp phone pairing failed")
)

type Connector struct {
	accountID        string
	db               *sql.DB
	client           *whatsmeow.Client
	emit             func(map[string]any)
	mu               sync.Mutex
	cancelQR         context.CancelFunc
	cancelConnection context.CancelFunc
	closedSignal     chan struct{}
	closed           bool
	hasSession       bool
	pairingReady     <-chan struct{}
	pairingExpiresAt time.Time
	pairPhone        func(context.Context, string, bool, whatsmeow.PairClientType, string) (string, error)
}

func New(accountID, directory string, key []byte, emit func(map[string]any)) (*Connector, error) {
	storageFailure := make(chan struct{}, 1)
	db, err := securedb.OpenWithFailure(directory, key, func() {
		select {
		case storageFailure <- struct{}{}:
		default:
		}
	})
	if err != nil {
		return nil, errors.New("Cannot unlock the WhatsApp session")
	}
	container := sqlstore.NewWithDB(db, "sqlite3", waLog.Noop)
	if err = container.Upgrade(context.Background()); err != nil {
		db.Close()
		return nil, errors.New("Cannot open the WhatsApp session")
	}
	if _, err = db.Exec("CREATE TABLE IF NOT EXISTS inboxplus_media (id TEXT PRIMARY KEY, message BLOB NOT NULL)"); err != nil {
		db.Close()
		return nil, errors.New("Cannot initialize attachment storage")
	}
	if _, err = db.Exec("CREATE TABLE IF NOT EXISTS inboxplus_chats (id TEXT PRIMARY KEY, title TEXT NOT NULL, timestamp INTEGER NOT NULL, unread_count INTEGER NOT NULL, is_group INTEGER NOT NULL)"); err != nil {
		db.Close()
		return nil, errors.New("Cannot initialize conversation storage")
	}
	device, err := container.GetFirstDevice(context.Background())
	if err != nil {
		db.Close()
		return nil, errors.New("Cannot read the WhatsApp session")
	}
	c := &Connector{accountID: accountID, db: db, emit: emit, closedSignal: make(chan struct{}), hasSession: device.ID != nil}
	c.client = whatsmeow.NewClient(device, waLog.Noop)
	c.pairPhone = c.client.PairPhone
	c.client.EnableAutoReconnect = true
	c.client.AddEventHandler(c.handleEvent)
	go func() {
		select {
		case <-storageFailure:
			c.client.Disconnect()
			c.mu.Lock()
			c.disconnect()
			c.mu.Unlock()
			c.event(map[string]any{"type": "error", "code": "storage_failed", "message": "WhatsApp was disconnected because its session changes could not be saved securely"})
		case <-c.closedSignal:
		}
	}()
	return c, nil
}

func (c *Connector) Handle(ctx context.Context, req map[string]any) (any, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil, errors.New("The WhatsApp session is closed")
	}
	op := text(req, "op")
	if op != "disconnect" && op != "capabilities" && c.db.PingContext(ctx) != nil {
		return nil, errors.New("Reopen WhatsApp before reconnecting after a storage failure")
	}
	switch op {
	case "capabilities":
		return Capabilities(), nil
	case "connect":
		if c.client.IsConnected() {
			return map[string]any{"connected": true}, nil
		}
		if c.client.Store.ID == nil {
			qrCtx, cancel := context.WithCancel(context.Background())
			if c.cancelQR != nil {
				c.cancelQR()
			}
			c.cancelQR = cancel
			ready := make(chan struct{})
			c.pairingReady = ready
			// The SDK closes the pairing socket after its 160-second QR sequence.
			c.pairingExpiresAt = time.Now().Add(160 * time.Second)
			channel, err := c.client.GetQRChannel(qrCtx)
			if err != nil {
				cancel()
				return nil, errors.New("Cannot begin WhatsApp pairing")
			}
			go func() {
				var firstCode sync.Once
				for item := range channel {
					if item.Event == "code" {
						firstCode.Do(func() { close(ready) })
						c.event(map[string]any{"type": "qr", "code": item.Code, "expires_in": int(item.Timeout.Seconds())})
					} else {
						c.event(map[string]any{"type": "login", "state": item.Event})
					}
				}
			}()
		}
		c.event(map[string]any{"type": "connection", "state": "connecting"})
		connectionCtx, cancelConnection := context.WithCancel(context.Background())
		stopCancellation := context.AfterFunc(ctx, cancelConnection)
		err := c.client.ConnectContext(connectionCtx)
		stopCancellation()
		if err != nil {
			cancelConnection()
			if c.cancelQR != nil {
				c.cancelQR()
			}
			return nil, errors.New("WhatsApp could not connect")
		}
		c.cancelConnection = cancelConnection
		return map[string]any{"started": true}, nil
	case "pair_phone":
		phone, err := pairingPhone(text(req, "phone"))
		if err != nil {
			return nil, err
		}
		if c.client.IsLoggedIn() {
			return map[string]any{"state": "connected"}, nil
		}
		if !c.pairingExpiresAt.IsZero() && !time.Now().Before(c.pairingExpiresAt) {
			return nil, ErrPairingExpired
		}
		select {
		case <-c.pairingReady:
		default:
			return nil, ErrPairingNotReady
		}
		code, err := c.pairPhone(ctx, phone, true, whatsmeow.PairClientChrome, "Chrome (Linux)")
		if err != nil {
			return nil, ErrPhonePairing
		}
		return map[string]any{"code": code, "expires_at": c.pairingExpiresAt.UnixMilli()}, nil
	case "start_conversation":
		phone := strings.TrimPrefix(text(req, "recipient"), "+")
		if !validPhone(phone) {
			return nil, errors.New("Enter a phone number with its country code")
		}
		if !c.client.IsLoggedIn() {
			return nil, errors.New("Connect WhatsApp before opening a conversation")
		}
		users, err := c.client.IsOnWhatsApp(ctx, []string{phone})
		if err != nil || len(users) != 1 || !users[0].IsIn {
			return nil, errors.New("This WhatsApp recipient could not be found")
		}
		chat := map[string]any{"id": users[0].JID.String(), "title": "+" + phone, "is_group": false, "timestamp": time.Now().UnixMilli()}
		chat["identity_id"] = users[0].JID.String()
		if err := c.recordChat(users[0].JID, "+"+phone, chat["timestamp"].(int64), -1); err != nil {
			return nil, err
		}
		c.event(map[string]any{"type": "chat", "id": users[0].JID.String(), "identity_id": users[0].JID.String(), "title": "+" + phone, "is_group": false, "timestamp": chat["timestamp"]})
		return chat, nil
	case "send_text":
		body := text(req, "body")
		if strings.TrimSpace(body) == "" {
			return nil, errors.New("A message cannot be empty")
		}
		return c.send(ctx, req, &waE2E.Message{Conversation: proto.String(body)})
	case "send_attachment":
		return c.sendAttachment(ctx, req)
	case "react":
		chat, err := conversationJID(req)
		if err != nil {
			return nil, err
		}
		if !c.client.IsLoggedIn() || c.client.Store.ID == nil {
			return nil, errors.New("Connect WhatsApp before reacting")
		}
		id, emoji := text(req, "message_id"), text(req, "emoji")
		if id == "" || len(id) > 128 || strings.ContainsAny(id, " \t\r\n") || len(emoji) > 256 {
			return nil, errors.New("The reaction target is invalid")
		}
		sender, err := types.ParseJID(text(req, "message_sender_id"))
		if req["message_outgoing"] == true {
			sender, err = c.client.Store.ID.ToNonAD(), nil
		}
		if err != nil || sender.User == "" || (sender.Server != types.DefaultUserServer && sender.Server != types.HiddenUserServer) {
			return nil, errors.New("The original message sender is unavailable")
		}
		message := c.client.BuildReaction(chat, sender, id, emoji)
		if _, err := c.client.SendMessage(ctx, chat, message); err != nil {
			return nil, errors.New("WhatsApp did not confirm the reaction")
		}
		return map[string]any{"applied": true, "type": "reaction", "account_id": c.accountID, "conversation_id": chat.String(), "id": id,
			"sender_id": c.client.Store.ID.ToNonAD().String(), "outgoing": true, "emoji": emoji, "timestamp": message.GetReactionMessage().GetSenderTimestampMS()}, nil
	case "download_attachment":
		var encoded []byte
		if err := c.db.QueryRowContext(ctx, "SELECT message FROM inboxplus_media WHERE id=?", text(req, "id")).Scan(&encoded); err != nil {
			return nil, errors.New("The attachment is not available locally")
		}
		message := &waE2E.Message{}
		if proto.Unmarshal(encoded, message) != nil {
			return nil, errors.New("The attachment record is invalid")
		}
		if mediaInfo(message).size > maxAttachmentBytes {
			return nil, errors.New("The attachment exceeds the 32 MiB download limit")
		}
		data, err := c.client.DownloadAny(ctx, message)
		if err != nil {
			return nil, errors.New("The attachment could not be downloaded")
		}
		if len(data) > maxAttachmentBytes {
			return nil, errors.New("The attachment exceeds the 32 MiB download limit")
		}
		return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data)}, nil
	case "list_chats":
		return c.listChats(ctx)
	case "disconnect":
		c.disconnect()
		return map[string]any{"disconnected": true}, nil
	case "logout":
		if err := c.client.Logout(ctx); err != nil {
			return nil, errors.New("WhatsApp could not unlink this device")
		}
		c.disconnect()
		c.event(map[string]any{"type": "connection", "state": "logged_out"})
		return map[string]any{"logged_out": true, "remote_session_revoked": true}, nil
	default:
		return nil, errors.New("This operation is unavailable for WhatsApp")
	}
}

func Capabilities() map[string]any {
	return map[string]any{"platform": "whatsapp", "qr_login": true, "phone_pairing": true, "send_text": true, "send_attachment": true, "download_attachment": true, "history_sync": true, "start_conversation": true, "replies": true, "reactions": true, "audio_attachment_captions": false, "max_attachment_bytes": maxAttachmentBytes}
}

func (c *Connector) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return nil
	}
	c.closed = true
	close(c.closedSignal)
	c.disconnect()
	c.client.RemoveEventHandlers()
	var devices int
	if err := c.db.QueryRow("SELECT COUNT(*) FROM whatsmeow_device").Scan(&devices); err != nil {
		c.hasSession = true
	} else {
		c.hasSession = devices > 0
	}
	return c.db.Close()
}

func (c *Connector) HasSession() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.hasSession
}

func (c *Connector) disconnect() {
	c.pairingReady = nil
	c.pairingExpiresAt = time.Time{}
	if c.cancelConnection != nil {
		c.cancelConnection()
		c.cancelConnection = nil
	}
	if c.cancelQR != nil {
		c.cancelQR()
		c.cancelQR = nil
	}
	c.client.Disconnect()
	c.event(map[string]any{"type": "connection", "state": "disconnected"})
}

func (c *Connector) send(ctx context.Context, req map[string]any, message *waE2E.Message) (any, error) {
	jid, err := conversationJID(req)
	if err != nil {
		return nil, err
	}
	if !c.client.IsLoggedIn() {
		return nil, errors.New("Connect WhatsApp before sending a message")
	}
	if err := applyReply(message, req, c.client.Store.ID); err != nil {
		return nil, err
	}
	extra := whatsmeow.SendRequestExtra{}
	if id := text(req, "id"); id != "" {
		if len(id) > 128 || strings.ContainsAny(id, " \t\r\n") {
			return nil, errors.New("The outgoing message identifier is invalid")
		}
		extra.ID = id
	}
	response, err := c.client.SendMessage(ctx, jid, message, extra)
	if err != nil {
		return nil, errors.New("WhatsApp could not send the message; check its delivery before retrying")
	}
	info := types.MessageInfo{MessageSource: types.MessageSource{Chat: jid, IsFromMe: true}, ID: response.ID, Timestamp: response.Timestamp}
	if c.client.Store.ID != nil {
		info.Sender = *c.client.Store.ID
	}
	c.message(&events.Message{Info: info, Message: message})
	return map[string]any{"id": response.ID, "timestamp": response.Timestamp.UnixMilli()}, nil
}

func (c *Connector) sendAttachment(ctx context.Context, req map[string]any) (any, error) {
	if !c.client.IsLoggedIn() {
		return nil, errors.New("Connect WhatsApp before sending an attachment")
	}
	if _, err := conversationJID(req); err != nil {
		return nil, err
	}
	encoded := text(req, "bytes")
	if len(encoded) > base64.StdEncoding.EncodedLen(maxAttachmentBytes) {
		return nil, errors.New("The attachment exceeds the 32 MiB upload limit")
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > maxAttachmentBytes {
		return nil, errors.New("The attachment data is invalid")
	}
	mimeType, name, caption := text(req, "mime_type"), text(req, "name"), text(req, "body")
	if strings.HasPrefix(mimeType, "audio/") && strings.TrimSpace(caption) != "" {
		return nil, errors.New("Send the text separately from a WhatsApp audio attachment")
	}
	mediaType := whatsmeow.MediaDocument
	if strings.HasPrefix(mimeType, "image/") {
		mediaType = whatsmeow.MediaImage
	} else if strings.HasPrefix(mimeType, "video/") {
		mediaType = whatsmeow.MediaVideo
	} else if strings.HasPrefix(mimeType, "audio/") {
		mediaType = whatsmeow.MediaAudio
	}
	upload, err := c.client.Upload(ctx, data, mediaType)
	if err != nil {
		return nil, errors.New("WhatsApp could not upload the attachment")
	}
	message := &waE2E.Message{}
	switch mediaType {
	case whatsmeow.MediaImage:
		message.ImageMessage = &waE2E.ImageMessage{URL: &upload.URL, DirectPath: &upload.DirectPath, MediaKey: upload.MediaKey, FileEncSHA256: upload.FileEncSHA256, FileSHA256: upload.FileSHA256, FileLength: proto.Uint64(uint64(len(data))), Mimetype: &mimeType, Caption: &caption}
	case whatsmeow.MediaVideo:
		message.VideoMessage = &waE2E.VideoMessage{URL: &upload.URL, DirectPath: &upload.DirectPath, MediaKey: upload.MediaKey, FileEncSHA256: upload.FileEncSHA256, FileSHA256: upload.FileSHA256, FileLength: proto.Uint64(uint64(len(data))), Mimetype: &mimeType, Caption: &caption}
	case whatsmeow.MediaAudio:
		message.AudioMessage = &waE2E.AudioMessage{URL: &upload.URL, DirectPath: &upload.DirectPath, MediaKey: upload.MediaKey, FileEncSHA256: upload.FileEncSHA256, FileSHA256: upload.FileSHA256, FileLength: proto.Uint64(uint64(len(data))), Mimetype: &mimeType}
	default:
		message.DocumentMessage = &waE2E.DocumentMessage{URL: &upload.URL, DirectPath: &upload.DirectPath, MediaKey: upload.MediaKey, FileEncSHA256: upload.FileEncSHA256, FileSHA256: upload.FileSHA256, FileLength: proto.Uint64(uint64(len(data))), Mimetype: &mimeType, FileName: &name, Caption: &caption}
	}
	return c.send(ctx, req, message)
}

func (c *Connector) listChats(ctx context.Context) (any, error) {
	contacts := map[types.JID]types.ContactInfo{}
	if c.client.Store.Contacts != nil {
		var err error
		contacts, err = c.client.Store.Contacts.GetAllContacts(ctx)
		if err != nil {
			return nil, errors.New("WhatsApp contacts could not be read")
		}
	}
	rows, err := c.db.QueryContext(ctx, "SELECT id,title,timestamp,unread_count,is_group FROM inboxplus_chats ORDER BY timestamp DESC")
	if err != nil {
		return nil, errors.New("WhatsApp conversations could not be read")
	}
	defer rows.Close()
	chats := []map[string]any{}
	for rows.Next() {
		var id, title string
		var timestamp int64
		var unread int
		var group bool
		if rows.Scan(&id, &title, &timestamp, &unread, &group) != nil {
			return nil, errors.New("WhatsApp conversations could not be read")
		}
		jid, _ := types.ParseJID(id)
		if !group {
			contact := contacts[jid]
			if contact.FullName != "" {
				title = contact.FullName
			} else if contact.PushName != "" {
				title = contact.PushName
			}
		}
		if title == "" {
			title = jid.User
		}
		chat := map[string]any{"id": id, "title": title, "timestamp": timestamp, "unread_count": unread, "is_group": group}
		if !group {
			chat["identity_id"] = id
		}
		chats = append(chats, chat)
	}
	if rows.Err() != nil {
		return nil, errors.New("WhatsApp conversations could not be read")
	}
	return map[string]any{"chats": chats}, nil
}

func (c *Connector) recordChat(jid types.JID, title string, timestamp int64, unread int) error {
	initialUnread := unread
	if initialUnread < 0 {
		initialUnread = 0
	}
	_, err := c.db.Exec("INSERT INTO inboxplus_chats(id,title,timestamp,unread_count,is_group) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=CASE WHEN excluded.title<>'' THEN excluded.title ELSE inboxplus_chats.title END,timestamp=MAX(inboxplus_chats.timestamp,excluded.timestamp),unread_count=CASE WHEN ?<0 THEN inboxplus_chats.unread_count ELSE excluded.unread_count END,is_group=excluded.is_group", jid.String(), title, timestamp, initialUnread, jid.Server == types.GroupServer, unread)
	if err != nil {
		return errors.New("The WhatsApp conversation could not be stored securely")
	}
	return nil
}

func (c *Connector) handleEvent(raw any) {
	switch event := raw.(type) {
	case *events.Connected:
		c.event(map[string]any{"type": "connection", "state": "connected"})
	case *events.Disconnected:
		c.event(map[string]any{"type": "connection", "state": "disconnected"})
	case *events.LoggedOut:
		c.event(map[string]any{"type": "connection", "state": "logged_out"})
	case *events.ConnectFailure, *events.StreamError:
		c.event(map[string]any{"type": "connection", "state": "error", "message": "WhatsApp connection failed"})
	case *events.Message:
		c.message(event)
	case *events.HistorySync:
		for _, conversation := range event.Data.GetConversations() {
			jid, err := types.ParseJID(conversation.GetID())
			if err != nil {
				continue
			}
			if err := c.recordChat(jid, conversation.GetName(), int64(conversation.GetConversationTimestamp())*1000, int(conversation.GetUnreadCount())); err != nil {
				c.event(map[string]any{"type": "error", "code": "storage_failed"})
				return
			}
			chat := map[string]any{"type": "chat", "id": jid.String(), "title": conversation.GetName(), "timestamp": int64(conversation.GetConversationTimestamp()) * 1000, "unread_count": conversation.GetUnreadCount(), "is_group": jid.Server == types.GroupServer}
			if jid.Server != types.GroupServer {
				chat["identity_id"] = jid.String()
			}
			c.event(chat)
			for _, item := range conversation.GetMessages() {
				message, parseErr := c.client.ParseWebMessage(jid, item.GetMessage())
				if parseErr == nil {
					c.emitMessage(message, true)
				}
			}
		}
		c.event(map[string]any{"type": "history_sync", "complete": true})
	case *events.Receipt:
		c.event(map[string]any{"type": "receipt", "conversation_id": event.Chat.String(), "ids": event.MessageIDs, "state": string(event.Type), "timestamp": event.Timestamp.UnixMilli()})
	}
}

func (c *Connector) message(event *events.Message) {
	c.emitMessage(event, false)
}

func (c *Connector) emitMessage(event *events.Message, historical bool) {
	message := event.Message
	if message == nil {
		return
	}
	reaction := message.GetReactionMessage()
	if message.GetEncReactionMessage() != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		decrypted, err := c.client.DecryptReaction(ctx, event)
		cancel()
		if err != nil {
			c.event(map[string]any{"type": "error", "code": "reaction_unavailable"})
			return
		}
		reaction = decrypted
	}
	if reaction != nil {
		key := reaction.GetKey()
		if key.GetID() == "" || event.Info.Sender.User == "" {
			return
		}
		if remote := key.GetRemoteJID(); remote != "" && remote != event.Info.Chat.ToNonAD().String() {
			return
		}
		timestamp := reaction.GetSenderTimestampMS()
		if timestamp == 0 {
			timestamp = event.Info.Timestamp.UnixMilli()
		}
		sender := event.Info.Sender.ToNonAD()
		if event.Info.IsFromMe && c.client.Store.ID != nil {
			sender = c.client.Store.ID.ToNonAD()
		}
		c.event(map[string]any{"type": "reaction", "conversation_id": event.Info.Chat.String(), "id": key.GetID(),
			"sender_id": sender.String(), "outgoing": event.Info.IsFromMe, "emoji": reaction.GetText(), "timestamp": timestamp})
		return
	}
	if protocol := message.GetProtocolMessage(); protocol != nil && protocol.GetType() == waE2E.ProtocolMessage_REVOKE {
		key := protocol.GetKey()
		if key.GetID() == "" {
			return
		}
		chat := event.Info.Chat.ToNonAD()
		if key.GetRemoteJID() != "" {
			target, err := types.ParseJID(key.GetRemoteJID())
			if err != nil || target.ToNonAD() != chat {
				return
			}
		}
		if _, err := c.db.Exec("DELETE FROM inboxplus_media WHERE id=?", event.Info.Chat.String()+"/"+key.GetID()); err != nil {
			c.event(map[string]any{"type": "error", "code": "storage_failed"})
			return
		}
		c.event(map[string]any{"type": "message_delete", "conversation_id": event.Info.Chat.String(), "id": key.GetID()})
		return
	}
	if err := c.recordChat(event.Info.Chat, "", event.Info.Timestamp.UnixMilli(), -1); err != nil {
		c.event(map[string]any{"type": "error", "code": "storage_failed"})
		return
	}
	body := message.GetConversation()
	if body == "" {
		body = message.GetExtendedTextMessage().GetText()
	}
	media := mediaInfo(message)
	if media.caption != "" {
		body = media.caption
	}
	kind := "text"
	attachments := []map[string]any{}
	if media.kind != "" {
		kind = media.kind
		id := event.Info.Chat.String() + "/" + event.Info.ID
		encoded, err := proto.Marshal(message)
		if err == nil {
			_, err = c.db.Exec("INSERT INTO inboxplus_media(id,message) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET message=excluded.message", id, encoded)
		}
		if err != nil {
			c.event(map[string]any{"type": "error", "message": "The attachment could not be stored securely"})
			return
		}
		attachments = append(attachments, map[string]any{"id": id, "name": media.name, "mime_type": media.mime, "size": media.size})
	}
	if body == "" && len(attachments) == 0 {
		kind = "unsupported"
		body = "Unsupported WhatsApp message"
	}
	normalized := map[string]any{"type": "message", "conversation_id": event.Info.Chat.String(), "id": event.Info.ID, "body": body, "timestamp": event.Info.Timestamp.UnixMilli(), "outgoing": event.Info.IsFromMe, "sender_id": event.Info.Sender.String(), "sender_name": event.Info.PushName, "kind": kind, "attachments": attachments, "historical": historical}
	if context := messageContext(message); context != nil && context.GetStanzaID() != "" {
		if remote := context.GetRemoteJID(); remote == "" || remote == event.Info.Chat.ToNonAD().String() {
			normalized["reply_to_message_id"] = context.GetStanzaID()
		}
	}
	normalized["is_group"] = event.Info.Chat.Server == types.GroupServer
	if event.Info.Chat.Server != types.GroupServer {
		normalized["identity_id"] = event.Info.Chat.String()
	}
	c.event(normalized)
}

func (c *Connector) event(event map[string]any) {
	event["account_id"] = c.accountID
	c.emit(event)
}

func applyReply(message *waE2E.Message, req map[string]any, own *types.JID) error {
	id := text(req, "reply_to_message_id")
	if id == "" {
		return nil
	}
	if len(id) > 128 || strings.ContainsAny(id, " \t\r\n") {
		return errors.New("The reply message identifier is invalid")
	}
	sender, err := types.ParseJID(text(req, "reply_to_sender_id"))
	if req["reply_to_outgoing"] == true && own != nil {
		sender, err = own.ToNonAD(), nil
	}
	if err != nil || sender.User == "" || (sender.Server != types.DefaultUserServer && sender.Server != types.HiddenUserServer) {
		return errors.New("The original message sender is unavailable for this reply")
	}
	context := &waE2E.ContextInfo{
		StanzaID: proto.String(id), Participant: proto.String(sender.ToNonAD().String()),
		QuotedMessage: &waE2E.Message{Conversation: proto.String(text(req, "reply_to_body"))},
	}
	switch {
	case message.Conversation != nil:
		message.ExtendedTextMessage = &waE2E.ExtendedTextMessage{Text: message.Conversation, ContextInfo: context}
		message.Conversation = nil
	case message.ExtendedTextMessage != nil:
		message.ExtendedTextMessage.ContextInfo = context
	case message.ImageMessage != nil:
		message.ImageMessage.ContextInfo = context
	case message.VideoMessage != nil:
		message.VideoMessage.ContextInfo = context
	case message.AudioMessage != nil:
		message.AudioMessage.ContextInfo = context
	case message.DocumentMessage != nil:
		message.DocumentMessage.ContextInfo = context
	default:
		return errors.New("This message cannot carry a reply")
	}
	return nil
}

func messageContext(message *waE2E.Message) *waE2E.ContextInfo {
	switch {
	case message.ExtendedTextMessage != nil:
		return message.ExtendedTextMessage.GetContextInfo()
	case message.ImageMessage != nil:
		return message.ImageMessage.GetContextInfo()
	case message.VideoMessage != nil:
		return message.VideoMessage.GetContextInfo()
	case message.AudioMessage != nil:
		return message.AudioMessage.GetContextInfo()
	case message.DocumentMessage != nil:
		return message.DocumentMessage.GetContextInfo()
	case message.StickerMessage != nil:
		return message.StickerMessage.GetContextInfo()
	default:
		return nil
	}
}

type attachmentInfo struct {
	kind, name, mime, caption string
	size                      uint64
}

func mediaInfo(message *waE2E.Message) attachmentInfo {
	if item := message.GetImageMessage(); item != nil {
		return attachmentInfo{"image", "image", item.GetMimetype(), item.GetCaption(), item.GetFileLength()}
	}
	if item := message.GetVideoMessage(); item != nil {
		return attachmentInfo{"video", "video", item.GetMimetype(), item.GetCaption(), item.GetFileLength()}
	}
	if item := message.GetAudioMessage(); item != nil {
		return attachmentInfo{"audio", "audio", item.GetMimetype(), "", item.GetFileLength()}
	}
	if item := message.GetDocumentMessage(); item != nil {
		return attachmentInfo{"file", item.GetFileName(), item.GetMimetype(), item.GetCaption(), item.GetFileLength()}
	}
	if item := message.GetStickerMessage(); item != nil {
		return attachmentInfo{"image", "sticker.webp", item.GetMimetype(), "", item.GetFileLength()}
	}
	return attachmentInfo{}
}

func text(req map[string]any, key string) string {
	value, _ := req[key].(string)
	return value
}

func conversationJID(req map[string]any) (types.JID, error) {
	jid, err := types.ParseJID(text(req, "conversation_id"))
	if err != nil || jid.User == "" || (jid.Server != types.DefaultUserServer && jid.Server != types.GroupServer && jid.Server != types.HiddenUserServer) {
		return types.EmptyJID, errors.New("The WhatsApp conversation address is invalid")
	}
	return jid, nil
}

func validPhone(phone string) bool {
	if len(phone) < 6 || len(phone) > 15 {
		return false
	}
	for _, digit := range phone {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

func pairingPhone(value string) (string, error) {
	value = strings.TrimPrefix(strings.TrimSpace(value), "+")
	var digits strings.Builder
	for _, char := range value {
		switch {
		case char >= '0' && char <= '9':
			digits.WriteRune(char)
		case char == ' ' || char == '-' || char == '(' || char == ')' || char == '.' || char == '\u00a0':
		default:
			return "", ErrInvalidPhone
		}
	}
	phone := digits.String()
	if len(phone) < 7 || !validPhone(phone) || phone[0] == '0' {
		return "", ErrInvalidPhone
	}
	return phone, nil
}
