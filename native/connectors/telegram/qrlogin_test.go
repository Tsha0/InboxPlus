package telegram

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gotd/td/bin"
	gotd "github.com/gotd/td/telegram"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

// qrBackend runs the real gotdBackend QR flow against scripted auth.exportLoginToken answers,
// without a network connection.
func qrBackend(t *testing.T, export func(call int32) (bin.Encoder, error)) (*gotdBackend, *atomic.Int32) {
	t.Helper()
	var calls atomic.Int32
	hash := strings.Repeat("a", 32)
	b := newGotdBackend("fixture-account", 1, hash, nil, func(map[string]any) {})
	scripted := gotd.MiddlewareFunc(func(tg.Invoker) gotd.InvokeFunc {
		return func(_ context.Context, input bin.Encoder, output bin.Decoder) error {
			if _, ok := input.(*tg.AuthExportLoginTokenRequest); !ok {
				return errors.New("unexpected request")
			}
			result, err := export(calls.Add(1))
			if err != nil {
				return err
			}
			var buffer bin.Buffer
			if err := result.Encode(&buffer); err != nil {
				return err
			}
			return output.Decode(&buffer)
		}
	})
	b.client = gotd.NewClient(1, hash, gotd.Options{
		UpdateHandler: gotd.UpdateHandlerFunc(b.routeUpdates),
		Middlewares:   []gotd.Middleware{scripted},
	})
	return b, &calls
}

func qrToken(expiresIn time.Duration) bin.Encoder {
	return &tg.AuthLoginToken{Token: []byte("fixture"), Expires: int(time.Now().Add(expiresIn).Unix())}
}

func qrAccepted() bin.Encoder {
	return &tg.AuthLoginTokenSuccess{Authorization: &tg.AuthAuthorization{User: &tg.User{ID: 7}}}
}

func scan(b *gotdBackend) {
	_ = b.routeUpdates(context.Background(), &tg.UpdateShort{Update: &tg.UpdateLoginToken{}})
}

func TestQRScanOfTwoStepAccountAsksForPassword(t *testing.T) {
	b, _ := qrBackend(t, func(call int32) (bin.Encoder, error) {
		if call == 1 {
			return qrToken(time.Minute), nil
		}
		return nil, tgerr.New(401, "SESSION_PASSWORD_NEEDED")
	})
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.QRLogin(ctx, func(string) { scan(b) }); !errors.Is(err, errPasswordNeeded) {
		t.Fatalf("scan of a two-step account returned %v", err)
	}
}

func TestQRRetryAfterAcceptedScanCompletesSignIn(t *testing.T) {
	b, _ := qrBackend(t, func(call int32) (bin.Encoder, error) {
		switch call {
		case 1:
			return qrToken(time.Minute), nil
		case 2:
			return nil, tgerr.New(500, "INTERNAL_SERVER_ERROR")
		}
		return qrAccepted(), nil
	})
	if err := b.QRLogin(context.Background(), func(string) { scan(b) }); err == nil {
		t.Fatal("the scripted import failure did not fail the first attempt")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.QRLogin(ctx, func(string) { t.Error("an accepted scan showed a new code") }); err != nil {
		t.Fatalf("retry after an accepted scan returned %v", err)
	}
	if b.selfID != 7 {
		t.Fatal("retry did not adopt the scanned account")
	}
}

func TestQRScanAcceptedWhileNoAttemptRanCompletesSignIn(t *testing.T) {
	b, _ := qrBackend(t, func(int32) (bin.Encoder, error) { return qrAccepted(), nil })
	scan(b)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.QRLogin(ctx, func(string) {}); err != nil {
		t.Fatalf("a scan accepted between attempts returned %v", err)
	}
}

func TestQRRefreshDoesNotSpinWhenClockIsAheadOfTelegram(t *testing.T) {
	b, calls := qrBackend(t, func(int32) (bin.Encoder, error) { return qrToken(-time.Minute), nil })
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	var shown atomic.Int32
	_ = b.QRLogin(ctx, func(string) { shown.Add(1) })
	if shown.Load() != 1 || calls.Load() != 1 {
		t.Fatalf("one second showed %d codes from %d exports", shown.Load(), calls.Load())
	}
}
