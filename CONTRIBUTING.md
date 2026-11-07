# Contributing to Inbox+

This guide applies to human and AI-assisted contributions. Contributors are responsible for
understanding their changes and checking the resulting behavior. Follow the critical architecture,
security and lifecycle rules in [AGENTS.md](AGENTS.md#code-review-rules).

## Setup

The primary development app is Flutter. Install Flutter **3.47.9** (Dart **3.13.7**), Go **1.27.3**,
and the native tools for your target in [README requirements](README.md#requirements).
Run from the repository root:

```bash
cd apps/inboxplus_flutter
flutter pub get --enforce-lockfile
flutter run -d macos
```

Select a device or another desktop target with `flutter devices`. Each runner builds its embedded
connector library; it does not start a homeserver or a separate bridge service. Keep credentials,
drafts and test data inside isolated test profiles. Do not open a real account or the real macOS
Messages database merely to verify a build.

The previous Swift application and packaging pipeline are retained during migration. On macOS,
`swift build` and `swift test` still verify those targets; `swift run InboxPlus` launches the old app.
`Scripts/build-app.sh` packages that old app, not the Flutter app. Do not confuse their test or
release results.

## Scope and architecture

- Keep each change focused on one behavior or problem. Inspect neighboring code and tests first;
  separate unrelated cleanup or broad formatting from behavior changes.
- Use the [module overview](README.md#how-it-fits-together) and `Package.swift` to find the owning
  target. Preserve the dependency boundaries in `AGENTS.md`.
- Flutter views use `InboxUiController`; the app controller owns state and persistence. Keep the
  encrypted Drift schema in `packages/inboxplus_storage` and network implementations in
  `native/connectors`. The C ABI is account-scoped; never put network secrets in UI models or logs.
- In the retained Swift code, UI and features use `MessagingGateway`. Put Matrix-specific handling
  in `InboxPlusMatrix`; test feature behavior with existing gateway fakes.
- Keep bridge protocol models and catalog data in `InboxPlusBridge`. Installation, configuration
  and interaction with real bridge processes belong in `InboxPlusBridgeService`.
- Do not add speculative compatibility shims, dependencies or abstractions for hypothetical future
  requirements. A new dependency must meet the existing exact-version and licensing requirements;
  see [dependencies](docs/dependencies.md).

## Code style

- Match surrounding style. Format Dart with `dart format` and Go with `gofmt`; avoid unrelated
  Swift formatting changes.
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
- Reuse the Flutter theme and controls in `apps/inboxplus_flutter/lib/ui`. For retained Swift UI,
  use `InboxPlusTheme.swift` and `ViewStyling.swift` before adding styling.

## Verification

Choose checks based on the affected behavior. Run focused tests while iterating, then the relevant
broader checks before submitting. Reuse successful results while their inputs remain unchanged.
Document checks you could not run and why; do not present an untested path as verified.

| Change | Local verification |
| --- | --- |
| Flutter application or UI | `flutter analyze` and `flutter test` inside `apps/inboxplus_flutter`; inspect affected desktop and mobile states |
| Encrypted storage | `dart analyze` and `dart test` inside `packages/inboxplus_storage` |
| Embedded connectors | `go mod verify` and `go test ./...` inside `native/connectors`; `build.sh host` for the C ABI |
| Native runners or packaging | Build the affected Flutter target on its native host; an unsigned build is not installation or signing verification |
| Swift behavior | Relevant tests via `swift test --filter <test-name-or-pattern>`; `swift test` for the default suite |
| Module dependencies or shared contracts | `swift build --build-tests` and `swift test` |
| UI behavior or layout | Relevant tests plus visual inspection of affected states; include screenshots or a recording in the issue description |
| Packaging or updates | Packaging checks below and, when bundle assembly is affected, the bundle checks |
| Icons, brand marks or dependency inventory | Regenerate affected outputs using the commands below and inspect the diff |
| Runtime integration | Relevant runtime tests; opt-in real-runtime tests when needed, clearly distinguished from fixture coverage |
| Documentation only | Check links, paths and commands against the repository, and run `git diff --check` |

For Flutter and storage changes, run `dart format --output=none --set-exit-if-changed lib test`.
Run the storage package's tests separately: the Flutter app does not
automatically run a path dependency's own suite. Native Cgo tests require a C compiler, not just Go.

Add a regression test for a bug fix and tests for new behavior when practical. Follow nearby test
patterns, use existing fixtures and fakes, and test observable behavior rather than duplicating the
implementation. Explain when automated coverage is impractical. For UI changes, inspect affected
loading, empty, error and cancellation states where applicable.

Native UI tests share one application and its windows. CI and release packaging run them serially
in a separate invocation. To use the same arrangement locally:

```bash
swift test --skip InboxPlusUITests
swift test --skip-build --filter InboxPlusUITests --no-parallel
```

For desktop visual comparisons on macOS, quit the two comparison apps and run
`python3 Scripts/build-desktop-comparison.py` with the toolchains above on `PATH` (or set
`FLUTTER_BINARY`). It builds `build/desktop-parity/Inbox+ reference.app` from the retained Swift UI
and `Inbox+v2 comparison.app` from the debug-only Flutter fixture entry. Both use
`Tests/Fixtures/desktop-parity.json`; the reference has separate preferences and the Flutter app
uses a temporary encrypted store and fake connectors. Compare their inbox, contacts, transcript,
Settings, light/dark themes and window sizes through computer control. The normal app entry never
loads these fixtures. No live network account or real Messages database is needed.

In the debug macOS comparison app, **F8** exercises native notification activation for the synthetic
Weekend plans conversation. It uses the same pending-route handoff as a notification response,
without posting a system notification or requesting permission. The native test entry accepts only
debug comparison bundle identities. Verify navigation from Settings or Contacts and preservation of
existing drafts; this fixture check does not establish OS notification delivery or permission behavior.

When building `lib/desktop_preview.dart` directly, use
`--dart-define=INBOXPLUS_PREVIEW_NOTIFICATION_STATUS=denied` or `not_determined` to inspect permission
guidance, or `--dart-define=INBOXPLUS_PREVIEW_NOTIFICATION_SOUND=false` for blocked sounds. These
fixture values do not read or change the operating system's notification permissions.

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

Build the affected Flutter target from `apps/inboxplus_flutter` with `flutter build macos`,
`flutter build windows`, `flutter build linux`, `flutter build apk`, or
`flutter build ios --no-codesign`. Android requires NDK **28.2.13676358**. Windows needs Git Bash,
Python 3 and MinGW for Go/cgo in addition to Visual Studio. Linux needs the packages listed in the
README, including GLib 2.66+, WebKitGTK 4.1 and Ayatana AppIndicator; its media plugin uses the system allocator rather than fetching
mimalloc. Platform SDKs and signing remain target-specific even though the UI is shared.

The Windows runner prepares media-kit archives with `Scripts/verify-media-artifacts.py` before
CMake can extract them. Never replace that SHA-256 check with the dependency's MD5-only check.

For iOS, `flutter build ipa --release --no-codesign` builds the archive TestFlight receives. Check
it with `python3 Scripts/verify-ios-app.py apps/inboxplus_flutter/build/ios/archive/Runner.xcarchive`
from the repository root. Archiving strips symbols, and the Dart side finds the embedded connectors
by name, so the Runner target must keep `STRIP_STYLE = non-global`. A stripped app still launches
but shows every network as unavailable. A plain device or simulator build does not show this.
Run the launch test on a booted simulator with `flutter test integration_test -d <simulator-id>`.

For Flutter desktop archives, use Python **3.12** and run
`python3 Scripts/package-flutter-desktop.py --target macos` (or `windows` / `linux`) from the
repository root after the native release build. `--bundle` selects a non-default release directory;
`--output` selects the archive directory. The script rejects missing, stale, debug or incompatible
runtime files and verifies macOS signatures before packaging. See
[desktop development packages](README.md#desktop-development-packages) for outputs and limitations.

Each desktop CI job runs `test_flutter_desktop.py`, packages its native build and uploads the
archive plus checksum. Upload the ZIP or tar archive rather than the raw app directory: GitHub
artifact uploads do not preserve executable permissions or framework symlinks. Extract and verify
the full runtime when changing the archive format; fixture tests alone do not prove a native app
launches. Signing, notarization, installers and automatic updates are separate release work.

The following checks protect the retained Swift packaging pipeline and shared packaging scripts:

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
   Use the connected GitHub issue-creation tool with the complete description as its body, or
   `gh issue create --repo Tsha0/InboxPlus` with `--title` and `--body`. Do not write a body file or
   assume the API applies the template. Use existing labels only when applicable.
5. Continue the original task. For each filed issue, notify the user with a one-sentence summary
   and the confirmed issue link. Do not repeat the full issue description or evidence in chat. Link
   existing matching issues with a brief summary, clearly distinguishing them from newly filed ones.
   If creation or duplicate checking fails, briefly report what failed and any required user action.
   Do not claim an issue was opened until its URL is confirmed.

Use fixtures or sanitized descriptions and screenshots. Never publish real message bodies, contact
details, tokens, cookies or attachment URLs. Inspect evidence before uploading it. Security-sensitive
findings go privately to the user, not into a public issue. Reproduction must stay within the task's
authorization: do not send messages, remove accounts, delete data or alter live runtime state merely
to confirm a finding. Record that verification was limited instead.

The GitHub issue description is the sole record of issue information: reproduction steps,
environment, observations, investigation, acceptance criteria and sanitized evidence. Prefer
screenshots and visual aids, with brief text explaining what they show. Embed GitHub-hosted
screenshots and recordings, or inline diagrams, directly in the issue description, and add later
findings there. Never create local files or directories for issue screenshots, recordings, reports,
investigation notes or drafts, inside or outside the repository. If evidence cannot be attached
directly, describe it and the limitation in the issue description; do not save local artifacts.

If the active task already fixes the finding, record it in the relevant issue description and link
the issue from the PR. Reuse an existing matching issue rather than opening a duplicate. A new issue
for an unrelated discovery does not expand implementation scope.

## Generated files

Edit the source and regenerate the corresponding output. Never hand-edit generated files.

| Source change | Generated output |
| --- | --- |
| Brand icons in `Scripts/brand-icons` | `Sources/InboxPlusUI/PlatformGlyphPaths.swift` |
| Canonical Swift brand paths | `apps/inboxplus_flutter/lib/ui/platform_glyphs.dart` |
| `EmojiCatalog` in `Sources/InboxPlusUI/ReactionPicker.swift` | `apps/inboxplus_flutter/assets/reaction_emoji.json` |
| Logo at `docs/assets/inboxplus-logo.png` | `Resources/AppIcon.icns` and Flutter Android/iOS/Windows/Linux launcher icons |
| Dependency lockfiles, toolchains or license reviews | `docs/sbom.cdx.json` and `apps/inboxplus_flutter/assets/third_party_notices.txt` |
| Drift schema | `packages/inboxplus_storage/lib/src/local_store.g.dart` |

```bash
swift Scripts/make-platform-glyphs.swift Scripts/brand-icons Sources/InboxPlusUI/PlatformGlyphPaths.swift
python3 Scripts/generate-flutter-glyphs.py
python3 Scripts/generate-flutter-emoji.py
swift Scripts/make-icon.swift docs/assets/inboxplus-logo.png Resources/AppIcon.icns
python3 -m pip install Pillow==10.4.0
python3 Scripts/generate-platform-icons.py
python3 Scripts/generate-sbom.py
python3 Scripts/generate-third-party-notices.py
(cd packages/inboxplus_storage && dart run build_runner build --delete-conflicting-outputs)
```

Include updated outputs with their source changes and inspect the generated diff. CI regenerates
the icons, combined SBOM, bundled notices and Drift source and fails if anything drifts. Resolve
both pub lockfiles and run `go -C native/connectors mod download` before generating notices; set
`PUB_CACHE` and `GO_BINARY` when using custom toolchain/cache locations. Review license evidence in
`docs/dependency-licenses.json` whenever a locked package version changes. Go's `h1:` module-content
checksums are not raw archive SHA-256 hashes; preserve that distinction in the SBOM.

`generate-flutter-glyphs.py --check` verifies the Flutter brand paths against the canonical Swift
output. `generate-platform-icons.py --check` verifies the Flutter launcher and in-app logo assets without rewriting them.
It compares decoded pixels and icon dimensions so PNG metadata differences do not create false
failures. Use Python 3.9 or later with Pillow **10.4.0**; CI uses Python 3.12. The macOS icon still
comes from the existing Swift generator above.

`generate-flutter-emoji.py --check` runs on macOS and verifies the shared emoji names and categories
against the retained Swift picker. Other platforms bundle the generated catalog without requiring Swift.

## Pull requests

`main` is protected: changes arrive through pull requests with green checks, not direct pushes.
Approvals are not required for this solo repository, but CI is. Use a focused branch such as
`codex/my-change`.

Required check names depend on the protected branch configuration. CI defines:

| Check | What it protects |
| --- | --- |
| **Flutter / macos, linux, windows** | Shared Dart checks, encrypted storage and connector tests, native desktop build and development archive |
| **Flutter / Android** | Deferred native Android build; manual opt-in only |
| **Flutter / iOS** | Unsigned App Store archive keeps its connector symbols, privacy manifest and pubspec version |
| **Build and test** | Retained Swift build and tests, packaging-script checks and whitespace checks |
| **Generated files are current** | Brand marks, app icon and SBOM match their sources |
| **Package the app** | Retained Swift bundle assembles, its signature verifies and its CLI runs |

The executable definitions live in [ci.yml](.github/workflows/ci.yml) and
[flutter-ci.yml](.github/workflows/flutter-ci.yml). Keep this guide's commands aligned when changing
those workflows.

The Flutter workflow runs desktop and iOS jobs by default. The Android job remains available only
through manual dispatch with `android_build` enabled.

### iOS releases

[ios-release.yml](.github/workflows/ios-release.yml) publishes iOS builds to TestFlight. To release,
raise `version:` in `apps/inboxplus_flutter/pubspec.yaml` on `main`, always with a new build number
after `+`, and run `python3 Scripts/generate-sbom.py`, which records the version. Then push a
matching tag: `0.9.1+114` is released by `v0.9.1`. The workflow refuses a tag that does not match. It runs the launch test on a fresh iPhone simulator, archives the app
unsigned, signs it for the App Store with the App Store Connect API key, checks it with
`Scripts/verify-ios-app.py --distribution` and uploads it. Manual dispatch releases the selected
branch without the tag check.

Signing uses the `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and
`APP_STORE_CONNECT_PRIVATE_KEY` repository secrets; the key needs the Admin role for cloud signing.
Export keeps the pubspec build number, so an already-uploaded number fails the upload rather than
being renumbered. After processing, answer the build's export-compliance questions in App Store
Connect and add it to TestFlight groups.

Use a short, descriptive title. The PR description should explain the problem and resulting
behavior, list checks and results, and identify untested paths or migration concerns when relevant.
For visible UI changes, link the issue description containing screenshots or a recording, using
fixtures or redacted content.
Review the diff for unrelated changes, debug output and sensitive data before submitting.

Agents must not commit or push without an explicit request, bypass hooks, or overwrite unrelated
user changes. Before finishing, summarize the change and verification evidence. Update these
instructions when a change invalidates them; document recurring, non-obvious pitfalls rather than
adding a rule for every task.

### Automatic code review

[OCR code review](.github/workflows/ocr-review.yml) posts advisory reviews on non-draft pull requests
from this repository's branches, using the rules in `AGENTS.md`. The existing CI checks remain required.
