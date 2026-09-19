# Phase 8 release certification — status

Phase 8 is the gate that says Mimo is ready to hand to the public: a live-network black-box suite,
clean-Mac installation, an upgrade matrix, failure injection, performance, accessibility, website
artifacts, checksums, release notes, and a license inventory.

**Phase 8 has not been run, and most of it cannot be run yet.** This document records what it needs
and what already exists, so the gate is not mistaken for a formality.

## What already exists

| Requirement | State |
| --- | --- |
| Licence inventory | Done. `docs/sbom.cdx.json` (CycloneDX 1.5) plus `docs/dependencies.md`. |
| Checksums | Done for inputs — every bridge and libolm is pinned and verified before execution. Release-artifact checksums are emitted by `Scripts/package-release.sh`, which has never run. |
| Failure injection | Partial. Bridge-crash isolation was demonstrated for real in Phase 6; supervisor restart, log-failure, data-loss and restore paths are covered by the Phase 2 suite. |
| Performance | Partial and **stale**. `docs/benchmarks/phase-2/` measured the runtime alone, before the Matrix client, nine bridges and the media cache existed. Its verdict was `Require PostgreSQL`. |
| Accessibility | Partial. Views carry labels, hints and identifiers, and those are asserted in `MimoUITests`. No audit with VoiceOver, Full Keyboard Access, Increase Contrast or Reduce Motion has been done. |
| Release notes | Not written. |
| Website artifacts | Not started. |

## What is blocked, and on what

- **Live-network black-box suite** — needs accounts on eleven networks. Only Instagram has ever
  been driven with real credentials. Several of these networks permanently ban accounts for using
  unofficial clients, so this needs throwaway accounts created deliberately, not a personal one.
- **Clean-Mac installation** — needs a second Mac, or a VM, that has never had Mimo, Homebrew
  Python, or `cmake` on it. Every install path here has been exercised only on a machine that
  already had its prerequisites.
- **Upgrade matrix** — needs at least two signed releases to upgrade between. There are none.
- **Notarized artifact verification** — `spctl --assess` is only meaningful against a signed,
  notarized bundle, which requires the Developer ID that Phase 7 is blocked on.

## The one blocking verdict already on record

Phase 2 benchmarked SQLite against the design's stated load and concluded **`Require PostgreSQL`**
before public release. Since then the deployment has grown a Matrix client store, a media cache,
and one SQLite database per bridge — eight of them on the demo profile.

Nothing has re-run that benchmark. Phase 8 cannot pass while a recorded verdict says the storage
engine is wrong and the load has only increased.

## Honest summary

The application works end to end on this machine: a real Instagram account connects, its
conversations appear, messages send and receive, media renders, and eight bridges supervise
cleanly on one homeserver. That is a working development build.

It is not a release. A release needs a signing identity, a clean-machine install, a re-run storage
benchmark, an accessibility audit, and live certification on the networks it claims to support.
Those are the remaining work, and none of them is a code change.
