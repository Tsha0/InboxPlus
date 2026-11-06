package telegram

import (
	"errors"
	"strconv"
	"strings"

	"github.com/gotd/td/tg"
)

func peerKey(peer tg.PeerClass) string {
	switch peer := peer.(type) {
	case *tg.PeerUser:
		return "user:" + strconv.FormatInt(peer.UserID, 10)
	case *tg.PeerChat:
		return "chat:" + strconv.FormatInt(peer.ChatID, 10)
	case *tg.PeerChannel:
		return "channel:" + strconv.FormatInt(peer.ChannelID, 10)
	default:
		return ""
	}
}

func normalizeMessage(accountID string, message *tg.Message, senderName string) map[string]any {
	conversationID := peerKey(message.PeerID)
	id := conversationID + ":" + strconv.Itoa(message.ID)
	kind := "text"
	attachments := []map[string]any{}
	switch media := message.Media.(type) {
	case nil, *tg.MessageMediaEmpty, *tg.MessageMediaWebPage:
	case *tg.MessageMediaPhoto:
		if _, size, available := mediaLocation(media); available {
			kind = "image"
			attachments = append(attachments, map[string]any{
				"id": id, "name": "photo.jpg", "mime_type": "image/jpeg", "size": size, "kind": kind,
			})
		} else {
			kind = "unsupported"
		}
	case *tg.MessageMediaDocument:
		if document, ok := media.Document.(*tg.Document); ok && media.TTLSeconds == 0 {
			name := "attachment"
			kind = "file"
			switch {
			case media.Voice || strings.HasPrefix(document.MimeType, "audio/"):
				kind = "audio"
			case media.Video || media.Round || strings.HasPrefix(document.MimeType, "video/"):
				kind = "video"
			case strings.HasPrefix(document.MimeType, "image/"):
				kind = "image"
			}
			for _, attribute := range document.Attributes {
				switch attribute := attribute.(type) {
				case *tg.DocumentAttributeFilename:
					name = attribute.FileName
				case *tg.DocumentAttributeAudio:
					kind = "audio"
				case *tg.DocumentAttributeVideo:
					kind = "video"
				}
			}
			attachments = append(attachments, map[string]any{
				"id": id, "name": name, "mime_type": document.MimeType, "size": document.Size, "kind": kind,
			})
		} else {
			kind = "unsupported"
		}
	default:
		kind = "unsupported"
	}
	event := map[string]any{
		"type": "message", "account_id": accountID, "conversation_id": conversationID,
		"id": id, "body": message.Message, "timestamp": int64(message.Date) * 1000,
		"outgoing": message.Out, "sender_id": peerKey(message.FromID), "sender_name": senderName,
		"kind": kind, "attachments": attachments,
		"is_group":  strings.HasPrefix(conversationID, "chat:") || strings.HasPrefix(conversationID, "channel:"),
		"reactions": normalizeReactions(&message.Reactions), "reactions_partial": message.Reactions.Min,
	}
	if strings.HasPrefix(conversationID, "user:") {
		event["identity_id"] = conversationID
	}
	if reply, ok := message.ReplyTo.(*tg.MessageReplyHeader); ok && reply.ReplyToMsgID > 0 &&
		(reply.ReplyToPeerID == nil || peerKey(reply.ReplyToPeerID) == conversationID) {
		event["reply_to_message_id"] = conversationID + ":" + strconv.Itoa(reply.ReplyToMsgID)
	}
	return event
}

func normalizeReactions(reactions *tg.MessageReactions) []map[string]any {
	values := []map[string]any{}
	if reactions == nil {
		return values
	}
	for _, reaction := range reactions.Results {
		if emoji, ok := reaction.Reaction.(*tg.ReactionEmoji); ok && emoji.Emoticon != "" && reaction.Count > 0 {
			_, own := reaction.GetChosenOrder()
			values = append(values, map[string]any{"key": emoji.Emoticon, "count": reaction.Count, "includes_me": own})
		}
	}
	return values
}

func reactionEvent(accountID, conversationID string, id int, reactions *tg.MessageReactions) map[string]any {
	return map[string]any{"type": "reactions", "account_id": accountID, "conversation_id": conversationID,
		"id": conversationID + ":" + strconv.Itoa(id), "reactions": normalizeReactions(reactions), "reactions_partial": reactions != nil && reactions.Min}
}

func replyMessageID(conversationID, replyTo string) (int, error) {
	if replyTo == "" {
		return 0, nil
	}
	prefix := conversationID + ":"
	if !strings.HasPrefix(replyTo, prefix) {
		return 0, errors.New("telegram_reply_conversation_mismatch")
	}
	id, err := strconv.ParseInt(strings.TrimPrefix(replyTo, prefix), 10, 32)
	if err != nil || id <= 0 {
		return 0, errors.New("telegram_invalid_reply")
	}
	return int(id), nil
}

func mediaLocation(media tg.MessageMediaClass) (tg.InputFileLocationClass, int64, bool) {
	switch media := media.(type) {
	case *tg.MessageMediaDocument:
		document, ok := media.Document.(*tg.Document)
		if !ok || media.TTLSeconds != 0 {
			return nil, 0, false
		}
		return &tg.InputDocumentFileLocation{
			ID: document.ID, AccessHash: document.AccessHash, FileReference: document.FileReference,
		}, document.Size, true
	case *tg.MessageMediaPhoto:
		photo, ok := media.Photo.(*tg.Photo)
		if !ok || media.TTLSeconds != 0 {
			return nil, 0, false
		}
		thumbType := ""
		var size int64
		for _, thumbnail := range photo.Sizes {
			switch thumbnail := thumbnail.(type) {
			case *tg.PhotoSize:
				if int64(thumbnail.Size) > size {
					thumbType, size = thumbnail.Type, int64(thumbnail.Size)
				}
			case *tg.PhotoSizeProgressive:
				for _, prefixSize := range thumbnail.Sizes {
					if int64(prefixSize) > size {
						thumbType, size = thumbnail.Type, int64(prefixSize)
					}
				}
			}
		}
		if thumbType == "" {
			return nil, 0, false
		}
		return &tg.InputPhotoFileLocation{
			ID: photo.ID, AccessHash: photo.AccessHash, FileReference: photo.FileReference, ThumbSize: thumbType,
		}, size, true
	default:
		return nil, 0, false
	}
}

func mediaDCID(media tg.MessageMediaClass) int {
	switch media := media.(type) {
	case *tg.MessageMediaDocument:
		if document, ok := media.Document.(*tg.Document); ok {
			return document.DCID
		}
	case *tg.MessageMediaPhoto:
		if photo, ok := media.Photo.(*tg.Photo); ok {
			return photo.DCID
		}
	}
	return 0
}
