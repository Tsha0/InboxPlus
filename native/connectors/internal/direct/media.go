package direct

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func MediaURL(raw string, domains ...string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || (u.Port() != "" && u.Port() != "443") {
		return false
	}
	host := strings.ToLower(u.Hostname())
	for _, domain := range domains {
		if host == domain || strings.HasSuffix(host, "."+domain) {
			return true
		}
	}
	return false
}

func Download(ctx context.Context, raw string, domains ...string) (any, error) {
	return download(ctx, raw, 32<<20, time.Minute, domains...)
}

func DownloadAvatar(ctx context.Context, raw string, domains ...string) (any, error) {
	return download(ctx, raw, 2<<20, 15*time.Second, domains...)
}

func download(ctx context.Context, raw string, limit int64, timeout time.Duration, domains ...string) (any, error) {
	if !MediaURL(raw, domains...) {
		return nil, errors.New("attachment_host_unavailable")
	}
	client := &http.Client{Timeout: timeout, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 || !MediaURL(req.URL.String(), domains...) {
			return errors.New("attachment_redirect_rejected")
		}
		return nil
	}}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return nil, errors.New("attachment_unavailable")
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, errors.New("attachment_download_failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK || response.ContentLength > limit {
		return nil, errors.New("attachment_download_failed")
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if err != nil || int64(len(data)) > limit {
		return nil, errors.New("attachment_download_failed")
	}
	return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data)}, nil
}

func AvatarID(raw string) string {
	if raw == "" {
		return ""
	}
	sum := sha256.Sum256([]byte(raw))
	return "avatar:" + hex.EncodeToString(sum[:])
}
