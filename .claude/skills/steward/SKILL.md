---
name: steward
description: Drive a Tsha0/InboxPlus (macOS app) pull request to green and mergeable — failing CI, review comments, merge conflicts. Repo-specific conventions for whoever is watching a PR here.
---

# Steward — InboxPlus

## Required checks

All three come from `ci.yml` on macOS runners and take roughly 10–20 minutes:

- **Build and test**: `swift test`, packaging tests, script syntax, whitespace.
- **Generated files are current**: the brand marks, app icon and SBOM regenerate unchanged.
- **Package the app**: `Scripts/build-app.sh` assembles `Inbox+.app` and its CLI runs.

A PR is mergeable only when all three are green on its head commit.

## Reading a failure

- Read the failed job's log. Swift Testing marks failures with `✘` and the compiler with
  `error:`; search for those first.
- **Generated files are current** failed: a source of a generated file changed. Regenerating needs
  macOS (the commands are in README → Contributing). In a cloud container, either revert the
  source change or comment the exact command and label the PR `needs-human`.
- **Package the app** failed and the PR does not touch `Sources/`, `Scripts/` or `Runtime/`: suspect
  the runner's tools (cmake, Rust, the Python runtime cache). Check whether `main` fails the same
  way before changing anything.
- A test that waits on a real process timed out: the runners are slow. Raising its deadline is
  fine when the PR states the measured time. Changing what it asserts is not.
- `cancelled` means a newer push superseded the run. Look at the newest run.

## Conventions

- Squash merge. The PR title becomes the commit message.
- Resolve conflicts by merging `main` into the branch. Never force-push.
- Never turn on live tests (`INBOXPLUS_RUNTIME_PYTHON` or similar) in CI or in a PR.
- If the change touches a shared module, the PR says so: `Tsha0/InboxPlus-IOS` keeps a copy that
  may need the fix later. The loop does not work in that repo for now.

## When to stop

After three failed attempts to fix the same check, comment your diagnosis and what you tried,
label the PR `needs-human`, and stop.
