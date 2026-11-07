package direct

import (
	"context"
	"encoding/base64"
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
	if !MediaURL(raw, domains...) {
		return nil, errors.New("attachment_host_unavailable")
	}
	client := &http.Client{Timeout: time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
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
	if response.StatusCode != http.StatusOK || response.ContentLength > 32<<20 {
		return nil, errors.New("attachment_download_failed")
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, (32<<20)+1))
	if err != nil || len(data) > 32<<20 {
		return nil, errors.New("attachment_download_failed")
	}
	return map[string]any{"bytes": base64.StdEncoding.EncodeToString(data)}, nil
}
