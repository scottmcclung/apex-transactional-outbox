# Unusable client settings, benchmark and reproduce results

- **Date:** 2026-11-17
- **Code:** branch `3-2-unusable-client-settings` at `3edb9d9`. Compared with the branch-side numbers in `2026-11-17-missing-configuration.md`, which were recorded on branch `3-1-missing-configuration` at `6b262e4`.
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

`RunLocalTests` on this branch in `outbox-dev`: 92 run, 92 passed, 0 failed, on the first run.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Commands: `node bench.js bench_noop 1,10,100 120` once, then `node bench.js bench_noop 100 120` twice more, so there are three samples at 100 messages.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send. The baseline rows are the branch rows from `2026-11-17-missing-configuration.md`.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | 3-1 branch (baseline) | 3, 3 | 27, 26 | 7,980, 7,980 | 2 / 2 | 1, 1 |
| 1 | 3-2 branch | 3 | 27 | 7,991 | 2 / 2 | 1 |
| 10 | 3-1 branch (baseline) | 3, 3 | 26, 24 | 13,979, 13,979 | 2 / 2 | 1, 1 |
| 10 | 3-2 branch | 3 | 29 | 14,026 | 2 / 2 | 1 |
| 100 | 3-1 branch (baseline) | 3, 3, 3, 3, 3 | 38, 46, 32, 38, 41 | 74,009 in every sample | 2 / 2 | 1 each |
| 100 | 3-2 branch | 3, 3, 3 | 47, 33, 34 | 74,416 in every sample | 2 / 2 | 1 each |

At 100 messages, the median run CPU over three samples is 34 ms, against a baseline median of 38 ms. The samples range from 33 to 47 ms.

Run heap is 11 bytes higher at 1 message, 47 bytes higher at 10 messages and 407 bytes higher at 100 messages. The change in heap was not investigated. It is consistent across samples at each size.

Publish-side and run-side query, DML and relay job counts match the baseline at every size.

Delay from publish to completion was 0 or 1 second and changed between samples, so it is not compared here.

## Reproduce

| Scenario | Result on this branch | 3-1 branch result | Difference |
|---|---|---|---|
| `malformed-config` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `Config__c` and `repro_badjson_sub`. Healthy outbox delivered. No failed job | 6 failed relay jobs, healthy outbox not delivered | Expected: this change. Three attempts because the fixture subscription has a backoff of 0 |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered. No failed job | Same | None |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered. No failed job | Same | None |
| `bad-action-class` | 1 failed job, `NoSuchActionClass does not exist`, nothing delivered | Same | None |
| `action-called-with-null` | `ReproActionA` got 1 context. `ReproActionB` got 1 context and got null | `ReproActionB` called with null and with one context | None. The two `ReproActionB` records appeared in the other order, which is run-to-run variation |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Same | None |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | Same | None |

`Relay Queuable Skipped: Already enqueue from this context` printed in the `missing-subscription` and `missing-definition` runs, as it did in the 3-1 run.
