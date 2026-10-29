---
name: release
description: Decide whether the Inbox+ macOS app has something worth shipping and whether it is safe to, then prepare the release for the owner to sign and publish. Run weekly by the improvement loop, or when asked to cut a release.
---

# Release

Read first: `docs/agents/autonomy.md` and `docs/updates.md`. A release reaches users through the
Sparkle feed, so when in doubt, prepare and hand over.

## 1. What changed since the last release

The last release is the newest **published** GitHub Release tagged `v*`. Drafts and prereleases
do not count. If there is none, nothing has shipped yet and everything on `main` counts.

List the PRs merged since then. Ignore PRs that only touch docs, CI, tests or the playbook.

## 2. Is it ready

Prepare a release only if all of these hold:

- at least one merged PR changes something a user would notice;
- the head of `main` is green on a `ci.yml` push run (all three jobs);
- no open issue is labelled both `P1` and `bug`;
- nothing in the notes depends on an open `risk:high` PR.

If it is not ready, say why in this week's "Agent loop log" issue and stop.

## 3. Version

Pre-1.0 semver: a new user-visible capability bumps the minor version; fixes only bump the patch.
The display version lives in `Sources/InboxPlusCore/InboxPlusVersion.swift`. Packaging also needs
a build number greater than every build ever shipped; read the current feed or the previous
release to find it.

## 4. Notes

Write notes from the merged PRs, for users, in plain words, grouped as Added, Fixed and Improved.
Leave out internal changes. Never claim a network works with live accounts unless the README says
it has been verified that way.

## 5. Hand over

- Open a PR that bumps `InboxPlusVersion.swift`, labelled `agent` and `release`. At level 3 you may
  merge it once green; otherwise it waits for the owner.
- Open an issue titled `Release macOS vX.Y.Z`, labelled `release` and `needs-human`, containing:
  the notes; the notes as an HTML fragment for `INBOXPLUS_RELEASE_NOTES_FILE`; the next build
  number; the commit SHA and the green run link; and the steps from `docs/updates.md` →
  "Package a release" with the values filled in.
- At level 3, if a release workflow exists in `.github/workflows/`, run it on `main` to build the
  signed draft release instead of listing the packaging steps, and link the draft in the issue.
  If it fails on missing signing settings, list the missing names and leave it `needs-human`.
  Never handle the secrets themselves.

Never publish a GitHub Release or deploy the Sparkle feed. Publishing is the owner's step.
