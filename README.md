# Inbox+

<p align="center">
  <img src="docs/assets/inboxplus-logo.png" alt="Inbox+ logo" width="320">
</p>

Inbox+ is a local-first messaging inbox being migrated to Flutter for Android, iOS, macOS,
Windows and Linux. Each device runs its own interface, encrypted SQLite database and network
connectors. A phone does not need a Mac, a shared server or an Inbox+ cloud account.

The app focuses on conversations, attachments and contacts. There are no feeds, stories or calls.

## Status

The Flutter app is a development build, version **0.9.0+112**. The five platform runners share Dart
application code and an embedded Go connector library. Platform builds, fixture tests and live
network verification are separate checks: a passing build does not establish that a real account
can sign in or send messages. New Flutter connectors have not been certified with live accounts.

Current implementation and verification focus on **macOS, Windows and Linux**. Android and iOS
scaffolding is retained, but mobile implementation and design are deferred. Desktop and mobile
select separate layouts while sharing application logic, encrypted storage and connector contracts.

The [published releases](https://github.com/Tsha0/InboxPlus/releases/latest) are still the previous
macOS application, version 0.8.5. Swift sources and the old packaging workflow remain in the
repository while migration and existing-profile handling are verified. The Flutter app does not
start Synapse or bridge processes.

## Requirements

Use **Flutter 3.47.9** (Dart 3.13.7) and **Go 1.27.3**. The Go build refuses other toolchain versions;
set `GO_BINARY` if the pinned executable is not called `go`. Commit both pub lockfiles and `go.sum`.
All connectors are built from pinned source dependencies rather than downloaded bridge executables.

Build each target on a supported host with its native tools:

| Target | Host and additional tools |
| --- | --- |
| Android | macOS, Linux or Windows; Android SDK, JDK 17+, NDK **28.2.13676358**, Python 3, Bash and C compiler |
| iOS | macOS; Xcode, iOS SDK, CocoaPods **1.16.2**; signing and a provisioning profile for installation |
| macOS | macOS 15+; Xcode, Swift 6.2+, CocoaPods **1.16.2** and C compiler |
| Windows (x64) | Windows; Visual Studio desktop C++ tools, CMake, Python 3, Git Bash and MinGW GCC for Go/cgo |
| Linux | Linux; Clang/GCC, CMake, Ninja, pkg-config, GTK 3, libsecret, libmpv, WebKitGTK 4.1 and Ayatana AppIndicator development packages |

On Debian/Ubuntu, install Linux native dependencies with:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libmpv-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev
```

These are build-machine requirements. A device running the packaged app does not install Flutter,
Go, Python, Synapse or a separate connector service.

## Build from source

From the repository root:

```bash
cd apps/inboxplus_flutter
flutter pub get --enforce-lockfile
flutter run -d macos
```

Use `-d windows`, `-d linux`, or a device ID from `flutter devices` for another target. The native
runner builds and bundles the connector library. Go, Bash and the relevant C compiler must be on
its environment's search path; an IDE launched before a toolchain installation may need restarting.

Release build commands, run inside `apps/inboxplus_flutter`:

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
flutter build apk --release
flutter build ios --release --no-codesign
```

Run only the command supported by the build host. The iOS command verifies an unsigned build;
installation and App Store distribution still need Apple's signing setup. Android release signing,
desktop installers, notarization, store publishing and automatic updates require release work beyond
these development builds. The previous Swift Sparkle updater is not part of the Flutter app.

Each desktop target has its own native runner and release artifact: a macOS `.app`, a Windows
executable with its bundled libraries, or a Linux executable with its bundled libraries. Build and
test each on its native host; the desktop CI matrix uses separate macOS, Windows and Linux runners.
Installers and OS signing are additional release steps, not outputs shared between platforms.

For connector-only development, `native/connectors/build.sh host` builds a shared library without
launching the app. `INBOXPLUS_CONNECTORS_LIBRARY` can point a development app at that library.

## Desktop development packages

After building a desktop release, run its packaging command from the repository root with
Python **3.12**:

```bash
python3 Scripts/package-flutter-desktop.py --target macos
python3 Scripts/package-flutter-desktop.py --target windows
python3 Scripts/package-flutter-desktop.py --target linux
```

Run the command for the target you built. Packages go to `build/flutter-desktop`, with the version,
build number, OS and architecture in their names, plus a `.sha256` checksum file. Each archive
contains an `Inbox+v2` folder with the full runtime, bundled dependency notices, `LICENSE`,
`sbom.cdx.json` and `build-info.json`. The desktop CI jobs also produce these archives.

| Platform | Archive | After extraction |
| --- | --- | --- |
| macOS | `.zip` | Open `Inbox+v2/Inbox+v2.app`; Finder or `ditto -x -k` preserves its framework links |
| Windows | `.zip` | Open `Inbox+v2/InboxPlus.exe`; keep the DLLs and data folder beside it |
| Linux | `.tar.gz` | Extract with `tar -xzf`, then run `Inbox+v2/InboxPlus`; keep the lib and data folders beside it |

The macOS development app is ad-hoc signed, without notarization. These packages do not install the
app or provide automatic updates. Linux still requires the GTK, libsecret, libmpv, WebKitGTK and
Ayatana AppIndicator system libraries. Windows C++ runtime prerequisites and clean-machine
installation remain to verify. Packaging fixtures do not establish native Windows/Linux execution.

## Networks

| Network | Device-local implementation | Sign-in and limitations |
| --- | --- | --- |
| WhatsApp | whatsmeow Go library | Link a device using a QR code or pairing code |
| Telegram | gotd MTProto client | Your Telegram API ID/hash, phone, code and optional two-step password; no secret chats |
| Instagram | mautrix-meta's instameow library | Network-owned sign-in page in an ephemeral browser where the platform adapter supports it |
| Facebook Messenger | mautrix-meta's messagix library | Ephemeral Facebook sign-in; protected end-to-end encrypted chats are not yet supported |
| iMessage | Local macOS Messages adapter | macOS only; explicit Full Disk Access and Automation permission |

Instagram and Messenger web sign-in is implemented on macOS, iOS and Linux. Android and Windows
currently leave those networks unavailable because their adapters do not yet provide the required
non-persistent sign-in environment. Windows builds currently support x64.

The interface advertises only capabilities implemented by a connector and its device adapter.
Unavailable authentication methods and unsupported operations must explain their limitation.
Link accounts separately on each device; local storage does not synchronize Inbox+ preferences,
drafts or contacts between devices. Existing network accounts still synchronize through their own
network, subject to that network's history and linked-device rules.

Mobile operating systems can suspend applications. This architecture does not provide an always-on
background server or a cross-device notification relay. Local notification delivery depends on the
app receiving events and on the device's permission and lifecycle rules.

### iMessage

Only macOS exposes the local Messages database and Apple-event sending used by Inbox+.
Connecting iMessage explicitly asks the user to grant Full Disk Access in System Settings; sending
may also prompt for Automation control of Messages. There is no Mac relay for other platforms.
New message can search this Mac's Contacts when access is allowed. Choose a phone number or email
before continuing; opening a conversation does not send a message. Manual address entry remains
available without Contacts access.

## Development profile compatibility

The application identity remains `com.inboxplus.app`. Existing macOS runtime profiles remain at
`~/Library/Application Support/Inbox+/DeveloperRuntime`; their Keychain identifiers must not be
changed or their data silently replaced. The encrypted Flutter store is application-owned data,
not a new reader for Synapse or Matrix SDK database files.

With one existing macOS profile, the app selects it and creates its encrypted store in that
profile's `flutter` subdirectory. With several profiles, set `INBOXPLUS_PROFILE` explicitly; an
ambiguous choice stops startup. `INBOXPLUS_RUNTIME_ROOT` can select an existing absolute root.
On other systems, profiles live in the OS application-support directory.

iOS keys use a stable profile identity. When the operating system relocates an app container,
saved attachment paths move with the restored profile without replacing its database or key.

On first open, saved contacts and conversation choices (favorites, unread overrides, mutes and
hidden chats) import in one database transaction. The original files remain intact. Accounts need
reconnecting with the new device-local connectors, and saved remote identities need relinking;
previous Matrix message history, credentials and staged files stay in the original profile.
A missing key, corrupt store, unsupported schema or failed import stops with an error and keeps the
data instead of substituting an empty profile. Keep the previous app and profile until the new
account connections and imported choices are verified.

## How it fits together

```text
apps/inboxplus_flutter          shared Flutter interface and application controller
  lib/ui                       responsive inbox, conversations, contacts and settings
  lib/connectors               C ABI worker isolate; normalized account-scoped events
  lib/platform                 credential store, private files and native method channel
  android/ios/macos/windows/linux   platform permissions, authentication and lifecycle
packages/inboxplus_storage      encrypted Drift/SQLite records, drafts and durable outbox
native/connectors              embedded Go network clients, encrypted connector state, C ABI
Sources/InboxPlusIMessage       reused macOS Messages adapter
Sources/InboxPlus*              retained Swift application and runtime during migration
```

`lib/ui/inbox_app.dart` selects the desktop shell for macOS, Windows and Linux. The desktop shell
and preferences live in `desktop_shell.dart` and `desktop_preferences.dart`; their pane widths adapt
to the window, and menus, shortcuts and fonts adapt to the OS. Flutter draws the interface from
these widgets: it does not automatically provide a different native design for every platform.
The deferred mobile layout can evolve independently while reusing the controller and storage.

On Windows and Linux, hold Alt to reveal menu letters: Alt+F/E/N/C/H opens
File/Edit/Navigate/Conversation/Help. Use arrow keys and Enter to choose an item; Escape returns to
the field you were editing with its selection intact. macOS uses the native menu bar and Command
shortcuts.

Account-scoped conversation routes keep identical network IDs from different accounts separate.
Draft revisions and durable pending sends prevent an acknowledged send from clearing newer text.
An uncertain send remains visible for reconciliation rather than being automatically duplicated.
SQLite3MultipleCiphers encrypts the app database; its random key lives in the operating system's
credential store. Connector state has separate per-account keys. Attachment files are kept inside
private app directories.

## Developing

```bash
cd packages/inboxplus_storage
dart pub get --enforce-lockfile
dart test
cd ../../apps/inboxplus_flutter
flutter pub get --enforce-lockfile
flutter analyze
flutter test
cd ../../native/connectors
go mod verify
go test ./...
```

Tests use fakes and isolated files, not your real accounts or Messages database. See
[CONTRIBUTING.md](CONTRIBUTING.md) for generated-code checks, native builds and the retained Swift
suite. Do not treat fixture coverage as live-network certification.

## Privacy and security

- No operated Inbox+ cloud or host computer. Each device talks directly to the networks it connects.
- Credentials and database keys belong in the OS credential store. Diagnostic messages must not
  expose tokens, cookies, message bodies or attachment URLs.
- Files and directories containing private app data use owner-only access. Cached media is private,
  but the media files are not described as database-encrypted.
- Web sign-ins use non-persistent browsing and collect only a network's declared credential cookies.
- Binary artifacts are pinned and verified before use. Go modules and pub archives have committed
  integrity locks. See [the dependency inventory](docs/dependencies.md) for native media artifacts.
- An "Open in app" link may follow only HTTPS links on a domain owned by the named network.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). Changes reach protected `main`
through pull requests with passing checks. Do not commit or push without the repository owner's
explicit request.

## License

[AGPL-3.0-or-later](LICENSE). The embedded Meta client is also AGPL-3.0-or-later; this migration does
not turn those libraries into permissively licensed code. Review the
[dependency inventory](docs/dependencies.md) and redistribution obligations before distribution.
