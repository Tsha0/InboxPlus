# Phase 2 local Synapse runtime — developer acceptance

This is the exact, reproducible sequence for accepting the Phase 2 runtime spike and producing the
evidence behind the database verdict. Everything here is developer-only: no product UI, no launch
agent, no signing, no redistribution.

## Prerequisites

- macOS 15 or later on Apple silicon.
- Swift 6.2 toolchain (`swift --version`).
- Homebrew CPython 3.12 at `/opt/homebrew/opt/python@3.12/bin/python3.12`.
- Run every command from the repository root, so `Runtime/Synapse` resolves. To run from elsewhere,
  set `MIMO_RUNTIME_PACKAGE_ROOT` to the repository root.

Profiles live under `~/Library/Application Support/Mimo/DeveloperRuntime/<profile>` with
user-only permissions. Override the root with `MIMO_RUNTIME_ROOT` for disposable runs.

## Runtime ownership model

The supervisor controls only its own direct child, which is what makes its process-identity and
signal guarantees sound. Consequently:

- `start` supervises **in the foreground** and holds the profile lock until you interrupt it.
- Commands that need a live Synapse (`benchmark`, `verify`) start and stop it internally, in one
  process. You do not need a separate `start` for them.
- `status` observes only. It takes no lock and never writes state, so it is always safe to run
  against a profile another session owns.
- `stop` reconciles a profile whose owning session is gone. It refuses to signal a runtime that a
  live session still owns.

## 1. Prepare the pinned runtime

```sh
swift run MimoRuntimeCLI bootstrap --profile phase-2-acceptance \
  --python /opt/homebrew/opt/python@3.12/bin/python3.12
```

Expect: `python=3.12.x synapse=1.158.0 packages=60`.

Bootstrap creates a profile-local virtual environment, installs the exact
`Runtime/Synapse/requirements.lock`, verifies the lock checksum against
`Runtime/Synapse/runtime-manifest.json`, writes a prepared-runtime receipt, generates signing keys,
and renders a loopback-only configuration. Version drift is an error: remove the profile and
bootstrap again rather than upgrading in place.

## 2. Verify the prepared runtime and its configuration

```sh
swift run MimoRuntimeCLI verify --profile phase-2-acceptance
```

Expect: `configuration=loopback-only` and the pinned Python and Synapse versions.

Inspect the generated configuration directly if you want to confirm the safety posture:

```sh
grep -E 'bind_addresses|enable_registration|allow_guest_access|send_federation' \
  ~/Library/Application\ Support/Mimo/DeveloperRuntime/phase-2-acceptance/configuration/homeserver.yaml
```

Expect `bind_addresses: ['127.0.0.1']`, registration and guest access disabled, federation off.

## 3. Exercise the supervised lifecycle

In one shell:

```sh
swift run MimoRuntimeCLI start --profile phase-2-acceptance
```

Expect `phase=healthy port=<allocated> pid=<pid>` then `supervising; press Ctrl-C to stop`.

In a second shell, while the first is supervising:

```sh
swift run MimoRuntimeCLI status --profile phase-2-acceptance   # phase=healthy
swift run MimoRuntimeCLI stop   --profile phase-2-acceptance   # refuses: the session owns it
```

Interrupt the first shell with Ctrl-C. It reports `phase=stopped`. Then:

```sh
swift run MimoRuntimeCLI status --profile phase-2-acceptance   # phase=stopped
```

Health is layered: the exact child process must match its recorded identity, the loopback
`/_matrix/client/versions` endpoint must respond, and an authenticated `whoami` must succeed using a
dedicated `mimo_probe` account whose token is stored `0600` inside the profile.

## 4. Reconcile deterministic fixtures

```sh
swift run MimoRuntimeCLI verify --profile phase-2-acceptance --fixture-rooms 10
```

Expect: `rooms=10/10 reconciled exactly`. Room aliases are derived from the seed, so repeating this
command adopts the same rooms instead of creating new ones.

## 5. Run a reduced benchmark

```sh
swift run MimoRuntimeCLI benchmark --profile phase-2-acceptance \
  --seed 42 --rooms 20 --messages 1000
```

Expect nonzero imports, zero missing events, zero duplicates, zero unrecoverable failures, and
`integrity=ok`. Reports land in the profile's `reports/` directory as JSON and Markdown.

Confirm no secrets were written:

```sh
grep -rE 'registration_shared_secret|access_token' \
  ~/Library/Application\ Support/Mimo/DeveloperRuntime/phase-2-acceptance/reports || echo clean
```

## 6. Back up, damage, and recover

```sh
swift run MimoRuntimeCLI backup --profile phase-2-acceptance --name acceptance
swift run MimoRuntimeCLI verify --profile phase-2-acceptance \
  --simulate-data-loss --restore acceptance
```

Expect `integrity=ok`, the fixture rooms recovered, and `accepted-new-write=true`.

Backups are offline only: a backup of a running profile is refused. Every file is checksummed, the
backup is published by atomic rename, and a restore verifies every checksum **before** touching the
target. A restore into a non-empty profile is refused.

## 7. Run the full representative benchmark

Close other workloads first; this run is the measurement of record.

```sh
swift run -c release MimoRuntimeCLI benchmark --profile phase-2-acceptance \
  --seed 20260813 --rooms 2000 --messages 100000 --import-workers 3
```

The command emits JSON and Markdown even when the verdict is PostgreSQL-required.

## 8. Remove the profile and export evidence

```sh
swift run MimoRuntimeCLI remove --profile phase-2-acceptance \
  --confirm phase-2-acceptance --export-report docs/benchmarks/phase-2/
```

Removal requires a confirmation matching the profile name exactly, refuses while the runtime is
live, deletes only the named profile, and verifies no residue remains. Reports are exported before
deletion. Symlinks inside a profile are unlinked, never followed, so nothing outside the profile is
touched.

## Gates and the database verdict

A run retains SQLite only when **every** gate passes:

| Gate | Limit |
| --- | --- |
| Warm timeline read p95 | below 500 ms |
| Committed event visibility p95 | below 2 s |
| Main-executor heartbeat delay | at most 16.67 ms |
| Event reconciliation | zero missing, duplicate, or absent rooms |
| Unrecoverable requests | zero |
| SQLite integrity | `ok` |
| Recovery verified | restored profile passes integrity and accepts a new write |

Any failure means `Require PostgreSQL`. Gates are never weakened to obtain a passing verdict.

### Benchmark caveat

The generated configuration raises Synapse's rate limiters (`rc_message`, `rc_room_creation`,
`rc_joins`, `rc_invites`, `rc_registration`, `rc_login`) far above production defaults. This is
deliberate: the benchmark measures storage and timeline behaviour under load, not the rate limiter.
Results describe SQLite under concurrent import and read traffic, not an end-user-facing throughput
guarantee.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | success |
| 10 | usage error (bad command, option, or confirmation) |
| 20 | invalid lifecycle transition, or the runtime is owned by a live session |
| 21 | profile not prepared |
| 22 | process launch failed |
| 23 | process identity mismatch |
| 24 | shutdown incomplete |
| 25 | unavailable dependency (Python, manifest, lock, profile lock) |
| 26 | health failure |
| 27 | integrity failure (checksums, snapshots, configuration, missing backup) |
| 28 | benchmark or verification failure |
| 29 | unsafe path (escapes the profile root, or a bad restore target) |

## Automated checks

```sh
swift test && swift build -c release && git diff --check
```

Real-Synapse integration tests are opt-in:

```sh
MIMO_RUNTIME_PYTHON=/opt/homebrew/opt/python@3.12/bin/python3.12 \
  swift test --filter 'RuntimeBootstrapperRealIntegrationTests|SynapseSupervisorRealIntegrationTests'
```
