package meta

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"maps"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Tsha0/InboxPlus/native/connectors/internal/securedb"
	"github.com/rs/zerolog"
	globalLog "github.com/rs/zerolog/log"
	"go.mau.fi/mautrix-meta/pkg/instameow"
	"go.mau.fi/mautrix-meta/pkg/messagix/cookies"
	"go.mau.fi/mautrix-meta/pkg/messagix/responses"
	"go.mau.fi/mautrix-meta/pkg/messagix/types"
)

const maxMediaBytes = 32 << 20

func init() { globalLog.Logger = zerolog.Nop() }

type sessionState struct {
	Cookies   map[cookies.MetaCookieName]string `json:"cookies"`
	SeqID     int64                             `json:"seq_id"`
	SeqTime   time.Time                         `json:"seq_time"`
	Reconnect json.RawMessage                   `json:"reconnect,omitempty"`
}

type mediaReference struct {
	URL           string
	MimeType      string
	Name          string
	ReelID        string
	ReelShortcode string
}

type instagramThread struct {
	isGroup    bool
	identityID string
}

type Connector struct {
	accountID        string
	platform         string
	ownID            string
	directory        string
	key              []byte
	emit             func(map[string]any)
	mu               sync.Mutex
	stateMu          sync.Mutex
	state            sessionState
	ig               *instameow.Client
	fb               *fbAdapter
	cancel           context.CancelFunc
	ready            bool
	transportReady   atomic.Bool
	restartRequired  atomic.Bool
	storageFailed    atomic.Bool
	mediaMu          sync.Mutex
	media            map[string]mediaReference
	threadKeys       map[string]int64
	threadMu         sync.RWMutex
	instagramThreads map[string]instagramThread
	fetchMedia       func(ctx context.Context, mediaID, shortcode string) (*responses.FetchMediaResponse, error)
}

func New(req map[string]any, emit func(map[string]any)) (*Connector, error) {
	key, err := base64.StdEncoding.DecodeString(str(req, "key"))
	if err != nil || len(key) != 32 {
		return nil, errors.New("a 32-byte encryption key is required")
	}
	accountID, directory, platform := str(req, "account_id"), str(req, "directory"), str(req, "platform")
	if accountID == "" || directory == "" || !filepath.IsAbs(directory) {
		return nil, errors.New("account and absolute storage directory are required")
	}
	if platform != "instagram" && platform != "messenger" {
		return nil, errors.New("unsupported Meta platform")
	}
	if err = securedb.SecureDirectory(directory); err != nil {
		return nil, errors.New("cannot protect account storage")
	}
	if emit == nil {
		emit = func(map[string]any) {}
	}
	c := &Connector{accountID: accountID, platform: platform, directory: directory, key: key,
		emit: emit, media: make(map[string]mediaReference), threadKeys: make(map[string]int64)}
	if err = c.loadState(); err != nil {
		return nil, err
	}
	if platform == "messenger" {
		c.fb = &fbAdapter{c: c}
	}
	return c, nil
}

func str(req map[string]any, key string) string {
	v, _ := req[key].(string)
	return v
}

func replyTarget(req map[string]any) *string {
	id := str(req, "reply_to_message_id")
	if id == "" {
		return nil
	}
	return &id
}

func (c *Connector) Handle(ctx context.Context, req map[string]any) (data any, resultErr error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.storageFailed.Load() && str(req, "op") != "disconnect" && str(req, "op") != "logout" && str(req, "op") != "capabilities" {
		return nil, errors.New("encrypted session could not be saved; reopen the account before reconnecting")
	}
	op := str(req, "op")
	if op == "send_text" || op == "send_attachment" || op == "react" || op == "history" || op == "list_chats" {
		defer func() {
			var jar *cookies.Cookies
			if c.ig != nil {
				jar = c.ig.GetCookies()
			} else if c.fb != nil && c.fb.client != nil {
				jar = c.fb.client.GetCookies()
			}
			if jar != nil {
				if err := c.updateCookies(jar); err != nil {
					data, resultErr = nil, err
				}
			}
		}()
	}
	log := zerolog.Nop()
	ctx = log.WithContext(ctx)
	switch op {
	case "capabilities":
		return c.capabilities(), nil
	case "login", "connect":
		return c.connect(ctx, req)
	case "disconnect":
		return map[string]any{"state": "disconnected"}, c.close()
	case "logout":
		return map[string]any{"state": "logged_out", "remote_session_revoked": false}, c.logout()
	case "send_text":
		if !c.ready {
			return nil, errors.New("account is not connected")
		}
		if c.fb == nil && !c.transportReady.Load() {
			return nil, errors.New("account is not connected")
		}
		conversationID, body := str(req, "conversation_id"), str(req, "body")
		if conversationID == "" || body == "" {
			return nil, errors.New("conversation and message text are required")
		}
		if c.fb != nil {
			return c.fb.sendText(ctx, conversationID, body, str(req, "reply_to_message_id"))
		}
		return c.sendInstagramText(ctx, req)
	case "send_attachment":
		if !c.ready {
			return nil, errors.New("account is not connected")
		}
		if c.fb == nil && !c.transportReady.Load() {
			return nil, errors.New("account is not connected")
		}
		if c.fb != nil {
			return nil, errors.New("Messenger attachment sending is not available")
		}
		return c.sendInstagramAttachment(ctx, req)
	case "react":
		if !c.ready || (c.fb == nil && !c.transportReady.Load()) {
			return nil, errors.New("account is not connected")
		}
		if str(req, "conversation_id") == "" || str(req, "message_id") == "" || len(str(req, "emoji")) > 256 {
			return nil, errors.New("invalid reaction target")
		}
		if c.fb != nil {
			return c.fb.react(ctx, req)
		}
		return c.reactInstagram(ctx, req)
	case "history", "list_chats":
		if !c.ready {
			return nil, errors.New("account is not connected")
		}
		if c.fb != nil {
			return c.fb.history(ctx, req)
		}
		return c.instagramHistory(ctx, req)
	case "download_attachment":
		return c.download(ctx, str(req, "id"))
	default:
		return nil, errors.New("unsupported Meta operation")
	}
}

func (c *Connector) connect(ctx context.Context, req map[string]any) (any, error) {
	_, supplied := req["cookies"]
	if c.ready && (supplied || c.restartRequired.Load()) {
		if err := c.close(); err != nil {
			return nil, err
		}
	}
	if c.ready {
		connected := c.transportReady.Load()
		if c.fb != nil {
			c.fb.mu.Lock()
			connected = c.fb.ready
			c.fb.mu.Unlock()
		}
		state := "connecting"
		if connected {
			state = "connected"
		}
		return map[string]any{"state": state, "capabilities": c.capabilities()}, nil
	}
	values := make(map[cookies.MetaCookieName]string)
	c.stateMu.Lock()
	for name, value := range c.state.Cookies {
		values[name] = value
	}
	c.stateMu.Unlock()
	if raw, ok := req["cookies"]; ok {
		values = make(map[cookies.MetaCookieName]string)
		data, err := json.Marshal(raw)
		if err != nil || json.Unmarshal(data, &values) != nil {
			return nil, errors.New("invalid login cookies")
		}
	}
	platform, required := types.Instagram, cookies.IGRequiredCookies
	if c.fb != nil {
		platform, required = types.Facebook, cookies.FBRequiredCookies
	}
	filtered := make(map[cookies.MetaCookieName]string, len(required))
	for _, name := range required {
		value := values[name]
		if value == "" || strings.ContainsAny(value, "\r\n;") {
			return nil, errors.New("required login cookies are missing or invalid")
		}
		filtered[name] = value
	}
	jar := &cookies.Cookies{Platform: platform}
	jar.UpdateValues(filtered)
	if jar.GetUserID() <= 0 {
		return nil, errors.New("login user identifier is invalid")
	}
	c.stateMu.Lock()
	if _, supplied := req["cookies"]; supplied {
		c.state.Reconnect = nil
		c.state.SeqID, c.state.SeqTime = 0, time.Time{}
	}
	c.state.Cookies = filtered
	c.stateMu.Unlock()
	if c.fb != nil {
		result, err := c.fb.connect(ctx, jar)
		if err != nil {
			_ = c.close()
			return nil, err
		}
		c.ready = true
		if err = c.saveState(); err != nil {
			_ = c.close()
			return nil, err
		}
		return result, nil
	}
	return c.connectInstagram(ctx, jar)
}

func (c *Connector) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.close()
}

func (c *Connector) HasSession() bool {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()
	return len(c.state.Cookies) != 0
}

func (c *Connector) close() error {
	if c.cancel != nil {
		c.cancel()
		c.cancel = nil
	}
	if c.ig != nil {
		c.ig.Disconnect()
		c.ig = nil
	}
	var err error
	if c.fb != nil {
		err = c.fb.close()
	}
	c.ready = false
	c.transportReady.Store(false)
	c.restartRequired.Store(false)
	return err
}

func (c *Connector) logout() error {
	if err := c.close(); err != nil {
		return err
	}
	path := filepath.Join(c.directory, "meta-session.enc")
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("cannot remove encrypted session")
	}
	c.stateMu.Lock()
	c.state = sessionState{}
	c.stateMu.Unlock()
	c.mediaMu.Lock()
	clear(c.media)
	c.mediaMu.Unlock()
	c.threadMu.Lock()
	clear(c.threadKeys)
	clear(c.instagramThreads)
	c.threadMu.Unlock()
	c.ownID = ""
	return nil
}

func (c *Connector) updateCookies(jar *cookies.Cookies) error {
	values := jar.GetAll()
	c.stateMu.Lock()
	changed := !maps.Equal(c.state.Cookies, values)
	c.state.Cookies = values
	c.stateMu.Unlock()
	if changed {
		return c.saveState()
	}
	return nil
}

func (c *Connector) aead() (cipher.AEAD, error) {
	block, err := aes.NewCipher(c.key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

func (c *Connector) loadState() error {
	path := filepath.Join(c.directory, "meta-session.enc")
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil || !info.Mode().IsRegular() {
		return errors.New("cannot read encrypted session")
	}
	if err = securedb.SecureFile(path); err != nil {
		return errors.New("cannot protect encrypted session")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return errors.New("cannot read encrypted session")
	}
	aead, err := c.aead()
	if err != nil || len(data) < aead.NonceSize() {
		return errors.New("encrypted session is invalid")
	}
	plain, err := aead.Open(nil, data[:aead.NonceSize()], data[aead.NonceSize():], []byte(c.accountID+"\x00"+c.platform))
	defer clear(plain)
	if err != nil || json.Unmarshal(plain, &c.state) != nil {
		return errors.New("cannot unlock encrypted session")
	}
	return nil
}

func (c *Connector) saveState() (saveErr error) {
	defer func() {
		if saveErr != nil && c.storageFailed.CompareAndSwap(false, true) {
			c.emit(map[string]any{"type": "connection", "account_id": c.accountID, "state": "error", "error": "Encrypted session could not be saved; reopen the account before reconnecting"})
			go func() { c.mu.Lock(); defer c.mu.Unlock(); _ = c.close() }()
		}
	}()
	c.stateMu.Lock()
	defer c.stateMu.Unlock()
	plain, err := json.Marshal(c.state)
	defer clear(plain)
	if err != nil {
		return errors.New("cannot encode encrypted session")
	}
	aead, err := c.aead()
	if err != nil {
		return errors.New("cannot encrypt session")
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return errors.New("cannot encrypt session")
	}
	data := aead.Seal(nonce, nonce, plain, []byte(c.accountID+"\x00"+c.platform))
	f, err := os.CreateTemp(c.directory, ".meta-session-*")
	if err != nil {
		return errors.New("cannot save encrypted session")
	}
	name := f.Name()
	defer os.Remove(name)
	if err = securedb.SecureFile(name); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err == nil {
		err = securedb.ReplaceSnapshot(name, filepath.Join(c.directory, "meta-session.enc"))
	}
	if err != nil {
		return errors.New("cannot save encrypted session")
	}
	return nil
}

func allowedMediaURL(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	for _, domain := range []string{"cdninstagram.com", "fbcdn.net", "facebook.com", "instagram.com"} {
		if host == domain || strings.HasSuffix(host, "."+domain) {
			return true
		}
	}
	return false
}

func (c *Connector) download(ctx context.Context, id string) (any, error) {
	c.mediaMu.Lock()
	ref, ok := c.media[id]
	c.mediaMu.Unlock()
	if ok && ref.ReelID != "" {
		resolved, err := c.resolveReelVideo(ctx, ref)
		if err != nil {
			return nil, err
		}
		ref.URL = resolved
	}
	if !ok || !allowedMediaURL(ref.URL) {
		return nil, errors.New("attachment is unavailable; reload its conversation")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, ref.URL, nil)
	if err != nil {
		return nil, errors.New("cannot download attachment")
	}
	client := &http.Client{Timeout: 90 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 || !allowedMediaURL(req.URL.String()) {
			return errors.New("attachment redirect is not allowed")
		}
		return nil
	}}
	resp, err := client.Do(req)
	if err != nil {
		return nil, errors.New("cannot download attachment")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, errors.New("attachment download failed; reload its conversation")
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxMediaBytes+1))
	if err != nil || len(data) > maxMediaBytes {
		return nil, errors.New("attachment download failed or exceeds 32 MiB")
	}
	mime := ref.MimeType
	if mime == "" {
		mime = http.DetectContentType(data)
	}
	return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data), "mime_type": mime, "name": ref.Name}, nil
}

// Reel video URLs expire quickly, so they are looked up only when the user asks to play one.
func (c *Connector) resolveReelVideo(ctx context.Context, ref mediaReference) (string, error) {
	fetch := c.fetchMedia
	if fetch == nil {
		client := c.ig
		if client == nil || !c.ready {
			return "", errors.New("account is not connected")
		}
		fetch = client.FetchMedia
	}
	resp, err := fetch(ctx, ref.ReelID, ref.ReelShortcode)
	if err != nil || resp == nil || len(resp.Items) == 0 || resp.Items[0] == nil {
		return "", errors.New("this Reel is unavailable; open it in Instagram")
	}
	video := playableReelURL(resp.Items[0].VideoVersions)
	if video == "" {
		return "", errors.New("this Reel is unavailable; open it in Instagram")
	}
	return video, nil
}

// playableReelURL prefers the sharpest version that fits a phone screen; full-resolution Reels
// often exceed the attachment size limit.
func playableReelURL(versions []responses.VideoVersions) string {
	var best, smallest *responses.VideoVersions
	for i := range versions {
		version := &versions[i]
		if !allowedMediaURL(version.URL) {
			continue
		}
		if smallest == nil || version.Width < smallest.Width {
			smallest = version
		}
		if version.Width <= 720 && (best == nil || version.Width > best.Width) {
			best = version
		}
	}
	if best == nil {
		best = smallest
	}
	if best == nil {
		return ""
	}
	return best.URL
}

func (c *Connector) rememberMedia(id, raw, mime, name string) map[string]any {
	if id == "" || !allowedMediaURL(raw) {
		return nil
	}
	c.mediaMu.Lock()
	c.media[id] = mediaReference{URL: raw, MimeType: mime, Name: name}
	c.mediaMu.Unlock()
	return map[string]any{"id": id, "name": name, "mime_type": mime, "downloadable": true}
}

func decimal(value int64) string { return strconv.FormatInt(value, 10) }

func (c *Connector) capabilities() map[string]any {
	return Capabilities(c.platform)
}

func Capabilities(platform string) map[string]any {
	if platform != "instagram" && platform != "messenger" {
		return nil
	}
	return map[string]any{"cookie_login": true, "send_text": true, "send_attachment": platform == "instagram",
		"download_attachment": true, "history": true, "encrypted_chats": false,
		"attachment_captions": false, "attachment_kinds": []string{"image", "video", "audio"}, "start_conversation": false,
		"replies": true, "reactions": true, "max_attachment_bytes": maxMediaBytes}
}
