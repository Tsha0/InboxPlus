# Agent autonomy

Agents read this file before merging, releasing, or touching a protected path. Only the owner
edits it. An agent may propose a change in a pull request, but never merges one that touches this
file.

**Current level: 1 — Propose**

| Level | Agents may also… | The owner still… |
| --- | --- | --- |
| 0 — Observe | File, triage and comment on issues | Writes or approves every code change |
| 1 — Propose | Open PRs and drive them to green; prepare releases | Merges every PR; starts every release |
| 2 — Merge | Merge their own PRs that meet every low-risk rule below | Merges every other PR; starts every release |
| 3 — Ship | Start an iOS TestFlight upload on the weekly cadence | Publishes macOS releases and anything that reaches the App Store or the Sparkle feed |

Each level includes everything above it.

## Low-risk PR

An agent may merge its own PR at level 2 or higher only when all of these hold:

- Every required check is green on the current head, and there is no merge conflict.
- A code-review pass at high effort, run after the last code change, left no unresolved blocking
  finding.
- The PR is labelled `risk:low`, and its body says why in one line.
- It changes at most 300 lines, not counting generated files.
- It fixes a bug, a flaky test, drift, CI, tests or docs. New features and visible UX changes wait
  for the owner, however small.
- It touches no protected path.

Anything else is `risk:high` and waits for the owner.

## Protected paths

A change to any of these waits for the owner, at every level.

- Agent rules: `docs/agents/autonomy.md`, `docs/agents/learnings.md`, `AGENTS.md`, `CLAUDE.md`,
  `.claude/**`.
- CI and release: `.github/workflows/**`, `Scripts/package-release.sh`, `Scripts/sign-bundled-runtime.sh`,
  `Scripts/embed-sparkle.sh`, `Scripts/generate-update-feed.sh`, `Scripts/validate-update-feed.py`,
  `Scripts/inboxplus.entitlements`, `Scripts/ci/release-ios.sh`, `Scripts/ci/verify-release.py`,
  `Scripts/ci/release-preflight.py`.
- What code gets executed: `Package.swift`, `Package.resolved`, `Runtime/**`,
  `Sources/InboxPlusBridge/BridgeCatalog.swift`, `Sources/InboxPlusBridgeService/LibolmProvisioner.swift`.
- Secrets and trust: Keychain code (`MatrixKeychain.swift`, `PairingKeychain.swift`),
  `DiagnosticsRedactor.swift`, `DeepLink.swift`, `CookieLoginWebView.swift`,
  `Sources/InboxPlusCompanionServer/**`.
- `LICENSE`, and identifiers that must stay stable between releases (`com.inboxplus.app`,
  `com.inboxplus.ios`, profile paths, Keychain service names).

## Never, at any level

- Run anything against a real messaging account or a real profile. Networks ban accounts
  permanently. Live tests stay opt-in and off.
- Read, print, move or commit secrets, signing material, cookies, tokens or pairing keys.
- Push to `main`, force-push, rewrite history, or delete a branch that is not the agent's own.
- Skip, disable or delete a test, or weaken an assertion, to get CI green. Raising a timeout that
  guards a real process on slow CI is allowed when the PR states the measured run time.
- Publish to the Sparkle feed, publish a GitHub Release, or submit to the App Store.
- Change the autonomy level, or merge a PR that touches a protected path.
