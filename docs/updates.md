# App updates

Inbox+ uses Sparkle 2.10.0. The app checks a stable HTTPS appcast, downloads a signed ZIP from a
specific GitHub Release, verifies it, and replaces only the app bundle. A reminder appears above
Settings in the rail as soon as an update is found. Clicking it opens Sparkle's standard update UI.
Dismiss keeps the reminder; Skip hides it. Manual checks are in the application menu.

Release builds enable checks and downloads every four hours. Downloads can install on normal quit.
The termination gate covers explicit update restarts and installation on quit: it refuses unsent
drafts, staged attachments, pending sends and setup in progress, disables messaging controls during
shutdown, and waits up to 30 seconds for the app-owned CLI to stop. A timeout cancels termination
instead of force-killing a database writer. Separately started runtimes remain under their owner's
control.

## One-time release setup

1. Obtain an Apple Developer ID Application certificate and configure notarization as described in
   `Scripts/package-release.sh`. Preserve the bundle identifier `com.inboxplus.app`, profile paths,
   and Keychain identifiers between releases.
2. Run `swift package resolve` and then:

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Sparkle stores the private key in the login Keychain and prints the public key. Keep a secure
   backup of the private key using the tool's `-x` option; never commit it. The public key is safe
   to distribute. The package scripts intentionally do not generate a production key for you.
3. Enable GitHub Pages for this repository, using **GitHub Actions** as its source. The default feed
   is `https://tsha0.github.io/InboxPlus/appcast.xml`. For another host, set
   `INBOXPLUS_UPDATE_FEED_URL` when building each release and publish the feed at that address.

## Package a release

Increment the app's display version in `Sources/InboxPlusCore/InboxPlusVersion.swift`. Choose a build
number greater than every shipped build; it is separate from the display version.

```bash
export INBOXPLUS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export INBOXPLUS_TEAM_ID='YOURTEAMID'
export INBOXPLUS_NOTARY_PROFILE='inboxplus-notary'
export INBOXPLUS_UPDATE_PUBLIC_KEY='PUBLIC_KEY_FROM_GENERATE_KEYS'
export INBOXPLUS_BUILD_NUMBER='106'
export INBOXPLUS_RELEASE_TAG='v0.6.0'
# Optional: an HTML fragment containing this release's notes.
export INBOXPLUS_RELEASE_NOTES_FILE='/absolute/path/to/release-notes.html'
Scripts/package-release.sh
```

Use your actual version, build number, identifiers and key. The script tests, builds, embeds and
signs Sparkle's helpers, signs the app/runtime, notarizes, staples, generates a final ZIP, then uses
Sparkle's `generate_appcast` to sign that exact ZIP. The private key comes from Keychain, or from
`INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE` for a controlled CI release environment. The public key embedded
in the app must match the signing key. The archive URL includes the release tag and versioned asset
name; do not replace a published ZIP with different bytes.

Reuse the release directory's existing `appcast.xml` on subsequent releases to preserve compatible
older items. On another build machine, first download the currently served feed into that directory.
Full ZIPs are used initially; delta generation is disabled. Release notes are embedded in the feed.

Upload the ZIP, `appcast.xml`, SBOM and checksums to a draft GitHub Release with the matching tag.
Review its artifacts and publish it. The **Publish update feed** workflow downloads the appcast
asset, validates its versioned GitHub download URLs, signature metadata and build numbers, and
deploys it to Pages. Prereleases do not automatically deploy to the stable feed. The workflow can
also be dispatched for a specific published tag.

Publishing a release without an `appcast.xml` asset fails the feed workflow rather than replacing
the live feed with an empty file. The feed is made discoverable after the release assets exist.
The workflow validates feed structure; clients perform cryptographic archive verification.

## User data and compatibility

Sparkle replaces `/Applications/Inbox+.app`; it does not delete or reset Application Support,
Messages' database, preferences, or Keychain entries. No runtime or database versions are changed
by this feature. This first updater release supports updates using the existing runtime contract.
Before shipping a future release that changes that contract, implement and verify its profile/data
migrations; do not assume app replacement upgrades the Python/runtime copy already in a profile.
Never recover from a failed migration by silently creating an empty profile.

An installed version without Sparkle needs one manual installation of the first signed
Sparkle-enabled release. Gatekeeper/notarization and a two-version update test on a separate
Mac/user account must pass before publishing the first production feed. Those checks require the
real Developer ID certificate and production Sparkle key.

## Development and verification

`Scripts/build-app.sh` embeds Sparkle but disables update checks unless explicitly opted in with
`INBOXPLUS_ENABLE_UPDATES=1`, a valid public key and build number. Running an unbundled executable
does not initialize Sparkle. The Debug-only `INBOXPLUS_UPDATE_PREVIEW_VERSION=0.6.0` environment
variable previews the rail button without contacting a feed or installing an update.

```bash
swift test
python3 -m unittest discover -s Tests/Packaging -v
bash -n Scripts/embed-sparkle.sh Scripts/generate-update-feed.sh Scripts/package-release.sh
Scripts/build-app.sh
codesign --verify --deep --strict 'build/Inbox+.app'
```

Release builds reject missing or malformed public keys, non-HTTPS feed URLs, and missing/nonpositive
build numbers. The Sparkle artifact is checksum-verified by SwiftPM and listed in the generated SBOM.
