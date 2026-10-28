# Learnings

Short, dated instructions that agents have learned the hard way. Read this before starting work.
The retro skill keeps it under 100 lines: it adds lessons that repeat, removes ones that no longer
apply, and moves lasting ones into a skill, `CLAUDE.md`, or a check.

## CI

- 2026-10-28 — CI runners are much slower than a developer Mac. A test that waits on a real
  process (Synapse, a bridge, the fixture companion, a simulator) needs a deadline sized for that.
  Both repos have already had to raise such timeouts (InboxPlus #47, InboxPlus-IOS #2).
- 2026-10-28 — A newer push cancels the previous CI run on the same branch. A `cancelled` run is
  not a failure.
- 2026-10-28 — The nightly iOS regression and companion runs have failed on an unchanged commit
  (2026-10-21, 2026-10-24) and passed the next night. Before calling a nightly failure a
  regression, compare the neighbouring runs on the same commit.
- 2026-10-28 — InboxPlus-IOS writes test and build output to files under `build/`, uploaded as
  artifacts. Read the "Show failure summary" step in the job log first. Cloud sessions cannot
  download artifacts unless the environment allows `*.blob.core.windows.net`.

## Code

- 2026-10-28 — The shared modules exist twice, once in each repo, and have already diverged. A
  fix to one copy usually needs the other: check, and file a `drift` issue if so.
- 2026-10-28 — Generated files (`PlatformGlyphPaths.swift`, `AppIcon.icns`, `docs/sbom.cdx.json`)
  can only be regenerated on macOS. A cloud agent that changes their sources must hand the PR to
  the owner with the exact command.
