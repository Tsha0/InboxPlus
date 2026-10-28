---
name: work
description: Take one ready Inbox+ issue from Tsha0/InboxPlus or Tsha0/InboxPlus-IOS to a tested, green pull request, finishing open agent PRs first. Run several times a day by the improvement loop, or when asked to work the agent queue.
---

# Work

One issue, one PR, one session. Finish what is open before starting anything new.

Read first: `docs/agents/autonomy.md`, `docs/agents/learnings.md`, and the target repo's
`CLAUDE.md` and `AGENTS.md`.

## 1. Finish open work first

List open PRs labelled `agent` in both repos.

- If any is red, has a merge conflict, or has review comments without a reply: take the oldest
  one, follow that repo's steward skill (`.claude/skills/steward/SKILL.md`) until it is green and
  every comment is answered, and end the session there.
- If a repo already has 3 open agent PRs, do not open another there.

## 2. Pick an issue

Candidates: open issues in both repos labelled `agent:ready` and not `agent:in-progress`. Order by
`P1`, `P2`, `P3`; then `bug`, `flake`, `drift` before `improvement`; then oldest.

Skip an issue if CI cannot check its "Done when". Comment why, swap `agent:ready` for
`needs-human`, and take the next one.

Claim it: add `agent:in-progress` and comment "Claimed by <this session's link>". Re-read the
issue. If someone else commented a claim in the last hour, remove your label and pick again.

## 3. Implement

- Use the branch this session was given, based on the latest `main` of the target repo.
- Read the whole code path before editing.
- For a bug, write the test that reproduces it first. You cannot run Swift here, so reason
  through why the test fails without the fix and passes with it.
- Change only what the issue needs. File other things you notice as issues; do not fix them here.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) in `Tests/<Module>Tests/`,
  following neighbouring files. iOS-only behaviour belongs in `iOS/InboxPlusIOSTests/` or the UI
  suites in `iOS/InboxPlusIOSUITests/`.
- Shared module changed? Decide whether the other repo needs it too, and file a `drift` issue there
  if so.
- Run the checks that work in a Linux container (`CLAUDE.md` → "In a cloud container").
- Changed a source of a generated file (brand icons, the logo, dependencies)? It can only be
  regenerated on macOS. Say so in the PR with the command, and label it `needs-human`.
- Compile errors cost a 15-minute CI round. Before pushing, re-read the diff for Swift 6 strict
  concurrency (`Sendable`, actor isolation, `@MainActor`), access control, and missing imports.

## 4. Review your own diff

Run the code-review skill on the diff at high effort. Also run security-review if the change
touches pairing, the companion server, Keychain, cookies or web sign-in, deep links, diagnostics,
or anything `AGENTS.md` names. Fix every confirmed finding before opening the PR.

## 5. Open the PR

- Title: an imperative summary, no prefix.
- Body: fill in `.github/pull_request_template.md`. Link the issue: `Fixes #N` in the same repo,
  or the full issue URL across repos.
- Labels: `agent`, plus `risk:low` or `risk:high` with a one-line reason, per `autonomy.md`.
- Subscribe to the PR's activity and follow the steward skill until every required check is
  green.

## 6. Merge, only if autonomy allows

At level 2 or higher, a PR that meets every low-risk rule may be squash-merged once green.
Otherwise, comment one line saying it is ready for the owner, and stop.

## 7. Leave a lesson

If CI or review caught something you could have caught yourself, comment on the PR:
`Lesson: <one line, phrased as an instruction>`. The retro collects these.
