---
name: scout
description: Find problems in Inbox+ across Tsha0/InboxPlus and Tsha0/InboxPlus-IOS and turn them into well-scoped GitHub issues. Run daily by the improvement loop, or when asked to look for bugs, flaky tests, drift, or work for agents. Files issues only; never changes code.
---

# Scout

Leave both repos with an accurate, de-duplicated queue of issues that an agent can pick up cold.
You file and triage issues. You do not change code.

Read first: `docs/agents/autonomy.md`, `docs/agents/learnings.md`, `AGENTS.md` (if present).

## Budget

- At most **5 new issues per run** across both repos. Fewer, better issues beat more.
- If 10 or more `agent:ready` issues are already open, file only P1s this run.
- Before filing anything, search open and recently closed issues in both repos for the same
  problem. If one exists, comment on it with the new evidence instead.

## 1. CI health (every run)

List runs from the last 3 days on `main` (push and schedule events):

- `Tsha0/InboxPlus`: `ci.yml`
- `Tsha0/InboxPlus-IOS`: `ios-ci.yml`, `companion-ci.yml`, `ios-regression.yml`

For each failed or timed-out run, read the failed jobs' logs (in InboxPlus-IOS, the "Show failure
summary" step has the test output). Find the failing test or step, then classify it:

- **Regression**: it fails on every run since a particular commit. → `bug`, `P1`, naming the
  commit and PR that introduced it.
- **Flake**: the same commit passes in other runs. → `flake`, `P2`. Record the test name, every
  run link, and the log excerpt. For a test that already has a `flake` issue, add a comment with
  the new run instead.
- **Infrastructure**: runner image, simulator runtime download, toolchain, network. → one
  `ci-infra` issue. Add `needs-human` only if a setting outside the repo must change.

A `cancelled` run is not a failure: a newer push cancels the older run.

## 2. Triage new issues (every run)

Take open issues in both repos that carry none of `agent:ready`, `agent:in-progress`,
`needs-human`, `proposal`, `report`, `release`.

- **Bug report**: find the code path, then comment the likely cause, a "Done when" list, and the
  test that would prove the fix. Label `bug`, a priority, and `agent:ready`. If confirming it
  needs a real account, a real Mac, or information only the reporter has, label `needs-human`
  and ask one specific question.
- **Feature, UX change, or anything that changes what the product does**: label `proposal` and
  `needs-human`. Agents build these only after the owner adds `agent:ready`.

## 3. Review one module (every run)

Rotate through these modules. Take entry number (day of the year mod 16):

0 Core · 1 Gateway · 2 Features · 3 UI · 4 Matrix · 5 Bridge · 6 BridgeService · 7 IMessage ·
8 Runtime · 9 RuntimeCLI · 10 App (all `Sources/InboxPlus<Name>` in InboxPlus) ·
11 Mobile · 12 Remote · 13 CompanionServer · 14 Companion (InboxPlus-IOS `Sources/`) ·
15 the iOS app and its tests (InboxPlus-IOS `iOS/`)

Read the module and its tests. Use the code-review skill on it if available. Look for:

- violations of the `AGENTS.md` rules (P1);
- crashes on external input: force unwraps, unchecked indexes, `try!` on data from a network,
  file, database or the companion;
- Swift concurrency hazards: shared mutable state outside an actor, actor re-entrancy across an
  `await`, tasks that are never cancelled;
- errors swallowed without a log or a user-visible state;
- behaviour no test covers, where a regression would reach users.

File a finding only when you can state a concrete input and the wrong result it produces. A
hunch is not an issue. Missing tests for an important path are fine to file as `improvement`,
`P3`.

## 4. Drift between the repos (every run)

Both repos carry their own copy of Core, Features, Gateway, Bridge, BridgeService, UI, Matrix,
Runtime, IMessage, RuntimeCLI and App. For each commit merged to either `main` in the last 3 days
that touches one of those `Sources/` folders, decide whether the other repo needs the same change.

- Bug fixes and security fixes almost always do.
- Mac-only features (Sparkle, notifications) and iOS portability changes usually do not.

If it is needed and not yet ported, file a `drift` issue in the other repo, linking the source PR,
labelled `agent:ready` and a priority matching the original.

## 5. Mondays only

- **Dependencies.** Compare the pins with upstream's latest stable release: Matrix SDK and Sparkle
  (`Package.swift`), Synapse (`Runtime/Synapse/requirements.in`), bridges
  (`Sources/InboxPlusBridge/BridgeCatalog.swift`). File one `dependency` issue per outdated pin,
  with the upstream changelog link, labelled `needs-human`: a pin decides what code gets executed.
- **Stale claims.** For an `agent:in-progress` issue with no linked PR and no activity for 2 days,
  remove the label, comment why, and leave it `agent:ready`.

## Writing an issue

Title: imperative and specific ("Fix …", "Add a test for …", "Port … to InboxPlus-IOS").

```
**Problem** — what is wrong, and where it shows (file:line, run link).
**Evidence** — the log excerpt or the failing input.
**Done when** — acceptance criteria, including the test that proves it.
**Scope** — repo and files likely involved; what is out of scope.
**Found by** — scout, YYYY-MM-DD.
```

Labels: one kind, one priority, and `agent:ready` or `needs-human`.

## Finish

Comment a short summary on this week's open "Agent loop log" issue in `Tsha0/InboxPlus` (labelled
`report`; create it if there is none): issues filed and triaged, CI state, and anything that needs
the owner. Keep it under 10 lines.
