package meta

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/mautrix-meta/pkg/messagix"
	"go.mau.fi/mautrix-meta/pkg/messagix/cookies"
	"go.mau.fi/mautrix-meta/pkg/messagix/methods"
	"go.mau.fi/mautrix-meta/pkg/messagix/socket"
	"go.mau.fi/mautrix-meta/pkg/messagix/table"
)

type fbThread struct {
	title      string
	timestamp  int64
	threadType table.ThreadType
	e2ee       bool
	canSend    bool
	syncGroup  int64
	beforeID   string
	beforeTS   int64
}

type fbAdapter struct {
	c        *Connector
	client   *messagix.Client
	mu       sync.Mutex
	ready    bool
	threads  map[int64]fbThread
	contacts map[int64]string
}

func fbContext(ctx context.Context) context.Context {
	log := zerolog.Nop()
	return log.WithContext(ctx)
}

func (f *fbAdapter) connect(ctx context.Context, jar *cookies.Cookies) (any, error) {
	f.threads = make(map[int64]fbThread)
	f.contacts = make(map[int64]string)
	f.client = messagix.NewClient(jar, zerolog.Nop(), &messagix.Config{})
	f.client.SetEventHandler(f.handleEvent)
	user, initial, err := f.client.LoadMessagesPage(fbContext(ctx))
	if err != nil {
		return nil, errors.New("meta_login_failed")
	}
	if user.GetFBID() != jar.GetUserID() {
		return nil, errors.New("meta_account_mismatch")
	}
	f.c.ownID = strconv.FormatInt(user.GetFBID(), 10)
	f.c.stateMu.Lock()
	f.c.state.Cookies = jar.GetAll()
	f.c.stateMu.Unlock()
	f.handleTable(initial, true)
	connectionCtx, cancel := context.WithCancel(fbContext(context.Background()))
	if err = f.client.Connect(connectionCtx); err != nil {
		cancel()
		return nil, errors.New("meta_connect_failed")
	}
	f.c.cancel = cancel
	return map[string]any{"state": "connecting", "user_id": f.c.ownID, "display_name": user.GetName(), "encrypted_chats_supported": false}, nil
}

func (f *fbAdapter) handleEvent(_ context.Context, event any) {
	if err := f.c.updateCookies(f.client.GetCookies()); err != nil {
		return
	}
	switch evt := event.(type) {
	case *table.LSTable:
		f.handleTable(evt, false)
	case *messagix.ConnectedEvent, *messagix.ReconnectedEvent:
		f.mu.Lock()
		f.ready = true
		f.mu.Unlock()
		f.c.emit(map[string]any{"type": "connection", "account_id": f.c.accountID, "state": "connected"})
	case *messagix.TransientDisconnectEvent:
		f.mu.Lock()
		f.ready = false
		f.mu.Unlock()
		f.c.emit(map[string]any{"type": "connection", "account_id": f.c.accountID, "state": "reconnecting"})
	case *messagix.PermanentErrorEvent:
		f.c.restartRequired.Store(true)
		f.mu.Lock()
		f.ready = false
		f.mu.Unlock()
		f.c.emit(map[string]any{"type": "connection", "account_id": f.c.accountID, "state": "error", "error": "meta_connection_failed"})
	}
}

func (f *fbAdapter) emitThread(id int64, thread fbThread) {
	event := map[string]any{
		"type": "chat", "account_id": f.c.accountID, "id": strconv.FormatInt(id, 10),
		"title": thread.title, "timestamp": thread.timestamp, "e2ee": thread.e2ee,
		"send_supported": thread.canSend, "unsupported_reason": fbUnsupportedReason(thread),
	}
	fbThreadMetadata(event, id, thread)
	f.c.emit(event)
}

func fbThreadMetadata(event map[string]any, id int64, thread fbThread) {
	if thread.threadType == table.UNKNOWN_THREAD_TYPE {
		return
	}
	event["is_group"] = !thread.threadType.IsOneToOne()
	if thread.threadType.IsOneToOne() {
		event["identity_id"] = strconv.FormatInt(id, 10)
	}
}

func fbUnsupportedReason(thread fbThread) string {
	if thread.e2ee {
		return "messenger_encrypted_chats_unavailable"
	}
	if !thread.canSend {
		return "messenger_chat_read_only"
	}
	return ""
}

func fbEncrypted(threadType table.ThreadType) bool {
	return threadType.IsWhatsApp() || threadType == table.TINCAN_ONE_TO_ONE || threadType == table.TINCAN_GROUP_DISAPPEARING || threadType == table.TINCAN_ONE_TO_ONE_DISAPPEARING
}

func fbWritable(threadType table.ThreadType) bool {
	switch threadType {
	case table.ONE_TO_ONE, table.GROUP_THREAD, table.MARKETPLACE, table.PAGE_FOLLOW_UP, table.COMMUNITY_GROUP, table.COMMUNITY_SUB_THREAD:
		return true
	default:
		return false
	}
}

func (f *fbAdapter) upsertThread(id int64, name string, timestamp int64, threadType table.ThreadType, syncGroup int64, disabled bool) {
	if id <= 0 || threadType == table.FOLDER || threadType == table.COMMUNITY_FOLDER {
		return
	}
	f.mu.Lock()
	if f.threads == nil {
		f.threads = make(map[int64]fbThread)
	}
	thread := f.threads[id]
	thread.title = name
	if thread.title == "" {
		thread.title = f.contacts[id]
	}
	thread.timestamp = timestamp
	if threadType != table.UNKNOWN_THREAD_TYPE {
		thread.threadType = threadType
	}
	thread.e2ee = thread.e2ee || fbEncrypted(threadType)
	thread.canSend = fbWritable(threadType) && !disabled && !thread.e2ee
	thread.syncGroup = syncGroup
	if thread.syncGroup == 0 {
		thread.syncGroup = 1
	}
	f.threads[id] = thread
	f.mu.Unlock()
	f.emitThread(id, thread)
}

func (f *fbAdapter) handleTable(data *table.LSTable, historical bool) {
	if data == nil {
		return
	}
	f.mu.Lock()
	if f.contacts == nil {
		f.contacts = make(map[int64]string)
	}
	for _, contact := range data.LSDeleteThenInsertContact {
		f.contacts[contact.Id] = contact.Name
	}
	for _, contact := range data.LSVerifyContactRowExists {
		f.contacts[contact.ContactId] = contact.Name
	}
	f.mu.Unlock()
	for _, thread := range data.LSDeleteThenInsertThread {
		f.upsertThread(thread.ThreadKey, thread.ThreadName, thread.LastActivityTimestampMs, thread.ThreadType, thread.SyncGroup, thread.DisableComposerInput)
	}
	for _, thread := range data.LSUpdateOrInsertThread {
		f.upsertThread(thread.ThreadKey, thread.ThreadName, thread.LastActivityTimestampMs, thread.ThreadType, thread.SyncGroup, thread.DisableComposerInput)
	}
	for _, thread := range data.LSVerifyHybridThreadExists {
		f.upsertThread(thread.ThreadKey, "", thread.LastActivityTimestampMS, thread.ThreadType, 1, true)
	}
	for _, link := range data.LSCreateOpenToE2EEThreadLink {
		f.markEncrypted(link.OpenThreadID)
	}
	for _, cutover := range data.LSMoveThreadToE2EECutoverFolder {
		f.markEncrypted(cutover.ThreadKey)
	}
	attachments := make(map[string][]map[string]any)
	for _, attachment := range data.LSInsertAttachment {
		raw := attachment.PlayableUrl
		if raw == "" {
			raw = attachment.ImageUrl
		}
		if attachment.DecryptionKey != "" {
			raw = ""
		}
		attachments[attachment.MessageId] = append(attachments[attachment.MessageId], f.attachment(attachment.MessageId, attachment.AttachmentFbid, attachment.Filename, attachment.AttachmentMimeType, raw, attachment.Filesize))
	}
	for _, attachment := range data.LSInsertBlobAttachment {
		attachments[attachment.MessageId] = append(attachments[attachment.MessageId], f.attachment(attachment.MessageId, attachment.AttachmentFbid, attachment.Filename, attachment.AttachmentMimeType, attachment.PlayableUrl, attachment.Filesize))
	}
	for _, message := range data.LSUpsertMessage {
		f.emitMessage(message.ThreadKey, message.MessageId, message.SenderId, message.Text, message.TimestampMs, message.IsUnsent, message.IsAdminMessage, attachments[message.MessageId], historical, message.ReplySourceId)
	}
	for _, message := range data.LSInsertMessage {
		f.emitMessage(message.ThreadKey, message.MessageId, message.SenderId, message.Text, message.TimestampMs, message.IsUnsent, message.IsAdminMessage, attachments[message.MessageId], historical, message.ReplySourceId)
	}
	for _, message := range data.LSDeleteThenInsertMessage {
		f.emitMessage(message.ThreadKey, message.MessageId, message.SenderId, message.Text, message.TimestampMs, message.IsUnsent, message.IsAdminMessage, attachments[message.MessageId], historical, message.ReplySourceId)
	}
	for _, reaction := range data.LSUpsertReaction {
		f.emitReaction(reaction.ThreadKey, reaction.MessageId, reaction.ActorId, reaction.Reaction, reaction.TimestampMs)
	}
	for _, reaction := range data.LSDeleteReaction {
		f.emitReaction(reaction.ThreadKey, reaction.MessageId, reaction.ActorId, "", time.Now().UnixMilli())
	}
	for _, receipt := range data.LSUpdateReadReceipt {
		f.c.emit(map[string]any{"type": "receipt", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(receipt.ThreadKey, 10), "sender_id": strconv.FormatInt(receipt.ContactId, 10), "timestamp": receipt.ReadWatermarkTimestampMs, "state": "read"})
	}
	for _, message := range data.LSDeleteMessage {
		f.c.emit(map[string]any{"type": "message_delete", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(message.ThreadKey, 10), "id": message.MessageId})
	}
	for _, messageRange := range data.LSInsertNewMessageRange {
		f.c.emit(map[string]any{"type": "history", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(messageRange.ThreadKey, 10), "has_more": messageRange.HasMoreBefore, "before_id": messageRange.MinMessageId, "before_timestamp": messageRange.MinTimestampMs})
	}
	if f.client != nil {
		f.client.PostHandlePublishResponse(data)
	}
}

func (f *fbAdapter) attachment(messageID, id, name, mime, raw string, size int64) map[string]any {
	result := f.c.rememberMedia(messageID+"/"+id, raw, mime, name)
	if result == nil {
		result = map[string]any{"id": messageID + "/" + id, "name": name, "mime_type": mime, "downloadable": false}
	}
	result["size"] = size
	return result
}

func (f *fbAdapter) markEncrypted(id int64) {
	f.mu.Lock()
	if f.threads == nil {
		f.threads = make(map[int64]fbThread)
	}
	thread := f.threads[id]
	thread.e2ee = true
	thread.canSend = false
	f.threads[id] = thread
	f.mu.Unlock()
	f.emitThread(id, thread)
}

func (f *fbAdapter) emitMessage(threadID int64, id string, senderID int64, body string, timestamp int64, deleted, admin bool, attachments []map[string]any, historical bool, replyID string) {
	if threadID <= 0 || id == "" {
		return
	}
	if deleted {
		f.c.emit(map[string]any{"type": "message_delete", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(threadID, 10), "id": id})
		return
	}
	f.mu.Lock()
	thread := f.threads[threadID]
	if thread.beforeID == "" || timestamp < thread.beforeTS {
		thread.beforeID, thread.beforeTS = id, timestamp
		if f.threads == nil {
			f.threads = make(map[int64]fbThread)
		}
		f.threads[threadID] = thread
	}
	senderName := f.contacts[senderID]
	f.mu.Unlock()
	if attachments == nil {
		attachments = []map[string]any{}
	}
	kind := "text"
	if len(attachments) > 0 {
		kind = "file"
	}
	if admin {
		kind = "notice"
	}
	sender := strconv.FormatInt(senderID, 10)
	event := map[string]any{"type": "message", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(threadID, 10), "id": id, "sender_id": sender, "sender_name": senderName, "body": body, "timestamp": timestamp, "outgoing": sender == f.c.ownID, "kind": kind, "attachments": attachments, "historical": historical}
	if replyID != "" {
		event["reply_to_message_id"] = replyID
	}
	fbThreadMetadata(event, threadID, thread)
	if historical {
		event["reactions"] = []map[string]any{}
	}
	f.c.emit(event)
}

func (f *fbAdapter) emitReaction(threadID int64, messageID string, actorID int64, emoji string, timestamp int64) {
	if threadID <= 0 || actorID <= 0 || messageID == "" {
		return
	}
	if timestamp <= 0 {
		timestamp = time.Now().UnixMilli()
	}
	actor := strconv.FormatInt(actorID, 10)
	f.c.emit(map[string]any{"type": "reaction", "account_id": f.c.accountID, "conversation_id": strconv.FormatInt(threadID, 10),
		"id": messageID, "sender_id": actor, "emoji": emoji, "outgoing": actor == f.c.ownID, "timestamp": timestamp})
}

func (f *fbAdapter) react(ctx context.Context, request map[string]any) (any, error) {
	threadID, _, err := f.target(str(request, "conversation_id"))
	if err != nil {
		return nil, err
	}
	actor := fbOwnID(f.c.ownID)
	if actor <= 0 {
		return nil, errors.New("meta_not_connected")
	}
	id, emoji := str(request, "message_id"), str(request, "emoji")
	response, err := f.client.ExecuteTasks(fbContext(ctx), &socket.SendReactionTask{
		ThreadKey: threadID, ActorID: actor, MessageID: id, Reaction: emoji, SendAttribution: table.MESSENGER_INBOX_IN_THREAD,
	})
	if err != nil || !fbReactionConfirmed(response, threadID, actor, id, emoji) {
		return nil, errors.New("meta_reaction_unconfirmed")
	}
	f.handleTable(response, false)
	return map[string]any{"applied": true, "type": "reaction", "account_id": f.c.accountID, "conversation_id": str(request, "conversation_id"),
		"id": id, "sender_id": f.c.ownID, "emoji": emoji, "outgoing": true, "timestamp": time.Now().UnixMilli()}, nil
}

func fbReactionConfirmed(response *table.LSTable, threadID, actorID int64, messageID, emoji string) bool {
	if response == nil {
		return false
	}
	for _, reaction := range response.LSReplaceOptimisticReaction {
		if reaction.ThreadKey == threadID && reaction.ActorId == actorID && reaction.MessageId == messageID {
			return true
		}
	}
	for _, reaction := range response.LSUpsertReaction {
		if reaction.ThreadKey == threadID && reaction.ActorId == actorID && reaction.MessageId == messageID && reaction.Reaction == emoji {
			return true
		}
	}
	if emoji == "" {
		for _, reaction := range response.LSDeleteReaction {
			if reaction.ThreadKey == threadID && reaction.ActorId == actorID && reaction.MessageId == messageID {
				return true
			}
		}
	}
	return false
}

func (f *fbAdapter) target(id string) (int64, fbThread, error) {
	threadID, err := strconv.ParseInt(id, 10, 64)
	if err != nil || threadID <= 0 {
		return 0, fbThread{}, errors.New("invalid_conversation")
	}
	f.mu.Lock()
	thread, known := f.threads[threadID]
	ready := f.ready
	f.mu.Unlock()
	if !known {
		return 0, fbThread{}, errors.New("conversation_not_loaded")
	}
	if thread.e2ee {
		return 0, fbThread{}, errors.New("messenger_encrypted_chats_unavailable")
	}
	if !ready {
		return 0, fbThread{}, errors.New("meta_not_connected")
	}
	return threadID, thread, nil
}

func (f *fbAdapter) sendText(ctx context.Context, conversationID, body, replyID string) (any, error) {
	threadID, thread, err := f.target(conversationID)
	if err != nil {
		return nil, err
	}
	if !thread.canSend {
		return nil, errors.New("messenger_chat_read_only")
	}
	if strings.TrimSpace(body) == "" {
		return nil, errors.New("message_empty")
	}
	otid := methods.GenerateEpochID()
	task := &socket.SendMessageTask{ThreadId: threadID, Otid: otid, Text: body, Source: table.MESSENGER_INBOX_IN_THREAD, InitiatingSource: table.FACEBOOK_INBOX, SendType: table.TEXT, SyncGroup: thread.syncGroup}
	if replyID != "" {
		task.ReplyMetaData = &socket.ReplyMetaData{ReplyMessageId: replyID, ReplySourceType: 1, ReplyType: 0}
	}
	response, err := f.client.ExecuteTasks(fbContext(ctx), task)
	if err != nil {
		return nil, errors.New("meta_send_unconfirmed")
	}
	id := fbConfirmedMessageID(response, strconv.FormatInt(otid, 10))
	if id == "" {
		return nil, errors.New("meta_send_unconfirmed")
	}
	f.handleTable(response, false)
	timestamp := time.Now().UnixMilli()
	f.emitMessage(threadID, id, fbOwnID(f.c.ownID), body, timestamp, false, false, nil, false, replyID)
	return map[string]any{"id": id, "timestamp": timestamp}, nil
}

func fbOwnID(id string) int64 {
	number, _ := strconv.ParseInt(id, 10, 64)
	return number
}

func fbConfirmedMessageID(response *table.LSTable, otid string) string {
	if response != nil {
		for _, replaced := range response.LSReplaceOptimsiticMessage {
			if replaced.OfflineThreadingId == otid {
				return replaced.MessageId
			}
		}
	}
	return ""
}

func (f *fbAdapter) history(ctx context.Context, req map[string]any) (any, error) {
	if str(req, "op") == "list_chats" {
		f.mu.Lock()
		ready := f.ready
		f.mu.Unlock()
		if !ready {
			return nil, errors.New("meta_not_connected")
		}
		_, response, err := f.client.FetchMoreThreads(fbContext(ctx), 1)
		if err != nil {
			return nil, errors.New("meta_history_failed")
		}
		f.handleTable(response, true)
		return map[string]any{"status": "requested"}, nil
	}
	threadID, thread, err := f.target(str(req, "conversation_id"))
	if err != nil {
		return nil, err
	}
	beforeID := str(req, "before_id")
	beforeTS := fbTimestamp(req["before_timestamp"])
	if beforeID == "" {
		beforeID, beforeTS = thread.beforeID, thread.beforeTS
	}
	var task socket.Task
	if beforeID == "" {
		task = &socket.CreateThreadTask{ThreadFBID: threadID, SyncGroup: int(thread.syncGroup)}
	} else {
		task = &socket.FetchMessagesTask{ThreadKey: threadID, Direction: 0, ReferenceTimestampMs: beforeTS, ReferenceMessageId: beforeID, SyncGroup: thread.syncGroup, Cursor: f.client.GetCursor(thread.syncGroup)}
	}
	response, err := f.client.ExecuteTasks(fbContext(ctx), task)
	if err != nil {
		return nil, errors.New("meta_history_failed")
	}
	f.handleTable(response, true)
	return map[string]any{"status": "requested"}, nil
}

func fbTimestamp(value any) int64 {
	switch number := value.(type) {
	case int64:
		return number
	case float64:
		return int64(number)
	default:
		return 0
	}
}

func (f *fbAdapter) close() error {
	if f.client != nil {
		f.client.Disconnect()
	}
	f.mu.Lock()
	f.ready = false
	f.mu.Unlock()
	return nil
}
