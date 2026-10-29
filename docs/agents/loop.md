# The Inbox+ improvement loop

Agents keep the Inbox+ macOS app improving on a schedule. They find problems, fix them in pull
requests, prepare releases, and review their own track record so the next round goes better.
This page is the map; each step's procedure is a skill in [`.claude/skills/`](../../.claude/skills).

The loop covers this repository, `Tsha0/InboxPlus`, only. The iOS app (`Tsha0/InboxPlus-IOS`) is
out of scope for now: agents do not file issues, open PRs, or release there.

```
            ┌──────────────────────── scout (daily) ────────────────────────┐
            │  CI failures · flaky tests · module review · triage           │
            ▼                                                               │
   issues labelled agent:ready  ◄──── you: file issues, approve proposals   │
            │                                                               │
            ▼                                                               │
   work (3× daily) ──► PR ──► CI + self-review ──► merge (you, or agent     │
            │                  steward fixes red    at autonomy level 2+)   │
            ▼                                                               │
   release (weekly) ──► release issue + version PR; you sign and publish    │
            │                                                               │
            ▼                                                               │
   retro (weekly) ──► learnings.md + playbook PRs + weekly report ──────────┘
```

## Roles

| Skill | Runs | Does | Leaves behind |
| --- | --- | --- | --- |
| [scout](../../.claude/skills/scout/SKILL.md) | daily | Reads CI, triages new issues, reviews one module | De-duplicated issues with acceptance criteria |
| [work](../../.claude/skills/work/SKILL.md) | 3× daily | Finishes open agent PRs first; otherwise takes one `agent:ready` issue to a green PR | One small PR per issue |
| [steward](../../.claude/skills/steward/SKILL.md) | inside work, and whenever a PR needs driving | Repo rules for fixing red CI, answering review, resolving conflicts | A green, mergeable PR |
| [release](../../.claude/skills/release/SKILL.md) | weekly | Decides whether there is something worth shipping and whether it is safe to | A release issue with notes and evidence, and a version-bump PR |
| [retro](../../.claude/skills/retro/SKILL.md) | weekly | Measures the week, finds repeated mistakes, changes the rules | [`learnings.md`](learnings.md) updates, playbook PRs, the weekly report |

## Labels

Agents create these on first use. Use exactly these names.

| Label | Meaning |
| --- | --- |
| `agent:ready` | Scoped and approved. Any agent may take it. |
| `agent:in-progress` | Claimed by an agent session; its claim comment links the session. |
| `needs-human` | Blocked on the owner: a decision, a secret, a Mac-only step, or a real account. |
| `proposal` | An idea waiting for the owner. Add `agent:ready` to approve it, or close it. |
| `bug` `flake` `ci-infra` `dependency` `improvement` | What kind of work it is. |
| `P1` `P2` `P3` | P1: broken for users, or `main` is red. P2: wrong with a workaround, or flaky. P3: polish. |
| `agent` | On a PR: opened by an agent. |
| `risk:low` `risk:high` | On a PR: see [autonomy](autonomy.md). |
| `release` `report` `playbook` | Release preparation; loop logs and weekly reports; changes to the agents' own rules. |

## How you steer it

- **Report a bug or idea** with the issue forms. Bugs go straight to triage; ideas wait as
  `proposal` until you add `agent:ready`.
- **Answer `needs-human` issues.** The weekly report lists them oldest first, each with the one
  decision needed. Reply in the issue, then swap `needs-human` for `agent:ready`.
- **Review and merge agent PRs** (at level 1). Comment on a PR to redirect it; the next work run
  picks up review comments before starting anything new.
- **Change how much agents may do** in [autonomy.md](autonomy.md). Agents never change that file.
- **Pause everything** by disabling the scheduled tasks. Nothing else runs on its own.
- **Watch** the weekly "Agent loop log" issue: each run posts a short summary there.

## Where agents run

**Cloud (default).** Each scheduled run starts a fresh Claude Code cloud session with this repo.
It is Linux with no Swift or Xcode, so GitHub Actions is the test runner: an agent pushes, waits
for checks (about 15 minutes a round) and reads the results. That suits bugs, tests, logic, CI
and docs. The repo is public, so the macOS runner minutes cost nothing.

**Your Mac (optional, faster).** A session started from the Claude desktop app, or with
`claude remote-control` in a checkout, can run `swift test` and `Scripts/build-app.sh`. Use it for
issues marked Mac-only: regenerating generated files, checking UI by eye, and signing a release.

## Guardrails

- One issue per PR, at most 3 open agent PRs, at most 5 new scout issues per run.
- Required CI checks gate every merge, for agents and people alike.
- Agents propose changes to their own rules (`playbook` PRs) but never merge them.
- Real messaging accounts, secrets, signing material, publishing a release and the Sparkle feed
  are off limits at every level. The full list is in [autonomy.md](autonomy.md).

## Turning it on

The loop is a set of Claude Code scheduled tasks, each starting a fresh cloud session on this
repo. Suggested schedule (Singapore time) and prompts:

| Task | When | Prompt |
| --- | --- | --- |
| Inbox+ scout | daily ~04:45 | `You are the Inbox+ scout. Work in Tsha0/InboxPlus only. Read .claude/skills/scout/SKILL.md and follow it. Do not change code. You may create, label and comment on issues in Tsha0/InboxPlus.` |
| Inbox+ worker | ~05:15, ~11:15, ~17:15 | `You are an Inbox+ worker. Work in Tsha0/InboxPlus only. Read .claude/skills/work/SKILL.md and follow it. You may commit, push your session branch, open pull requests, and comment on issues and PRs in Tsha0/InboxPlus, as that skill and docs/agents/autonomy.md allow.` |
| Inbox+ release | Fridays ~10:15 | `You are the Inbox+ release manager. Work in Tsha0/InboxPlus only. Read .claude/skills/release/SKILL.md and follow it, within docs/agents/autonomy.md. You may open the version-bump pull request.` |
| Inbox+ retro | Sundays ~18:15 | `You run the Inbox+ weekly retro. Work in Tsha0/InboxPlus only. Read .claude/skills/retro/SKILL.md and follow it. You may open pull requests that change the playbook; never merge them.` |

Start at autonomy level 1 and raise it when the weekly reports earn it.
