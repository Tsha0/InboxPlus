# Pallo Phase 2 Local Synapse Runtime Spike Design

Status: Approved in collaborative design review on 2026-08-13

Project: Pallo

Phase: 2 — developer spike

## Summary

Phase 2 determines whether Pallo can safely own a loopback-only Synapse process on macOS and whether SQLite is suitable for Pallo's single-user workload. The spike uses a pinned Python virtual environment and a developer-only Swift CLI. It exercises runtime bootstrap, lifecycle supervision, health and crash recovery, representative-load benchmarking, backup and recovery, and clean removal.

The spike does not connect Synapse to the product UI or the existing `MessagingGateway`. It does not implement real messaging adapters, Matrix client synchronization, production runtime packaging, signing, notarization, launch at login, updating, or public redistribution.

## Goals

- Prove that Pallo can directly start, monitor, stop, and recover a local Synapse child process.
- Enforce a local-only Synapse configuration with no remotely reachable service.
- Reproduce a representative Pallo workload and measure the approved SQLite gates.
- Verify integrity-preserving offline backup, restore, recovery, and clean removal.
- Produce an evidence-based provisional SQLite verdict or a PostgreSQL requirement.
- Provide repeatable developer commands, automated tests, and durable result reports.

## Non-goals

- Real messaging adapters or bridge provisioning
- Matrix Rust SDK integration or client synchronization
- Product diagnostics or runtime controls in the Pallo UI
- Federation or any multi-user/public homeserver behavior
- Launch agents, launch at login, or background operation independent of the harness
- Signed or notarized runtime bundles, an updater, universal packaging, or public redistribution
- PostgreSQL implementation if SQLite fails
- Hot backup support

## Selected developer runtime

The spike uses a pinned Python virtual environment rather than Docker.

This arrangement makes Synapse a direct macOS child process of Pallo's supervisor and therefore exercises the intended process, filesystem, networking, and crash-recovery boundaries more faithfully than a Linux container. A compatible Homebrew Python and supporting developer libraries are acceptable prerequisites for this developer spike. They do not become public-release requirements.

An explicit bootstrap command creates the virtual environment and installs the exact dependency set declared by a checked-in runtime manifest. Bootstrap records the selected interpreter, installed packages, macOS version, and hardware. Normal lifecycle and benchmark commands use the prepared environment and never install or upgrade dependencies.

The implementation plan must select and record exact compatible Python, Synapse, and package versions in the manifest. Version changes are intentional repository changes, never implicit bootstrap behavior.

## Architecture and module boundaries

Phase 2 adds two focused Swift package targets beside the existing app:

- **`PalloRuntime`** is a library that owns profile layout, manifest validation, Synapse configuration, process supervision, loopback enforcement, health checking, backup and restore, removal, workload orchestration, and result reporting.
- **`PalloRuntimeCLI`** is a developer executable that exposes these capabilities as explicit commands without adding temporary product UI.

The CLI supports named, isolated profiles and commands equivalent to:

- `bootstrap`
- `start`
- `status`
- `stop`
- `benchmark`
- `backup`
- `restore`
- `verify`
- `remove`

Command names and flags may be refined in the implementation plan, but their safety and lifecycle boundaries must remain explicit.

The runtime targets do not depend on `PalloUI`, change the product's in-memory Phase 1 gateway, or introduce a Matrix client. The benchmark talks to Synapse through local Matrix HTTP endpoints. Three synthetic import workers represent later bridges without implementing bridge adapters.

## Profile and data layout

Every named developer profile lives beneath one validated, user-scoped Pallo developer-runtime root. Each profile has separate locations for:

- Runtime environment and recorded manifest metadata
- Generated Synapse configuration
- SQLite database and local media fixtures
- Logs and verified process state
- Internal backups and staging areas
- Benchmark JSON and Markdown reports

Profiles must use restrictive user-only filesystem permissions. Profile names and resolved paths are validated before any read, write, launch, restore, or removal operation. No operation may escape the developer-runtime root through absolute paths, traversal, symlinks, or an unresolved alias.

Each command acquires an exclusive profile lock before changing runtime or data state. This prevents two supervisors from operating the same Synapse profile concurrently.

## Local-only Synapse configuration

Synapse binds only to `127.0.0.1` on an available port allocated for the supervised run. Generated configuration disables:

- Federation listeners and federation participation
- Public registration
- Guest access
- Public room directories
- Remote administration

Only the narrow local endpoints required by the spike are enabled. Local control and benchmark requests authenticate even though the listener is loopback-only. Generated credentials and registration secrets never appear in process arguments or reports.

Before every launch, `PalloRuntime` validates the effective configuration and rejects any non-loopback listener or forbidden feature. The supervisor also verifies after launch that the expected process is listening only on the allocated loopback endpoint.

## Runtime lifecycle and supervision

### State model

The normal lifecycle is:

`unprepared → stopped → starting → healthy → stopping → stopped`

Failure handling adds `degraded`, `recovering`, and `failed`. Commands reject invalid transitions and return a stable nonzero exit status rather than silently mutating unrelated state.

### Startup

Startup performs these steps:

1. Validate the runtime manifest, virtual environment, exact installed versions, profile permissions, configuration invariants, and profile lock.
2. Allocate an available loopback port and generate the effective run configuration.
3. Launch Synapse as a direct child process with an explicit executable, argument list, environment, and working directory.
4. Capture standard output and error in bounded, redacted profile logs.
5. Poll health until the configured startup deadline.
6. Persist verified process metadata only after the child reaches the healthy state.

Process metadata is never trusted by PID alone. A later command must verify process identity before signalling or reporting the process.

### Health

A healthy runtime satisfies all three checks:

1. The expected child process is alive and its identity matches recorded metadata.
2. Its loopback health endpoint responds within the deadline.
3. A lightweight authenticated Matrix request succeeds.

A live process that cannot serve requests is `degraded`, not `healthy`.

### Shutdown

Shutdown requests graceful child termination, waits for the configured deadline, and escalates to forced termination only when necessary. It then verifies that neither the child nor its associated listener remains. A user-requested stop never triggers automatic recovery.

### Crash recovery

An unexpected child exit during a supervised run triggers bounded exponential-backoff recovery. The supervisor attempts at most three restarts in that run. A sufficiently stable recovery resets the consecutive-failure count. Exhausting the limit enters a terminal `failed` state and preserves diagnostics for inspection.

The CLI reports the profile state, process identity, loopback port, restart count, last health result, and diagnostic location without exposing secrets.

## Representative-load benchmark

The benchmark is deterministic from a recorded seed. It creates and exercises:

- 2,000 local Matrix rooms representing conversations
- At least 100,000 message events
- Three concurrent synthetic history-import workers
- A separate live incoming-traffic worker during import
- Concurrent timeline reads and search requests
- Representative attachment metadata and small local fixture uploads

The synthetic workers test Synapse and SQLite concurrency only. They are not application services and do not establish a bridge contract for later phases.

The harness performs warm-up before measured runs. It records workload parameters, failures, wall-clock duration, CPU and memory use, database size, exact event counts, request latency distributions, environment details, and the pinned runtime manifest. It emits machine-readable JSON and a concise Markdown report.

### Gate mapping

The approved product gates are represented in this spike as follows:

- **Warm timeline:** authenticated local timeline retrieval is below 500 ms at the 95th percentile.
- **Committed-event visibility:** a successful local send followed by verified retrieval is below 2 seconds at the 95th percentile.
- **Responsiveness during import:** a Swift main-executor heartbeat is not delayed by more than one 60 Hz animation frame while background import proceeds.
- **Integrity:** expected rooms, imported events, live events, searchable content, and media metadata reconcile exactly after the run.

The timeline and main-executor measurements are server-and-harness proxies. Phase 2 does not claim that Matrix SDK synchronization or SwiftUI responsiveness has been proven. Those product-level gates must be repeated through the real client and UI in a later phase.

### Provisional hardware baseline

The current development Mac is the provisional benchmark baseline. Reports record its model, processor architecture, memory, macOS version, Python version, Synapse version, and pinned package set. The benchmark must be rerun on the eventual release-baseline Mac before a public-release database decision becomes final.

### SQLite verdict

SQLite fails the spike if any latency or responsiveness gate is missed, event reconciliation is inexact, corruption occurs, recovery cannot restore a consistent workload, or an unrecoverable benchmark request failure occurs.

The final report produces exactly one result:

- **Retain SQLite provisionally:** every Phase 2 gate passes, subject to later Matrix-client, product-UI, and release-baseline validation.
- **Require PostgreSQL:** at least one gate fails, with the evidence and workload context recorded for a separately scoped PostgreSQL design.

PostgreSQL is not implemented during this spike.

## Backup, restore, and recovery

Phase 2 supports application-coordinated offline backups only.

### Backup

1. Gracefully stop Synapse and verify that its process and listener are gone.
2. Run SQLite integrity and consistency checks.
3. Copy the database, required configuration, recovery secrets, media fixtures/metadata, and runtime manifest into a staging directory.
4. Generate backup metadata and checksums.
5. Atomically publish the completed backup.

An interrupted or invalid staging backup never replaces a previously valid backup.

### Restore

Restore accepts only a fresh or explicitly empty target profile. It verifies the backup manifest and every checksum before copying data, restores restrictive permissions, launches Synapse, and reconciles rooms, events, media metadata, health, and representative reads against the backup metadata.

### Recovery exercise

The acceptance workflow creates representative data, makes a verified backup, deliberately damages or removes the working profile data, restores into a clean profile, and repeats integrity plus read/write checks. Recovery passes only if all expected content is present and Synapse accepts new writes after restoration.

Secrets remain local. Logs and reports redact access tokens, registration secrets, generated credentials, message bodies, and sensitive identifiers.

## Clean removal

Removal requires a specific profile name and an explicit confirmation flag. It:

1. Stops the selected Synapse instance and verifies termination.
2. Resolves and revalidates every deletion target beneath the developer-runtime root.
3. Removes that profile's virtual environment, configuration, database, media, logs, process state, internal backups, and internal reports.
4. Verifies that no associated child, listener, or profile artifact remains.

The user may explicitly export a benchmark report outside the profile before removal. Removal never deletes such an external export. Partial failure is reported with the exact remaining artifacts and a nonzero exit status; it is never reported as success.

## Error handling and fault injection

Expected failures have stable CLI exit codes and concise diagnostics. Detailed redacted logs remain inside the profile.

Automated fault injection covers:

- Missing or drifted runtime dependencies
- Invalid or non-loopback configuration
- Occupied ports
- Startup timeout
- Unexpected process exit
- Healthy process identity with an unhealthy endpoint
- Exhaustion of the three-restart limit
- Stale process metadata
- Corrupted or incomplete backup
- Interrupted backup or restore staging
- Attempted restore into a nonempty target
- Attempted traversal or removal outside the developer-runtime root

## Testing strategy

### Unit tests

Test profile-path validation, state transitions, configuration invariants, manifest parsing, installed-version comparison, port allocation behavior, retry/backoff policy, checksum verification, report calculations, secret redaction, and verdict logic.

### Process integration tests

Using isolated profiles, test bootstrap validation, start, health, status, graceful stop, forced-stop fallback, restart, stale-state detection, injected crashes, bounded recovery, and loopback-only binding.

### Data-safety tests

Create representative data, perform backup, inject damage, restore into a clean profile, reconcile content, execute SQLite integrity checks, accept new writes, and verify scoped clean removal.

### Benchmark acceptance run

Run the full representative workload on the current development Mac and retain its JSON and Markdown reports as Phase 2 evidence. A result is valid only when its environment manifest, workload seed, counts, gate calculations, and integrity outcome are complete.

## Deliverables and completion criteria

Phase 2 is complete only when the repository contains:

- A checked-in manifest pinning the developer runtime and dependency set
- An explicit, repeatable bootstrap flow
- The `PalloRuntime` library and `PalloRuntimeCLI` executable
- Automated lifecycle, health, crash, backup, recovery, removal, and safety tests
- A deterministic representative workload
- JSON and Markdown results from the current development Mac
- A written provisional SQLite or PostgreSQL verdict backed by the results

No real adapter, Matrix client synchronization, product diagnostics UI, launch agent, updater, signing, notarization, or redistribution work is included in completion.

## Implementation planning and progress tracking

After this design is approved in its written form, the detailed implementation plan will also be represented as a GitHub Issues backlog. The backlog will contain one Phase 2 tracking issue and ordered implementation issues with:

- Explicit scope and out-of-scope boundaries
- Dependencies and execution order
- Acceptance criteria and verification commands
- Expected artifacts or benchmark evidence
- Progress updates and completion evidence as tasks advance

Issue creation is a planning action performed after the written spec review gate. It does not begin implementation. The repository plan document remains the durable technical plan; GitHub Issues provide the operational backlog and progress view.

## Authoritative context

- [Pallo macOS design](./2026-08-12-pallo-macos-design.md)
- [Pallo implementation roadmap](../plans/2026-08-12-pallo-implementation-roadmap.md)
- [Synapse installation documentation](https://matrix-org.github.io/synapse/latest/setup/installation.html)
- [Synapse configuration documentation](https://matrix-org.github.io/synapse/latest/usage/configuration/config_documentation.html)
- [Synapse administration documentation](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/index.html)
