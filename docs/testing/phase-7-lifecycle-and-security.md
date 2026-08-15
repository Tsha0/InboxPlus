# Phase 7 production lifecycle and security — developer acceptance

Phase 7 covers what has to be true before Pallo can be handed to someone else: a signed bundle, a
bill of materials, diagnostics that are safe to share, and a way to remove the whole thing.

Part of it is delivered and tested. Part of it cannot be done on this machine, and that part is
named rather than approximated.

## 1. Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Expect 531 tests passing.

## 2. Software bill of materials

```sh
PalloRuntimeCLI sbom --output docs/sbom.cdx.json
```

CycloneDX 1.5, generated from `BridgeCatalog` and the runtime pins rather than maintained by hand.
14 components, 12 with verified SHA-256 hashes, 13 with a package URL.

The document is **deterministic**: the timestamp and serial are derived from the content, so
identical pins produce a byte-identical file and two releases can be diffed. An inventory that
changes on every run cannot be reviewed.

The one component a scanner cannot look up — `libolm`, which is built from a patched tarball rather
than consumed from a package registry — is reported in the tool's own output:

```
1 component(s) have no package URL and cannot be matched against an advisory database: libolm
```

Stating the gap is the point. A bill of materials that silently omits what it cannot describe is
worse than none, because it will be believed.

## 3. Redacted diagnostics

```sh
PalloRuntimeCLI diagnostics --profile demo --output ~/Desktop/pallo-diagnostics
```

Collects logs and configuration only, passes every byte through `DiagnosticsRedactor`, and writes
`0600` files into a `0700` directory alongside a manifest naming what was included and what was
excluded.

The rule is that a bundle is something a user can hand to a stranger, so the question for each file
is not "is this useful" but "would I be comfortable if this were posted publicly".

Removed by pattern, so a secret nobody registered is still caught:

| Category | Treatment |
| --- | --- |
| Access tokens, `Authorization` headers | removed |
| `as_token`, `hs_token`, `shared_secret`, passwords | removed |
| Cookies, whole headers and individual pairs | removed |
| Message bodies and formatted bodies | removed |
| `mxc://` attachment URLs | removed — the id alone fetches the file |
| Verification codes | removed |
| User IDs, emails, phone numbers | **pseudonymised**, not deleted |

Identifiers are pseudonymised rather than dropped because a log in which every user is `[redacted]`
cannot show that two events concern the same person, which is usually the thing being debugged. The
pseudonym is salted, so it cannot be reversed by hashing a suspected handle.

**This design was corrected by running it.** The first version excluded files by exact name. Run
against a real profile, it collected `pallo.signing.key` — the homeserver's raw ed25519 key — because
the blocklist said `signing.key` and the file had a prefix. It also collected a probe credential
file. Exclusion is now deny-by-substring, which fails safe: it can only ever exclude too much, and
excluding a log is a nuisance where including a key is a compromise. Both files are now regression
tests.

## 4. Signing and notarization

`Scripts/package-release.sh` builds an `.app` bundle, signs inner binaries before the bundle, signs
with the hardened runtime and `Scripts/pallo.entitlements`, notarizes, staples, re-zips after
stapling, then emits the bill of materials and `SHA256SUMS.txt`.

**It has never run.** It requires:

```sh
export PALLO_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export PALLO_TEAM_ID="XXXXXXXXXX"
export PALLO_NOTARY_PROFILE="pallo-notary"
```

Without a Developer ID there is nothing to sign with, so the script has only been checked for
syntax and for failing cleanly when the variables are absent. Every step in it is unverified.

The entitlements are deliberately narrow. `disable-library-validation` is present because bridges
are Go binaries built elsewhere and the runtime is a Python interpreter, none of which carry Pallo's
signature. JIT and unsigned executable memory are deliberately absent: Pallo runs no interpreted
code of its own, so granting either would widen the attack surface for nothing. Pallo is not
sandboxed — supervising downloaded processes is not something the App Sandbox permits — so hardened
runtime plus notarization is the applicable protection for Developer ID distribution.

### Why this matters beyond distribution

macOS binds permission grants to a **code identity**. An ad-hoc signature has none: its CDHash
changes on every build, so each rebuild looks like a different application and every Full Disk
Access, Automation and Screen Recording grant must be given again. That is the cause of the
repeated permission prompts during development, and signing is the fix.

It is also why no screenshot in this project's Phase 5 notes could be captured: screen recording
against an ad-hoc binary returns black.

## What Phase 7 did not deliver

- **Nothing is signed or notarized.** Blocked on an Apple Developer ID. The script exists and is
  unverified.
- **No launch-at-login.** `SMAppService` registers a bundled application, and Pallo has no signed
  bundle yet, so this is blocked behind the same door.
- **No atomic updater and no rollback.** These need a release feed, a signed artifact to update
  *to*, and a version to roll back *from* — none of which exist before the first signed release.
  `PalloVersion.compare` is in place and tested, because comparing versions as text is how an
  updater offers `0.9.0` as an upgrade from `0.10.0`.
- **No in-app uninstall flow.** The design requires **Settings → Uninstall Pallo** and a standalone
  uninstaller. The machinery exists and is tested — `ProfileRemover` and
  `PalloRuntimeCLI remove --profile <name> --confirm <name>` stop the runtime and remove exactly one
  contained profile — but it is not surfaced in the app and there is no separate signed uninstaller
  binary.
- **No vulnerability scanning in CI.** The SBOM is the input a scanner needs and is now generated;
  nothing consumes it yet. There is no CI in this repository at all.
- **Keychain policy is inherited, not hardened.** The store passphrase uses
  `kSecAttrAccessibleWhenUnlocked` from Phase 3. It was not revisited here, and there is no
  documented rotation or migration path.
