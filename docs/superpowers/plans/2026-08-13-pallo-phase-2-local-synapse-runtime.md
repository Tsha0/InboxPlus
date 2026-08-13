# Pallo Phase 2 Local Synapse Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a developer-only Swift runtime harness that supervises a pinned, loopback-only Synapse process, benchmarks SQLite under representative Pallo load, verifies backup/recovery/removal, and produces an evidence-based database verdict.

**Architecture:** Add a `PalloRuntime` library and `PalloRuntimeCLI` executable beside the existing Phase 1 targets. The library owns validated profile paths, Synapse configuration, child-process lifecycle, health, Matrix test traffic, backup/recovery, benchmark measurement, and reporting; the CLI is a thin command adapter. A checked-in Python dependency lock prepares Synapse 1.158.0 in a profile-local virtual environment using Homebrew CPython 3.12.

**Tech Stack:** Swift 6.2 package on macOS 15+, Swift Testing, Foundation `Process`, `URLSession`, POSIX process/filesystem APIs, CPython 3.12 virtual environments, Synapse 1.158.0, SQLite, Matrix client-server HTTP APIs.

## Global Constraints

- This is a developer spike; Homebrew Python and developer libraries are permitted only for bootstrap.
- Use Homebrew CPython 3.12; require the `3.12` minor line and record the detected patch version in each prepared profile.
- Pin `matrix-synapse==1.158.0` and every transitive Python package to exact versions in `Runtime/Synapse/requirements.lock`.
- Bind Synapse only to `127.0.0.1` on an allocated port; reject every non-loopback listener.
- Disable federation, public registration, guests, public room directories, and remote administration.
- Keep every profile beneath the user-scoped Pallo developer-runtime root with user-only permissions.
- Use a maximum of three bounded exponential-backoff restarts per supervised run.
- Benchmark at least 100,000 messages in 2,000 rooms with three concurrent synthetic import workers plus live traffic, timeline reads, search, and attachment metadata.
- Pass gates: warm timeline p95 below 500 ms, committed-event visibility p95 below 2 seconds, main-executor heartbeat delay no more than 16.67 ms, and exact data reconciliation.
- Any missed gate, event loss, corruption, unrecoverable request failure, or recovery failure requires PostgreSQL.
- Backups are offline and application-coordinated; hot backup is not part of this phase.
- Do not add real adapters, Matrix Rust SDK synchronization, product UI, launch-at-login, updater, signing, notarization, universal packaging, or public redistribution.
- Do not implement PostgreSQL in this phase.

## Execution sequencing clarifications

- Task 1 defines `PreparedRuntimeReceipt` beside `RuntimeManifest` so `validatePreparedRuntime(at:)` has a concrete return type; Task 3 adds the bootstrap behavior that creates and validates receipt contents.
- Task 3's disposable real-bootstrap coverage belongs in `Tests/PalloRuntimeTests/RuntimeBootstrapperRealIntegrationTests.swift`.
- Task 5's real lifecycle coverage belongs in `Tests/PalloRuntimeTests/SynapseSupervisorRealIntegrationTests.swift`.
- Task 6 creates the CLI shell and wires only bootstrap/start/status/stop, whose services exist by then. Tasks 7–11 wire `verify`, `benchmark`, `backup`, `restore`, and `remove` as their corresponding services are implemented. Command parsing may recognize the full planned command vocabulary in Task 6, but must not pretend an unavailable service is implemented.

## File and responsibility map

### Package and runtime manifest

- `Package.swift`: expose `PalloRuntime` and `PalloRuntimeTests` in Task 1, then add `PalloRuntimeCLI` when its source is introduced in Task 6.
- `Runtime/Synapse/runtime-manifest.json`: declare schema version, Python minor line, Synapse version, lockfile path, and lockfile checksum.
- `Runtime/Synapse/requirements.in`: declare direct Python dependency `matrix-synapse==1.158.0`.
- `Runtime/Synapse/requirements.lock`: exact transitive package versions used by bootstrap.
- `Scripts/lock-synapse-runtime.sh`: regenerate the lock deterministically with CPython 3.12.

### Profile, configuration, and process lifecycle

- `Sources/PalloRuntime/RuntimeManifest.swift`: decode and validate the checked-in manifest and prepared-runtime receipt.
- `Sources/PalloRuntime/RuntimePaths.swift`: validate profile names and contain all paths beneath one root.
- `Sources/PalloRuntime/ProfileLock.swift`: exclusive nonblocking profile lock.
- `Sources/PalloRuntime/SynapseConfiguration.swift`: render and validate the loopback-only YAML configuration.
- `Sources/PalloRuntime/RuntimeState.swift`: stable lifecycle states, snapshots, and CLI error codes.
- `Sources/PalloRuntime/ManagedProcess.swift`: injectable child-process boundary.
- `Sources/PalloRuntime/FoundationManagedProcess.swift`: `Foundation.Process` implementation with verified identity and bounded logs.
- `Sources/PalloRuntime/RuntimeBootstrapper.swift`: create the virtual environment, install the lock, and write the receipt.
- `Sources/PalloRuntime/SynapseSupervisor.swift`: state transitions, start/stop, health, and bounded crash recovery.
- `Sources/PalloRuntime/SynapseHealthChecker.swift`: process, endpoint, and authenticated Matrix checks.

### Matrix fixtures and benchmark

- `Sources/PalloRuntime/MatrixHTTPClient.swift`: narrow authenticated HTTP client used only by the spike.
- `Sources/PalloRuntime/MatrixFixtureProvisioner.swift`: create the local test user, token, rooms, and deterministic fixture metadata.
- `Sources/PalloRuntime/BenchmarkModels.swift`: workload, samples, environment, reconciliation, and verdict models.
- `Sources/PalloRuntime/BenchmarkRunner.swift`: concurrent synthetic imports, live traffic, reads, search, media metadata, and heartbeat.
- `Sources/PalloRuntime/BenchmarkReporter.swift`: calculate p95, decide verdict, redact, and write JSON/Markdown.

### Data safety and CLI

- `Sources/PalloRuntime/BackupManager.swift`: offline backup, checksums, atomic publication, restore, and recovery verification.
- `Sources/PalloRuntime/ProfileRemover.swift`: confirmed, contained removal and residue verification.
- `Sources/PalloRuntimeCLI/RuntimeCommand.swift`: parse commands and stable exit behavior.
- `Sources/PalloRuntimeCLI/main.swift`: construct dependencies, execute one command, and print concise output.
- `docs/testing/phase-2-runtime-acceptance.md`: exact developer acceptance workflow.
- `docs/benchmarks/phase-2/`: checked-in JSON/Markdown result and database verdict from the provisional baseline.

---

### Task 1: Add runtime targets, pinned manifest, and contained profile paths

**Files:**
- Modify: `Package.swift`
- Create: `Runtime/Synapse/runtime-manifest.json`
- Create: `Runtime/Synapse/requirements.in`
- Create: `Runtime/Synapse/requirements.lock`
- Create: `Scripts/lock-synapse-runtime.sh`
- Create: `Sources/PalloRuntime/RuntimeManifest.swift`
- Create: `Sources/PalloRuntime/RuntimePaths.swift`
- Create: `Tests/PalloRuntimeTests/RuntimeManifestTests.swift`
- Create: `Tests/PalloRuntimeTests/RuntimePathsTests.swift`

**Interfaces:**
- Produces: `RuntimeManifest.load(from:) throws -> RuntimeManifest`
- Produces: `RuntimeManifest.validatePreparedRuntime(at:) throws -> PreparedRuntimeReceipt`
- Produces: `RuntimePaths(root:profileName:) throws` with `runtime`, `configuration`, `data`, `logs`, `backups`, `reports`, and `state` URLs.

- [ ] **Step 1: Add failing manifest and traversal tests**

```swift
@Test func manifestRequiresPinnedSynapseAndPythonMinor() throws {
    let manifest = try RuntimeManifest.load(from: fixture("valid-runtime-manifest.json"))
    #expect(manifest.pythonMinor == "3.12")
    #expect(manifest.synapseVersion == "1.158.0")
}

@Test(arguments: ["../escape", "/tmp/escape", "a/b", "", "."])
func profileNameCannotEscapeRoot(_ name: String) {
    #expect(throws: RuntimePathError.self) {
        try RuntimePaths(root: URL(fileURLWithPath: "/tmp/pallo-runtime"), profileName: name)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify missing types fail**

Run: `swift test --filter 'RuntimeManifestTests|RuntimePathsTests'`

Expected: FAIL because `RuntimeManifest` and `RuntimePaths` do not exist.

- [ ] **Step 3: Add package targets and minimal validated models**

```swift
public struct RuntimeManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let pythonMinor: String
    public let synapseVersion: String
    public let requirementsLockSHA256: String
}

public struct RuntimePaths: Sendable {
    public let root: URL
    public let profile: URL
    public let runtime: URL
    public let configuration: URL
    public let data: URL
    public let logs: URL
    public let backups: URL
    public let reports: URL
    public let state: URL
}
```

Add the `PalloRuntime` product/target and `PalloRuntimeTests` target. Defer the `PalloRuntimeCLI` product/target to Task 6, where its first source file is created. Validate names against `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`, standardize every URL, reject symlinked ancestors, and require every resolved child path to remain beneath the standardized root.

- [ ] **Step 4: Generate and check the exact Python dependency lock**

`Runtime/Synapse/requirements.in`:

```text
matrix-synapse==1.158.0
```

`Scripts/lock-synapse-runtime.sh` must create a temporary CPython 3.12 virtual environment, install only the direct requirement, emit sorted `name==version` lines using `pip freeze --all`, and remove the temporary environment through a trap. Run it once and commit the concrete generated `requirements.lock`; calculate its SHA-256 into `runtime-manifest.json`.

```bash
#!/bin/sh
set -eu

python_path=/opt/homebrew/opt/python@3.12/bin/python3.12
temporary_runtime=$(mktemp -d)
trap 'rm -rf "$temporary_runtime"' EXIT INT TERM

"$python_path" -m venv "$temporary_runtime/venv"
"$temporary_runtime/venv/bin/python" -m pip install -r Runtime/Synapse/requirements.in
"$temporary_runtime/venv/bin/python" -m pip freeze --all | LC_ALL=C sort > Runtime/Synapse/requirements.lock
```

Run: `Scripts/lock-synapse-runtime.sh && shasum -a 256 Runtime/Synapse/requirements.lock`

Expected: the printed checksum exactly matches `requirementsLockSHA256`.

- [ ] **Step 5: Run tests and repository checks**

Run: `swift test --filter 'RuntimeManifestTests|RuntimePathsTests' && git diff --check`

Expected: PASS with zero failures and no whitespace errors.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Runtime/Synapse Scripts/lock-synapse-runtime.sh Sources/PalloRuntime/RuntimeManifest.swift Sources/PalloRuntime/RuntimePaths.swift Tests/PalloRuntimeTests
git commit -m "feat: define pinned Synapse runtime profiles"
```

### Task 2: Generate and enforce the local-only Synapse configuration

**Files:**
- Create: `Sources/PalloRuntime/SynapseConfiguration.swift`
- Create: `Tests/PalloRuntimeTests/SynapseConfigurationTests.swift`

**Interfaces:**
- Consumes: `RuntimePaths`
- Produces: `SynapseConfiguration(profile:port:credentials:)`
- Produces: `render() throws -> String` and `validate() throws`

- [ ] **Step 1: Write failing loopback and forbidden-feature tests**

```swift
@Test func renderedConfigurationIsPrivateAndLoopbackOnly() throws {
    let yaml = try fixtureConfiguration(port: 18_008).render()
    #expect(yaml.contains("bind_addresses: ['127.0.0.1']"))
    #expect(yaml.contains("enable_registration: false"))
    #expect(yaml.contains("allow_guest_access: false"))
    #expect(!yaml.contains("federation"))
}

@Test func nonLoopbackListenerIsRejected() {
    #expect(throws: SynapseConfigurationError.nonLoopbackAddress("0.0.0.0")) {
        try fixtureConfiguration(bindAddress: "0.0.0.0").validate()
    }
}
```

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter SynapseConfigurationTests`

Expected: FAIL because `SynapseConfiguration` is absent.

- [ ] **Step 3: Implement explicit YAML rendering and validation**

```swift
public struct SynapseConfiguration: Sendable {
    public let serverName: String
    public let bindAddress: String
    public let port: UInt16
    public let databasePath: URL
    public let mediaPath: URL
    public let signingKeyPath: URL
    public let registrationSecret: String

    public func validate() throws
    public func render() throws -> String
}
```

Render only the client/resource listener needed for the spike, set `federation: false` on the listener, disable registration/guests/room-list publication, disable URL previews and telemetry, and keep secrets in the YAML file with mode `0600`, never in arguments.

- [ ] **Step 4: Run the focused and full suites**

Run: `swift test --filter SynapseConfigurationTests && swift test`

Expected: PASS with zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/SynapseConfiguration.swift Tests/PalloRuntimeTests/SynapseConfigurationTests.swift
git commit -m "feat: enforce private Synapse configuration"
```

### Task 3: Bootstrap and verify the profile-local Python runtime

**Files:**
- Create: `Sources/PalloRuntime/RuntimeBootstrapper.swift`
- Create: `Sources/PalloRuntime/ProfileLock.swift`
- Create: `Tests/PalloRuntimeTests/RuntimeBootstrapperTests.swift`
- Create: `Tests/PalloRuntimeTests/ProfileLockTests.swift`

**Interfaces:**
- Consumes: `RuntimeManifest`, `RuntimePaths`
- Produces: `RuntimeBootstrapper.bootstrap(python:manifest:paths:) async throws -> PreparedRuntimeReceipt`
- Produces: `ProfileLock.acquire(at:) throws -> ProfileLock`

- [ ] **Step 1: Write failing bootstrap receipt, drift, permission, and lock tests**

```swift
@Test func bootstrapRecordsInterpreterAndExactPackages() async throws {
    let receipt = try await bootstrapper.bootstrap(python: fakePython, manifest: manifest, paths: paths)
    #expect(receipt.pythonVersion == "3.12.7")
    #expect(receipt.synapseVersion == "1.158.0")
    #expect(receipt.requirementsLockSHA256 == manifest.requirementsLockSHA256)
}

@Test func secondProfileLockIsRejected() throws {
    let first = try ProfileLock.acquire(at: lockURL)
    defer { _ = first }
    #expect(throws: ProfileLockError.alreadyLocked) { try ProfileLock.acquire(at: lockURL) }
}
```

- [ ] **Step 2: Verify focused tests fail**

Run: `swift test --filter 'RuntimeBootstrapperTests|ProfileLockTests'`

Expected: FAIL because bootstrap and locking types are missing.

- [ ] **Step 3: Implement bootstrap without implicit upgrades**

```swift
public struct PreparedRuntimeReceipt: Codable, Sendable, Equatable {
    public let pythonExecutable: String
    public let pythonVersion: String
    public let synapseVersion: String
    public let requirementsLockSHA256: String
    public let installedPackages: [String: String]
    public let createdAt: Date
}
```

Bootstrap must require an executable reporting Python `3.12.x`, create directories with mode `0700`, run `python -m venv`, install `-r requirements.lock` with version checks, compare `pip freeze --all` exactly to the lock, run `synapse_homeserver --version`, and atomically write the receipt. Existing valid runtimes are idempotent; drift is an error requiring explicit profile removal and bootstrap.

- [ ] **Step 4: Run unit tests and a disposable real bootstrap integration test**

Run: `swift test --filter 'RuntimeBootstrapperTests|ProfileLockTests'`

Run: `PALLO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test --filter RuntimeBootstrapperRealIntegrationTests`

Expected: tests PASS; smoke bootstrap reports Python 3.12.x, Synapse 1.158.0, and a matching lock checksum.

- [ ] **Step 5: Verify the integration test removes its disposable profile**

Run: `test ! -e "$(getconf DARWIN_USER_CACHE_DIR)/PalloRuntimeTests/bootstrap-real"`

Expected: exit 0 and no disposable integration profile residue.

- [ ] **Step 6: Commit**

```bash
git add Sources/PalloRuntime/RuntimeBootstrapper.swift Sources/PalloRuntime/ProfileLock.swift Tests/PalloRuntimeTests/RuntimeBootstrapperTests.swift Tests/PalloRuntimeTests/ProfileLockTests.swift
git commit -m "feat: bootstrap pinned Synapse environment"
```

### Task 4: Implement lifecycle state and verified child-process control

**Files:**
- Create: `Sources/PalloRuntime/RuntimeState.swift`
- Create: `Sources/PalloRuntime/ManagedProcess.swift`
- Create: `Sources/PalloRuntime/FoundationManagedProcess.swift`
- Create: `Sources/PalloRuntime/SynapseSupervisor.swift`
- Create: `Tests/PalloRuntimeTests/RuntimeStateTests.swift`
- Create: `Tests/PalloRuntimeTests/SynapseSupervisorLifecycleTests.swift`

**Interfaces:**
- Produces: `RuntimePhase`, `RuntimeSnapshot`, `RuntimeExitCode`
- Produces: `ManagedProcessFactory.make(_:) throws -> ManagedProcess`
- Produces: `SynapseSupervisor.start() async throws -> RuntimeSnapshot`
- Produces: `SynapseSupervisor.stop() async throws -> RuntimeSnapshot`
- Produces: `SynapseSupervisor.status() async -> RuntimeSnapshot`

- [ ] **Step 1: Write failing state-transition and lifecycle tests with a fake process**

```swift
@Test func userStopTransitionsHealthyToStoppedWithoutRestart() async throws {
    let process = FakeManagedProcess()
    let supervisor = makeSupervisor(process: process)
    _ = try await supervisor.start()
    let stopped = try await supervisor.stop()
    #expect(stopped.phase == .stopped)
    #expect(process.terminateCalls == 1)
    #expect(process.launchCalls == 1)
}

@Test func startFromStartingIsRejected() async {
    let supervisor = makeSupervisor(initialPhase: .starting)
    await #expect(throws: RuntimeStateError.invalidTransition(from: .starting, to: .starting)) {
        try await supervisor.start()
    }
}
```

- [ ] **Step 2: Verify the lifecycle tests fail**

Run: `swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests'`

Expected: FAIL because lifecycle types are absent.

- [ ] **Step 3: Implement the actor state machine and process abstraction**

```swift
public enum RuntimePhase: String, Codable, Sendable {
    case unprepared, stopped, starting, healthy, degraded, recovering, stopping, failed
}

public actor SynapseSupervisor {
    public func start() async throws -> RuntimeSnapshot
    public func stop() async throws -> RuntimeSnapshot
    public func status() async -> RuntimeSnapshot
}
```

Use `Foundation.Process` only inside `FoundationManagedProcess`. Record executable path, launch timestamp, PID, and a process-start identity token; never signal a PID until those fields match. Write stdout/stderr to rotating bounded files. Graceful stop sends termination, waits five seconds, then escalates and verifies process plus listener disappearance.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter 'RuntimeStateTests|SynapseSupervisorLifecycleTests' && swift test`

Expected: PASS with zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/RuntimeState.swift Sources/PalloRuntime/ManagedProcess.swift Sources/PalloRuntime/FoundationManagedProcess.swift Sources/PalloRuntime/SynapseSupervisor.swift Tests/PalloRuntimeTests/RuntimeStateTests.swift Tests/PalloRuntimeTests/SynapseSupervisorLifecycleTests.swift
git commit -m "feat: supervise Synapse lifecycle"
```

### Task 5: Add layered health checks and bounded crash recovery

**Files:**
- Create: `Sources/PalloRuntime/SynapseHealthChecker.swift`
- Modify: `Sources/PalloRuntime/SynapseSupervisor.swift`
- Create: `Tests/PalloRuntimeTests/SynapseHealthCheckerTests.swift`
- Create: `Tests/PalloRuntimeTests/SynapseSupervisorRecoveryTests.swift`

**Interfaces:**
- Produces: `SynapseHealthChecker.check(snapshot:) async -> HealthResult`
- Extends: `SynapseSupervisor.supervise() async`
- Produces: retry delays of 1, 2, and 4 seconds and terminal failure after attempt three.

- [ ] **Step 1: Write failing health and recovery-policy tests**

```swift
@Test func liveProcessWithFailedAuthenticatedRequestIsDegraded() async {
    let health = await checker.check(snapshot: healthyProcessSnapshot)
    #expect(health == .degraded(.matrixRequestFailed(status: 401)))
}

@Test func fourthCrashEntersFailedWithoutRelaunch() async throws {
    let process = CrashableFakeProcess()
    let supervisor = makeSupervisor(process: process, retrySleeper: immediateSleeper)
    try await process.crashFourTimes()
    #expect(await supervisor.status().phase == .failed)
    #expect(process.launchCalls == 4) // initial launch plus three recovery attempts
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter 'SynapseHealthCheckerTests|SynapseSupervisorRecoveryTests'`

Expected: FAIL because health and recovery behavior is missing.

- [ ] **Step 3: Implement layered health and recovery**

```swift
public enum HealthResult: Sendable, Equatable {
    case healthy(latency: Duration)
    case degraded(HealthFailure)
    case stopped
}
```

Require matching process identity, a responsive `/_matrix/client/versions` endpoint, and a lightweight authenticated `/_matrix/client/v3/account/whoami` request. Poll every 500 ms during startup up to 30 seconds. On unexpected exit, transition through `recovering`, sleep 1/2/4 seconds, and stop after three failed restarts. A healthy interval of 60 seconds resets the consecutive crash count.

On the first successful unauthenticated versions response, use the profile's local registration shared secret to create a dedicated `_pallo_probe` local user, store its access token in a `0600` profile credential file, and use only that token for subsequent authenticated health checks. Reuse and verify the probe identity on later starts; never print the secret or token.

- [ ] **Step 4: Run focused tests and a real start/status/stop integration test**

Run: `swift test --filter 'SynapseHealthCheckerTests|SynapseSupervisorRecoveryTests'`

Run: `PALLO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 swift test --filter SynapseSupervisorRealIntegrationTests`

Expected: tests PASS; the real supervisor reaches `healthy`, then `stopped`, and the listener is gone.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/SynapseHealthChecker.swift Sources/PalloRuntime/SynapseSupervisor.swift Tests/PalloRuntimeTests/SynapseHealthCheckerTests.swift Tests/PalloRuntimeTests/SynapseSupervisorRecoveryTests.swift
git commit -m "feat: recover bounded Synapse crashes"
```

### Task 6: Add the developer CLI and stable command outcomes

**Files:**
- Modify: `Package.swift`
- Create: `Sources/PalloRuntimeCLI/RuntimeCommand.swift`
- Create: `Sources/PalloRuntimeCLI/main.swift`
- Create: `Tests/PalloRuntimeTests/RuntimeCommandTests.swift`

**Interfaces:**
- Consumes: runtime bootstrapper, supervisor, backup, benchmark, and removal services.
- Produces: `RuntimeCommand.parse(_:) throws -> RuntimeCommand`
- Produces: stable exit codes for usage, invalid state, unavailable dependency, health failure, integrity failure, benchmark failure, and unsafe path.

- [ ] **Step 1: Write failing command parsing and safety tests**

```swift
@Test func removeRequiresMatchingConfirmation() throws {
    let command = try RuntimeCommand.parse(["remove", "--profile", "alpha", "--confirm", "alpha"])
    #expect(command == .remove(profile: "alpha", confirmation: "alpha", exportReport: nil))
}

@Test func missingProfileIsUsageError() {
    #expect(throws: RuntimeCommandError.missingOption("--profile")) {
        try RuntimeCommand.parse(["start"])
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter RuntimeCommandTests`

Expected: FAIL because the command parser does not exist.

- [ ] **Step 3: Implement the thin CLI adapter**

```swift
enum RuntimeCommand: Equatable {
    case bootstrap(profile: String, python: String)
    case start(profile: String)
    case status(profile: String)
    case stop(profile: String)
    case benchmark(profile: String, options: BenchmarkCLIOptions)
    case backup(profile: String, name: String)
    case restore(profile: String, backup: String)
    case verify(profile: String, options: VerifyCLIOptions)
    case remove(profile: String, confirmation: String, exportReport: String?)
}

struct BenchmarkCLIOptions: Equatable {
    let seed: UInt64
    let rooms: Int
    let messages: Int
    let importWorkers: Int
}

struct VerifyCLIOptions: Equatable {
    let fixtureRooms: Int?
    let simulateDataLoss: Bool
    let restoreBackup: String?
    let reportName: String?
}
```

Add the `PalloRuntimeCLI` executable product/target to `Package.swift`. Keep construction and formatted output in `main.swift`; business logic remains in `PalloRuntime`. Print one concise summary to stdout, diagnostics to stderr, and map typed runtime errors to documented stable integer codes.

- [ ] **Step 4: Run CLI parser and package tests**

Run: `swift test --filter RuntimeCommandTests && swift test`

Run: `swift run PalloRuntimeCLI bootstrap --profile lifecycle-smoke --python /opt/homebrew/opt/python@3.12/bin/python3.12 && swift run PalloRuntimeCLI start --profile lifecycle-smoke && swift run PalloRuntimeCLI status --profile lifecycle-smoke && swift run PalloRuntimeCLI stop --profile lifecycle-smoke`

Expected: tests PASS; CLI bootstrap succeeds, status reports `healthy` while started, stop reports `stopped`, and the profile remains available to later integration tasks.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/PalloRuntimeCLI Tests/PalloRuntimeTests/RuntimeCommandTests.swift
git commit -m "feat: expose Synapse developer CLI"
```

### Task 7: Provision deterministic Matrix fixtures through a narrow HTTP client

**Files:**
- Create: `Sources/PalloRuntime/MatrixHTTPClient.swift`
- Create: `Sources/PalloRuntime/MatrixFixtureProvisioner.swift`
- Create: `Tests/PalloRuntimeTests/MatrixHTTPClientTests.swift`
- Create: `Tests/PalloRuntimeTests/MatrixFixtureProvisionerTests.swift`

**Interfaces:**
- Produces: `MatrixHTTPClient.request<T: Decodable>(...) async throws -> T`
- Produces: `MatrixFixtureProvisioner.prepare(seed:) async throws -> FixtureContext`
- Produces: `FixtureContext` containing user ID, access token, device ID, and deterministic room IDs.

- [ ] **Step 1: Write failing authenticated request and deterministic fixture tests**

```swift
@Test func clientRejectsNonLoopbackBaseURL() {
    #expect(throws: MatrixHTTPError.nonLoopbackBaseURL) {
        try MatrixHTTPClient(baseURL: URL(string: "http://192.0.2.10:8008")!, token: "secret")
    }
}

@Test func sameSeedProducesSameRoomAliases() async throws {
    let first = try await provisioner.plan(seed: 42, roomCount: 2_000)
    let second = try await provisioner.plan(seed: 42, roomCount: 2_000)
    #expect(first.roomAliases == second.roomAliases)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter 'MatrixHTTPClientTests|MatrixFixtureProvisionerTests'`

Expected: FAIL because the Matrix fixture types are absent.

- [ ] **Step 3: Implement the local authenticated client and provisioner**

Use ephemeral admin credentials created during profile initialization, then create a normal local benchmark user and token. Accept only `http://127.0.0.1:<port>`. Percent-encode path segments, use deterministic transaction IDs, enforce request deadlines, decode Matrix error bodies, retry only explicit transient statuses with idempotent transaction IDs, and redact authorization headers.

```swift
public struct FixtureContext: Codable, Sendable {
    public let seed: UInt64
    public let userID: String
    public let accessToken: String
    public let deviceID: String
    public let roomIDs: [String]
}
```

- [ ] **Step 4: Run unit and real 10-room fixture smoke tests**

Run: `swift test --filter 'MatrixHTTPClientTests|MatrixFixtureProvisionerTests'`

Run: `swift run PalloRuntimeCLI verify --profile lifecycle-smoke --fixture-rooms 10`

Expected: tests PASS and the smoke profile reconciles exactly 10 rooms.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/MatrixHTTPClient.swift Sources/PalloRuntime/MatrixFixtureProvisioner.swift Tests/PalloRuntimeTests/MatrixHTTPClientTests.swift Tests/PalloRuntimeTests/MatrixFixtureProvisionerTests.swift
git commit -m "feat: provision local Matrix fixtures"
```

### Task 8: Execute the representative concurrent workload

**Files:**
- Create: `Sources/PalloRuntime/BenchmarkModels.swift`
- Create: `Sources/PalloRuntime/BenchmarkRunner.swift`
- Create: `Tests/PalloRuntimeTests/BenchmarkRunnerTests.swift`

**Interfaces:**
- Consumes: `MatrixHTTPClient`, `FixtureContext`
- Produces: `BenchmarkRunner.run(_:) async throws -> BenchmarkRun`
- Produces: `BenchmarkWorkload.representative(seed:)` with exact counts and concurrency.

- [ ] **Step 1: Write failing workload-shape, concurrency, and reconciliation tests**

```swift
@Test func representativeWorkloadMeetsApprovedShape() {
    let workload = BenchmarkWorkload.representative(seed: 42)
    #expect(workload.roomCount == 2_000)
    #expect(workload.messageCount >= 100_000)
    #expect(workload.importWorkerCount == 3)
    #expect(workload.liveTrafficCount > 0)
}

@Test func missingEventFailsReconciliation() async throws {
    let run = try await runner.run(.small(seed: 7, omittedEvent: true))
    #expect(run.reconciliation.missingEventIDs.count == 1)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter BenchmarkRunnerTests`

Expected: FAIL because benchmark models and runner are missing.

- [ ] **Step 3: Implement deterministic concurrent workload execution**

```swift
public struct BenchmarkWorkload: Codable, Sendable {
    public let seed: UInt64
    public let roomCount: Int
    public let messageCount: Int
    public let importWorkerCount: Int
    public let liveTrafficCount: Int
    public let timelineReadCount: Int
    public let searchCount: Int
    public let mediaMetadataCount: Int
}
```

Partition deterministic rooms among exactly three import task-group children. Run a fourth live-traffic child plus timeline, search, and media-metadata children while imports remain active. Use stable transaction IDs so retries cannot duplicate committed events. Record every expected room/event ID and reconcile through independent reads after all writers finish.

- [ ] **Step 4: Add and run a reduced integration workload**

Run: `swift test --filter BenchmarkRunnerTests`

Run: `swift run PalloRuntimeCLI benchmark --profile lifecycle-smoke --seed 42 --rooms 20 --messages 1000`

Expected: tests PASS; reduced run reports 20 rooms, 1,000 imported messages, live traffic, reads, search, media metadata, and zero missing/duplicate events.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/BenchmarkModels.swift Sources/PalloRuntime/BenchmarkRunner.swift Tests/PalloRuntimeTests/BenchmarkRunnerTests.swift
git commit -m "feat: generate representative Matrix load"
```

### Task 9: Measure gates and emit redacted JSON/Markdown verdicts

**Files:**
- Create: `Sources/PalloRuntime/BenchmarkReporter.swift`
- Modify: `Sources/PalloRuntime/BenchmarkRunner.swift`
- Create: `Tests/PalloRuntimeTests/BenchmarkReporterTests.swift`

**Interfaces:**
- Consumes: `BenchmarkRun`
- Produces: `BenchmarkReporter.evaluate(_:) -> BenchmarkVerdict`
- Produces: `BenchmarkReporter.write(_:to:) throws -> ReportArtifacts`

- [ ] **Step 1: Write failing percentile, gate, redaction, and verdict tests**

```swift
@Test func percentileUsesNearestRank() {
    #expect(BenchmarkReporter.percentile([1, 2, 3, 100], percentile: 0.95) == 100)
}

@Test func anyIntegrityFailureRequiresPostgreSQL() {
    let run = fixtureRun(missingEvents: 1, allLatencyGatesPassing: true)
    #expect(BenchmarkReporter.evaluate(run).decision == .requirePostgreSQL)
}

@Test func reportsDoNotContainTokensOrMessageBodies() throws {
    let report = try reporter.markdown(for: fixtureRun(token: "secret-token", body: "private body"))
    #expect(!report.contains("secret-token"))
    #expect(!report.contains("private body"))
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter BenchmarkReporterTests`

Expected: FAIL because reporter behavior is missing.

- [ ] **Step 3: Implement measurements and strict verdict logic**

Measure warm timeline request duration, send-to-retrieval duration, and a main-actor heartbeat scheduled every 16.67 ms during background import. Record all raw samples in JSON and p50/p95/p99 summaries in Markdown. Collect Mac model, architecture, memory, macOS, Swift, Python, Synapse, dependency-lock checksum, database bytes, CPU time, and peak resident memory.

```swift
public enum DatabaseDecision: String, Codable, Sendable {
    case retainSQLiteProvisionally
    case requirePostgreSQL
}
```

Return `requirePostgreSQL` when warm timeline p95 is at least 500 ms, committed-event p95 is at least 2 seconds, heartbeat delay is greater than 16.67 ms, reconciliation is nonempty, SQLite integrity is not `ok`, recovery is unverified, or an unrecoverable request occurred. Write reports atomically and exclude tokens, secrets, message bodies, and sensitive identifiers.

- [ ] **Step 4: Run reporter tests and inspect a reduced report**

Run: `swift test --filter BenchmarkReporterTests`

Run: `swift run PalloRuntimeCLI benchmark --profile lifecycle-smoke --seed 42 --rooms 20 --messages 1000 && ! rg -n 'secret|access_token|private body' "$HOME/Library/Application Support/Pallo/DeveloperRuntime/lifecycle-smoke/reports"`

Expected: tests PASS; JSON and Markdown exist; secret scan returns no matches.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/BenchmarkReporter.swift Sources/PalloRuntime/BenchmarkRunner.swift Tests/PalloRuntimeTests/BenchmarkReporterTests.swift
git commit -m "feat: report SQLite benchmark verdict"
```

### Task 10: Implement atomic offline backup, restore, and recovery verification

**Files:**
- Create: `Sources/PalloRuntime/BackupManager.swift`
- Create: `Tests/PalloRuntimeTests/BackupManagerTests.swift`

**Interfaces:**
- Consumes: `RuntimePaths`, stopped `RuntimeSnapshot`, `SynapseSupervisor`
- Produces: `BackupManager.create(name:) async throws -> BackupManifest`
- Produces: `BackupManager.restore(name:into:) async throws -> RestoreResult`
- Produces: `BackupManager.verifyRecovery(...) async throws -> RecoveryResult`

- [ ] **Step 1: Write failing stopped-state, atomicity, checksum, and nonempty-target tests**

```swift
@Test func backupRejectsRunningProfile() async {
    await #expect(throws: BackupError.runtimeMustBeStopped) {
        try await manager.create(name: "before-damage")
    }
}

@Test func corruptedFilePreventsRestoreBeforeTargetMutation() async throws {
    try corruptBackupDatabase()
    await #expect(throws: BackupError.checksumMismatch) {
        try await manager.restore(name: "before-damage", into: emptyTarget)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: emptyTarget.profile.path).isEmpty)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter BackupManagerTests`

Expected: FAIL because backup behavior is absent.

- [ ] **Step 3: Implement offline backup and restore**

```swift
public struct BackupManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let profileName: String
    public let runtimeManifestSHA256: String
    public let files: [BackupFile]
    public let expectedRoomCount: Int
    public let expectedEventCount: Int
}
```

Require a verified stopped runtime; run `sqlite3 <database> 'PRAGMA quick_check; PRAGMA integrity_check;'`; copy database, configuration, signing/recovery keys, media, and runtime receipt into a sibling staging directory; hash every regular file; fsync and atomically rename staging to the final backup. Restore only after all checksums pass and only into a fresh or explicitly empty profile. Apply `0700` directories and `0600` secret/data files before launch.

- [ ] **Step 4: Implement and run the destructive recovery exercise on an isolated profile**

Run: `swift test --filter BackupManagerTests`

Run: `swift run PalloRuntimeCLI backup --profile lifecycle-smoke --name before-damage && swift run PalloRuntimeCLI verify --profile lifecycle-smoke --simulate-data-loss --restore before-damage`

Expected: tests PASS; restored profile passes SQLite integrity, exact room/event/media reconciliation, health, and a new post-restore write.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/BackupManager.swift Tests/PalloRuntimeTests/BackupManagerTests.swift
git commit -m "feat: verify Synapse backup recovery"
```

### Task 11: Implement confirmed clean removal and residue checks

**Files:**
- Create: `Sources/PalloRuntime/ProfileRemover.swift`
- Create: `Tests/PalloRuntimeTests/ProfileRemoverTests.swift`

**Interfaces:**
- Consumes: `RuntimePaths`, `SynapseSupervisor`
- Produces: `ProfileRemover.remove(confirmation:exportReportTo:) async throws -> RemovalResult`

- [ ] **Step 1: Write failing confirmation, containment, symlink, export, and residue tests**

```swift
@Test func confirmationMustExactlyMatchProfile() async {
    await #expect(throws: RemovalError.confirmationMismatch) {
        try await remover.remove(confirmation: "wrong", exportReportTo: nil)
    }
}

@Test func symlinkOutsideRootIsRejectedWithoutDeletingTarget() async throws {
    try createEscapingSymlink()
    await #expect(throws: RuntimePathError.self) {
        try await remover.remove(confirmation: paths.profileName, exportReportTo: nil)
    }
    #expect(FileManager.default.fileExists(atPath: outsideSentinel.path))
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter ProfileRemoverTests`

Expected: FAIL because profile removal is missing.

- [ ] **Step 3: Implement stop-first, contained removal**

Revalidate standardized paths immediately before each deletion, refuse symlinks, stop and verify the exact process/listener first, optionally copy the newest redacted report to an explicitly external destination, delete only the named profile, then verify the profile path, process identity, and listener are absent. Return exact residue paths and nonzero status for partial failure.

- [ ] **Step 4: Run tests and remove disposable profiles**

Run: `swift test --filter ProfileRemoverTests`

Run: `swift run PalloRuntimeCLI remove --profile lifecycle-smoke --confirm lifecycle-smoke`

Expected: tests PASS; no runtime process, listener, or `lifecycle-smoke` profile remains.

- [ ] **Step 5: Commit**

```bash
git add Sources/PalloRuntime/ProfileRemover.swift Tests/PalloRuntimeTests/ProfileRemoverTests.swift
git commit -m "feat: remove isolated Synapse profiles"
```

### Task 12: Add end-to-end fault injection and acceptance documentation

**Files:**
- Create: `Tests/PalloRuntimeTests/RuntimeFaultInjectionTests.swift`
- Create: `Tests/PalloRuntimeTests/RuntimeEndToEndTests.swift`
- Create: `docs/testing/phase-2-runtime-acceptance.md`

**Interfaces:**
- Consumes: all runtime and CLI interfaces from Tasks 1–11.
- Produces: one documented, reproducible acceptance sequence and fault matrix.

- [ ] **Step 1: Add integration tests for every approved fault**

```swift
@Test(.tags(.runtimeIntegration))
func occupiedPortIsRejectedBeforeProcessLaunch() async throws

@Test(.tags(.runtimeIntegration))
func unhealthyRunningProcessBecomesDegraded() async throws

@Test(.tags(.runtimeIntegration))
func interruptedRestoreLeavesOriginalProfileUnchanged() async throws

@Test(.tags(.runtimeIntegration))
func versionDriftBlocksStartupUntilExplicitBootstrap() async throws
```

Also cover startup timeout, unexpected exit, restart exhaustion, stale process state, corrupted backup, invalid non-loopback configuration, nonempty restore target, and out-of-root removal.

- [ ] **Step 2: Verify new tests fail for unimplemented fault seams**

Run: `swift test --filter 'RuntimeFaultInjectionTests|RuntimeEndToEndTests'`

Expected: at least one fault test FAILS before the required injection seam is added.

- [ ] **Step 3: Add deterministic injection seams without production-only branches**

Inject clocks, sleepers, port allocators, file operations, process factories, and HTTP transports through protocols or closures. Production defaults use Foundation/POSIX implementations; tests supply deterministic failures.

- [ ] **Step 4: Write the acceptance guide**

Document prerequisites, bootstrap, configuration inspection, start/status/stop, injected crash recovery, reduced benchmark, full benchmark, backup/damage/restore, removal, report paths, exit-code meanings, and exact evidence required for the database verdict.

- [ ] **Step 5: Run all automated checks**

Run: `swift test && swift build -c release && git diff --check`

Expected: all tests PASS, release build exits 0, and diff check is clean.

- [ ] **Step 6: Commit**

```bash
git add Tests/PalloRuntimeTests/RuntimeFaultInjectionTests.swift Tests/PalloRuntimeTests/RuntimeEndToEndTests.swift docs/testing/phase-2-runtime-acceptance.md
git commit -m "test: verify Synapse runtime failures"
```

### Task 13: Run the full benchmark and commit the database decision

**Files:**
- Create: `docs/benchmarks/phase-2/2026-08-13-environment.json`
- Create: `docs/benchmarks/phase-2/2026-08-13-environment.json`
- Create: `docs/benchmarks/phase-2/2026-08-13-sqlite-results.json`
- Create: `docs/benchmarks/phase-2/2026-08-13-sqlite-report.md`
- Create: `docs/benchmarks/phase-2/sqlite-verdict.md`

**Interfaces:**
- Consumes: completed runtime CLI and acceptance workflow.
- Produces: immutable raw environment/results files, human report, and one explicit database decision.

- [ ] **Step 1: Verify the machine and runtime receipt before measurement**

Run: `swift run -c release PalloRuntimeCLI bootstrap --profile phase-2-acceptance --python /opt/homebrew/opt/python@3.12/bin/python3.12`

Run: `swift run -c release PalloRuntimeCLI verify --profile phase-2-acceptance`

Expected: CPython 3.12.x, Synapse 1.158.0, exact lock checksum, user-only permissions, and loopback-only configuration all verify.

- [ ] **Step 2: Run the complete representative benchmark once without competing developer workloads**

Run: `swift run -c release PalloRuntimeCLI benchmark --profile phase-2-acceptance --seed 20260813 --rooms 2000 --messages 100000 --import-workers 3`

Expected: command completes and emits immutable JSON plus Markdown even when the verdict is PostgreSQL-required.

- [ ] **Step 3: Verify report completeness and integrity**

Run: `swift run -c release PalloRuntimeCLI verify --profile phase-2-acceptance --report latest`

Expected: report contains environment, seed, exact counts, raw samples, p95 calculations, SQLite integrity, recovery evidence, reconciliation, and one decision; secret scan is empty.

- [ ] **Step 4: Execute backup, destructive recovery, and removal acceptance**

Run: `swift run -c release PalloRuntimeCLI backup --profile phase-2-acceptance --name acceptance && swift run -c release PalloRuntimeCLI verify --profile phase-2-acceptance --simulate-data-loss --restore acceptance`

Run: `swift run -c release PalloRuntimeCLI remove --profile phase-2-acceptance --confirm phase-2-acceptance --export-report docs/benchmarks/phase-2/`

Expected: recovery accepts a new write; removal leaves no profile/process/listener; exported evidence remains.

- [ ] **Step 5: Write the verdict without weakening failed gates**

`sqlite-verdict.md` must state exactly `Retain SQLite provisionally` only when every gate and recovery check passed. Otherwise it must state exactly `Require PostgreSQL`, enumerate failing gates with measured values, and scope PostgreSQL implementation to a new design.

- [ ] **Step 6: Run final verification**

Run: `swift test && swift build -c release && git diff --check && ! rg -n 'access_token|registration_shared_secret|private body' docs/benchmarks/phase-2`

Expected: tests and release build PASS, diff check is clean, reports contain no secrets, and the verdict matches the raw results.

- [ ] **Step 7: Commit**

```bash
git add docs/benchmarks/phase-2
git commit -m "docs: record Phase 2 SQLite verdict"
```

## GitHub Issues backlog mapping

Create one parent issue titled **Phase 2: local Synapse runtime and SQLite decision**. Create one child backlog issue for each Task 1–13 using the task title, file scope, dependencies, acceptance criteria, and verification commands above. The parent body contains an ordered checklist linking every child issue.

Progress policy:

- Move or label only one dependency-chain issue as active at a time unless two issues are demonstrably independent.
- Add a start comment naming the branch/commit baseline before implementation.
- Check acceptance boxes and attach command output or report links before closing an issue.
- Update the parent checklist as each child closes.
- Do not close the parent until Task 13 records a database decision and all excluded-scope items remain excluded.

Dependency order:

1. Task 1 is the root.
2. Task 2 depends on Task 1.
3. Task 3 depends on Tasks 1–2.
4. Task 4 depends on Tasks 1–3.
5. Task 5 depends on Task 4.
6. Task 6 depends on Tasks 3–5.
7. Task 7 depends on Tasks 2, 5, and 6.
8. Task 8 depends on Task 7.
9. Task 9 depends on Task 8.
10. Task 10 depends on Tasks 5, 7, and 9.
11. Task 11 depends on Tasks 4, 6, and 10.
12. Task 12 depends on Tasks 1–11.
13. Task 13 depends on Task 12.

## Authoritative references

- Design: `docs/superpowers/specs/2026-08-13-pallo-phase-2-local-synapse-runtime-design.md`
- Roadmap: `docs/superpowers/plans/2026-08-12-pallo-implementation-roadmap.md`
- Synapse releases: <https://github.com/element-hq/synapse/releases>
- Synapse PyPI metadata: <https://pypi.org/project/matrix-synapse/>
- Synapse installation: <https://element-hq.github.io/synapse/latest/setup/installation.html>
- Synapse configuration: <https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html>
- Matrix client-server API: <https://spec.matrix.org/latest/client-server-api/>
