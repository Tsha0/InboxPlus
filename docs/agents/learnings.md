# Learnings

Short, dated instructions that agents have learned the hard way. Read this before starting work.
The retro skill keeps it under 100 lines: it adds lessons that repeat, removes ones that no longer
apply, and moves lasting ones into a skill, `CLAUDE.md`, or a check.

## CI

- 2026-10-28 — CI runners are much slower than a developer Mac. A test that waits on a real
  process or on concurrent work needs a deadline sized for that; #47 already had to raise the
  media tests' deadlines for concurrent CI load.
- 2026-10-28 — A newer push cancels the previous CI run on the same branch. A `cancelled` run is
  not a failure.
- 2026-10-28 — CI runs only on pull requests and pushes to `main`; there is no nightly run. A flaky
  test shows up as the same failure on unrelated PRs, so compare across PRs before calling one a
  regression.

## Code

- 2026-10-28 — Generated files (`PlatformGlyphPaths.swift`, `AppIcon.icns`, `docs/sbom.cdx.json`)
  can only be regenerated on macOS. A cloud agent that changes their sources must hand the PR to
  the owner with the exact command.
- 2026-10-28 — `Tsha0/InboxPlus-IOS` keeps its own copy of the shared modules. It is outside the
  loop for now: do not file issues or PRs there, but say in the PR when a fix touches a shared
  module, so it can be ported later.
