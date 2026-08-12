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

## Vertical slice behavior

The runnable app demonstrates this six-step flow:

1. The main window shows Maya once and Family separately.
2. Opening Maya shows WhatsApp and Instagram as distinct cards.
3. Opening Instagram and sending a message adds it only to the Instagram timeline.
4. Closing the main window leaves the menu-bar icon present.
5. Choosing **Open Pallo** from the menu restores the main window.
6. Choosing **Quit Pallo** removes the menu-bar item and ends the process.

All accounts, contacts, conversations, and messages in this vertical slice are deterministic fixtures, not real accounts or live service data.
