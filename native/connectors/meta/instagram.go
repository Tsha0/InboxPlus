package meta

import (
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/mautrix-meta/pkg/instameow"
	"go.mau.fi/mautrix-meta/pkg/instameow/slidetypes"
	"go.mau.fi/mautrix-meta/pkg/messagix/cookies"
	"go.mau.fi/mautrix-meta/pkg/messagix/httpclient"
	"go.mau.fi/mautrix-meta/pkg/messagix/methods"
)

func (c *Connector) connectInstagram(ctx context.Context, jar *cookies.Cookies) (any, error) {
	log := zerolog.Nop()
	c.stateMu.Lock()
	seqID, seqTime, reconnect := c.state.SeqID, c.state.SeqTime, c.state.Reconnect
	c.stateMu.Unlock()
	var client *instameow.Client
	client = instameow.NewClient(instameow.ClientParams{Cookies: jar, Log: log,
		SeqID: seqID, SeqIDTS: seqTime, DisableTyping: true, EventHandler: func(ctx context.Context, event slidetypes.ClientEvent) error {
			c.stateMu.Lock()
			c.state.Cookies = jar.GetAll()
			c.stateMu.Unlock()
			err := c.instagramEvent(ctx, event)
			if _, resnapshot := event.(*slidetypes.ResnapshotRequired); resnapshot {
				go c.resnapshotInstagram(client)
			}
			return err
		}})
	if len(reconnect) > 0 {
		if err := client.LoadState(reconnect); err != nil && !errors.Is(err, instameow.ErrCachedStateTooOld) {
			return nil, errors.New("cannot restore Instagram connection state")
		}
	}
	_, mailbox, err := client.LoadIndex(ctx)
	if err != nil {
		client.Disconnect()
		return nil, errors.New("Instagram sign-in failed; sign in again or complete the account challenge in Instagram")
	}
	c.ig = client
	c.ownID = decimal(client.GetOwnFBID())
	if c.ownID == "0" {
		client.Disconnect()
		c.ig = nil
		return nil, errors.New("Instagram did not return the signed-in identity")
	}
	c.stateMu.Lock()
	c.state.Cookies = jar.GetAll()
	c.state.SeqID, c.state.SeqTime = mailbox.UQSeqID, time.Now()
	c.stateMu.Unlock()
	if err = c.saveState(); err != nil {
		client.Disconnect()
		c.ig = nil
		return nil, err
	}
	c.emitMailbox(mailbox)
	connectionCtx, cancel := context.WithCancel(log.WithContext(context.Background()))
	c.cancel = cancel
	c.ready = true
	go client.Connect(connectionCtx)
	return map[string]any{"state": "connecting", "user_id": c.ownID, "capabilities": c.capabilities()}, nil
}

func (c *Connector) instagramEvent(ctx context.Context, event slidetypes.ClientEvent) error {
	switch evt := event.(type) {
	case *slidetypes.Connected:
		c.transportReady.Store(true)
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "connected"})
	case *slidetypes.Disconnected:
		c.transportReady.Store(false)
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "disconnected"})
	case *slidetypes.AuthError:
		c.transportReady.Store(false)
		c.restartRequired.Store(true)
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "needs_login"})
	case *slidetypes.SeqIDUpdate:
		c.stateMu.Lock()
		c.state.SeqID, c.state.SeqTime = evt.SeqID, evt.Timestamp
		c.stateMu.Unlock()
		return c.saveState()
	case *slidetypes.ReconnectionStateUpdate:
		c.stateMu.Lock()
		c.state.Reconnect = append(c.state.Reconnect[:0], evt.State...)
		c.stateMu.Unlock()
		return c.saveState()
	case *slidetypes.ResnapshotRequired:
		c.transportReady.Store(false)
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "resync_required"})
	case *slidetypes.Delta:
		switch delta := evt.Data.(type) {
		case *slidetypes.NewMessageEvent:
			c.emitInstagramMessage(evt.ThreadIGID, delta.Message, false)
		case *slidetypes.AdminMessageEvent:
			c.emitInstagramMessage(evt.ThreadIGID, delta.Message, false)
		case *slidetypes.EditMessageEvent:
			c.emit(map[string]any{"type": "message_edit", "account_id": c.accountID, "conversation_id": evt.ThreadIGID,
				"id": delta.MessageID, "body": delta.TextBody, "timestamp": delta.SlideEditHistoryEntry.TimestampMS.UnixMilli()})
		case *slidetypes.DeleteMessageEvent:
			c.emit(map[string]any{"type": "message_delete", "account_id": c.accountID, "conversation_id": evt.ThreadIGID, "id": delta.MessageID})
		case *slidetypes.CreateReactionEvent:
			c.emitInstagramReaction(evt.ThreadIGID, delta.MessageID, delta.Reaction, false)
		case *slidetypes.DeleteReactionEvent:
			c.emitInstagramReaction(evt.ThreadIGID, delta.MessageID, delta.Reaction, true)
		case *slidetypes.UpdateThreadNameEvent:
			c.emit(map[string]any{"type": "chat", "account_id": c.accountID, "id": evt.ThreadIGID, "title": delta.ThreadName})
		}
	}
	return nil
}

func (c *Connector) emitMailbox(mailbox *slidetypes.Mailbox) {
	if mailbox == nil {
		return
	}
	for _, edge := range mailbox.ThreadsByFolder.Edges {
		c.emitInstagramThread(edge.Node.AsIGDirectThread)
	}
	for _, thread := range mailbox.PinnedThreadsV2 {
		c.emitInstagramThread(thread.AsIGDirectThread)
	}
}

func (c *Connector) emitInstagramThread(thread *slidetypes.ThreadInfo) {
	if thread == nil {
		return
	}
	metadata := instagramThread{isGroup: thread.IsGroup}
	if !thread.IsGroup {
		for _, user := range thread.Users {
			if user != nil && user.InteropMessagingUserFBID != 0 && decimal(user.InteropMessagingUserFBID) != c.ownID {
				metadata.identityID = decimal(user.InteropMessagingUserFBID)
				break
			}
		}
	}
	c.threadMu.Lock()
	if c.threadKeys == nil {
		c.threadKeys = make(map[string]int64)
	}
	if c.instagramThreads == nil {
		c.instagramThreads = make(map[string]instagramThread)
	}
	c.threadKeys[thread.ID] = thread.ThreadKey
	c.instagramThreads[thread.ID] = metadata
	c.threadMu.Unlock()
	title := thread.ThreadTitle
	if title == "" {
		var names []string
		for _, user := range thread.Users {
			if user != nil {
				if user.FullName != "" {
					names = append(names, user.FullName)
				} else {
					names = append(names, user.Username)
				}
			}
		}
		title = strings.Join(names, ", ")
	}
	unreadCount := 0
	if thread.MarkedAsUnread {
		unreadCount = 1
	}
	event := map[string]any{"type": "chat", "account_id": c.accountID, "id": thread.ID, "title": title,
		"timestamp": thread.LastActivityTimestampMS.UnixMilli(), "unread_count": unreadCount, "is_group": thread.IsGroup, "send_supported": true}
	if thread.IsGroup {
		event["avatar_source"] = c.avatarSource(thread.ThreadImageURL)
	} else {
		for _, user := range thread.Users {
			if user != nil && decimal(user.InteropMessagingUserFBID) == metadata.identityID {
				event["avatar_source"] = c.avatarSource(user.ProfilePicURL)
				break
			}
		}
	}
	if metadata.identityID != "" {
		event["identity_id"] = metadata.identityID
	}
	c.emit(event)
}

func (c *Connector) instagramHistory(ctx context.Context, req map[string]any) (any, error) {
	conversationID := str(req, "conversation_id")
	cursor := str(req, "cursor")
	if conversationID == "" {
		if cursor == "" {
			resp, err := c.ig.GetMailbox(ctx)
			if err != nil || resp.GetMailbox() == nil {
				return nil, errors.New("cannot load Instagram conversations")
			}
			c.emitMailbox(resp.Mailbox)
			return pageResult(resp.Mailbox.ThreadsByFolder.PageInfo), nil
		}
		folder := str(req, "folder")
		if folder == "" {
			folder = "INBOX"
		}
		viewerID, _ := strconv.ParseInt(c.ownID, 10, 64)
		resp, err := c.ig.PaginateMailbox(ctx, slidetypes.MakePaginateMailboxRequest(viewerID, cursor, folder, nil))
		if err != nil || resp == nil || resp.Mailbox == nil {
			return nil, errors.New("cannot load more Instagram conversations")
		}
		for _, edge := range resp.Mailbox.ThreadsByFolder.Edges {
			c.emitInstagramThread(edge.Node.AsIGDirectThread)
		}
		return pageResult(resp.Mailbox.ThreadsByFolder.PageInfo), nil
	}
	if cursor == "" {
		resp, err := c.ig.GetThread(ctx, slidetypes.MakeGetThreadInfoRequest(conversationID))
		if err != nil || resp == nil || resp.ThreadInfo.AsIGDirectThread == nil {
			return nil, errors.New("cannot load Instagram conversation")
		}
		thread := resp.ThreadInfo.AsIGDirectThread
		c.emitInstagramThread(thread)
		if thread.SlideMessages == nil {
			return map[string]any{"has_more": false}, nil
		}
		for _, edge := range thread.SlideMessages.Edges {
			c.emitInstagramMessage(thread.ID, edge.Node, true)
		}
		return pageResult(thread.SlideMessages.PageInfo), nil
	}
	resp, err := c.ig.PaginateMessages(ctx, &slidetypes.PaginateMessagesRequest{
		ThreadID: conversationID, FirstN: 30, AfterCursor: &cursor, InitialMessagePageCount: 30})
	if err != nil || resp == nil || resp.ThreadInfo.AsIGDirectThread == nil || resp.ThreadInfo.AsIGDirectThread.Messages == nil {
		return nil, errors.New("cannot load more Instagram messages")
	}
	messages := resp.ThreadInfo.AsIGDirectThread.Messages
	for _, edge := range messages.Edges {
		c.emitInstagramMessage(conversationID, edge.Node, true)
	}
	return pageResult(messages.PageInfo), nil
}

func pageResult(page slidetypes.PageInfo) map[string]any {
	return map[string]any{"cursor": page.EndCursor, "has_more": page.HasNextPage}
}

func (c *Connector) sendInstagramText(ctx context.Context, req map[string]any) (any, error) {
	conversationID, body := str(req, "conversation_id"), str(req, "body")
	otid := str(req, "transaction_id")
	if otid == "" {
		otid = decimal(methods.GenerateEpochID())
	}
	resp, err := c.ig.SendMessage(ctx, &slidetypes.SendTextRequest{IGThreadIGID: &conversationID,
		OfflineThreadingID: otid, Text: slidetypes.SensitiveString{Value: body}, ReplyToMessageID: replyTarget(req)})
	if err != nil || resp == nil {
		return nil, errors.New("Instagram message was not confirmed")
	}
	sent := resp.GetMessage()
	if sent.ID == "" {
		return nil, errors.New("Instagram did not confirm the message identifier")
	}
	event := map[string]any{"type": "message", "account_id": c.accountID, "conversation_id": conversationID,
		"id": sent.ID, "body": body, "timestamp": sent.TimestampMS.UnixMilli(), "outgoing": true,
		"sender_id": c.ownID, "sender_name": "", "kind": "text", "attachments": []any{}}
	if reply := replyTarget(req); reply != nil {
		event["reply_to_message_id"] = *reply
	}
	c.instagramThreadMetadata(event, conversationID)
	c.emit(event)
	return map[string]any{"id": sent.ID, "timestamp": sent.TimestampMS.UnixMilli(), "transaction_id": otid}, nil
}

func (c *Connector) sendInstagramAttachment(ctx context.Context, req map[string]any) (any, error) {
	conversationID := str(req, "conversation_id")
	encoded := str(req, "bytes")
	if conversationID == "" || len(encoded) == 0 || len(encoded) > (maxMediaBytes+2)/3*4 {
		return nil, errors.New("attachment is missing or exceeds 32 MiB")
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(data) == 0 || len(data) > maxMediaBytes {
		return nil, errors.New("invalid attachment data")
	}
	name := filepath.Base(str(req, "name"))
	if name == "." || name == "" {
		name = "attachment"
	}
	mime := str(req, "mime_type")
	if mime == "" {
		mime = http.DetectContentType(data)
	}
	if !strings.HasPrefix(mime, "image/") && !strings.HasPrefix(mime, "video/") && !strings.HasPrefix(mime, "audio/") {
		return nil, errors.New("Instagram supports image, video and audio attachments")
	}
	if str(req, "body") != "" {
		return nil, errors.New("Instagram attachment captions are not supported; send the text separately")
	}
	c.threadMu.RLock()
	threadKey := c.threadKeys[conversationID]
	c.threadMu.RUnlock()
	if threadKey == 0 {
		resp, loadErr := c.ig.GetThread(ctx, slidetypes.MakeGetThreadInfoRequest(conversationID))
		if loadErr != nil || resp == nil || resp.ThreadInfo.AsIGDirectThread == nil {
			return nil, errors.New("cannot resolve Instagram conversation")
		}
		threadKey = resp.ThreadInfo.AsIGDirectThread.ThreadKey
		c.threadMu.Lock()
		c.threadKeys[conversationID] = threadKey
		c.threadMu.Unlock()
	}
	upload, err := c.ig.GetHTTP().SendMercuryUploadRequest(ctx, threadKey, &httpclient.MercuryUploadMedia{Filename: name, MimeType: mime, MediaData: data})
	if err != nil || upload == nil || upload.Payload.RealMetadata == nil || upload.Payload.RealMetadata.GetFbId() == 0 {
		return nil, errors.New("Instagram attachment upload was not confirmed")
	}
	otid := str(req, "transaction_id")
	if otid == "" {
		otid = decimal(methods.GenerateEpochID())
	}
	resp, err := c.ig.SendMedia(ctx, &slidetypes.SendMediaRequest{AttachmentFBID: decimal(upload.Payload.RealMetadata.GetFbId()),
		ThreadID: conversationID, OfflineThreadingID: otid, ReplyToMessageID: replyTarget(req)})
	if err != nil || resp == nil || resp.GetMessage().ID == "" {
		return nil, errors.New("Instagram attachment message was not confirmed")
	}
	sent := resp.GetMessage()
	return map[string]any{"id": sent.ID, "timestamp": sent.TimestampMS.UnixMilli(), "transaction_id": otid}, nil
}

func (c *Connector) resnapshotInstagram(expected *instameow.Client) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ig != expected || !c.ready {
		return
	}
	_ = c.close()
	c.stateMu.Lock()
	c.state.Reconnect = nil
	c.state.SeqID, c.state.SeqTime = 0, time.Time{}
	c.stateMu.Unlock()
	log := zerolog.Nop()
	ctx, cancel := context.WithTimeout(log.WithContext(context.Background()), 90*time.Second)
	defer cancel()
	if _, err := c.connect(ctx, map[string]any{}); err != nil {
		c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "error", "error": "Instagram could not resynchronize; reconnect the account"})
	}
}

func (c *Connector) reactInstagram(ctx context.Context, req map[string]any) (any, error) {
	emoji := str(req, "emoji")
	status := slidetypes.ReactionStatusCreated
	if emoji == "" {
		emoji, status = str(req, "previous_emoji"), slidetypes.ReactionStatusDeleted
	}
	if emoji == "" {
		return nil, errors.New("reaction is missing")
	}
	response, err := c.ig.SendReaction(ctx, &slidetypes.CreateReactionRequest{Input: slidetypes.ReactionInput{
		ThreadID: str(req, "conversation_id"), MessageID: str(req, "message_id"), Emoji: emoji, ReactionStatus: status,
	}})
	if err != nil || response == nil || response.Message.ID != str(req, "message_id") {
		return nil, errors.New("Instagram did not confirm the reaction")
	}
	values := make([]*slidetypes.Reaction, len(response.Message.Reactions))
	for index := range response.Message.Reactions {
		values[index] = &response.Message.Reactions[index]
	}
	return map[string]any{"applied": true, "type": "reactions", "account_id": c.accountID, "conversation_id": str(req, "conversation_id"),
		"id": response.Message.ID, "reactions": c.instagramReactions(values)}, nil
}

func (c *Connector) emitInstagramReaction(conversationID, messageID string, reaction slidetypes.Reaction, removed bool) {
	if conversationID == "" || messageID == "" || reaction.SenderFBID <= 0 {
		return
	}
	emoji := reaction.Reaction
	if removed {
		emoji = ""
	}
	timestamp := reaction.ReactionTimestampMS.UnixMilli()
	if timestamp <= 0 {
		timestamp = time.Now().UnixMilli()
	}
	sender := decimal(reaction.SenderFBID)
	c.emit(map[string]any{"type": "reaction", "account_id": c.accountID, "conversation_id": conversationID, "id": messageID,
		"sender_id": sender, "emoji": emoji, "outgoing": sender == c.ownID, "timestamp": timestamp})
}
