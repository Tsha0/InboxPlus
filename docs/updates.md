# macOS updates

How to release a macOS update. The release scripts are `Scripts/package-macos-release.py`,
[macos-release.yml](../.github/workflows/macos-release.yml) and
[update-feed.yml](../.github/workflows/update-feed.yml).

## Keys and certificates

- Keep the original Sparkle private key. Installed apps reject updates signed with any other key.
- Never commit private keys, certificate backups or provisioning profiles.
- To create or renew the provisioning profile, add a **Developer ID** profile for the
  `com.inboxplus.app` App ID in the Apple Developer portal.

## GitHub Actions settings

Set these in the `macos-release` environment:

| Setting | Kind | Value |
| --- | --- | --- |
| `INBOXPLUS_RELEASE_SIGNING` | Variable | `developer-id` |
| `INBOXPLUS_SIGNING_IDENTITY` | Variable | Name of the Developer ID Application certificate |
| `MACOS_TEAM_ID` | Variable | `36T8WB4DH2` |
| `MACOS_SIGNING_P12_BASE64` | Secret | Base64 of the certificate and private key as a P12 file |
| `MACOS_SIGNING_P12_PASSWORD` | Secret | P12 password |
| `MACOS_PROVISIONING_PROFILE_BASE64` | Secret | Base64 of the Developer ID `.provisionprofile` |
| `MACOS_NOTARY_APPLE_ID` | Secret | Apple ID used for notarization |
| `MACOS_NOTARY_PASSWORD` | Secret | App-specific password for that Apple ID |
| `INBOXPLUS_SPARKLE_PRIVATE_KEY` | Secret | Original Sparkle key exported with `generate_keys -x` |

GitHub Pages must use **GitHub Actions** as its publishing source.

## Release

1. Raise `version:` in `apps/inboxplus/pubspec.yaml`. The build number must be greater than every
   published build. Regenerate the SBOM and notices.
2. After the change merges, push the matching tag. `v0.9.1` releases `0.9.1+115`.
3. Run **macOS release** with that tag. It creates a draft GitHub Release.
4. Run the [installed-update test](#test-an-installed-update) with the draft's ZIP.
5. Review the draft and publish it as a stable release.

If **Publish update feed** did not start after you published, run it manually with the tag.

## Test an installed update

Use a separate Mac or user account with isolated test profiles. No live account is needed.

1. Install the current release.
2. Serve the new build from a controlled feed signed with the original keys. Never publish the
   production feed to test an install.
3. Update, and confirm discovery, download, restart, app path, permission grants and profile
   access.
4. Postpone and cancel a restart with drafts, staged attachments and pending sends. Confirm that
   they survive the update.
5. Confirm that an interrupted download and an invalid signature both leave the installed app
   working.

## Package locally

With the signing certificate in Keychain, from the repository root:

```bash
mkdir -p build
export INBOXPLUS_RELEASE_SIGNING=self-signed
export INBOXPLUS_SIGNING_IDENTITY='Inbox+ Release Signing'
curl --fail --location --proto '=https' --proto-redir '=https' \
  https://tsha0.github.io/InboxPlus/appcast.xml --output build/previous-appcast.xml
python3 Scripts/package-macos-release.py --previous-feed build/previous-appcast.xml
```

- Use Python 3.12 with the pinned Flutter and Go toolchains on `PATH`.
- Use `developer-id` for any build you hand to someone else. Then also set
  `INBOXPLUS_NOTARY_PROFILE` to a configured `notarytool` profile and
  `INBOXPLUS_PROVISIONING_PROFILE` to the `.provisionprofile` path.
- `INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE` names a key file if the Sparkle key is not in Keychain.
- `INBOXPLUS_RELEASE_NOTES_FILE` optionally supplies an HTML fragment for the update notes.

## Verify before publishing

- Run the packaging suite, `swift test --package-path native/updates --force-resolved-versions`,
  Flutter analysis and tests, and a native macOS release build.
- Extract the release ZIP. Check that `Inbox+.app` is at its root and that it passes strict
  code-signature checks, notarization, stapling and Gatekeeper assessment.
- Only the signed release and the installed-update test prove that an update works.
