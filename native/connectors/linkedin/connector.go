package linkedin

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/direct"
	"github.com/rs/zerolog"
	li "go.mau.fi/mautrix-linkedin/pkg/linkedingo"
)

func Capabilities() map[string]any {
	return map[string]any{"platform": "linkedIn", "send_text": true, "send_attachment": false, "download_attachment": true, "history_sync": true, "replies": false, "reactions": false, "start_conversation": false}
}

func New(id, directory string, key []byte, emit func(map[string]any)) (*direct.Connector, error) {
	return direct.New(id, directory, key, Capabilities(), emit, func(c *direct.Connector) direct.Backend {
		return &backend{c: c, media: map[string]string{}}
	})
}

type savedSession struct {
	Cookies *li.StringCookieJar `json:"cookies"`
	Headers http.Header         `json:"headers,omitempty"`
	UserID  string              `json:"user_id"`
}

type backend struct {
	c          *direct.Connector
	client     networkClient
	checkpoint *li.PasswordCheckpoint
	saved      savedSession
	mu         sync.Mutex
	media      map[string]string
	stop       context.CancelFunc
}

type networkClient interface {
	GetConversationsUpdatedBefore(context.Context, time.Time) (*li.CollectionResponse[li.ConversationCursorMetadata, li.Conversation], error)
	GetMessagesBefore(context.Context, li.URN, time.Time, int) (*li.CollectionResponse[li.MessageMetadata, li.Message], error)
	SendMessage(context.Context, li.URN, li.SendMessageBody, []li.SendRenderContent, string) (*li.MessageSentResponse, error)
	RealtimeConnect(context.Context) error
	RealtimeDisconnect()
}

func privateContext(ctx context.Context) context.Context {
	log := zerolog.Nop()
	return log.WithContext(ctx)
}

func (b *backend) Connect(ctx context.Context, req map[string]any) (string, error) {
	ctx = privateContext(ctx)
	var login *li.PasswordLoginSession
	var err error
	switch direct.Text(req, "op") {
	case "login_code":
		if b.checkpoint == nil {
			return "", errors.New("linkedin_verification_not_started")
		}
		login, err = b.checkpoint.SubmitCode(ctx, direct.Text(req, "code"))
	case "login_wait":
		if b.checkpoint == nil {
			return "", errors.New("linkedin_verification_not_started")
		}
		login, err = b.checkpoint.WaitForApp(ctx)
	default:
		if err = b.Close(); err != nil {
			return "", err
		}
		if direct.Text(req, "username") != "" && direct.Text(req, "password") != "" {
			login, err = li.NewPasswordLoginClient(nil).Login(ctx, direct.Text(req, "username"), direct.Text(req, "password"))
		} else {
			hasSession, loadErr := b.c.Load(&b.saved)
			if loadErr != nil {
				return "", loadErr
			}
			if !hasSession {
				return "needs_login", nil
			}
		}
	}
	if err != nil {
		var challenge *li.PasswordLoginError
		if errors.As(err, &challenge) && challenge.Checkpoint() != nil {
			b.checkpoint = challenge.Checkpoint()
			if b.checkpoint.Kind() == li.PasswordCheckpointApp {
				return "approval", nil
			}
			return "code", nil
		}
		return "", errors.New("linkedin_sign_in_failed")
	}
	if login != nil {
		b.saved = savedSession{Cookies: login.Cookies, Headers: login.BrowserHeaders}
	}
	if b.saved.Cookies == nil {
		return "needs_login", nil
	}
	probe := li.NewClient(ctx, li.NewURN(""), b.saved.Cookies, "", "", "", li.Handlers{})
	probe.SetBrowserHeaders(b.saved.Headers)
	profile, err := probe.GetCurrentUserProfile(ctx)
	if err != nil || profile == nil || profile.MiniProfile.EntityURN.ID() == "" {
		return "", errors.New("linkedin_session_rejected")
	}
	b.saved.UserID = profile.MiniProfile.EntityURN.ID()
	if err := b.c.Save(b.saved); err != nil {
		return "", err
	}
	b.checkpoint = nil
	lifetime, stop := context.WithCancel(privateContext(context.Background()))
	b.stop = stop
	client := li.NewClient(lifetime, profile.MiniProfile.EntityURN, b.saved.Cookies, "", "", "", li.Handlers{
		ClientConnection: func(context.Context, *li.ClientConnection) {
			if lifetime.Err() == nil {
				b.c.Event(map[string]any{"type": "connection", "state": "connected"})
			}
		},
		TransientDisconnect: func(context.Context, error) {
			if lifetime.Err() == nil {
				b.c.Event(map[string]any{"type": "connection", "state": "disconnected"})
			}
		},
		BadCredentials: func(context.Context, error) {
			if lifetime.Err() == nil {
				b.c.Event(map[string]any{"type": "connection", "state": "needs_login"})
			}
		},
		DecoratedEvent: func(_ context.Context, event *li.DecoratedEvent) {
			if lifetime.Err() != nil {
				return
			}
			data := event.Payload.Data
			if data.DecoratedConversation != nil {
				b.c.Event(b.chat(data.DecoratedConversation.Result))
			}
			if data.DecoratedMessage != nil {
				b.c.Event(b.message(data.DecoratedMessage.Result))
			}
		},
	})
	client.SetBrowserHeaders(b.saved.Headers)
	b.client = client
	if err := b.client.RealtimeConnect(lifetime); err != nil {
		stop()
		return "", errors.New("linkedin_realtime_failed")
	}
	return "connected", nil
}

func (b *backend) Handle(ctx context.Context, req map[string]any) (result any, resultErr error) {
	ctx = privateContext(ctx)
	defer func() {
		if err := b.c.Save(b.saved); err != nil {
			result, resultErr = nil, err
		}
	}()
	switch direct.Text(req, "op") {
	case "list_chats":
		before := time.Now().Add(time.Second)
		chats := []any{}
		seen := map[string]bool{}
		for {
			page, err := b.client.GetConversationsUpdatedBefore(ctx, before)
			if err != nil || page == nil {
				return nil, errors.New("linkedin_chats_failed")
			}
			added := 0
			for _, conversation := range page.Elements {
				id := conversation.EntityURN.String()
				if seen[id] {
					continue
				}
				seen[id] = true
				added++
				chats = append(chats, b.chat(conversation))
				for _, message := range conversation.Messages.Elements {
					if message.ConversationURN.IsEmpty() {
						message.ConversationURN = conversation.EntityURN
					}
					event := b.message(message)
					event["historical"] = true
					event["type"] = "message"
					b.c.Event(event)
				}
				if conversation.LastActivityAt.Time.Before(before) {
					before = conversation.LastActivityAt.Time
				}
			}
			if added == 0 || len(page.Elements) < 20 {
				break
			}
		}
		return map[string]any{"chats": chats}, nil
	case "history":
		conversation, err := conversationURN(req)
		if err != nil {
			return nil, err
		}
		page, err := b.client.GetMessagesBefore(ctx, conversation, time.Now().Add(time.Second), direct.Limit(req))
		if err != nil || page == nil {
			return nil, errors.New("linkedin_history_failed")
		}
		for _, message := range page.Elements {
			if message.ConversationURN.IsEmpty() {
				message.ConversationURN = conversation
			}
			event := b.message(message)
			event["historical"] = true
			event["type"] = "message"
			b.c.Event(event)
		}
		return map[string]any{"synced": len(page.Elements)}, nil
	case "send_text":
		conversation, err := conversationURN(req)
		if err != nil {
			return nil, err
		}
		response, err := b.client.SendMessage(ctx, conversation, li.SendMessageBody{Text: direct.Text(req, "body")}, nil, direct.Text(req, "id"))
		if err != nil || response == nil || response.Data.EntityURN.IsEmpty() {
			return nil, errors.New("linkedin_send_unconfirmed")
		}
		if response.Data.ConversationURN.IsEmpty() {
			response.Data.ConversationURN = conversation
		}
		return b.message(response.Data), nil
	case "download_attachment":
		b.mu.Lock()
		raw := b.media[direct.Text(req, "id")]
		b.mu.Unlock()
		if strings.HasPrefix(direct.Text(req, "id"), "avatar:") {
			return direct.DownloadAvatar(ctx, raw, "licdn.com", "linkedin.com")
		}
		return direct.Download(ctx, raw, "licdn.com", "linkedin.com")
	default:
		return nil, errors.New("linkedin_operation_unavailable")
	}
}

func conversationURN(req map[string]any) (li.URN, error) {
	id := direct.Text(req, "conversation_id")
	if !strings.HasPrefix(id, "urn:li:msg_conversation:") || len(id) > 2048 {
		return li.URN{}, errors.New("linkedin_conversation_invalid")
	}
	return li.NewURN(id), nil
}

func (b *backend) chat(conversation li.Conversation) map[string]any {
	names := []string{}
	identity := ""
	avatar := ""
	for _, participant := range conversation.ConversationParticipants {
		if participant.EntityURN.ID() == b.saved.UserID {
			continue
		}
		identity = participant.EntityURN.String()
		if member := participant.ParticipantType.Member; member != nil && member.ProfilePicture != nil {
			avatar = member.ProfilePicture.GetLargestArtifactURL()
		}
		names = append(names, participantName(participant))
	}
	title := conversation.Title
	if title == "" {
		title = strings.Join(names, ", ")
	}
	if title == "" {
		title = "LinkedIn conversation"
	}
	result := map[string]any{"type": "chat", "id": conversation.EntityURN.String(), "title": title, "is_group": conversation.GroupChat, "timestamp": conversation.LastActivityAt.Time.UnixMilli()}
	if !conversation.Read {
		result["unread_count"] = 1
	} else {
		result["unread_count"] = 0
	}
	if !conversation.GroupChat {
		source := direct.AvatarID(avatar)
		b.mu.Lock()
		b.media[source] = avatar
		b.mu.Unlock()
		result["avatar_source"] = source
	}
	if !conversation.GroupChat && identity != "" {
		result["identity_id"] = identity
	}
	return result
}

func participantName(participant li.MessagingParticipant) string {
	if member := participant.ParticipantType.Member; member != nil {
		return strings.TrimSpace(member.FirstName.Text + " " + member.LastName.Text)
	}
	if org := participant.ParticipantType.Organization; org != nil {
		return org.Name.Text
	}
	return "LinkedIn member"
}

func (b *backend) message(message li.Message) map[string]any {
	conversation := message.ConversationURN
	if conversation.IsEmpty() {
		conversation = message.Conversation.EntityURN
	}
	result := map[string]any{"type": "message", "id": message.EntityURN.String(), "conversation_id": conversation.String(), "body": message.Body.Text, "timestamp": message.DeliveredAt.Time.UnixMilli(), "sender_id": message.Sender.EntityURN.String(), "sender_name": participantName(message.Sender), "outgoing": message.Sender.EntityURN.ID() == b.saved.UserID, "kind": "text"}
	if message.MessageBodyRenderFormat == li.MessageBodyRenderFormatEdited {
		result["type"] = "message_edit"
	}
	attachments := []any{}
	for index, content := range message.RenderContent {
		raw, mime, name := "", "application/octet-stream", "LinkedIn attachment"
		if content.File != nil {
			raw, mime, name = content.File.URL, content.File.MediaType, content.File.Name
		}
		if content.VectorImage != nil {
			raw, mime, name = content.VectorImage.GetLargestArtifactURL(), "image/jpeg", "LinkedIn image"
		}
		if content.Audio != nil {
			raw, mime, name = content.Audio.URL, "audio/mp4", "LinkedIn audio"
		}
		if !direct.MediaURL(raw, "licdn.com", "linkedin.com") {
			continue
		}
		id := message.EntityURN.String() + "/" + strconv.Itoa(index)
		b.mu.Lock()
		b.media[id] = raw
		b.mu.Unlock()
		attachments = append(attachments, map[string]any{"id": id, "name": name, "mime_type": mime})
	}
	if len(attachments) > 0 {
		result["attachments"] = attachments
		result["kind"] = "file"
	}
	if len(message.RenderContent) > 0 && len(attachments) == 0 && message.Body.Text == "" {
		result["kind"], result["body"] = "unsupported", "This message type is unavailable in Inbox+."
	}
	return result
}

func (b *backend) Close() error {
	if b.stop != nil {
		b.stop()
		b.stop = nil
	}
	if b.client != nil {
		b.client.RealtimeDisconnect()
		b.client = nil
	}
	b.checkpoint = nil
	return nil
}
