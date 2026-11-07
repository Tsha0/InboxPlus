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
`com.inboxplus.app`, the existing GitHub Pages feed, Sparkle public key and certificate-based signing
requirement. The packager refuses a different feed/key, a non-increasing build or a signature that
does not satisfy that requirement. It stages the production bundle as `Inbox+.app`, independently
of the development app's `Inbox+v2` name. Profile paths and Keychain identifiers are unchanged.

Application replacement does not migrate every part of the old runtime. The current Flutter
migration imports saved contacts and conversation choices, requires reconnecting accounts, and
leaves previous message history and staged files in the original profile. Every generated release
includes this warning in its embedded update notes. Finish pending work in 0.8.5 before updating.
A failed migration must keep the old data and must never silently open an empty profile.

## Signing setup

Keep the original release certificate/private key and the original Sparkle private signing key.
A newly generated certificate or update key will not satisfy the existing compatibility checks.
Never commit private keys or certificate backups.

The original release used a self-signed certificate. Keep `INBOXPLUS_RELEASE_SIGNING=self-signed`
for this restoration. Those releases are not notarized: new users may need **Open Anyway** in
System Settings, while the existing Sparkle update path must be tested separately. The packager
also contains a Developer ID/notarization path, but changing from the original certificate requires
a separately reviewed identity transition and an updated compatibility contract; toggling the
signing mode alone does not bypass the existing signing requirement.

For GitHub Actions, configure the `macos-release` environment:

| Setting | Kind | Value |
| --- | --- | --- |
| `INBOXPLUS_SIGNING_IDENTITY` | Variable | Original release certificate's name |
| `INBOXPLUS_RELEASE_SIGNING` | Variable | `self-signed` (default) |
| `MACOS_SIGNING_P12_BASE64` | Secret | Base64 of the original certificate/private-key P12 backup |
| `MACOS_SIGNING_P12_PASSWORD` | Secret | P12 password |
| `INBOXPLUS_SPARKLE_PRIVATE_KEY` | Secret | Original Sparkle key exported with `generate_keys -x` |

Credentials are written with mode `0600` in a `0700` temporary directory and imported into an
isolated temporary Keychain. Cleanup runs even after failure. The public update key comes from the
committed compatibility contract; it is not a secret. Developer ID mode additionally requires
`MACOS_NOTARY_APPLE_ID` and `MACOS_NOTARY_PASSWORD` secrets and the `MACOS_TEAM_ID` variable.

## Build a release

1. Raise `version:` in `apps/inboxplus_flutter/pubspec.yaml`, including a build number greater than
   every published build. Regenerate the SBOM/notices and run the relevant checks.
2. After the change is merged, push a matching version tag (for example `0.9.1+115` uses `v0.9.1`).
   Tags also trigger the separate iOS TestFlight workflow.
3. Run **macOS release** manually with that tag. The workflow uses Flutter 3.47.9, Go 1.27.3,
   Python 3.12 and Xcode 27.2. It checks the tag/version, runs tests, downloads the current feed,
   builds the native app and signs all nested code before the outer bundle.
4. It verifies runtime files/architectures and signatures, packages the exact final bundle,
   generates the appcast, cryptographically verifies its archive signature against the embedded
   public key, and attaches ZIP, SBOM, appcast and checksums to a draft GitHub Release. Existing
   assets are never overwritten. A published release cannot be reused as the output target.
5. Perform the installation tests below, review the artifacts and publish the stable release.
   **Publish update feed** then validates and deploys its appcast to the existing GitHub Pages URL.
   It refuses prereleases, drafts, rollback to an older build, or changes/removal of existing feed
   entries. Assets must already exist before the feed becomes discoverable. GitHub Pages must use
   **GitHub Actions** as its publishing source.

If the release was published by automation that suppresses subsequent workflow events, manually
run **Publish update feed** with its published stable tag. Do not enable stable publication until
the migration behavior and two-version installation test have been reviewed.

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
For Developer ID packaging, `INBOXPLUS_NOTARY_PROFILE` names a configured `notarytool` profile.

The local packager never uploads artifacts or publishes the feed. Development archives from
`Scripts/package-flutter-desktop.py` remain separate and cannot serve as Sparkle release archives.

## Verification before publishing

Run the packaging suite, `swift test --package-path native/updates --force-resolved-versions`,
Flutter analysis/tests, and a native macOS release build. Verify that the extracted production ZIP
has an `Inbox+.app` at its root, keeps framework symlinks and executable permissions, and passes
strict code-signature and runtime checks. A Developer ID release must also pass notarization,
stapling and Gatekeeper assessment.

On a separate Mac/user account with isolated test profiles, test an actual installed 0.8.5 → Flutter
update and a Flutter → Flutter update. Use a controlled feed with the original trust credentials;
do not publish a production feed merely to test installation. Confirm discovery, compatible
macOS/architecture filtering, download, restart, app path, permission grants and profile access.
Verify reconnect/import messaging, old data retention, and that a migration failure keeps data.
Test postponing/cancelling a restart with drafts, staged attachments and pending sends, restoring
them after upgrade, interrupted downloads and invalid signatures. No live account is needed.

A successful development build or fixture suite does not establish production signing, Gatekeeper
acceptance or a working end-to-end update. Those checks need the original signing credentials and
the installed-release test above.
