package meta

import (
	"net/url"
	"strings"

	"go.mau.fi/mautrix-meta/pkg/instameow/slidetypes"
)

func (c *Connector) emitInstagramMessage(conversationID string, message *slidetypes.Message, historical bool) {
	if event := c.instagramMessage(conversationID, message); event != nil {
		event["historical"] = historical
		c.emit(event)
	}
}

func (c *Connector) instagramMessage(conversationID string, message *slidetypes.Message) map[string]any {
	if message == nil || message.ID == "" {
		return nil
	}
	if conversationID == "" {
		conversationID = message.ThreadFBID
	}
	senderID, senderName := decimal(message.SenderFBID), ""
	if message.Sender != nil {
		senderName = message.Sender.Name
	}
	body, kind := message.TextBody, "text"
	attachments := make([]any, 0)
	mediaIndex := 0
	add := func(id, raw, mime, name string) {
		if id == "" {
			id = decimal(int64(mediaIndex))
		}
		mediaIndex++
		if attachment := c.rememberMedia(message.ID+"/"+id, raw, mime, name); attachment != nil {
			attachments = append(attachments, attachment)
		}
	}
	addVisual := func(items []*slidetypes.Attachment, mime string) {
		for _, attachment := range items {
			if attachment == nil {
				continue
			}
			id := attachment.AttachmentFBID
			raw := attachment.AttachmentCDNURL
			if raw == "" {
				raw = attachment.AttachmentCDNFallbackURL
			}
			add(id, raw, mime, kind)
		}
	}
	switch content := message.Content.Content.(type) {
	case *slidetypes.MessageContentText:
		body = content.TextBody
	case *slidetypes.MessageContentImage:
		kind = "image"
		addVisual(content.Attachments, "image/jpeg")
	case *slidetypes.MessageContentVideo:
		kind = "video"
		addVisual(content.Videos, "video/mp4")
	case *slidetypes.MessageContentMultiMedia:
		kind = "media"
		for _, attachment := range content.Attachments {
			mime := "image/jpeg"
			if attachment != nil && (attachment.AttachmentType == 2 || attachment.DashManifest != "") {
				mime = "video/mp4"
			}
			addVisual([]*slidetypes.Attachment{attachment}, mime)
		}
	case *slidetypes.MessageContentAudio:
		kind = "audio"
		for _, attachment := range content.AudioAttachments {
			if attachment != nil {
				add(attachment.AttachmentFBID, attachment.AttachmentCDNURL, "audio/mp4", "Audio")
			}
		}
	case *slidetypes.MessageContentAnimatedMedia:
		kind = "image"
		for index, attachment := range content.AnimatedMedia {
			if attachment == nil {
				continue
			}
			if attachment.AttachmentMP4URL != "" {
				add(decimal(int64(index)), attachment.AttachmentMP4URL, "video/mp4", attachment.AltText)
			} else {
				add(decimal(int64(index)), attachment.AttachmentWebpURL, "image/webp", attachment.AltText)
			}
		}
	case *slidetypes.MessageContentSticker:
		kind = "sticker"
		body = content.AltText
		add("sticker", content.PreviewURL, "image/webp", content.AltText)
	case *slidetypes.MessageContentRavenImage, *slidetypes.MessageContentRavenVideo:
		kind, body = "unsupported", "Disappearing media — open Instagram to view"
	case *slidetypes.MessageContentAdminText:
		kind = "system"
		if body == "" {
			for _, fragment := range content.TextFragments {
				body += fragment.Plaintext
			}
		}
	case *slidetypes.MessageContentXMA:
		kind, body = "link", content.XMATextBody
		if xma := content.XMA; xma != nil {
			if body == "" {
				body = xma.TitleText
			}
			if body == "" {
				body = xma.XMATitle
			}
			if body == "" {
				body = xma.CaptionBodyText
			}
			if validInstagramLink(xma.TargetURL) {
				attachment := map[string]any{"id": message.ID + "/link", "name": body, "kind": "link", "deep_link": xma.TargetURL, "downloadable": false}
				if strings.Contains(xma.TargetURL, "/reel/") || strings.Contains(xma.TargetURL, "/reels/") {
					attachment["kind"] = "reel"
				}
				preview := xma.PreviewImage
				if preview == nil {
					preview = xma.XMAPreviewImage
				}
				if preview != nil {
					if media := c.rememberMedia(message.ID+"/preview", preview.URL, "image/jpeg", "Preview"); media != nil {
						attachment["preview_id"] = media["id"]
					}
				}
				attachments = append(attachments, attachment)
			}
		}
	case nil:
		if body == "" {
			kind, body = "unsupported", "Unsupported Instagram message"
		}
	default:
		kind = "unsupported"
		if body == "" {
			body = "Unsupported Instagram message"
		}
	}
	if kind != "text" && len(attachments) == 0 && body == "" {
		body = "Media unavailable — open Instagram to view"
	}
	event := map[string]any{"type": "message", "account_id": c.accountID, "conversation_id": conversationID,
		"id": message.ID, "body": body, "timestamp": message.TimestampMS.UnixMilli(), "outgoing": senderID == c.ownID,
		"sender_id": senderID, "sender_name": senderName, "kind": kind, "attachments": attachments}
	event["reactions"] = c.instagramReactions(message.Reactions)
	if message.RepliedToMessageID != "" {
		event["reply_to_message_id"] = message.RepliedToMessageID
	}
	c.instagramThreadMetadata(event, conversationID)
	return event
}

func (c *Connector) instagramThreadMetadata(event map[string]any, conversationID string) {
	c.threadMu.RLock()
	thread, known := c.instagramThreads[conversationID]
	c.threadMu.RUnlock()
	if known {
		event["is_group"] = thread.isGroup
		if thread.identityID != "" {
			event["identity_id"] = thread.identityID
		}
	}
}

func validInstagramLink(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	return host == "instagram.com" || strings.HasSuffix(host, ".instagram.com")
}

func (c *Connector) instagramReactions(reactions []*slidetypes.Reaction) []map[string]any {
	values := []map[string]any{}
	for _, reaction := range reactions {
		if reaction == nil || reaction.SenderFBID <= 0 || reaction.Reaction == "" {
			continue
		}
		sender := decimal(reaction.SenderFBID)
		values = append(values, map[string]any{"key": reaction.Reaction, "sender_id": sender, "includes_me": sender == c.ownID, "timestamp": reaction.ReactionTimestampMS.UnixMilli()})
	}
	return values
}
