---
name: scout
description: Find problems in the Inbox+ macOS app (Tsha0/InboxPlus) and turn them into well-scoped GitHub issues. Run daily by the improvement loop, or when asked to look for bugs, flaky tests, or work for agents. Files issues only; never changes code.
---

# Scout

Leave `Tsha0/InboxPlus` with an accurate, de-duplicated queue of issues that an agent can pick
up cold. You file and triage issues. You do not change code. The iOS repo is outside the loop
for now: do not file anything there.

Read first: `docs/agents/autonomy.md`, `docs/agents/learnings.md`, `AGENTS.md` (if present).

## Budget

- At most **5 new issues per run**. Fewer, better issues beat more.
- If 10 or more `agent:ready` issues are already open, file only P1s this run.
- Before filing anything, search open and recently closed issues for the same problem. If one
  exists, comment on it with the new evidence instead.

## 1. CI health (every run)

List `ci.yml` runs from the last 7 days: pushes to `main`, and pull requests. For each failed or
timed-out run, read the failed jobs' logs, find the failing test or step (search for `✘` and
`error:`), then classify it:

- **`main` is red**: the newest push run on `main` failed. → `bug`, `P1`, naming the commit and
  PR that introduced it.
- **Flake**: the same test failed on unrelated PRs, or failed and then passed on the same commit.
  → `flake`, `P2`. Record the test name, every run link, and the log excerpt. For a test that
  already has a `flake` issue, add a comment with the new run instead.
- **Infrastructure**: runner image, toolchain, package or runtime download, network. → one
  `ci-infra` issue. Add `needs-human` only if a setting outside the repo must change.

A failure on a PR that its own later commits fixed is not an issue. A `cancelled` run is not a
failure: a newer push cancels the older run.

## 2. Triage new issues (every run)

Take open issues that carry none of `agent:ready`, `agent:in-progress`, `needs-human`,
`proposal`, `report`, `release`.

- **Bug report**: find the code path, then comment the likely cause, a "Done when" list, and the
  test that would prove the fix. Label `bug`, a priority, and `agent:ready`. If confirming it
  needs a real account, a real Mac, or information only the reporter has, label `needs-human`
  and ask one specific question.
- **Feature, UX change, or anything that changes what the product does**: label `proposal` and
  `needs-human`. Agents build these only after the owner adds `agent:ready`.
- **Explorer bugs** (labelled `explorer` and `bug`) come from an agent clicking through the demo
  app, with steps and screenshots. Find the code that causes it before adding `agent:ready`. If it
  is only a limit of the demo (no login, no media download, no notifications), close it as not
  planned with a one-line reason: the explorer will not report it again. Its improvement ideas
  already arrive as `proposal` and need nothing from you.

## 3. Review one module (every run)

Rotate through these. Take entry number (day of the year mod 12):

0 Core · 1 Gateway · 2 Features · 3 UI · 4 Matrix · 5 Bridge · 6 BridgeService · 7 IMessage ·
8 Runtime · 9 RuntimeCLI · 10 App (each is `Sources/InboxPlus<Name>`) ·
11 packaging and update scripts (`Scripts/`, `Tests/Packaging/`)

Read the module and its tests. Use the code-review skill on it if available. Look for:

- violations of the `AGENTS.md` rules (P1);
- crashes on external input: force unwraps, unchecked indexes, `try!` on data from a network,
  file, database or the Messages store;
- Swift concurrency hazards: shared mutable state outside an actor, actor re-entrancy across an
  `await`, tasks that are never cancelled;
- errors swallowed without a log or a user-visible state;
- behaviour no test covers, where a regression would reach users.

File a finding only when you can state a concrete input and the wrong result it produces. A
hunch is not an issue. Missing tests for an important path are fine to file as `improvement`,
`P3`.

## 4. Mondays only

- **Dependencies.** Compare the pins with upstream's latest stable release: Matrix SDK and Sparkle
  (`Package.swift`), Synapse (`Runtime/Synapse/requirements.in`), bridges
  (`Sources/InboxPlusBridge/BridgeCatalog.swift`). File one `dependency` issue per outdated pin,
  with the upstream changelog link, labelled `needs-human`: a pin decides what code gets executed.
- **Stale claims.** For an `agent:in-progress` issue with no linked PR and no activity for 2 days,
  remove the label, comment why, and leave it `agent:ready`.

## Writing an issue

Title: imperative and specific ("Fix …", "Add a test for …").

```
**Problem** — what is wrong, and where it shows (file:line, run link).
**Evidence** — the log excerpt or the failing input.
**Done when** — acceptance criteria, including the test that proves it.
**Scope** — files likely involved; what is out of scope.
**Found by** — scout, YYYY-MM-DD.
```

Labels: one kind, one priority, and `agent:ready` or `needs-human`.

## Finish

Comment a short summary on this week's open "Agent loop log" issue (labelled `report`; create it
if there is none): issues filed and triaged, CI state, and anything that needs the owner. Keep it
under 10 lines.
