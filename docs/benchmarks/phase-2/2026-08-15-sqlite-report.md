# Phase 2 SQLite benchmark

**Decision: Require PostgreSQL**

## Workload

| Dimension | Value |
| --- | --- |
| Seed | 20260813 |
| Rooms | 2000 |
| Messages | 100000 |
| Import workers | 3 |
| Import partitions | 667, 667, 666 |
| Live traffic events | 1000 |
| Elapsed | 579.41 s |

## Gates

| Gate | Measured | Limit | Result |
| --- | --- | --- | --- |
| warm timeline read p95 | 0.0157345 s | 0.5 s | pass |
| committed event visibility p95 | 0.041621 s | 2 s | pass |
| main executor heartbeat delay | 0.0191393 s | 0.01667 s | FAIL |
| event reconciliation | 0 discrepancies | 0 discrepancies | pass |
| unrecoverable requests | 0 requests | 0 requests | pass |
| sqlite integrity | 0 failures | 0 failures | pass |
| recovery verified | 0 failures | 0 failures | pass |

## Latency summary

| Series | p50 | p95 | p99 | Samples |
| --- | --- | --- | --- | --- |
| Imports | 0.0151118 | 0.0230357 | 0.0300194 | 100000 |
| Warm timeline reads | 0.011186 | 0.0157345 | 0.0307846 | 200 |
| Committed event visibility | 0.0321606 | 0.041621 | 0.0500627 | 1000 |
| Searches | 0.00493779 | 0.0119558 | 0.0361692 | 20 |
| Media metadata | 0.000985625 | 0.00504429 | 0.0122271 | 100 |
| Heartbeat delays | 0.00205508 | 0.00420788 | 0.00422238 | 30778 |

The heartbeat probe runs on the main executor at user-initiated priority, standing in
for an app's UI main thread. The gate uses the worst observed sample, not a percentile.

## Reconciliation

| Measure | Value |
| --- | --- |
| Expected events | 101000 |
| Observed events | 101000 |
| Missing events | 0 |
| Duplicate events | 0 |
| Missing rooms | 0 |
| Unrecoverable requests | 0 |
| SQLite integrity | ok |
| Recovery verified | true |

## Environment

| Property | Value |
| --- | --- |
| Hardware | Mac15,7 (arm64) |
| Memory | 19327352832 bytes |
| OS | Version 26.5.1 (Build 25F80) |
| Swift | 6.2 |
| Python | 3.12.7 |
| Synapse | 1.158.0 |
| Dependency lock SHA-256 | b57db5ecc3784d2ef6f2c13ff5cf55c471e91a3fb57cb92992954baa368f14c6 |
| Database size | 326430720 bytes |
| Peak resident memory | 167919616 bytes |
| CPU time | 84.7321 s |

## Failing gates

- main executor heartbeat delay measured 0.0191393 s against a 0.01667 s limit
