# Missing configuration, benchmark and reproduce results

- **Date:** 2026-11-17
- **Code:** branch `3-1-missing-configuration` at `6b262e4`, and `main` at `3784a23` for the same-day comparison
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

Compared with `2026-11-16-baseline.md`, which was recorded on `main` at `aad6e5f`. `main` changed after that baseline, so some differences below come from `main`, not from this branch.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Command: `node bench.js bench_noop 1,10,100 120`, run twice for each code version. Five more runs at 100 messages were added to measure the spread there: `node bench.js bench_noop 100 120`.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | main | 3, 3 | 31, 23 | 8,038, 8,038 | 2 / 2 | 1, 1 |
| 1 | branch | 3, 3 | 27, 26 | 7,980, 7,980 | 2 / 2 | 1, 1 |
| 10 | main | 3, 3 | 22, 31 | 14,037, 14,037 | 2 / 2 | 1, 1 |
| 10 | branch | 3, 3 | 26, 24 | 13,979, 13,979 | 2 / 2 | 1, 1 |
| 100 | main | 3, 3, 3, 3, 3 | 32, 32, 55, 34, 42 | 74,067 in every sample | 2 / 2 | 1 each |
| 100 | branch | 3, 3, 3, 3, 3 | 38, 46, 32, 38, 41 | 74,009 in every sample | 2 / 2 | 1 each |

At 100 messages, run CPU over five samples gives a median of 34 ms for `main` and 38 ms for the branch. The ranges overlap (32 to 55 ms for `main`, 32 to 46 ms for the branch), so a small increase is possible and not shown.

The branch uses 58 fewer heap bytes than `main` at each size. Heap was the same in every sample of a version.

Delay from publish to completion was 0 or 1 second in the same runs and changed between samples, so it is not compared here.

## Reproduce

Run on the branch. `main` was not run for the reproduce scenarios.

| Scenario | Result on the branch | 2026-11-16 baseline | Difference |
|---|---|---|---|
| `malformed-config` | 6 failed relay jobs, healthy outbox not delivered | 6 failed jobs, healthy message undelivered | None |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered. No failed job | 6 failed jobs, healthy message undelivered | Expected: this change |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered. No failed job | 1 failed job, nothing delivered | Expected: this change. Three attempts because the fixture subscription has a backoff of 0 |
| `bad-action-class` | 1 failed job, `NoSuchActionClass does not exist`, nothing delivered | 1 failed job, nothing delivered | None |
| `action-called-with-null` | `ReproActionB` called with null and with one context | Action called with null | None |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Query selected a future-TTL outbox and the real cleanup threw | From `main`, not this branch. See below |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | No baseline | First recorded result |

### Differences from the 2026-11-16 baseline that come from `main`

- **`cleanup`:** the behavior matches PR #47 (commits `861638b` and `7254a5d`), which merged to `main` after the baseline was recorded. This branch does not change any cleanup code, so the attribution rests on that diff. It is not based on a same-day run of `main`.
- **Query count inside the run:** 2 in the baseline, 3 now. `main` also shows 3 on the same day, before this branch's changes, so the change is from `main`.

### Output not in the baseline

- `missing-subscription` and `missing-definition` each printed `Relay Queuable Skipped: Already enqueue from this context`. The baseline did not record this line. Its cause has not been looked into.
