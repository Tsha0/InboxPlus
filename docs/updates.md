# macOS updates

Production macOS releases update through Sparkle 2.10.0.

- Sparkle checks the stable HTTPS feed every four hours and can download an update automatically.
- **Inbox+ → Check for Updates…** opens Sparkle's standard update window.
- Installing on quit and restarting for an update both go through the app's termination gate. The
  gate flushes drafts, asks before it closes unfinished work, waits for connector operations and
  shutdown, and closes encrypted storage.
- A failed shutdown cancels termination. No writer is force-killed.
- Development and preview builds do not enable updates.

## Upgrading from 0.8.5

A Sparkle-enabled 0.8.5 installation updates straight to the Flutter app. Nobody has to download
or reinstall it by hand.

- The first update downloads a full signed ZIP. New delta patches are disabled. Older feed entries
  and delta URLs stay as published.
- `native/updates/legacy-release.json` records what 0.8.5 expects: build 111, `com.inboxplus.app`,
  the GitHub Pages feed, the Sparkle public key, the certificate-based signing requirement and the
  Developer ID team.
- The packager refuses a different feed or key, a build number that does not increase, or a
  signature that fails the requirement for its signing mode. It stages the bundle as `Inbox+.app`.
- Profile paths and Keychain identifiers are unchanged.

The update replaces the app but does not move everything from the old runtime:

- On first open, the app imports saved contacts and conversation choices in one database
  transaction. Conversation choices are favorites, unread overrides, mutes and hidden chats. The
  original files stay intact.
- You reconnect each account with the device-local connectors and relink saved remote identities.
- Earlier message history, credentials and staged files stay in the original profile.
- A missing key, a corrupt store, an unsupported schema or a failed import stops with an error and
  keeps the data. The app never opens an empty profile in its place.
- Every release repeats this warning in its update notes. Finish pending work in 0.8.5 before you
  update, and keep the old profile until the new connections and imported choices are verified.

## Signing setup

- Keep the original Sparkle private signing key. A new key fails the compatibility checks.
- Never commit private keys, certificate backups or provisioning profiles.

`INBOXPLUS_RELEASE_SIGNING` selects how the packager signs the app:

- `self-signed` uses the original self-signed release certificate and checks the recorded
  certificate requirement.
  - These releases are not notarized, so a new user may need **Open Anyway** in System Settings.
  - Each new build needs fresh Keychain approval for every saved secret, so users see several
    Keychain prompts after each update.
- `developer-id` uses a Developer ID Application certificate from team `36T8WB4DH2`.
  - The packager embeds a Developer ID provisioning profile, then notarizes and staples the app.
  - It checks for an Apple-issued certificate with the recorded team and the `com.inboxplus.app`
    identifier.
  - The profile grants the keychain access group `36T8WB4DH2.com.inboxplus.app`. The app then
    stores its secrets in the data protection keychain and opens without Keychain prompts.

### Create the Developer ID profile

In the Apple Developer portal, add a **Developer ID** provisioning profile for the
`com.inboxplus.app` App ID.

- The packager decodes the profile with `security cms`. It refuses any profile that is not a macOS
  Developer ID profile for `36T8WB4DH2.com.inboxplus.app` with that keychain group.
- It copies the profile to `Contents/embedded.provisionprofile`.
- It signs the app with `Release.entitlements` plus the application identifier, the team
  identifier and the keychain group.
- `Release.entitlements` has none of those three entitlements, because an ad-hoc development build
  cannot launch with them. Development builds keep the file-based login keychain.

### Switch to Developer ID signing

- The first Developer ID release moves each saved secret from the file-based login keychain to the
  data protection keychain, under the same service and account names.
- The app must read a secret before it moves it, so users see one last round of Keychain prompts.
  There is one prompt for each saved secret: the database key, two profile records, the
  preferences and each connected account.
- If a user denies a prompt, that secret stays in the old keychain and the next launch asks again.
- After the move, later releases open without prompts.
- The new signing identity changes the app's code requirement. macOS can ask users to grant Full
  Disk Access and Automation access again.

### Configure GitHub Actions

Set these in the `macos-release` environment:

| Setting | Kind | Value |
| --- | --- | --- |
| `INBOXPLUS_SIGNING_IDENTITY` | Variable | Name of the signing certificate for the selected mode |
| `INBOXPLUS_RELEASE_SIGNING` | Variable | `self-signed` (default) or `developer-id` |
| `MACOS_SIGNING_P12_BASE64` | Secret | Base64 of the signing certificate and private key as a P12 file |
| `MACOS_SIGNING_P12_PASSWORD` | Secret | P12 password |
| `INBOXPLUS_SPARKLE_PRIVATE_KEY` | Secret | Original Sparkle key exported with `generate_keys -x` |
| `MACOS_PROVISIONING_PROFILE_BASE64` | Secret | Developer ID only. Base64 of the Developer ID `.provisionprofile` |
| `MACOS_NOTARY_APPLE_ID` | Secret | Developer ID only. Apple ID used for notarization |
| `MACOS_NOTARY_PASSWORD` | Secret | Developer ID only. App-specific password for that Apple ID |
| `MACOS_TEAM_ID` | Variable | Developer ID only. `36T8WB4DH2` |

- The workflow writes credentials and the provisioning profile with mode `0600` in a `0700`
  temporary directory, and imports certificates into an isolated temporary Keychain. Cleanup runs
  even after a failure.
- The public update key and the Developer ID team come from the committed compatibility contract.
  They are not secrets.

## Build a release

1. Raise `version:` in `apps/inboxplus/pubspec.yaml`. The build number must be greater than every
   published build. Regenerate the SBOM and notices and run the relevant checks.
2. After the change merges, push the matching version tag. `v0.9.1` releases `0.9.1+115`. The tag
   also triggers the separate iOS TestFlight workflow.
3. Run **macOS release** manually with that tag.
4. Review the artifacts on the draft GitHub Release and publish the stable release.

The **macOS release** workflow:

- Uses the pinned Flutter, Go and Python versions and the runner's default Xcode, which it records
  in the log.
- Checks the tag against the version, runs tests, downloads the current feed and builds the app.
- Signs all nested code before the outer bundle, then verifies runtime files, architectures and
  signatures.
- Packages the exact final bundle, generates the appcast and verifies the archive signature
  against the embedded public key.
- Attaches the ZIP, SBOM, appcast and checksums to a draft GitHub Release. It never overwrites an
  existing asset and never reuses a published release as its output.

Publishing the stable release starts **Publish update feed**:

- It validates the appcast and deploys it to the existing GitHub Pages URL.
- It refuses a prerelease, a draft, a rollback to an older build, and any change to or removal of
  an existing feed entry.
- The release assets must exist before the feed points to them.
- GitHub Pages must use **GitHub Actions** as its publishing source.
- If automation published the release and suppressed the workflow event, run **Publish update
  feed** manually with the published stable tag.

## Package a release locally

Local packaging uses the same script, with the original certificate in Keychain:

```bash
export INBOXPLUS_RELEASE_SIGNING=self-signed
export INBOXPLUS_SIGNING_IDENTITY='Inbox+ Release Signing'
curl --fail --location --proto '=https' --proto-redir '=https' \
  https://tsha0.github.io/InboxPlus/appcast.xml --output build/previous-appcast.xml
python3 Scripts/package-macos-release.py --previous-feed build/previous-appcast.xml
```

- Use Python 3.12 with the pinned Flutter and Go toolchains on `PATH`. Create `build` first if it
  does not exist.
- Sparkle reads the private key from its Keychain entry, or from the protected key file that
  `INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE` names.
- `INBOXPLUS_RELEASE_NOTES_FILE` optionally supplies an HTML fragment. The packager appends the
  migration notice to it.
- `--bundle` selects a release app that is already built. `--output` selects a fresh artifact
  directory.
- For Developer ID packaging, `INBOXPLUS_NOTARY_PROFILE` names a configured `notarytool` profile
  and `INBOXPLUS_PROVISIONING_PROFILE` is the path to the `.provisionprofile` file.
- The local packager never uploads artifacts or publishes the feed.
- A development archive from `Scripts/package-flutter-desktop.py` cannot serve as a Sparkle
  release archive.

## Verify before publishing

- Run the packaging suite, `swift test --package-path native/updates --force-resolved-versions`,
  Flutter analysis and tests, and a native macOS release build.
- Extract the production ZIP. It must have `Inbox+.app` at its root, keep framework symlinks and
  executable permissions, and pass strict code-signature and runtime checks.
- A Developer ID release must also pass notarization, stapling and Gatekeeper assessment.
- A development build or a fixture suite does not prove production signing, Gatekeeper acceptance
  or a working end-to-end update. Signing and Gatekeeper checks need the original signing
  credentials.
- A release does not test an installed update.
