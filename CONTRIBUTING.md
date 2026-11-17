# Contributing to Inbox+

This guide applies to human and AI-assisted contributions. You are responsible for understanding
your change and checking the behavior it produces. Every change must follow the
[Code Review Rules](AGENTS.md#code-review-rules).

## Setup

Install the toolchain in the [README requirements](README.md#requirements), then run the app:

```bash
cd apps/inboxplus
flutter pub get --enforce-lockfile
flutter run -d macos
```

- Keep credentials, drafts and test data in isolated test profiles. Do not open a real account or
  the real macOS Messages database to verify a build.
- For connector-only work, run `native/connectors/build.sh host`. Point a development app at the
  result with `INBOXPLUS_CONNECTORS_LIBRARY`.
- If you have several macOS profiles, choose one with `INBOXPLUS_PROFILE`.
  `INBOXPLUS_RUNTIME_ROOT` selects a different absolute profile root.

## Scope

- Change one behavior or fix one problem. Keep unrelated cleanup and broad formatting out.
- Read the neighboring code and tests first. The [repository layout](README.md#repository-layout)
  shows which package or runner owns a change.
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
| Embedded connectors | `go mod verify` and `go test ./...` in `native/connectors`, then `build.sh host` |
| macOS Messages adapter | `swift test --package-path native/imessage` |
| macOS updater | `swift test --package-path native/updates --force-resolved-versions` |
| Native runners or packaging | Build the affected target on its native host, then run the [packaging checks](#packaging-checks) |
| Icons, brand marks or dependencies | Regenerate the [generated files](#generated-files) and read the diff |
| Documentation only | Check links, paths and commands against the repository, and run `git diff --check` |

- For Flutter and storage changes, also run
  `dart format --output=none --set-exit-if-changed lib test`.
- Run the storage tests separately. `flutter test` in the app does not run them.
- Native cgo tests need a C compiler as well as Go.
- Add a regression test for a bug fix and tests for new behavior when practical. Use the existing
  fixtures and fakes, and assert observable behavior. Say so when a test is impractical.
- Never point a test at a real account. Passing fixture tests do not prove that a network's live
  sign-in or messaging works.
- Give a test that waits on a real process a timeout generous enough for slow CI runners.

### Preview the app with fixtures

From `apps/inboxplus`, with the absolute path to the fixture in this checkout:

```bash
flutter run -d macos --target lib/desktop_preview.dart --dart-define=INBOXPLUS_DESKTOP_FIXTURE=/absolute/path/to/InboxPlus/Tests/Fixtures/desktop-parity.json
```

Compare the inbox, contacts, transcript, Settings, both themes and several window sizes. Mark a
fixture attachment `"remote": true` to preview a photo that is not downloaded yet.

| Extra `--dart-define` | Effect |
| --- | --- |
| `INBOXPLUS_PREVIEW_FIXTURE_JSON='<fixture JSON>'` | Passes the fixture contents to a phone preview, in place of a path |
| `INBOXPLUS_PREVIEW_CONVERSATION=<account>/<conversation>` | Opens a fixture conversation at launch, for example `instagram/nora` |
| `INBOXPLUS_PREVIEW_NOTIFICATION_STATUS=denied` or `not_determined` | Shows the notification permission guidance |
| `INBOXPLUS_PREVIEW_NOTIFICATION_SOUND=false` | Shows blocked notification sounds |

## Packaging checks

Build the affected target from `apps/inboxplus` with `flutter build macos`, `windows`, `linux`,
`apk` or `ios --no-codesign`. Then run the packaging suite from the repository root:

```bash
python3 -m unittest discover -s Tests/Packaging -v
```

Before you distribute a desktop build, check its signing, installation and update behavior on the
target OS. An unsigned build proves none of them.

### Desktop archives

After a release build, run the packager from the repository root with Python **3.12**:

```bash
python3 Scripts/package-flutter-desktop.py --target macos   # or windows, linux
```

Archives go to `build/flutter-desktop`. `--output` changes the directory and `--bundle` selects a
different release build.

| Platform | Archive | After extraction |
| --- | --- | --- |
| macOS | `.zip` | Open `Inbox+/Inbox+.app`. Extract with Finder or `ditto -x -k` |
| Windows | `.zip` | Open `Inbox+/InboxPlus.exe`. Keep the DLLs and data folder beside it |
| Linux | `.tar.gz` | Extract with `tar -xzf`, then run `Inbox+/InboxPlus`. Keep the lib and data folders beside it |

- Upload the archive from CI, never the raw app directory. GitHub artifact uploads drop executable
  permissions and symlinks.
- When you change the archive format, extract an archive and launch the app.

### Android dependency locks

Keep Gradle checksum verification on. After an intentional Android dependency update:

1. From `apps/inboxplus/android`, run
   `./gradlew resolveDependencyLocks --write-locks --write-verification-metadata sha256`. Keep the
   AAPT2 version aligned with AGP.
2. For debug, profile and release, one at a time, run `flutter build apk --<mode> --config-only`
   from `apps/inboxplus`. Then run
   `./gradlew assemble<Mode> --write-locks --write-verification-metadata sha256` from `android`.
3. Review the resolved versions and checksums.
4. Repeat the builds without the two write flags.

### Verified downloads

- Never replace the SHA-256 check in `Scripts/verify-media-artifacts.py` with media-kit's own
  MD5-only check.
- When you change the pinned Dart SDK or sqlite3 version, update `Scripts/retry-sqlite-download.py`
  to match.

### iOS archive

- Build the TestFlight archive with `flutter build ipa --release --no-codesign`.
- From the repository root, check it with
  `python3 Scripts/verify-ios-app.py apps/inboxplus/build/ios/archive/Runner.xcarchive`.
- Keep `STRIP_STYLE = non-global` on the Runner target. Without it the archived app shows every
  network as unavailable, and a device or simulator build does not show the problem.
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

- Commit each regenerated output with its source change and read the generated diff.
- Before you generate notices, resolve both pub lockfiles and run
  `go -C native/connectors mod download`. Set `PUB_CACHE` and `GO_BINARY` for a custom cache or
  toolchain location.
- When a locked package version changes, review its license evidence in
  `docs/dependency-licenses.json`.
- Run `generate-flutter-glyphs.py --check` or `generate-platform-icons.py --check` to verify the
  outputs without rewriting them.
- The icon scripts need Python 3.9 or later with Pillow **10.4.0**.
- `apps/inboxplus/assets/reaction_emoji.json` is not generated. Edit it directly to add emoji
  names or categories.

## Pull requests

- `main` is protected. Changes arrive through pull requests, and **CI passed** must be green. This
  solo repository does not require an approval.
- Use a focused branch such as `codex/my-change` and a short, descriptive title.
- Fill in the [pull request template](.github/pull_request_template.md). For a visible UI change,
  link the issue that holds the screenshots or recording.
- Before you submit, read the diff for unrelated changes, debug output and sensitive data.
- To include the Android build, dispatch **CI** manually with `android_build` enabled.

## Releases

### macOS releases

Follow [macOS updates](docs/updates.md).

When you change Sparkle, keep `native/updates/Package.swift` and both Xcode `Package.resolved`
files aligned. Update `native/updates/sparkle-artifact.json`, the reviewed license evidence and
the generated SBOM and notices in the same change.

### iOS releases

1. On `main`, raise `version:` in `apps/inboxplus/pubspec.yaml`. Always use a new build number
   after the `+`.
2. Run `python3 Scripts/generate-sbom.py`.
3. Wait for CI to pass on that commit. A pull request run does not count.
4. Push the matching tag. `v0.9.1` releases `0.9.1+115`.
   [ios-release.yml](.github/workflows/ios-release.yml) builds, signs and uploads to TestFlight.
5. After processing, answer the export-compliance questions in App Store Connect and add the build
   to the TestFlight groups.

Signing uses the `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and
`APP_STORE_CONNECT_PRIVATE_KEY` repository secrets. The key needs the Admin role.
