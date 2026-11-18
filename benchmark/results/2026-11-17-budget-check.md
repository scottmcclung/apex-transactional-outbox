# Budget check before each attempt, benchmark and reproduce results

- **Date:** 2026-11-17. The session ran past midnight UTC, so the later samples are from early on 2026-11-18.
- **Code:** branch `4-2-budget-check` at `baefff3`. Compared with `main` at `7a6a1a6`, measured in the same session in the same org, and with `2026-11-17-send-cost.md`, which was recorded on branch `4-1-send-cost` at `e43327b`. That branch is now `main`.
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

`RunLocalTests` on this branch in `outbox-dev`: 171 run, 171 passed, 0 failed, on the first run. It was run a second time after the last redeploy of the branch, with the same result. Org-wide coverage is 89%. The test run reports 0% line coverage for `TB_SendCost`.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Commands: `node bench.js bench_noop 1,10,100 120` once, then `node bench.js bench_noop 100 120` four more times, so there are five samples at 100 messages. The samples were run one after another, not at the same time. The first 100-message sample is the one printed by the sweep.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send.

`main` and this branch were measured in alternating rounds in the same session: main, the branch before the change described below, the branch after it, the branch at `baefff3`, main again, and the branch at `baefff3` again. Each round deployed `force-app` and then `benchmark/fixtures`. Deploying main over the branch leaves the branch-only classes in the org. They are not called by main's code.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | main, round 1 | 3 | 28 | 8,626 | 2 / 2 | 1 |
| 1 | main, round 2 | 3 | 31 | 8,626 | 2 / 2 | 1 |
| 1 | branch before the change | 3 | 35 | 9,048 | 2 / 2 | 1 |
| 1 | branch, round 1 | 3 | 31 | 9,048 | 2 / 2 | 1 |
| 1 | branch, round 2 | 3 | 34 | 9,048 | 2 / 2 | 1 |
| 10 | main, round 1 | 3 | 30 | 14,751 | 2 / 2 | 1 |
| 10 | main, round 2 | 3 | 32 | 14,751 | 2 / 2 | 1 |
| 10 | branch before the change | 3 | 35 | 15,168 | 2 / 2 | 1 |
| 10 | branch, round 1 | 3 | 25 | 15,168 | 2 / 2 | 1 |
| 10 | branch, round 2 | 3 | 31 | 15,168 | 2 / 2 | 1 |
| 100 | main, round 1 | 3 in every sample | 67, 58, 62, 55, 56 | 76,041 in every sample | 2 / 2 | 1 each |
| 100 | main, round 2 | 3 in every sample | 66, 64, 63, 61, 60 | 76,041 in every sample | 2 / 2 | 1 each |
| 100 | branch before the change | 3 in every sample | 101, 99, 91, 96, 90 | 76,461 in the first sample, 76,458 in the others | 2 / 2 | 1 each |
| 100 | branch after the change, at `c82ce94` | 3 in every sample | 77, 95, 78, 78, 86 | 76,458 in every sample | 2 / 2 | 1 each |
| 100 | branch, round 1 | 3 in every sample | 90, 84, 82, 88, 86 | 76,458 in every sample | 2 / 2 | 1 each |
| 100 | branch, round 2 | 3 in every sample | 86, 87, 75, 83, 82 | 76,458 in every sample | 2 / 2 | 1 each |

The rows "branch, round 1" and "branch, round 2" are the code at `baefff3`. It differs from `c82ce94` only in tests, comments and the README.

### What the check costs per attempt

At 100 messages the median run CPU is 61.5 ms for main over its ten samples, and 84 ms for the branch over its fifteen samples after the change. That is about 22 ms for 99 checked attempts, or about 0.2 ms of CPU per attempt. Before the change the branch's median was 96 ms over five samples, about 0.35 ms per attempt.

For each outbox the run now builds the relay client before the attempt instead of during it, calls `costOfSend`, checks the nine fields of the declaration, reads nine limits from the `Limits` class and the clock, and compares the two. Building the client is not new work. The client is cached per subscription, as it was on main. Timed in anonymous Apex in this org, 500 times each, the parts before the change were: building the three maps of nine fields each that the check and the comparison used, about 0.14 ms; reading the nine limits and the clock, about 0.04 ms; calling `costOfSend`, about 0.02 ms. The change compares and checks the nine fields directly, without the maps. Timed the same way after the change, `costOfSend` with the check took about 0.025 ms and reading the limits with the comparison about 0.05 ms. Anonymous Apex and the relay job both run with the org's Apex debug log level at FINEST, which adds to the cost of every statement, so these times are for comparing parts and do not add up to the benchmark figure. Asking for the declaration once per subscription per run would save at most the 0.025 ms, which is smaller than the spread between samples, so that was not done.

Run heap is 422 bytes higher at 1 message and 417 bytes higher at 10 and 100 messages, against main. The offset does not grow with the number of messages, and the change did not alter it.

At 1 and 10 messages, run CPU varies by several ms between rounds for the same code, and the branch's figures overlap main's.

### Against `2026-11-17-send-cost.md`

That file recorded 74,662 bytes of run heap at 100 messages and a median run CPU of 42 ms for main. Main gave 76,041 bytes and a median of 61.5 ms in this session. So figures from different sessions in this org are not comparable: an earlier estimate of the branch's cost, made against that file, gave about 0.5 ms and 18 bytes per message, and both were too high. The same-session figures above replace it.

Each outbox completed with one attempt in every run. Publish-side and run-side query, DML and relay job counts are the same for main and this branch at every size, and match `2026-11-17-send-cost.md`.

Delay from publish to completion was between 0 and 1 second at the median in every run, except two 100-message samples: one of the branch before the change took 5 seconds, and the last of the branch's second round took 2 seconds. Delay is not compared here.

The reset step did not fail in any run in this session. Every anonymous Apex response was kept while the scripts ran, and none reported a failure.

## Reproduce

| Scenario | Result on this branch | Result in `2026-11-17-send-cost.md` | Difference |
|---|---|---|---|
| `malformed-config` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `Config__c` and `repro_badjson_sub`. Healthy outbox delivered | Same | None |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered | Same | None |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered | Same | None |
| `bad-action-class` | 1 completed job. Both outboxes delivered, 1 attempt each. No failed job | Same | None |
| `action-called-with-null` | 2 completed jobs. Both outboxes delivered, 1 attempt each. `ReproActionA got 1 context(s)`. `ReproActionB got 1 context(s)`. No null | Same | None |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Same | None |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | Same | None |

`Relay Queuable Skipped: Already enqueue from this context` printed in the `missing-subscription` and `missing-definition` runs, as it did before.
