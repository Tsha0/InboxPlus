# Contributing to Inbox+

This guide applies to human and AI-assisted contributions. Contributors are responsible for
understanding their changes and checking the resulting behavior. Follow the critical architecture,
security and lifecycle rules in [AGENTS.md](AGENTS.md#code-review-rules).

## Setup

Use an Apple silicon Mac with macOS 15 or later and Swift 6.2 or newer. See the
[README requirements](README.md#requirements) for the development toolchain and the additional
Python, CMake and Rust tools used by runtime and bundle builds.

Run commands from the repository root:

```bash
swift build
swift test
swift run InboxPlus
```

Without a bundled runtime or prepared profile, the app opens an empty inbox without connecting to
a network. For profile setup and real-runtime development, follow [Developing](README.md#developing).
For a double-clickable app, use [Build from source](README.md#build-from-source).

## Scope and architecture

- Keep each change focused on one behavior or problem. Inspect neighboring code and tests first;
  separate unrelated cleanup or broad formatting from behavior changes.
- Use the [module overview](README.md#how-it-fits-together) and `Package.swift` to find the owning
  target. Preserve the dependency boundaries in `AGENTS.md`.
- UI and feature code use `MessagingGateway`. Put Matrix-specific handling in `InboxPlusMatrix`;
  test feature behavior with the existing fake gateway and test support.
- Keep bridge protocol models and catalog data in `InboxPlusBridge`. Installation, configuration
  and interaction with real bridge processes belong in `InboxPlusBridgeService`.
- Do not add speculative compatibility shims, dependencies or abstractions for hypothetical future
  requirements. A new dependency must meet the existing exact-version and licensing requirements;
  see [dependencies](docs/dependencies.md).

## Code style

- Match the surrounding Swift style, including indentation, wrapping and declaration organization.
  There is currently no repository-wide formatter configured; avoid bulk reformatting.
- Use names that convey domain meaning, such as `pendingSend` or `profileDirectory`. Avoid unclear
  abbreviations and redundant type suffixes.
- Prefer editing existing files. Add a file when introducing a distinct component, not just to wrap
  a trivial operation.
- Reuse established helpers and components. Extract a helper when it removes meaningful duplication
  or names an operation that makes the caller clearer; avoid single-use forwarding layers.
- Validate external input at the boundary that owns it, then pass typed values inward. Do not add
  repeated checks for cases already excluded by internal types or established invariants.
- Handle realistic failures explicitly. Do not silently discard errors or add fallbacks for cases
  that cannot happen. Keep sensitive values out of logs and error descriptions.
- Add comments only when the reason or constraint is non-obvious. Remove obsolete comments and dead
  code touched by the change; do not narrate obvious assignments or control flow.
- Reuse the existing UI controls and conventions in
  [InboxPlusTheme.swift](Sources/InboxPlusUI/InboxPlusTheme.swift) and
  [ViewStyling.swift](Sources/InboxPlusUI/ViewStyling.swift) before adding new styling.

## Verification

Choose checks based on the affected behavior. Run focused tests while iterating, then the relevant
broader checks before submitting. Reuse successful results while their inputs remain unchanged.
Document checks you could not run and why; do not present an untested path as verified.

| Change | Local verification |
| --- | --- |
| Swift behavior | Relevant tests via `swift test --filter <test-name-or-pattern>`; `swift test` for the default suite |
| Module dependencies or shared contracts | `swift build --build-tests` and `swift test` |
| UI behavior or layout | Relevant tests plus visual inspection of affected states; include screenshots or a recording |
| Packaging or updates | Packaging checks below and, when bundle assembly is affected, the bundle checks |
| Icons, brand marks or dependency inventory | Regenerate affected outputs using the commands below and inspect the diff |
| Runtime integration | Relevant runtime tests; opt-in real-runtime tests when needed, clearly distinguished from fixture coverage |
| Documentation only | Check links, paths and commands against the repository, and run `git diff --check` |

Add a regression test for a bug fix and tests for new behavior when practical. Follow nearby test
patterns, use existing fixtures and fakes, and test observable behavior rather than duplicating the
implementation. Explain when automated coverage is impractical. For UI changes, inspect affected
loading, empty, error and cancellation states where applicable.

The default Swift suite does not require live accounts or a homeserver. Real Synapse tests are
opt-in because they download dependencies and start processes:

```bash
INBOXPLUS_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test
```

To exercise first-install setup using an already built app's bundled runtime:

```bash
INBOXPLUS_SETUP_RUNTIME_PACKAGE_ROOT="/Applications/Inbox+.app/Contents/Resources" swift test --filter realBridgeFirstInstallRefreshesServicesAndRestoresTheInboxWithoutRelaunching
```

This uses an isolated profile, downloads and verifies the pinned Instagram bridge, refreshes the
app-owned runtime, and restores the Matrix session. It checks that sign-in methods are available;
it does not sign into Instagram or read any real account.

These tests do not touch real network accounts. Passing fixture or local-runtime tests does not
certify a network's live login or messaging behavior. Timeouts for real processes must be generous
enough for slower CI runners: they guard against hangs, not assert developer-machine speed.

### Packaging checks

These commands mirror the packaging-script checks in CI:

```bash
python3 -m unittest discover -s Tests/Packaging -v
bash Tests/Packaging/verify-signed-feed.sh
bash Tests/Packaging/verify-self-signed-identity.sh
bash -n Scripts/embed-sparkle.sh Scripts/generate-update-feed.sh Scripts/package-release.sh Scripts/build-app.sh Scripts/create-signing-certificate.sh
```

When bundle assembly is affected, build and verify the local app without installing it:

```bash
Scripts/build-app.sh
codesign --verify --strict build/Inbox+.app
build/Inbox+.app/Contents/MacOS/InboxPlusRuntimeCLI sbom > /dev/null
otool -L build/Inbox+.app/Contents/MacOS/InboxPlus | grep -q '/AVKit.framework/'
```

The default bundle is ad-hoc signed. Release signing and publishing follow
[the update guide](docs/updates.md).

## Reporting UI findings

During UI exploration, record actionable bugs, usability and accessibility problems, and feature
gaps with a concrete user impact. For example, losing a search query after visiting Settings is an
actionable workflow problem; a color preference alone needs a clearer usability impact.

Agents are authorized to open issues in `Tsha0/InboxPlus` for these findings without asking for
approval each time. This authorization covers reporting discoveries during the current task, not
starting a background monitor or implementing unrelated fixes.

1. Verify the observation. Reproduce a bug when practical and record the steps, affected screen,
   app version/build, macOS version and whether the app uses fixtures or a live profile. If testing
   an uncommitted build, say so. Describe intermittent or unreproduced observations honestly.
2. Search open and closed issues and related PRs using the affected feature and symptom. Read likely
   matches before filing; a related feature request is not necessarily the same problem. Link an
   existing matching issue instead of creating a duplicate. Respect intentional product decisions;
   do not refile a rejected proposal without new evidence that changes its premise.
3. Prepare a concise report using the [bug report](.github/ISSUE_TEMPLATE/bug_report.md) or
   [UX and feature request](.github/ISSUE_TEMPLATE/ux_feature_request.md) template. Include observed
   behavior, user impact, expected behavior or proposed outcome, evidence and acceptance criteria.
   Separate confirmed facts, suspected causes and proposed solutions. Do not invent a root cause.
4. Open one issue per distinct new problem, grouping symptoms that belong to the same problem.
   Use the connected GitHub issue-creation tool, or `gh issue create --repo Tsha0/InboxPlus` with
   `--title` and `--body-file` when needed. Supply the completed template body explicitly; do not
   assume the API applies it. Use existing labels only when applicable. The issue is the lasting
   record; do not maintain a second repository backlog.
5. Continue the original task. In the final report, link issues created and existing reports found,
   and distinguish findings from fixes. If creation fails or duplicate checking is unavailable,
   preserve the complete draft in the task report or a linked local file and explain what failed.
   Do not claim an issue was opened until its URL is confirmed.

Use fixtures or sanitized descriptions and screenshots. Never publish real message bodies, contact
details, tokens, cookies or attachment URLs. Inspect evidence before uploading it. Security-sensitive
findings go privately to the user, not into a public issue. Reproduction must stay within the task's
authorization: do not send messages, remove accounts, delete data or alter live runtime state merely
to confirm a finding. Record that verification was limited instead.

If the active task already fixes the finding, link its existing issue or document it in the PR rather
than opening a redundant backlog item. A new issue for an unrelated discovery does not expand the
implementation scope.

## Generated files

Edit the source and regenerate the corresponding output. Never hand-edit generated files.

| Source change | Generated output |
| --- | --- |
| Brand icons in `Scripts/brand-icons` | `Sources/InboxPlusUI/PlatformGlyphPaths.swift` |
| Logo at `docs/assets/inboxplus-logo.png` | `Resources/AppIcon.icns` |
| Dependencies or runtime inventory | `docs/sbom.cdx.json` |

```bash
swift Scripts/make-platform-glyphs.swift Scripts/brand-icons Sources/InboxPlusUI/PlatformGlyphPaths.swift
swift Scripts/make-icon.swift docs/assets/inboxplus-logo.png Resources/AppIcon.icns
swift run InboxPlusRuntimeCLI sbom --output docs/sbom.cdx.json
```

Include updated outputs with their source changes and inspect the generated diff. CI regenerates
all three and fails if anything drifts.

## Pull requests

`main` is protected: changes arrive through pull requests with green checks, not direct pushes.
Approvals are not required for this solo repository, but CI is. Use a focused branch such as
`codex/my-change`.

Three checks must pass before merging:

| Check | What it protects |
| --- | --- |
| **Build and test** | Swift build and tests, packaging-script checks and whitespace checks |
| **Generated files are current** | Brand marks, app icon and SBOM match their sources |
| **Package the app** | The app bundle assembles, its signature verifies and its CLI runs |

The executable definitions live in [ci.yml](.github/workflows/ci.yml). Keep this guide's commands
aligned when changing that workflow.

Use a short, descriptive title. The PR description should explain the problem and resulting
behavior, list checks and results, and identify untested paths or migration concerns when relevant.
Include screenshots or a recording for visible UI changes, using fixtures or redacted content.
Review the diff for unrelated changes, debug output and sensitive data before submitting.

Agents must not commit or push without an explicit request, bypass hooks, or overwrite unrelated
user changes. Before finishing, summarize the change and verification evidence. Update these
instructions when a change invalidates them; document recurring, non-obvious pitfalls rather than
adding a rule for every task.
