---
name: retro
description: Weekly review of how the Inbox+ agent loop performed — what shipped, what broke, what CI and review caught — turned into better rules for next week and a report for the owner. Run weekly by the improvement loop.
---

# Retro

This is where the loop improves itself. Gather data first, then change rules only where the
data shows a pattern.

## 1. Gather (last 7 days, both repos)

- **Agent PRs** (label `agent`): merged, closed without merging, still open. For each, count the
  failed CI runs before it went green, the review comments it received, and its `Lesson:`
  comments, and note how many days it stayed open.
- **Escapes**: reverts on `main`, issues labelled `bug` whose cause was an agent PR, reopened
  issues.
- **Nightly health**: pass rate of `ios-regression.yml` and the scheduled `companion-ci.yml`.
- **Queue**: how many issues are `agent:ready`, and how many are `needs-human` with their ages.
- **Scout accuracy**: scout issues closed as not planned or duplicate.

## 2. Find patterns

A pattern is the same root cause at least twice: the same kind of CI failure, the same review
comment, the same kind of rejected issue. One-offs are not patterns. Ignore them.

## 3. Change something

- **Learnings.** Update `docs/agents/learnings.md`: dated, one line each, written as an instruction
  ("Before X, check Y"). Remove lessons that are obsolete or already in a skill. Keep the file
  under 100 lines.
- **Rules.** When a lesson belongs in a skill, `CLAUDE.md`, or `AGENTS.md`, change it there.
- **Checks beat prose.** If a test, lint or CI step could catch the mistake, propose that instead
  of another sentence.

Put all of it in one PR labelled `agent` and `playbook`. It always waits for the owner, so never
merge it.

## 4. Report

Close last week's "Agent loop log" issue in `Tsha0/InboxPlus`. Open this week's, labelled
`report`, starting with:

- **Shipped**: merged PRs (links) and releases.
- **Health**: nightly pass rate; median failed CI runs per agent PR; escapes.
- **Waiting on you**: `needs-human` issues, oldest first, each with the one decision needed.
- **Playbook changes**: the PR link and a sentence on each change.

Recommend raising or lowering the autonomy level only with evidence, for example: "14 agent PRs
merged, 0 escapes, median 0 failed CI runs: consider level 2."
