# macOS updates

Production Flutter macOS releases use Sparkle 2.10.0. It checks the existing stable HTTPS feed every
four hours and can download updates automatically. **Inbox+ → Check for Updates…** opens Sparkle's
standard update UI. Installation on quit and explicit update restarts both use the app's termination
gate: flush drafts, confirm closing with unfinished work, wait for connector operations and shutdown,
and close encrypted storage. A failed shutdown cancels termination; no writer is force-killed.
Ordinary development and preview builds do not enable updates.

## Upgrading from 0.8.5

A Sparkle-enabled 0.8.5 installation can receive the Flutter app directly. Users do not need to
manually download or reinstall it. The first transition downloads a full signed ZIP; new delta
patches are disabled. Older published feed entries and delta URLs remain intact.

The shipped 0.8.5 archive was inspected without running it, and its archive signature was verified.
Its public compatibility contract is recorded in `native/updates/legacy-release.json`: build 111,
`com.inboxplus.app`, the existing GitHub Pages feed, Sparkle public key, certificate-based signing
requirement and Developer ID team. The packager refuses a different feed or key, a non-increasing
build, or a signature that fails the requirement for its signing mode. It stages the production
bundle as `Inbox+.app`. Profile paths and Keychain identifiers are unchanged.

Application replacement does not migrate every part of the old runtime. The current Flutter
migration imports saved contacts and conversation choices, requires reconnecting accounts, and
leaves previous message history and staged files in the original profile. Every generated release
includes this warning in its embedded update notes. Finish pending work in 0.8.5 before updating.
A failed migration must keep the old data and must never silently open an empty profile.

## Signing setup

Keep the original Sparkle private signing key. A newly generated update key will not satisfy the
existing compatibility checks. Never commit private keys, certificate backups or provisioning
profiles.

`INBOXPLUS_RELEASE_SIGNING` selects how the packager signs the app:

- `self-signed` uses the original self-signed release certificate and checks the recorded
  certificate requirement. These releases are not notarized, so new users may need **Open Anyway**
  in System Settings. Each new build also needs fresh Keychain approval for every saved secret, so
  users see several Keychain prompts after each update.
- `developer-id` uses a Developer ID Application certificate from team `36T8WB4DH2`. It embeds a
  Developer ID provisioning profile, then notarizes and staples the app. The packager checks for an
  Apple-issued certificate with the recorded team and the `com.inboxplus.app` identifier. The
  profile grants the keychain access group `36T8WB4DH2.com.inboxplus.app`, so the app stores its
  secrets in the data protection keychain and opens without Keychain prompts.

To create the profile, add a **Developer ID** provisioning profile for the `com.inboxplus.app` App ID
in the Apple Developer portal. The packager decodes it with `security cms` and refuses it unless it
is a macOS Developer ID profile for `36T8WB4DH2.com.inboxplus.app` that allows that keychain group.
It copies the profile to `Contents/embedded.provisionprofile`. It signs the app with
`Release.entitlements` plus the application identifier, the team identifier and the keychain group.
`Release.entitlements` itself has none of these entitlements, because ad-hoc development builds
cannot launch with them. Those builds keep using the file-based login keychain.

### Switch to Developer ID signing

The first Developer ID release moves each saved secret from the file-based login keychain to the
data protection keychain, under the same service and account names. Before moving a secret, the app
must read it, so users see one final round of Keychain prompts. There is one prompt for each saved
secret: the database key, two profile records, the preferences and each connected account. If a
user denies a prompt, that secret stays in the old keychain and the next launch asks again. After
the move, later releases open without prompts.

The new signing identity also changes the app's code requirement. macOS can ask users to grant Full
Disk Access and Automation access again.

For GitHub Actions, configure the `macos-release` environment:

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

Credentials and the provisioning profile are written with mode `0600` in a `0700` temporary
directory. Certificates are imported into an isolated temporary Keychain. Cleanup runs even after
failure. The public update key and the Developer ID team come from the committed compatibility
contract; they are not secrets.

## Build a release

1. Raise `version:` in `apps/inboxplus/pubspec.yaml`, including a build number greater than
   every published build. Regenerate the SBOM/notices and run the relevant checks.
2. After the change is merged, push a matching version tag (for example `0.9.1+115` uses `v0.9.1`).
   Tags also trigger the separate iOS TestFlight workflow.
3. Run **macOS release** manually with that tag. The workflow uses Flutter 3.47.9, Go 1.27.3,
   Python 3.12 and the runner's default Xcode, which it records in the log. It checks the tag/version, runs tests, downloads the current feed,
   builds the native app and signs all nested code before the outer bundle.
4. It verifies runtime files/architectures and signatures, packages the exact final bundle,
   generates the appcast, cryptographically verifies its archive signature against the embedded
   public key, and attaches ZIP, SBOM, appcast and checksums to a draft GitHub Release. Existing
   assets are never overwritten. A published release cannot be reused as the output target.
5. Review the artifacts and publish the stable release.
   **Publish update feed** then validates and deploys its appcast to the existing GitHub Pages URL.
   It refuses prereleases, drafts, rollback to an older build, or changes/removal of existing feed
   entries. Assets must already exist before the feed becomes discoverable. GitHub Pages must use
   **GitHub Actions** as its publishing source.

If the release was published by automation that suppresses subsequent workflow events, manually
run **Publish update feed** with its published stable tag.

Local packaging uses the same script, with the original certificate available in Keychain:

```bash
export INBOXPLUS_RELEASE_SIGNING=self-signed
export INBOXPLUS_SIGNING_IDENTITY='Inbox+ Release Signing'
curl --fail --location --proto '=https' --proto-redir '=https' \
  https://tsha0.github.io/InboxPlus/appcast.xml --output build/previous-appcast.xml
python3 Scripts/package-macos-release.py --previous-feed build/previous-appcast.xml
```

Use Python 3.12 and the pinned Flutter/Go toolchains on `PATH`; create `build` first if absent.
Sparkle reads the private key from its existing Keychain entry, or from
`INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE` pointing to a protected exported key file. Optional
`INBOXPLUS_RELEASE_NOTES_FILE` supplies an HTML fragment; the migration notice is appended.
`--bundle` selects an already-built release app, and `--output` selects a fresh artifact directory.
For Developer ID packaging, `INBOXPLUS_NOTARY_PROFILE` names a configured `notarytool` profile, and
`INBOXPLUS_PROVISIONING_PROFILE` is the path to the Developer ID `.provisionprofile` file.

The local packager never uploads artifacts or publishes the feed. Development archives from
`Scripts/package-flutter-desktop.py` remain separate and cannot serve as Sparkle release archives.

## Verification before publishing

Run the packaging suite, `swift test --package-path native/updates --force-resolved-versions`,
Flutter analysis/tests, and a native macOS release build. Verify that the extracted production ZIP
has an `Inbox+.app` at its root, keeps framework symlinks and executable permissions, and passes
strict code-signature and runtime checks. A Developer ID release must also pass notarization,
stapling and Gatekeeper assessment.

A successful development build or fixture suite does not establish production signing, Gatekeeper
acceptance or a working end-to-end update. Signing and Gatekeeper checks need the original signing
credentials. An installed update is not tested as part of a release.
