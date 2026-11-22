# Inbox+

<p align="center">
  <img src="docs/assets/inboxplus-logo.png" alt="Inbox+ logo" width="320">
</p>

Inbox+ is a local-first messaging inbox for macOS, Windows, Linux, iOS and Android.

- There is no Inbox+ cloud account or server. Each device connects directly to your networks.
- It covers conversations, attachments and contacts. It has no feeds, stories or calls.

## Status

- **macOS** ships through [GitHub Releases](https://github.com/Tsha0/InboxPlus/releases). Open the
  DMG and drag Inbox+ onto Applications. Existing installations can use **Check for Updates…**.
- **iOS** builds go to TestFlight.
- **Windows and Linux** build in CI as development archives, with no installer or updates yet.
- **Android** builds are manual. The phone layouts are deferred.
- The newer connectors are not yet verified with live accounts.

## Networks

| Network | Client library | Sign-in | Limits |
| --- | --- | --- | --- |
| WhatsApp | whatsmeow | QR code or pairing code | |
| Telegram | gotd | Your Telegram API ID and hash, then a QR code or your phone and code, and an optional two-step password | No secret chats |
| Instagram | mautrix-meta (instameow) | Instagram's own sign-in page | macOS, iOS and Linux only |
| Facebook Messenger | mautrix-meta (messagix) | Facebook's own sign-in page | macOS, iOS and Linux only. No end-to-end encrypted chats yet |
| WeChat | openwechat | QR code, for accounts with WeChat web access | Experimental. Text and incoming attachments only. No older history |
| Discord | Arikawa | Email and password with an authenticator or backup code, or a session token | Experimental. Direct and group messages only, with replies and uploads up to 10 MiB |
| LinkedIn | linkedingo | Email and password with an email, SMS or authenticator code, or app approval | Experimental. History, text and attachment downloads only |
| iMessage | Local macOS Messages adapter | Full Disk Access and Automation permission | macOS only |

- **Experimental** means live sign-in and messaging are not validated yet.
- WeChat and LinkedIn cannot send attachments, replies or reactions yet.
- WeChat receives only messages that arrive after you connect. Download an attachment during the
  connection that received it.
- Discord's [self-bot policy](https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots)
  can lead to account restrictions.
- Discord cannot pass captcha, security-key or SMS-only challenges. LinkedIn cannot pass captcha
  or other verification challenges.
- Signing out of WeChat, Discord or LinkedIn removes the local session. Revoke any remaining
  session in that network's own settings.

## Using the app

- Link your accounts on each device. Inbox+ does not sync preferences, drafts or contacts between
  devices.
- On a phone, notifications arrive only while the app is running.
- On Windows and Linux, hold Alt to show the menu letters, then press F, E, N, C or H.
- iMessage's **New message** can search this Mac's Contacts when you allow access. You can always
  type an address instead.

## Requirements

Use **Flutter 3.47.9** (Dart 3.13.7) and **Go 1.27.3**. Set `GO_BINARY` if the pinned Go
executable is not called `go`.

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

## Build from source

```bash
cd apps/inboxplus
flutter pub get --enforce-lockfile
flutter run -d macos
```

- Use `-d windows`, `-d linux` or a device ID from `flutter devices` for another target.
- Go, Bash and a C compiler must be on the search path. Restart an IDE that was open before you
  installed a toolchain.
- For a release build, run `flutter build macos --release` on the matching host. The other targets
  are `windows`, `linux`, `apk` and `ios --no-codesign`.
- Tests, packaging and releases are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

```text
apps/inboxplus                Flutter app and platform runners
packages/inboxplus_storage    Encrypted local database
native/connectors             Go network connectors
native/imessage               macOS Messages adapter
native/updates                macOS updater
website                       Product site
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Agents also follow [AGENTS.md](AGENTS.md).

## License

[AGPL-3.0-or-later](LICENSE). The embedded Meta and LinkedIn clients are also AGPL-3.0-or-later.
Check the [dependency inventory](docs/dependencies.md) before you distribute a build.

<!-- Temporary PR review trigger test. -->
