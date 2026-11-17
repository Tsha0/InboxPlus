# Inbox+

<p align="center">
  <img src="docs/assets/inboxplus-logo.png" alt="Inbox+ logo" width="320">
</p>

Inbox+ is a local-first messaging inbox for macOS, Windows, Linux, iOS and Android, built with
Flutter.

- Each device runs its own interface, encrypted SQLite database and network connectors.
- There is no Inbox+ cloud account, shared server or host computer. A phone does not need a Mac.
- The app covers conversations, attachments and contacts. It has no feeds, stories or calls.

## Status

- **macOS** ships through [GitHub Releases](https://github.com/Tsha0/InboxPlus/releases) and
  updates itself with [Sparkle](docs/updates.md).
- **iOS** builds reach TestFlight through the [iOS release workflow](CONTRIBUTING.md#ios-releases).
- **Windows and Linux** build in CI as development archives. They have no installer or automatic
  updates yet.
- **Android** builds are manual. The mobile layout and design are deferred on both phones.
- Connectors pass fixture tests. A fixture test does not prove that a real account can sign in or
  send messages, and the newer connectors are not yet verified with live accounts.

## Networks

| Network | Client library | Sign-in | Limits |
| --- | --- | --- | --- |
| WhatsApp | whatsmeow | QR code or pairing code | |
| Telegram | gotd | Your Telegram API ID and hash, phone, code and optional two-step password | No secret chats |
| Instagram | mautrix-meta (instameow) | Instagram's own sign-in page in a non-persistent web view | macOS, iOS and Linux only |
| Facebook Messenger | mautrix-meta (messagix) | Facebook's own sign-in page in a non-persistent web view | macOS, iOS and Linux only. No end-to-end encrypted chats yet |
| WeChat | openwechat | QR code, for accounts with WeChat web access | Experimental. Text and incoming attachments only. No older history |
| Discord | Arikawa | Email and password with an authenticator or backup code, or a session token | Experimental. Direct and group messages only, with replies and uploads up to 10 MiB |
| LinkedIn | linkedingo | Email and password with an email, SMS or authenticator code, or app approval | Experimental. History, text and attachment downloads only |
| iMessage | Local macOS Messages adapter | Full Disk Access and Automation permission | macOS only |

- **Experimental** means fixture coverage only. Live sign-in and messaging still need validation.
- Instagram and Messenger are unavailable on Android and Windows, which have no non-persistent
  sign-in web view yet.
- WeChat and LinkedIn cannot send attachments, replies or reactions yet.
- WeChat receives only messages that arrive after you connect. Download an attachment during the
  connection that received it.
- Discord's [self-bot policy](https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots)
  can lead to account restrictions.
- Discord cannot pass captcha, security-key or SMS-only challenges. LinkedIn cannot pass captcha
  or other verification challenges.
- Signing out of WeChat, Discord or LinkedIn removes the encrypted local session. Revoke any
  remaining session in that network's own settings.
- iMessage reads the local Messages database and sends through Apple events, so there is no relay
  for other platforms. iOS shows a disabled "Coming soon" placeholder.

## Using the app

- Link your accounts on each device. Inbox+ does not sync preferences, drafts or contacts between
  devices. Your messages still sync through each network's own linked-device rules.
- The app shows only the sign-in methods and actions that a connector supports on that device.
- A phone can suspend the app. There is no always-on server or notification relay, so
  notifications arrive only while the app receives events.
- On Windows and Linux, hold Alt to show the menu letters, then press F, E, N, C or H. macOS uses
  the menu bar and Command shortcuts.
- iMessage's **New message** can search this Mac's Contacts when you allow access. You can always
  type an address instead.
- Updating from 0.8.5 keeps contacts and conversation choices, but you reconnect each account. See
  [Upgrading from 0.8.5](docs/updates.md#upgrading-from-085).

## Requirements

Use **Flutter 3.47.9** (Dart 3.13.7) and **Go 1.27.3**. The Go build refuses any other version. Set
`GO_BINARY` if the pinned executable is not called `go`.

| Target | Host and extra tools |
| --- | --- |
| macOS | macOS 15+, Xcode, Swift 6.2+, CocoaPods **1.16.2** and a C compiler |
| Windows (x64) | Windows, Visual Studio desktop C++ tools, CMake, Python 3, Git Bash and MinGW GCC |
| Linux | Clang or GCC, CMake, Ninja, pkg-config, and the GTK 3, libsecret, libmpv, WebKitGTK 4.1 and Ayatana AppIndicator development packages |
| iOS | macOS, Xcode, the iOS SDK and CocoaPods **1.16.2**. Installing needs signing and a provisioning profile |
| Android | macOS, Linux or Windows, with the Android SDK, JDK 17+, NDK **28.2.13676358**, Python 3, Bash and a C compiler |

On Debian or Ubuntu:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libmpv-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev
```

Only the build machine needs these tools. The packaged app needs none of them, apart from the
Linux system libraries.

## Build from source

```bash
cd apps/inboxplus
flutter pub get --enforce-lockfile
flutter run -d macos
```

- Use `-d windows`, `-d linux` or a device ID from `flutter devices` for another target.
- The native runner builds and bundles the connector library, so Go, Bash and a C compiler must be
  on its search path. Restart an IDE that was open before you installed a toolchain.
- For a release build, run `flutter build macos --release` on the matching host. The other targets
  are `windows`, `linux`, `apk` and `ios --no-codesign`.
- Tests, packaging and releases are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## How it fits together

```text
apps/inboxplus          shared Flutter interface and application controller
  lib/ui                       responsive inbox, conversations, contacts and settings
  lib/connectors               C ABI worker isolate; normalized account-scoped events
  lib/platform                 credential store, private files and native method channel
  android/ios/macos/windows/linux   platform permissions, authentication and lifecycle
packages/inboxplus_storage      encrypted Drift/SQLite records, drafts and durable outbox
native/connectors              embedded Go network clients, encrypted connector state, C ABI
native/imessage                Swift package for the local macOS Messages adapter
```

- All five runners share the Dart application code and one embedded Go connector library, built
  from pinned source.
- `lib/ui/inbox_app.dart` picks the desktop shell on macOS, Windows and Linux. The mobile layout
  is separate and reuses the controller and storage.
- Conversation routes are account-scoped, so the same network ID in two accounts stays separate.
- Draft revisions and a durable outbox stop an acknowledged send from clearing newer text. An
  uncertain send stays visible instead of being sent twice.
- SQLite3MultipleCiphers encrypts the database. Its random key lives in the OS credential store,
  and each account's connector state has its own key.

## Privacy and security

- No Inbox+ cloud. Each device talks directly to the networks it connects.
- Credentials and database keys live in the OS credential store. Logs and errors never include
  tokens, cookies, message bodies or attachment URLs.
- Private app files are owner-only. Cached media is private but not database-encrypted.
- Web sign-ins use a non-persistent web view and keep only the cookies a connector declares.
- Downloaded binaries are pinned and SHA-256 verified before use. Go modules and pub packages have
  committed integrity locks. See the [dependency inventory](docs/dependencies.md).
- **Open in app** follows only `https` links on a domain the named network owns.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Agents also follow [AGENTS.md](AGENTS.md). Changes reach
`main` through pull requests with passing checks.

## License

[AGPL-3.0-or-later](LICENSE). The embedded Meta and LinkedIn clients are also AGPL-3.0-or-later.
Check the [dependency inventory](docs/dependencies.md) and its redistribution obligations before
you distribute a build.
