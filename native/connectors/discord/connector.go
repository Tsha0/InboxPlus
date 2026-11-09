package discord

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
	"sync"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/direct"
	"github.com/diamondburned/arikawa/v3/api"
	dc "github.com/diamondburned/arikawa/v3/discord"
	"github.com/diamondburned/arikawa/v3/gateway"
	"github.com/diamondburned/arikawa/v3/session"
	"github.com/diamondburned/arikawa/v3/utils/sendpart"
	"github.com/diamondburned/arikawa/v3/utils/ws"
)

func init() { ws.WSError = func(error) {} }

func Capabilities() map[string]any {
	return map[string]any{"platform": "discord", "send_text": true, "send_attachment": true, "download_attachment": true, "history_sync": true, "replies": true, "reactions": false, "start_conversation": true, "max_attachment_bytes": 10 << 20}
}

func New(id, directory string, key []byte, emit func(map[string]any)) (*direct.Connector, error) {
	return direct.New(id, directory, key, Capabilities(), emit, func(c *direct.Connector) direct.Backend {
		return &backend{c: c, channels: map[dc.ChannelID]dc.Channel{}, media: map[string]string{}}
	})
}

type credentials struct {
	Token string `json:"token"`
}
type backend struct {
	c           *direct.Connector
	client      *session.Session
	mu          sync.Mutex
	ownID       dc.UserID
	channels    map[dc.ChannelID]dc.Channel
	media       map[string]string
	stop        context.CancelFunc
	done        chan struct{}
	mfaTicket   string
	mfaInstance string
}

func (b *backend) Connect(ctx context.Context, req map[string]any) (string, error) {
	var saved credentials
	if _, err := b.c.Load(&saved); err != nil {
		return "", err
	}
	if direct.Text(req, "op") == "login_code" {
		if b.mfaTicket == "" {
			return "", errors.New("discord_verification_not_started")
		}
		response, err := api.NewClient("").WithContext(ctx).TOTP(direct.Text(req, "code"), b.mfaTicket, b.mfaInstance)
		if err != nil || response == nil {
			return "", errors.New("discord_verification_failed")
		}
		saved.Token = response.Token
	} else {
		if err := b.Close(); err != nil {
			return "", err
		}
		if token := strings.TrimSpace(direct.Text(req, "token")); token != "" {
			saved.Token = token
		} else if username, password := direct.Text(req, "username"), direct.Text(req, "password"); username != "" && password != "" {
			response, err := api.NewClient("").WithContext(ctx).Login(username, password)
			if err != nil || response == nil {
				return "", errors.New("discord_sign_in_failed")
			}
			if response.MFA {
				if !response.TOTP && !response.Backup {
					return "", errors.New("discord_authenticator_required")
				}
				b.mfaTicket, b.mfaInstance = response.Ticket, response.LoginInstanceID
				return "code", nil
			}
			saved.Token = response.Token
		}
	}
	if saved.Token == "" {
		return "needs_login", nil
	}
	if strings.ContainsAny(saved.Token, "\r\n\t ") || len(saved.Token) > 4096 {
		return "", errors.New("discord_token_invalid")
	}
	client := session.New(saved.Token)
	b.client = client
	lifetime, stop := context.WithCancel(context.Background())
	b.stop = stop
	me, err := client.WithContext(ctx).Me()
	if err != nil {
		return "", errors.New("discord_sign_in_failed")
	}
	b.mu.Lock()
	b.ownID = me.ID
	b.mu.Unlock()
	client.AddHandler(func(event *gateway.ReadyEvent) {
		if lifetime.Err() != nil {
			return
		}
		for _, channel := range event.PrivateChannels {
			b.recordChannel(channel)
		}
	})
	client.AddHandler(func(event *gateway.ChannelCreateEvent) {
		if lifetime.Err() != nil {
			return
		}
		if event.Channel.Type == dc.DirectMessage || event.Channel.Type == dc.GroupDM {
			b.recordChannel(event.Channel)
		}
	})
	client.AddHandler(func(event *gateway.MessageCreateEvent) {
		if lifetime.Err() != nil || event.GuildID.IsValid() {
			return
		}
		b.c.Event(b.message(&event.Message))
	})
	if err := client.Open(ctx); err != nil {
		return "", errors.New("discord_gateway_failed")
	}
	if err := b.c.Save(saved); err != nil {
		return "", err
	}
	b.mfaTicket, b.mfaInstance = "", ""
	b.done = make(chan struct{})
	done := b.done
	go func() {
		defer close(done)
		_ = client.Wait(lifetime)
		if lifetime.Err() == nil {
			b.c.Event(map[string]any{"type": "connection", "state": "disconnected"})
		}
	}()
	return "connected", nil
}

func (b *backend) recordChannel(channel dc.Channel) map[string]any {
	b.mu.Lock()
	b.channels[channel.ID] = channel
	b.mu.Unlock()
	result := normalizeChannel(channel)
	raw := ""
	if channel.Type == dc.DirectMessage && len(channel.DMRecipients) == 1 {
		raw = channel.DMRecipients[0].AvatarURL()
	} else if channel.Type == dc.GroupDM {
		raw = channel.IconURL()
	}
	source := direct.AvatarID(raw)
	b.mu.Lock()
	b.media[source] = raw
	b.mu.Unlock()
	result["avatar_source"] = source
	b.c.Event(result)
	return result
}

func normalizeChannel(channel dc.Channel) map[string]any {
	title := channel.Name
	if title == "" {
		names := []string{}
		for _, recipient := range channel.DMRecipients {
			name := recipient.DisplayName
			if name == "" {
				name = recipient.Username
			}
			names = append(names, name)
		}
		title = strings.Join(names, ", ")
	}
	if title == "" {
		title = "Discord conversation"
	}
	result := map[string]any{"type": "chat", "id": channel.ID.String(), "title": title, "is_group": channel.Type == dc.GroupDM}
	if channel.LastMessageID.IsValid() {
		result["timestamp"] = channel.LastMessageID.Time().UnixMilli()
	}
	if channel.Type == dc.DirectMessage && len(channel.DMRecipients) == 1 {
		result["identity_id"] = channel.DMRecipients[0].ID.String()
	}
	return result
}

func (b *backend) Handle(ctx context.Context, req map[string]any) (any, error) {
	client := b.client.WithContext(ctx)
	// Retrying after a lost acknowledgement can send the same message twice.
	client.Client.Retries = 1
	op := direct.Text(req, "op")
	if op == "list_chats" {
		channels, err := client.PrivateChannels()
		if err != nil {
			return nil, errors.New("discord_chats_failed")
		}
		chats := []any{}
		for _, channel := range channels {
			chats = append(chats, b.recordChannel(channel))
		}
		return map[string]any{"chats": chats}, nil
	}
	if op == "start_conversation" {
		id, err := strconv.ParseUint(direct.Text(req, "recipient"), 10, 64)
		if err != nil || id == 0 {
			return nil, errors.New("discord_user_id_required")
		}
		channel, err := client.CreatePrivateChannel(dc.UserID(id))
		if err != nil {
			return nil, errors.New("discord_recipient_unavailable")
		}
		return b.recordChannel(*channel), nil
	}
	if op == "download_attachment" {
		b.mu.Lock()
		raw := b.media[direct.Text(req, "id")]
		b.mu.Unlock()
		if strings.HasPrefix(direct.Text(req, "id"), "avatar:") {
			return direct.DownloadAvatar(ctx, raw, "discordapp.com", "discordapp.net")
		}
		return direct.Download(ctx, raw, "discordapp.com", "discordapp.net")
	}
	id, err := strconv.ParseUint(direct.Text(req, "conversation_id"), 10, 64)
	if err != nil || id == 0 {
		return nil, errors.New("discord_channel_required")
	}
	channelID := dc.ChannelID(id)
	b.mu.Lock()
	_, known := b.channels[channelID]
	b.mu.Unlock()
	if !known {
		return nil, errors.New("discord_private_channel_required")
	}
	switch op {
	case "history":
		messages, err := client.Messages(channelID, uint(direct.Limit(req)))
		if err != nil {
			return nil, errors.New("discord_history_failed")
		}
		for _, message := range messages {
			event := b.message(&message)
			event["historical"] = true
			b.c.Event(event)
		}
		return map[string]any{"synced": len(messages)}, nil
	case "send_text", "send_attachment":
		data := api.SendMessageData{Content: direct.Text(req, "body"), AllowedMentions: &api.AllowedMentions{Parse: []api.AllowedMentionType{}}}
		if stable := direct.Text(req, "id"); stable != "" {
			hash := sha256.Sum256([]byte(stable))
			data.Nonce = hex.EncodeToString(hash[:12])
		}
		if reply := direct.Text(req, "reply_to_message_id"); reply != "" {
			messageID, err := strconv.ParseUint(reply, 10, 64)
			if err != nil || messageID == 0 {
				return nil, errors.New("discord_reply_invalid")
			}
			data.Reference = &dc.MessageReference{MessageID: dc.MessageID(messageID), ChannelID: channelID}
		}
		if op == "send_attachment" {
			encoded := direct.Text(req, "bytes")
			if len(encoded) > base64.StdEncoding.EncodedLen(10<<20) {
				return nil, errors.New("discord_attachment_too_large")
			}
			file, err := base64.StdEncoding.DecodeString(encoded)
			if err != nil || len(file) == 0 || len(file) > 10<<20 {
				return nil, errors.New("discord_attachment_invalid")
			}
			name := direct.Text(req, "name")
			if name == "" {
				name = "attachment"
			}
			data.Files = []sendpart.File{{Name: name, Reader: bytes.NewReader(file)}}
		}
		message, err := client.SendMessageComplex(channelID, data)
		if err != nil || message == nil {
			return nil, errors.New("discord_send_unconfirmed")
		}
		return b.message(message), nil
	default:
		return nil, errors.New("discord_operation_unavailable")
	}
}

func (b *backend) message(message *dc.Message) map[string]any {
	b.mu.Lock()
	ownID := b.ownID
	b.mu.Unlock()
	event := map[string]any{"type": "message", "conversation_id": message.ChannelID.String(), "id": message.ID.String(), "body": message.Content, "timestamp": message.Timestamp.Time().UnixMilli(), "sender_id": message.Author.ID.String(), "sender_name": message.Author.Username, "outgoing": message.Author.ID == ownID, "kind": "text"}
	if message.Reference != nil && message.Reference.MessageID.IsValid() {
		event["reply_to_message_id"] = message.Reference.MessageID.String()
	}
	attachments := []any{}
	for _, attachment := range message.Attachments {
		if !direct.MediaURL(attachment.URL, "discordapp.com", "discordapp.net") {
			continue
		}
		id := message.ID.String() + "/" + attachment.ID.String()
		b.mu.Lock()
		b.media[id] = attachment.URL
		b.mu.Unlock()
		mime := attachment.ContentType
		if mime == "" {
			mime = "application/octet-stream"
		}
		attachments = append(attachments, map[string]any{"id": id, "name": attachment.Filename, "mime_type": mime, "size": attachment.Size})
	}
	if len(attachments) > 0 {
		event["attachments"] = attachments
		event["kind"] = "file"
	}
	return event
}

func (b *backend) Close() error {
	if b.stop != nil {
		b.stop()
		b.stop = nil
	}
	if b.client != nil {
		_ = b.client.Close()
		b.client = nil
	}
	if b.done != nil {
		<-b.done
		b.done = nil
	}
	b.mfaTicket, b.mfaInstance = "", ""
	b.mu.Lock()
	b.channels = map[dc.ChannelID]dc.Channel{}
	b.media = map[string]string{}
	b.mu.Unlock()
	return nil
}
