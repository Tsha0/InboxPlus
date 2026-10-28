# Inbox+ (macOS)

Inbox+ is a local-first universal messaging inbox for macOS: a SwiftUI app, a local Synapse
homeserver and network bridges, all running on the user's Mac. `README.md` covers the
architecture and the module map.

Sibling repo: `Tsha0/InboxPlus-IOS`, the iOS app and its Mac companion. It has its own copy of the
shared modules (Core, Features, Gateway, Bridge, BridgeService, UI, Matrix, Runtime, IMessage,
RuntimeCLI, App). That copy was imported from this repo at `2b819ad` and both have changed since,
so a fix to a shared module here usually needs porting there.

## Rules

- `AGENTS.md` holds the code review rules. Breaking one is a P1.
- `docs/agents/autonomy.md` says what an agent may do without the owner. Read it before merging,
  releasing, or touching a protected path.
- Never run anything against a real messaging account or profile; networks ban accounts for good.
  Live tests are opt-in (`INBOXPLUS_RUNTIME_PYTHON`) and stay off.
- Never print, log, move or commit secrets, signing material, cookies or tokens.

## Build and test (macOS 15+, Xcode 26 / Swift 6.2+)

```bash
swift build
swift test                                          # default suite; no live accounts
python3 -m unittest discover -s Tests/Packaging -v
bash Tests/Packaging/verify-signed-feed.sh
Scripts/build-app.sh                                # builds build/Inbox+.app, ad-hoc signed
```

CI fails if a generated file is stale. README → Contributing has the three regenerate commands.

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), one folder per module under
`Tests/`. A test that waits on a real process needs a deadline sized for slow CI runners.

## In a cloud container (Linux, no Swift)

The app is macOS-only, so nothing here compiles on Linux. These checks do run:

```bash
python3 -m unittest discover -s Tests/Packaging
bash -n Scripts/*.sh
git diff --check
```

CI checks everything else on the pull request: **Build and test**, **Generated files are
current**, and **Package the app**. Push, wait for the checks, and report what CI showed. Never
claim a Swift test passed unless you saw it pass. Each CI round takes about 15 minutes, so check
the diff for compile and Swift 6 concurrency errors before pushing.

## Improvement loop

Agents improve both repos on a schedule. The map is `docs/agents/loop.md`. The procedures are in
`.claude/skills/` (`scout`, `work`, `steward`, `release`, `retro`). Read `docs/agents/learnings.md`
before starting work.
