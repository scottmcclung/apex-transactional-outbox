# Message resolver given only the messages the run may attempt, benchmark and reproduce results

- **Date:** 2026-11-17
- **Code:** branch `3-4-resolver-messages` at `125db0b`. Compared with `2026-11-17-after-relay-actions.md`, which was recorded on branch `3-3-after-relay-actions` at `3017fcb`. That branch is now `main`, so its 3-3 rows are the baseline for this file.
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

`RunLocalTests` on this branch in `outbox-dev`: 125 run, 125 passed, 0 failed, on the first run.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Commands: `node bench.js bench_noop 1,10,100 120` once, then `node bench.js bench_noop 100 120` four more times, so there are five samples at 100 messages. The samples were run one after another, not at the same time. The first 100-message sample is the one printed by the sweep.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send. The 3-3 rows are from `2026-11-17-after-relay-actions.md`.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | 3-3 branch (main) | 3 | 27 | 8,047 | 2 / 2 | 1 |
| 1 | 3-4 branch | 3 | 33 | 8,234 | 2 / 2 | 1 |
| 10 | 3-3 branch (main) | 3 | 19 | 14,082 | 2 / 2 | 1 |
| 10 | 3-4 branch | 3 | 25 | 14,269 | 2 / 2 | 1 |
| 100 | 3-3 branch (main) | 3, 3, 3 | 38, 37, 39 | 74,472 in every sample | 2 / 2 | 1 each |
| 100 | 3-4 branch | 3, 3, 3, 3, 3 | 43, 37, 39, 39, 40 | 74,659 in every sample | 2 / 2 | 1 each |

At 100 messages, the median run CPU over five samples is 39 ms, against 38 ms for the 3-3 branch. The 3-4 samples range from 37 to 43 ms. The 3-3 samples range from 37 to 39 ms. The 3-4 branch is 1 ms higher at the median.

Run heap is 187 bytes higher at 1 message, 187 bytes higher at 10 messages and 187 bytes higher at 100 messages, against the 3-3 branch. The offset is the same at every size.

Each outbox completed with one attempt in every run. Publish-side and run-side query, DML and relay job counts match the 3-3 branch at every size.

Delay from publish to completion was between 0 and 1 second and changed between runs, so it is not compared here.

## Reproduce

| Scenario | Result on this branch | 3-3 branch result (main) | Difference |
|---|---|---|---|
| `malformed-config` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `Config__c` and `repro_badjson_sub`. Healthy outbox delivered | Same | None |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered | Same | None |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered | Same | None |
| `bad-action-class` | 1 completed job. Both outboxes delivered, 1 attempt each. No failed job | Same | None |
| `action-called-with-null` | 2 completed jobs. Both outboxes delivered, 1 attempt each. `ReproActionA got 1 context(s)`. `ReproActionB got 1 context(s)`. No null | Same | None |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Same | None |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | Same | None |

`Relay Queuable Skipped: Already enqueue from this context` printed in the `missing-subscription` and `missing-definition` runs, as it did before.
