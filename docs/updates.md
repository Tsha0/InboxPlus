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

1. Create the release signing certificate. Every release must be signed with the same one: macOS
   remembers Full Disk Access and Automation grants by it, so a release signed with another
   certificate makes every user grant access again. Preserve the bundle identifier
   `com.inboxplus.app`, profile paths, and Keychain identifiers between releases too.

   The free route is a self-signed certificate:

   ```bash
   Scripts/create-signing-certificate.sh .signing/inboxplus-release-signing.p12
   ```

   It adds **Inbox+ Release Signing** to the login Keychain and writes a password-protected backup.
   `.signing/` is ignored by git, but it is on the same disk as the Keychain, so also copy the
   backup and its password somewhere offline; without them, no future release can be signed as the
   same app. The first time a release is signed, macOS asks whether `codesign` may use the key;
   choose **Always Allow**.

   Self-signed releases are not notarized. On first launch of a downloaded copy, macOS blocks
   Inbox+ until the user chooses **Open Anyway** in System Settings → Privacy & Security. Updates
   installed by Sparkle after that open normally.

   With a paid Apple Developer Program membership, use a Developer ID Application certificate and
   configure notarization as described in `Scripts/package-release.sh` instead. Moving from a
   self-signed certificate to Developer ID later changes the app's identity once.
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
export INBOXPLUS_RELEASE_SIGNING='self-signed'
export INBOXPLUS_SIGNING_IDENTITY='Inbox+ Release Signing'
export INBOXPLUS_UPDATE_PUBLIC_KEY='PUBLIC_KEY_FROM_GENERATE_KEYS'
export INBOXPLUS_BUILD_NUMBER='106'
export INBOXPLUS_RELEASE_TAG='v0.6.0'
# Optional: an HTML fragment containing this release's notes.
export INBOXPLUS_RELEASE_NOTES_FILE='/absolute/path/to/release-notes.html'
Scripts/package-release.sh
```

For Developer ID, set `INBOXPLUS_RELEASE_SIGNING='developer-id'`, use the Developer ID certificate's
name as the identity, and also set `INBOXPLUS_TEAM_ID` and `INBOXPLUS_NOTARY_PROFILE`.

Use your actual version, build number, identifiers and key. The script tests, builds, embeds and
signs Sparkle's helpers, signs the app/runtime, and refuses a signature whose identity is not tied
to a certificate. Developer ID releases are then hardened, notarized and stapled; self-signed
releases are not hardened, because hardened library validation needs an Apple Team ID and would
refuse the bundled runtime's native modules. It generates a final ZIP, then uses Sparkle's
`generate_appcast` to sign that exact ZIP. The private key comes from Keychain, or from
`INBOXPLUS_SPARKLE_PRIVATE_KEY_FILE` for a controlled CI release environment. The public key embedded
in the app must match the signing key. The archive URL includes the release tag and versioned asset
name; do not replace a published ZIP with different bytes.

Reuse the release directory's existing `appcast.xml` on subsequent releases to preserve compatible
older items, and keep earlier release ZIPs there. Each new release gets a delta update from up to
three earlier builds whose ZIPs are present: a small patch, so an app on 0.5.1 downloads tens of KB
for a version-only change instead of the full 125 MB ZIP. Sparkle falls back to the full ZIP if a
patch cannot be applied. On another build machine, first download the currently served feed and
the most recent release ZIPs into that directory. Earlier feed entries are kept exactly as
published (`Scripts/finalize-update-feed.py`). Release notes are embedded in the feed.

Upload the files the script lists — the ZIP, its `InboxPlus-<build>-<earlier>.delta` patches,
`appcast.xml`, SBOM and checksums — to a draft GitHub Release with the matching tag.
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
Sparkle-enabled release. A first-launch Gatekeeper check (and notarization, for Developer ID) and a
two-version update test on a separate Mac/user account must pass before publishing the first
production feed. Those checks require the production signing certificate and Sparkle key. The
update test should confirm Full Disk Access is still granted after the update installs.

## Development and verification

`Scripts/build-app.sh` embeds Sparkle but disables update checks unless explicitly opted in with
`INBOXPLUS_ENABLE_UPDATES=1`, a valid public key and build number. Running an unbundled executable
does not initialize Sparkle. The Debug-only `INBOXPLUS_UPDATE_PREVIEW_VERSION=0.6.0` environment
variable previews the rail button without contacting a feed or installing an update.

```bash
swift test
python3 -m unittest discover -s Tests/Packaging -v
bash Tests/Packaging/verify-self-signed-identity.sh
bash -n Scripts/embed-sparkle.sh Scripts/generate-update-feed.sh Scripts/package-release.sh
Scripts/build-app.sh
codesign --verify --deep --strict 'build/Inbox+.app'
```

Release builds reject missing or malformed public keys, non-HTTPS feed URLs, and missing/nonpositive
build numbers. The Sparkle artifact is checksum-verified by SwiftPM and listed in the generated SBOM.
