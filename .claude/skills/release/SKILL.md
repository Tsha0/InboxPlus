---
name: release
description: Decide whether Inbox+ has something worth shipping and whether it is safe to, then prepare the iOS TestFlight and macOS releases, or start the iOS upload when autonomy allows. Run weekly by the improvement loop, or when asked to cut a release.
---

# Release

Read first: `docs/agents/autonomy.md`. Releasing is the one step users feel directly, so when in
doubt, prepare and hand over instead of shipping.

## 1. What changed since the last release

- **iOS**: the last release is the newest closed issue labelled `release` titled
  `Release iOS v…`. If there is none, nothing has shipped yet and everything on `main` counts.
- **macOS**: the last release is the newest published GitHub Release tagged `v*` in
  `Tsha0/InboxPlus`. Drafts and prereleases do not count as shipped.

List the PRs merged since then. Ignore PRs that only touch docs, CI, tests or the playbook.

## 2. Is it ready

Ship an app only if all of these hold:

- at least one merged PR changes something a user would notice;
- the head of `main` is green on every required workflow, on a push run: `ci.yml` for macOS;
  `ios-ci.yml` and `companion-ci.yml` for iOS (the iOS release workflow enforces this too);
- for iOS, the latest nightly `ios-regression.yml` and `companion-ci.yml` runs passed;
- no open issue labelled `P1` with `bug`, in the repo being released;
- nothing in the notes depends on an open `risk:high` PR.

If an app is not ready, say why in this week's "Agent loop log" issue and stop for that app.

## 3. Version

Pre-1.0 semver: a new user-visible capability bumps the minor version; fixes only bump the patch.

- **iOS** takes its version from the release input or the `ios-vX.Y.Z` tag. No file changes. The
  first iOS release is `0.1.0` unless the owner says otherwise.
- **macOS** keeps its display version in `Sources/InboxPlusCore/InboxPlusVersion.swift`. Packaging
  also needs a build number greater than every build ever shipped.

## 4. Notes

Write notes from the merged PRs, for users, in plain words, grouped as Added, Fixed and Improved.
Leave out internal changes. Never claim a network works with live accounts unless the README
says it has been verified that way.

## 5. Hand over or ship

Open one issue per app, titled `Release iOS vX.Y.Z` or `Release macOS vX.Y.Z`, labelled `release`,
containing the notes, the commit SHA, links to the green runs, and a checklist.

**iOS**

- Levels 1–2: add `needs-human`. Checklist: Actions → *iOS release* → Run workflow on `main`, with
  version `X.Y.Z` and destination `testflight` (or push tag `ios-vX.Y.Z` on that commit).
- Level 3: run `ios-release.yml` yourself with a workflow dispatch on `main`, inputs
  `version=X.Y.Z` and `destination=testflight`. Follow the run. When it succeeds, comment the run
  link and close the issue. If it fails on missing Apple settings, add `needs-human` and list the
  missing names from `docs/ios-testing-and-release.md` in InboxPlus-IOS. Never handle the secrets
  themselves.

**macOS** (every level: signing and notarization run on the owner's Mac)

- Open a PR that bumps `InboxPlusVersion.swift`, labelled `agent` and `release`.
- In the release issue, add `needs-human`, the HTML release-notes fragment for
  `INBOXPLUS_RELEASE_NOTES_FILE`, the next build number, and the steps from `docs/updates.md` →
  "Package a release".

Never publish a GitHub Release, update the Sparkle feed, or submit to the App Store.
