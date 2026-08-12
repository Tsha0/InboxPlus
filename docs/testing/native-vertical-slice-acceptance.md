# Native Vertical Slice Acceptance

## Automated

- `swift test` passes.
- `swift build -c release` passes.
- Contact linking is explicit and one-to-one per remote identity.
- Linked inbox aggregation sums unread counts and orders by newest activity.
- Route-safety test proves an Instagram send does not enter the WhatsApp route.
- Every platform badge has an accessible network name.
- Startup failure produces a visible needs-attention state.

## Manual

- Run `swift run Pallo` on Apple silicon/macOS 15+.
- Verify the compact three-pane layout at 900×600 and larger.
- Verify keyboard navigation reaches inbox rows, contact cards, composer, send, and menu-bar actions.
- Verify VoiceOver announces platform names without visible network-name labels.
- Verify Maya opens a contact summary before either network conversation.
- Verify closing the window preserves the menu-bar process and Open Pallo restores it.
- Verify Quit Pallo terminates the process.

## Out of scope for this gate

Synapse, Matrix encryption, bridge provisioning, real accounts, media, launch at login, signed updates, notarization, and uninstallation are covered by later roadmap phases.

## Latest result

Recorded 2026-08-13 00:05 SGT.

### Environment

- Architecture: Apple silicon (`arm64`).
- macOS: 26.5.1 (build 25F80).
- Swift: 6.3.2 (`swiftlang-6.3.2.1.108`, target `arm64-apple-macosx26.0`).
- Xcode: 26.5 (build 17F42).

### Automated result

- `swift test`: PASS (34 tests, 0 failures).
- `swift build -c release`: PASS.
- `swift build -c release -Xswiftc -warnings-as-errors`: PASS with no warnings.
- `git diff --check`: PASS with no output.

### Manual result

| Item | Result | Evidence |
| --- | --- | --- |
| Run `swift run Pallo` on Apple silicon/macOS 15+ | PASS | The product built, launched on the environment above, and remained running until explicitly interrupted. |
| Compact three-pane layout at 900×600 and larger | UNVERIFIED | Computer Use rejected `Pallo` as an addressable app, and its running-app inventory contained no Pallo entry, so no app screenshot or accessibility tree was available. |
| Keyboard navigation reaches inbox rows, contact cards, composer, send, and menu-bar actions | UNVERIFIED | No addressable app accessibility tree was available for keyboard traversal. |
| VoiceOver announces platform names without visible network-name labels | UNVERIFIED | No addressable app accessibility tree was available for VoiceOver inspection. |
| Maya opens a contact summary before either network conversation | UNVERIFIED | No addressable app accessibility tree was available for interaction. |
| Closing the window preserves the menu-bar process and Open Pallo restores it | UNVERIFIED | No addressable app accessibility tree was available for window or menu-bar interaction. |
| Quit Pallo terminates the process | UNVERIFIED | The menu-bar Quit action could not be reached. The test process was instead interrupted from its launching terminal, after which `pgrep -x Pallo` confirmed that no Pallo process remained. |

There were no observed manual failures. Six UI-only items remain environment-caused
`UNVERIFIED`; they require a bundled app or a human-run pass on a host that exposes
the launched Pallo process to macOS accessibility tooling.
