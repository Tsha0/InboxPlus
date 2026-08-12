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
