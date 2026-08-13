# Task 4 implementation report

Status: DONE

## Scope

Implemented only the Task 4 lifecycle boundary:

- `RuntimePhase`, checked `RuntimeState` transitions, serializable `RuntimeSnapshot`, and stable `RuntimeExitCode` values.
- `ManagedProcess`, `ManagedProcessFactory`, identity/status/signal contracts, and loopback-listener checking.
- `FoundationManagedProcess`, the sole owner of `Foundation.Process`, with macOS process-start identity, identity-gated signalling, bounded rotating stdout/stderr logs, and child cleanup.
- `SynapseSupervisor` actor start/status/stop behavior, five-second graceful-stop default, identity-reverified escalation, and process/listener disappearance verification.
- Unit, adversarial, concurrency, log-bound, and real child-process lifecycle tests.

Health endpoint polling, authenticated Matrix probes, crash recovery, and restart backoff remain intentionally deferred to Task 5.

## TDD evidence

### Initial RED

Command:

`swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`

Observed result: build failed as intended because `RuntimePhase`, `RuntimeState`, `RuntimeSnapshot`, `ManagedProcess`, `ManagedProcessIdentity`, `ManagedProcessFactory`, `LoopbackListenerChecking`, and `SynapseSupervisor` did not exist. The failure was caused by the missing Task 4 behavior, not a fixture typo.

### Additional RED cycles

- `swift test --filter stopDuringSuspendedLaunchIsRejectedWithoutCorruptingLaunch` failed because stop during an awaited launch produced `shutdownIncomplete` instead of the required invalid transition. The state machine was then tightened so launch cannot be reentered by stop before identity publication.
- `swift test --filter boundedLogWriterNormalizesOversizedExistingGenerations` failed because pre-existing log generations remained at 32 and 24 bytes with an 8-byte bound. Initialization now securely opens, validates, permissions-normalizes, and truncates retained generations to the configured cap.
- `swift test --filter statusDoesNotReportHealthyAfterProcessIdentityChanges` failed because status returned `.healthy` for a reused PID identity. Status now performs a fresh identity check and moves the snapshot to `.failed` without signalling.

### GREEN and verification

- `swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 18 tests passed, 0 failed.
- `swift test -c release --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 18 tests passed, 0 failed; clean production build output.
- `swift test`: 130 tests passed, 0 failed, 1 opt-in real-bootstrap test skipped as expected.
- `git diff --check`: passed with no whitespace errors.

## Safety coverage

- Full identity includes executable path, OS launch timestamp, PID, and start token.
- Both graceful and forced signals revalidate identity; mismatch tests prove no signal is issued, including against the production adapter and a real child.
- Status refuses to report a replacement PID as healthy.
- Actor reentrancy tests cover concurrent start/start, stop/stop, and stop during suspended launch.
- Graceful timeout escalates only after another identity match.
- Shutdown fails if either the process or loopback listener remains.
- Logs use user-only directory/file modes, no-follow descriptor-relative opens, regular single-link validation, per-file byte caps, and bounded retained generations.
- A real `/bin/sleep` child verifies production launch, identity capture, graceful termination, disappearance, and cleanup.

## Self-review

- Confirmed `Foundation.Process` appears only in `FoundationManagedProcess.swift` within `Sources/PalloRuntime`.
- Checked actor suspension points for stale state: status validates that its observed snapshot is unchanged before applying identity results; start/stop reject conflicting operations while suspended.
- Checked failure paths preserve identity and diagnostics rather than signalling or claiming stopped.
- Checked log rotation cannot follow a final-component symlink or accept hard-linked/non-regular files.
- Mutation review: removing the second identity check, allowing `.starting -> .stopping`, trusting stored status, skipping listener verification, omitting forced escalation, or allowing oversized rotations causes a named test to fail.

## Concerns / deferred work

- Task 4 marks a successfully launched child `.healthy` as the lifecycle placeholder expected by the plan examples. Task 5 must replace that provisional transition with the required layered endpoint/authenticated health deadline and add crash recovery.
- Task 5 should evolve `lastHealthResult` from the current serializable summary field to its final structured health representation.

## Fix round 1 — independent review rejection

Status: IMPLEMENTED, pending independent re-review

### Review findings addressed

- Replaced `Foundation.Process` with direct `posix_spawn` ownership inside `FoundationManagedProcess`. The adapter is the sole reaper of its direct child and checks exit with `waitid(..., WNOWAIT)` before identity verification and signalling. While the child is owned, an exit leaves an unreaped zombie, so its PID cannot be reused between the final identity check and `kill(2)`. A deterministic hook kills the child in that exact interval and the regression proves the PID remains reserved. Probe uncertainty never authorizes a signal.
- Added observation-only process rehydration. Persisted snapshots are revalidated; stale identity becomes failed, exact but unowned identity becomes degraded, and stop conservatively refuses to signal an observed process.
- Made every normal post-spawn identity failure, cancellation, and owner-release path terminate and reap the owned child. Failed starts can transition safely through stop and retry. Child-probe errors are retained as actionable failures and never converted into PID-only signals.
- Replaced Boolean listener checks with `present` / `absent` / `indeterminate(error)`. Only confirmed absence permits `.stopped`.
- Rebuilt log setup and rotation around descriptor-relative, no-follow operations. Profile/log directories and files are checked for owner, mode, type, link count, and retained identity; existing attacker-selected paths are never chmod-repaired. Profile ancestor replacement and symlink redirection are rejected before writes.
- Drained both output pipes through EOF before completion, added streaming redaction for explicit admin credentials and sensitive launch-environment values, and surfaced read/write failures through lifecycle status while still terminating and reaping the exact child.

### RED evidence

- `swift test --filter 'rehydratedStatus|logSetupRejectsSymlinkedDirectory|logWriterRejectsProfileAncestorReplacement'` failed because persisted healthy state was trusted and profile replacement was not detected.
- `swift test --filter logSetupRejectsSymlinkedDirectoryWithoutChangingExternalPermissions` failed because setup followed the symlink and changed the external directory from `0755` to `0700`.
- The output/redaction regression initially exposed `environment-token` in stdout.
- `swift test --filter 'indeterminateProcessIdentityNeverReceivesAnySignal|supervisorSurfacesAsynchronousLogFailureAndCleansExactChild'` failed to compile because process identity had no indeterminate state.
- The first full-suite run exposed timing-dependent log-failure tests under parallel load. Replacing fixed sleeps with an explicit post-launch filesystem gate made the failure injection deterministic.

### GREEN verification

- `swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 34 tests passed, 0 failed.
- `swift test -c release --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 34 tests passed, 0 failed; production build succeeded.
- `swift test`: 146 tests passed, 0 failed; 1 opt-in real-bootstrap test skipped as expected.
- `git diff --check`: passed with no whitespace errors.

### Fix-round self-review

- Confirmed the signal syscall and identity verification share the direct-child ownership/reaping critical section. No `Foundation.Process` reference remains in the Task 4 process adapter.
- Confirmed observation-only rehydration has no signalling path, including exact identity matches.
- Confirmed identity, listener, and log I/O uncertainty all fail conservatively rather than producing healthy/stopped state.
- Confirmed stdout/stderr readers continue through EOF after a write failure, preserve the first actionable failure, and child cleanup completes before it is surfaced.
- Confirmed log path validation is descriptor anchored from `/` through the retained profile/log descriptors and revalidates both pathname and descriptor identities before writes and rotation.
- Health polling, automatic crash recovery, and restart policy remain deferred to Task 5.

## Fix round 2 — stale actor observations, snapshot invariants, launch reservation

Status: IMPLEMENTED, pending independent re-review

### Review findings addressed

- Added supervisor operation tokens plus state/process generations. Start and stop hold an exclusive operation across every suspension point; status records an observation generation and revalidates it after lifecycle, identity, and ownership probes before cleanup or mutation. Status only claims exclusive cleanup after the ownership probe is still current, so a stop that completes while either probe is suspended wins and cannot be overwritten or signalled again.
- Added phase-specific persisted-snapshot invariants. Healthy/degraded require both process identity and loopback port; stopped/unprepared forbid both. A malformed initial snapshot is sanitized to an actionable failed snapshot, retains no signal authority, and start/stop refuse it with `invalidSnapshot`.
- Added an atomic `idle` / `launching` / `launched` reservation inside `FoundationManagedProcess`. Concurrent or sequential reuse of a successfully launched adapter throws `alreadyLaunched` before spawning. A failed launch resets to idle only after exact-child cleanup, and a real retry regression verifies the same adapter can intentionally try again.
- Moved pipe readers from the shared global pool to dedicated reader threads. The aggregate RED run exposed cooperative-thread starvation when many real-process tests simultaneously waited for EOF; dedicated readers preserve complete drain semantics and deterministic cleanup under concurrent load.

### RED evidence

Command:

`swift test --filter 'suspendedLifecycleFailureProbeCannotOverwriteNewerStoppedState|suspendedOwnershipProbeCannotOverwriteNewerStoppedState|corruptActiveSnapshotWithoutIdentityBecomesActionableFailure|corruptInactiveSnapshotWithRuntimeMetadataIsNeverStoppedOrSignalled|foundationManagedProcessRejectsSequentialSecondLaunchAndRetainsFirstChild|foundationManagedProcessReservesConcurrentLaunchBeforeSpawning'`

Observed failures:

- Both suspended status probes resumed after stop and changed the newer `.stopped` snapshot.
- Healthy/degraded snapshots without identity remained running; stopped/unprepared snapshots with stale PID/listener metadata remained inactive rather than actionable failures.
- Both sequential and concurrent second launch calls spawned another child.

The first aggregate focused run then hung with multiple process tests blocked in synchronous EOF drain. A process sample showed cooperative executor threads waiting in `ManagedOutputCollector.waitForEOF()` while global-pool readers could not make progress; dedicated pipe readers removed that starvation.

### GREEN verification

- Targeted round-2 regressions: 6 tests passed, 0 failed (including parameterized corrupt phases).
- `swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 41 tests passed, 0 failed.
- `swift test -c release --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`: 41 tests passed, 0 failed; production build succeeded.
- `swift test`: 153 tests passed, 0 failed; 1 opt-in real-bootstrap test skipped as expected.
- `git diff --check`: passed with no whitespace errors.

### Fix-round self-review

- Audited every supervisor await followed by snapshot/process mutation. Exclusive operations are revalidated after awaits; observation-only status paths verify both state and managed-process generations before acting.
- Confirmed lifecycle cleanup cannot claim signal authority until its suspended ownership result is still current. Once claimed, concurrent start/stop is rejected until cleanup completes, preventing duplicate termination.
- Confirmed malformed inactive snapshots discard stale process identity and cannot reach rehydration/signalling; malformed active snapshots cannot be returned as healthy/degraded.
- Confirmed the launch reservation is acquired before `posix_spawn`, is not overwritten by a concurrent caller, remains terminal after successful launch, and resets only after a failed launch has no owned child.
- Re-ran all previously accepted direct-child PID, rehydration, listener, descriptor-anchored log, EOF/redaction, and I/O-failure regressions unchanged.
