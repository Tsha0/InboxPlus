# Contributing to Inbox+

This guide applies to human and AI-assisted contributions. You are responsible for understanding
your change and checking the behavior it produces. Every change must keep the architecture,
security and lifecycle rules in the [Code Review Rules](AGENTS.md#code-review-rules).

## Setup

Install the toolchain in the [README requirements](README.md#requirements), then run the app:

```bash
cd apps/inboxplus
flutter pub get --enforce-lockfile
flutter run -d macos
```

- Each runner builds its embedded connector library. Nothing starts a homeserver or a bridge
  service.
- Keep credentials, drafts and test data in isolated test profiles. Do not open a real account or
  the real macOS Messages database to verify a build.
- For connector-only work, `native/connectors/build.sh host` builds the shared library without
  launching the app. Point a development app at that library with `INBOXPLUS_CONNECTORS_LIBRARY`.

### Profiles

- macOS profiles live in `~/Library/Application Support/Inbox+/DeveloperRuntime`. Other systems use
  the OS application-support directory.
- With one macOS profile, the app selects it and keeps its encrypted store in the profile's
  `flutter` subdirectory.
- With several profiles, set `INBOXPLUS_PROFILE`. An ambiguous choice stops startup.
  `INBOXPLUS_RUNTIME_ROOT` selects an existing absolute root.
- iOS keys use a stable profile identity. When iOS relocates the app container, saved attachment
  paths move with the profile, and its database and key stay as they are.

## Scope

- Change one behavior or fix one problem. Keep unrelated cleanup and broad formatting out.
- Read the neighboring code and tests first. The
  [module overview](README.md#how-it-fits-together) shows which package or runner owns a change.
- Do not add a compatibility shim, dependency or abstraction for a requirement that does not exist
  yet.
- Pin a new dependency to an exact version and review its license. See
  [dependencies](docs/dependencies.md). Commit both pub lockfiles and `go.sum` with the change.

## Code style

- Match the surrounding style. Format Dart with `dart format` and Go with `gofmt`. Leave unrelated
  Swift formatting alone.
- Reuse the Flutter theme and controls in `apps/inboxplus/lib/ui`, and an existing helper before
  you add a new one.
- Validate external input at the boundary that owns it, then pass typed values inward.
- Handle the failures that can happen. Do not swallow an error or add a fallback for a case that
  cannot happen.
- Comment only a reason or constraint that the code cannot show.

## Verification

Pick checks by what the change affects. Run focused tests while you iterate and the broader checks
before you submit. Say which checks you could not run and why.

| Change | Check |
| --- | --- |
| Flutter app or UI | `flutter analyze` and `flutter test` in `apps/inboxplus`. Look at each affected state on desktop and mobile, including loading, empty, error and cancellation. Put screenshots or a recording in the issue description |
| Encrypted storage | `dart analyze` and `dart test` in `packages/inboxplus_storage` |
| Embedded connectors | `go mod verify` and `go test ./...` in `native/connectors`, then `build.sh host` for the C ABI |
| macOS Messages adapter | `swift test --package-path native/imessage` |
| macOS updater | `swift test --package-path native/updates --force-resolved-versions` |
| Native runners or packaging | Build the affected target on its native host, then run the [packaging checks](#packaging-checks) |
| Icons, brand marks or dependencies | Regenerate the [generated files](#generated-files) and read the diff |
| Documentation only | Check links, paths and commands against the repository, and run `git diff --check` |

- For Flutter and storage changes, also run
  `dart format --output=none --set-exit-if-changed lib test`.
- Run the storage tests on their own. `flutter test` in the app does not run the suite of a path
  dependency.
- Native cgo tests need a C compiler as well as Go.
- Add a regression test for a bug fix and tests for new behavior when practical. Use the existing
  fixtures and fakes, and assert observable behavior. Say so when a test is impractical.
- Tests never touch a real account. Passing fixture tests does not prove that a network's live
  sign-in or messaging works.
- A timeout on a real process guards against a hang. Make it generous enough for slow CI runners.

### Preview the app with fixtures

From `apps/inboxplus`:

```bash
flutter run -d macos --target lib/desktop_preview.dart --dart-define=INBOXPLUS_DESKTOP_FIXTURE=/absolute/path/to/InboxPlus/Tests/Fixtures/desktop-parity.json
```

- Use the absolute path to the fixture in this checkout.
- The preview uses a temporary encrypted store and fake connectors. The normal app entry never
  loads a fixture.
- Compare the inbox, contacts, transcript, Settings, both themes and several window sizes.
- A fixture attachment with `"remote": true` starts without a local copy. The preview connector
  serves it, like a newly received photo.

| Extra `--dart-define` | Effect |
| --- | --- |
| `INBOXPLUS_PREVIEW_FIXTURE_JSON='<fixture JSON>'` | Passes the fixture contents to a phone preview, in place of a path |
| `INBOXPLUS_PREVIEW_CONVERSATION=<account>/<conversation>` | Opens a fixture conversation at launch, for example `instagram/nora` |
| `INBOXPLUS_PREVIEW_NOTIFICATION_STATUS=denied` or `not_determined` | Shows the notification permission guidance |
| `INBOXPLUS_PREVIEW_NOTIFICATION_SOUND=false` | Shows blocked notification sounds |

The notification values never read or change the operating system's permissions.

## Packaging checks

Build the affected target from `apps/inboxplus` with `flutter build macos`, `windows`, `linux`,
`apk` or `ios --no-codesign`. Then run the packaging suite from the repository root:

```bash
python3 -m unittest discover -s Tests/Packaging -v
```

An unsigned build does not verify installation or signing. Before you distribute a desktop build,
check its signing, installation and update behavior on the target OS.

### Desktop archives

After a release build, run the packager from the repository root with Python **3.12**:

```bash
python3 Scripts/package-flutter-desktop.py --target macos   # or windows, linux
```

- Archives go to `build/flutter-desktop` with a `.sha256` file. `--output` changes the directory
  and `--bundle` selects a release directory other than the default.
- The archive name carries the version, build number, OS and architecture.
- Each archive holds an `Inbox+` folder with the full runtime, the dependency notices, `LICENSE`,
  `sbom.cdx.json` and `build-info.json`.
- The script rejects missing, stale, debug or incompatible runtime files, and verifies macOS
  signatures before it packages.

| Platform | Archive | After extraction |
| --- | --- | --- |
| macOS | `.zip` | Open `Inbox+/Inbox+.app`. Finder or `ditto -x -k` keeps its framework links |
| Windows | `.zip` | Open `Inbox+/InboxPlus.exe`. Keep the DLLs and data folder beside it |
| Linux | `.tar.gz` | Extract with `tar -xzf`, then run `Inbox+/InboxPlus`. Keep the lib and data folders beside it |

- These archives do not install the app, and updates stay disabled. The macOS app is ad-hoc
  signed and not notarized. Production macOS releases use the [release pipeline](docs/updates.md).
- Windows C++ runtime prerequisites and a clean-machine install are not verified yet.
- CI uploads the ZIP or tar file, never the raw app directory. GitHub artifact uploads drop
  executable permissions and framework symlinks.
- When you change the archive format, extract an archive and check the full runtime. Fixture tests
  do not prove that a native app launches.

### Android dependency locks

Gradle verifies every Maven artifact and plugin classpath against
`android/gradle/verification-metadata.xml` and the version locks in `android/gradle/locks`, both
under `apps/inboxplus`. Locks for pub plugins stay in this checkout, not in the pub cache. A missing
checksum or lock fails the build. Keep checksum verification on.

After an intentional Android dependency update:

1. From `apps/inboxplus/android`, run
   `./gradlew resolveDependencyLocks --write-locks --write-verification-metadata sha256`. This also
   verifies the AAPT2 archives for all three build hosts. Keep the AAPT2 version aligned with AGP.
2. For debug, profile and release in turn, run `flutter build apk --<mode> --config-only` from
   `apps/inboxplus`. Then run
   `./gradlew assemble<Mode> --write-locks --write-verification-metadata sha256` from `android` to
   capture task-time dependencies. Run one mode at a time, because Flutter regenerates the plugin
   registrant for each mode.
3. Review the resolved versions and checksums.
4. Repeat the builds without the two write flags.

### Verified downloads

- `Scripts/verify-media-artifacts.py` checks media-kit archives against pinned SHA-256 values
  before CMake or CocoaPods can extract them. Never replace that check with the dependency's
  MD5-only check.
- The Apple Podfiles run the verifier before CocoaPods evaluates media-kit's podspecs. A `make`
  failure inside a podspec can be ignored, and then shows up as a missing framework at link time.
- If a GitHub release download fails, the verifier uses the GitHub CLI asset API and checks the
  same pinned SHA-256. CI provides a read-only `GH_TOKEN` for those requests.
- `--platform sparkle` fills SwiftPM's artifact cache from `sparkle-artifact.json`. It does not
  change the SwiftPM target or its checksum verification.
- Desktop CI runs `Scripts/retry-sqlite-download.py`. It retries only a SQLite hook download that
  failed its pinned SHA-256. It never retries a test failure or accepts a mismatched checksum. Keep
  its cache handling aligned with the pinned Dart SDK and sqlite3 version.

### iOS archive

- `flutter build ipa --release --no-codesign` builds the archive that TestFlight receives.
- From the repository root, check it with
  `python3 Scripts/verify-ios-app.py apps/inboxplus/build/ios/archive/Runner.xcarchive`.
- The Runner target must keep `STRIP_STYLE = non-global`. Archiving strips symbols, and the Dart
  side finds the embedded connectors by name. A stripped app still launches but shows every network
  as unavailable. A device or simulator build does not show the problem.
- Run the launch test on a booted simulator with `flutter test integration_test -d <simulator-id>`.

## Reporting UI findings

During UI exploration, report bugs, usability and accessibility problems, and feature gaps that
have a concrete user impact. Losing a search query after a visit to Settings qualifies. A color
preference alone does not.

Agents may open issues in `Tsha0/InboxPlus` for these findings without asking each time. That
covers findings from the current task. It does not cover background monitoring or unrelated fixes.

1. **Verify.** Reproduce the problem when practical. Record the steps, the screen, the app version
   and build, the OS and device, and whether you used fixtures or a live profile. Say so if the
   build is uncommitted or the problem is intermittent.
2. **Search.** Look through open and closed issues and related PRs. Link a matching issue instead
   of filing a duplicate. Do not refile a rejected proposal without new evidence.
3. **Write.** Use the [bug report](.github/ISSUE_TEMPLATE/bug_report.md) or
   [UX and feature request](.github/ISSUE_TEMPLATE/ux_feature_request.md) template. Keep
   observations, suspected causes and proposals separate. Do not invent a root cause.
4. **File.** Open one issue per distinct problem, with the GitHub issue tool or
   `gh issue create --repo Tsha0/InboxPlus --title ... --body ...`. Pass the whole description as
   the body, because the API does not apply the template. Use only labels that exist.
5. **Tell the user.** Give one sentence and the confirmed issue link for each issue. Do not repeat
   the description in chat. If filing or the duplicate search fails, say what failed and what the
   user must do. Then continue the original task.

Evidence rules:

- The issue description is the only record. Embed GitHub-hosted screenshots, recordings or inline
  diagrams there with short captions, and add later findings to it.
- Never create local files or directories for screenshots, recordings, reports, notes or drafts,
  inside or outside the repository. If you cannot attach evidence, describe it in the issue.
- Use fixtures or sanitized content. Never publish real message bodies, contact details, tokens,
  cookies or attachment URLs. Look at evidence before you upload it.
- Report a security-sensitive finding privately to the user, not in a public issue.
- Do not send messages, remove accounts, delete data or change live state to confirm a finding.
  Record that verification was limited.
- A new issue does not widen the task. If the task already fixes the finding, say so in the issue
  and link the issue from the PR.

## Generated files

Edit the source and regenerate the output. Never edit a generated file by hand.

| Source | Generated output |
| --- | --- |
| Brand icons in `Scripts/brand-icons` | `apps/inboxplus/lib/ui/platform_glyphs.dart` |
| Logo at `docs/assets/inboxplus-logo.png` | `Resources/AppIcon.icns` and the Flutter Android, iOS, Windows and Linux launcher icons |
| Dependency lockfiles, toolchains or license reviews | `docs/sbom.cdx.json` and `apps/inboxplus/assets/third_party_notices.txt` |
| Drift schema | `packages/inboxplus_storage/lib/src/local_store.g.dart` |

```bash
python3 Scripts/generate-flutter-glyphs.py
swift Scripts/make-icon.swift docs/assets/inboxplus-logo.png Resources/AppIcon.icns
python3 -m pip install Pillow==10.4.0
python3 Scripts/generate-platform-icons.py
python3 Scripts/generate-sbom.py
python3 Scripts/generate-third-party-notices.py
(cd packages/inboxplus_storage && dart run build_runner build --delete-conflicting-outputs)
```

- Commit each regenerated output with its source change and read the generated diff. CI
  regenerates the icons, SBOM, notices and Drift source, and fails if anything differs.
- Before you generate notices, resolve both pub lockfiles and run
  `go -C native/connectors mod download`. Set `PUB_CACHE` and `GO_BINARY` for a custom cache or
  toolchain location.
- When a locked package version changes, review its license evidence in
  `docs/dependency-licenses.json`.
- `generate-flutter-glyphs.py --check` and `generate-platform-icons.py --check` verify the outputs
  without rewriting them. The icon check compares decoded pixels and dimensions, so a PNG metadata
  difference does not fail it.
- The icon scripts need Python 3.9 or later with Pillow **10.4.0**. CI uses Python 3.12.
- `apps/inboxplus/assets/reaction_emoji.json` is not generated. Edit it directly to add emoji
  names or categories.

## Pull requests

- `main` is protected. Changes arrive through pull requests with green checks. This solo
  repository does not require an approval.
- Use a focused branch such as `codex/my-change` and a short, descriptive title.
- Fill in the [pull request template](.github/pull_request_template.md). For a visible UI change,
  link the issue that holds the screenshots or recording.
- Before you submit, read the diff for unrelated changes, debug output and sensitive data.

### CI

The [CI workflow](.github/workflows/ci.yml) runs on every pull request.

- **CI passed** is the only required check. A failure, a cancellation or an unexpected skip fails
  it.
- **Detect changes** picks the jobs. A documentation or website change runs only the whitespace
  check. A change to shared Dart, storage, connector, asset or packaging input runs every platform
  that uses it. A runner change runs its own platform. An unknown path runs every platform.
- Each desktop has its own job. A failed macOS-only check blocks macOS while Windows and Linux
  continue.
- Formatting, analysis and each generated-file check run once. Go, storage, Flutter and connector
  smoke tests run on every affected desktop.
- The Android build runs only when you dispatch **CI** manually with `android_build` enabled. A
  manual run checks every component.
- The macOS build log and the `macos-build-timings` artifact show phase timings and connector
  cache hits.
- Releases and website deployment are separate workflows.

## Releases

### macOS releases

Follow [macOS updates](docs/updates.md) for credentials, the release steps, local packaging and
the installed-update test.

When you change Sparkle, keep `native/updates/Package.swift` and both Xcode `Package.resolved`
files aligned. Update `native/updates/sparkle-artifact.json`, the reviewed license evidence and
the generated SBOM and notices in the same change.

### iOS releases

[ios-release.yml](.github/workflows/ios-release.yml) publishes iOS builds to TestFlight.

1. On `main`, raise `version:` in `apps/inboxplus/pubspec.yaml`. Always use a new build number
   after the `+`.
2. Run `python3 Scripts/generate-sbom.py`, which records the version.
3. Push the matching tag. `v0.9.1` releases `0.9.1+115`. The workflow refuses a tag that does not
   match.

The workflow then does the rest:

- It requires a successful CI run for the exact commit, from a push to `main` or a manual CI run.
  A pull request run does not count. If CI is missing or still running, let it finish and rerun
  the release.
- It runs the launch test on a fresh iPhone simulator, then archives and verifies the app
  unsigned.
- It signs the app with the App Store Connect API key, checks it with
  `Scripts/verify-ios-app.py --distribution` and uploads it.
- A manual dispatch releases the selected branch without the tag check.

Signing and upload:

- Signing uses the `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and
  `APP_STORE_CONNECT_PRIVATE_KEY` repository secrets. The key needs the Admin role for cloud
  signing.
- Export keeps the pubspec build number, so a build number that was already uploaded fails the
  upload.
- After processing, answer the export-compliance questions in App Store Connect and add the build
  to the TestFlight groups.
