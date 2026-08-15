# Phase 2 database verdict

## Require PostgreSQL

One approved gate was not met. Per the Phase 2 rule that any missed gate, event loss, corruption,
unrecoverable request failure, or recovery failure requires PostgreSQL, SQLite is not retained.

Measurement of record: seed `20260813`, 2,000 rooms, 100,000 imported messages, 3 concurrent import
workers plus live traffic, timeline reads, search, and media metadata. Raw samples in
`2026-08-15-sqlite-results.json`, human report in `2026-08-15-sqlite-report.md`, machine and runtime
facts in `2026-08-15-environment.json`.

## Failing gate

| Gate | Measured | Limit |
| --- | --- | --- |
| Main-executor heartbeat delay | **19.139 ms** | 16.67 ms |

The gate is the worst observed sample. Exactly one heartbeat of 30,778 exceeded one 60 Hz frame,
overshooting by 2.47 ms.

| Statistic | Value |
| --- | --- |
| p50 | 2.055 ms |
| p95 | 4.208 ms |
| p99 | 4.222 ms |
| p99.9 | 4.735 ms |
| Second-worst sample | 7.43 ms |
| Worst sample | 19.139 ms |
| Samples over budget | 1 of 30,778 (0.0032%) |

This is a single dropped frame under sustained import load, not sustained unresponsiveness. That
distinction matters for scoping the follow-up, but it does not change the verdict: the approved gate
is a hard maximum and it was exceeded. The gate was not relaxed, and no percentile was substituted
for the maximum in order to obtain a pass.

## Passing gates

| Gate | Measured | Limit | Margin |
| --- | --- | --- | --- |
| Warm timeline read p95 | 15.735 ms | 500 ms | 32× |
| Committed event visibility p95 | 41.621 ms | 2 s | 48× |
| Event reconciliation | 0 discrepancies | 0 | exact |
| Unrecoverable requests | 0 | 0 | exact |
| SQLite integrity | `ok` | `ok` | — |
| Recovery verified | verified | — | — |

Data integrity was exact. All 100,000 imported events plus 1,000 live-traffic events were read back
through independent queries after every writer finished, with zero missing events, zero duplicates,
and zero missing rooms. `PRAGMA quick_check` and `PRAGMA integrity_check` both returned `ok`.

Recovery was verified destructively on the full dataset: the stopped profile was backed up, its
database and configuration deleted, and the checksummed backup restored. The restored runtime passed
integrity, reconciled **2,000 rooms and 101,000 events**, and accepted a new write.

## Measurement caveats

Two facts materially affect how these numbers should be read.

**Rate limiters are raised far above production defaults.** The generated configuration sets
`rc_message`, `rc_room_creation`, `rc_joins`, `rc_invites`, `rc_registration`, and `rc_login` to
effectively unlimited. Without this, room creation fails with `M_LIMIT_EXCEEDED` after roughly ten
rooms. These results therefore describe SQLite and Synapse under concurrent import and read load,
not an end-user-facing throughput guarantee.

**Earlier runs of this benchmark were invalidated by the measurement harness itself and are not
reported here.** The heartbeat probe originally accumulated scheduling debt instead of measuring
per-frame lateness, reporting a nonsensical 1,072 s delay. After that was corrected it still
inherited the benchmark's own low priority, so the saturated import workers descheduled it for
minutes at a time. Pinning the probe to user-initiated priority — the QoS an app's UI main thread
actually runs at — fixed the measurement and also removed an 8× throughput distortion the probe had
been inflicting on the workload under test: the identical workload fell from 4,788 s to 579 s. Only
the corrected run is reported above.

## Scope of the PostgreSQL decision

Implementing PostgreSQL is explicitly out of scope for Phase 2 and must be scoped in a new design.
That design should resolve, before any implementation:

1. Whether a single 19.1 ms frame under sustained 100,000-message import is an acceptable
   responsiveness cost for a local-first app, or whether the 60 Hz maximum is the correct gate at
   all. Every other measured dimension passed with 32–48× margin, so this one sample is the entire
   basis for the decision.
2. Whether the heartbeat gate should remain a hard maximum or move to a high percentile with a
   separate bound on worst-case frame time. Changing it is a design decision to be argued on its
   merits — not something to be adjusted after seeing a result.
3. What PostgreSQL costs the product: bundling and supervising a second server process, its own
   backup and recovery story, and per-profile lifecycle, weighed against a measured SQLite failure
   of one dropped frame.

Recommendation for the follow-up design: re-run this same benchmark with the heartbeat treated as an
explicit research question rather than a pass/fail gate, and gather several runs to establish whether
the 19.1 ms outlier is reproducible or a single scheduling artifact. A one-sample failure is thin
evidence on which to adopt a second database engine, and the harness is now trustworthy enough to
answer that cheaply — a full run takes about ten minutes.
