# After-relay actions built per subscription, benchmark and reproduce results

- **Date:** 2026-11-17
- **Code:** branch `3-3-after-relay-actions` at `3017fcb`. Compared with `2026-11-17-unusable-client-settings.md`, which was recorded on branch `3-2-unusable-client-settings` at `3edb9d9`. That branch is now `main`, so its rows are the comparison that matters. The `3-1 branch (baseline)` rows in that file are shown for reference only.
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

`RunLocalTests` on this branch in `outbox-dev`: 108 run, 108 passed, 0 failed, on the first run.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Commands: `node bench.js bench_noop 1,10,100 120` once, then `node bench.js bench_noop 100 120` twice more, so there are three samples at 100 messages. The three samples were run one after another, not at the same time.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send. The 3-2 rows are from `2026-11-17-unusable-client-settings.md`.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | 3-2 branch (main) | 3 | 27 | 7,991 | 2 / 2 | 1 |
| 1 | 3-3 branch | 3 | 27 | 8,047 | 2 / 2 | 1 |
| 10 | 3-2 branch (main) | 3 | 29 | 14,026 | 2 / 2 | 1 |
| 10 | 3-3 branch | 3 | 19 | 14,082 | 2 / 2 | 1 |
| 100 | 3-2 branch (main) | 3, 3, 3 | 47, 33, 34 | 74,416 in every sample | 2 / 2 | 1 each |
| 100 | 3-3 branch | 3, 3, 3 | 38, 37, 39 | 74,472 in every sample | 2 / 2 | 1 each |

At 100 messages, the median run CPU over three samples is 38 ms, against 34 ms for the 3-2 branch. The 3-3 samples range from 37 to 39 ms. The 3-2 samples range from 33 to 47 ms.

Run heap is 56 bytes higher at 1 message, 56 bytes higher at 10 messages and 56 bytes higher at 100 messages, against the 3-2 branch. The run no longer builds the after-relay actions, so a small move either way is expected. Against the older 3-1 branch numbers, the difference at 100 messages is 463 bytes, which is well under the 1,000 byte bound.

Each outbox completed with one attempt in every run. Publish-side and run-side query, DML and relay job counts match the 3-2 branch at every size.

Delay from publish to completion was between 0 and 4 seconds and changed between runs, so it is not compared here.

## Reproduce

| Scenario | Result on this branch | 3-2 branch result (main) | Difference |
|---|---|---|---|
| `malformed-config` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `Config__c` and `repro_badjson_sub`. Healthy outbox delivered | Same | None |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered | Same | None |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered | Same | None |
| `bad-action-class` | 1 completed job. Both outboxes delivered, 1 attempt each. No failed job | 1 failed job, `NoSuchActionClass does not exist`, nothing delivered | Expected: this change |
| `action-called-with-null` | 2 completed jobs. Both outboxes delivered, 1 attempt each. `ReproActionA got 1 context(s)`. `ReproActionB got 1 context(s)`. No null | `ReproActionB` received null | Expected: this change |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Same | None |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | Same | None |

`Relay Queuable Skipped: Already enqueue from this context` printed in the `missing-subscription` and `missing-definition` runs, as it did before.
