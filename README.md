# Pallo

Pallo is a local-first universal messaging inbox for macOS. This repository currently contains the native vertical slice described in `docs/superpowers/plans/2026-08-12-pallo-native-vertical-slice.md`.

## Requirements

- Apple silicon Mac
- macOS 15 or later
- Xcode 26.5 or a compatible Swift 6.3 toolchain

## Commands

```bash
swift build
swift test
swift run Pallo
```

The first slice uses deterministic local fixtures. It does not connect real accounts or include Synapse yet.

`swift run` produces a bare executable rather than an `.app` bundle, and macOS starts
unbundled processes as background-only — the window draws but never becomes key, so it
takes no clicks and no keyboard input. `PalloAppDelegate` promotes the process to a
regular app at launch, which is what makes the window usable.

## Vertical slice behavior

The runnable app demonstrates this six-step flow:

1. The main window shows Maya once and Family separately.
2. Opening Maya shows WhatsApp and Instagram as distinct cards.
3. Opening Instagram and sending a message adds it only to the Instagram timeline.
4. Closing the main window leaves the menu-bar icon present.
5. Choosing **Open Pallo** from the menu restores the main window.
6. Choosing **Quit Pallo** removes the menu-bar item and ends the process.

Around that flow the shell provides a navigation rail (Inbox, Contacts, Settings), inbox
search and an unread filter, read state that clears when a conversation is opened,
sender-distinguished message bubbles, and Return-to-send in the composer.

All accounts, contacts, conversations, and messages in this vertical slice are deterministic fixtures, not real accounts or live service data. `Fixtures.snapshot` keeps fixed
timestamps for tests; the app seeds from `Fixtures.demoSnapshot`, the same data anchored
to launch time so relative dates read sensibly.
