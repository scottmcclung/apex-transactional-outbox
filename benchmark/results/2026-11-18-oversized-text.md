# Shortening oversized error and log text, benchmark and reproduce results

- **Date:** 2026-11-18, between 02:00 and 02:25 UTC
- **Code:** branch `5-5-shorten-oversized-text` at `8ba0ef5`. Compared with `main` at `cd22d63`, measured in the same session in the same org. For main, only its three changed relay classes (`TB_OutboxRelayContext`, `TB_OutboxRelayQueuable`, `TB_GenericHttpRelayClient`) were deployed over the branch, and the branch was deployed again afterwards.
- **Org:** scratch org `outbox-dev`
- **Setup:** one subscription per message, max attempts 3, retry backoff 0 for the benchmark fixtures

`RunLocalTests` on this branch in `outbox-dev`: 185 run, 185 passed, 0 failed.

**Debug logging.** The org's only trace flag, a `DEVELOPER_LOG` flag at ApexCode `FINEST` on the running user, expired at 00:40:02 UTC. It was checked at 02:02 and 02:23 UTC and was still expired. Every figure below was taken without a debug log on the relay job.

These are scratch org figures. They are for comparing versions and do not predict production.

## Benchmark

Commands: `node bench.js bench_noop 1,10,100 120` once, then `node bench.js bench_noop 100 120` more times, in alternating rounds: main, then the branch, then main, then the branch. The samples were run one after another, not at the same time.

"Run CPU" and "run heap" are the maximums printed by `bench.js` as seen at each send.

| Messages | Code | Queries inside the run | Run CPU (ms) | Run heap (bytes) | Publish queries / DML statements | Relay jobs |
|---|---|---|---|---|---|---|
| 1 | main | 3 | 29 | 9,794 | 2 / 2 | 1 |
| 1 | branch | 3 | 23 | 9,823 | 2 / 2 | 1 |
| 10 | main | 3 | 25 | 15,824 | 2 / 2 | 1 |
| 10 | branch | 3 | 24 | 15,853 | 2 / 2 | 1 |
| 100 | main, round 1 | 3 in every sample | 50, 52, 47 | 76,214 in every sample | 2 / 2 | 1 each |
| 100 | main, round 2 | 3 in every sample | 52, 44, 44, 45 | 76,214 in every sample | 2 / 2 | 1 each |
| 100 | branch, round 1 | 3 in every sample | 54, 50, 54 | 76,243 in every sample | 2 / 2 | 1 each |
| 100 | branch, round 2 | 3 in every sample | 50, 50, 47, 46 | 76,243 in every sample | 2 / 2 | 1 each |

Run heap is 29 bytes higher on the branch at every size. The offset does not grow with the number of messages. It matches the two field lengths the context class now reads into static fields when it loads.

An earlier version of the branch assigned the log and the error on every attempt, even when neither was shortened. It gave 9,791, 16,078 and 78,718 bytes at 1, 10 and 100 messages, about 25 bytes more for every outbox, with run CPU of 43, 25 and 62 ms in one sample each. The branch now assigns a field only when it shortens it, which removed that growth. Those samples are not in the table.

At 100 messages the median run CPU is 47 ms for main over seven samples and 50 ms for the branch over seven. The 3 ms difference is inside the spread of either version's samples, so it is not taken as a cost of the change.

Each outbox completed with one attempt in every run. Publish-side and run-side query, DML and relay job counts are the same for main and the branch at every size.

### Against `2026-11-18-cpu-growth.md`

That file recorded 52, 49 and 53 ms and 75,079 bytes at 100 messages for main at `da41ad9`, also without logging. Main gave 44 to 52 ms and 76,214 bytes in this session. The 1,135 byte heap difference for the same relay code across sessions is not explained here. The same-session figures above are the comparison.

## Reproduce

| Scenario | Result on this branch | Result in `2026-11-17-budget-check.md` | Difference |
|---|---|---|---|
| `malformed-config` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `Config__c` and `repro_badjson_sub`. Healthy outbox delivered | Same | None |
| `missing-subscription` | 1 completed job. Faulty outbox: 1 attempt, error names `subscription_that_was_deleted`. Healthy outbox delivered | Same | None |
| `missing-definition` | 3 completed jobs. Faulty outbox: 3 attempts, dead-lettered, error names `definition_that_was_deleted`. Healthy outbox delivered | Same | None |
| `bad-action-class` | 1 completed job. Both outboxes delivered, 1 attempt each. No failed job | Same | None |
| `action-called-with-null` | 2 completed jobs. Both outboxes delivered, 1 attempt each. `ReproActionA got 1 context(s)`. `ReproActionB got 1 context(s)`. No null | Same | None |
| `cleanup` | Selects the outbox whose TTL has passed and keeps the one whose TTL is ahead. Runs without an exception. 1 outbox left | Same | None |
| `blank-max-attempts` | After blanking max attempts, the outbox is dead-lettered at once | Same | None |
| `oversized-text` | 1 completed job. Error outbox: 1 attempt, not delivered, not dead-lettered. Its error is 131,072 characters, starts with `OVERSIZED-START`, does not hold `OVERSIZED-END`, and ends with `[Shortened from 136245 characters to fit its field. The end was dropped.]`. Log outbox: 1 attempt, delivered, not sent again while watched. Its log is 131,071 characters, starts with `[Shortened from 136094 characters to fit its field. The start was dropped.]`, does not hold `OVERSIZED-START`, and ends with `OVERSIZED-END`. `ReproActionB got 1 context(s)` | New scenario | New |

`Relay Queuable Skipped: Already enqueue from this context` printed in the `missing-subscription` and `missing-definition` runs, as it did before.

The two oversized messages were also published by hand, with the commands in `benchmark/README.md`, and their outboxes read with SOQL. The result was the same as the scenario's, and the error outbox showed a next attempt 60 minutes after its attempt. Those records were deleted afterwards.

## Note on the final commit, 554b502

This note supersedes the code and heap lines above, which were measured at `8ba0ef5`.

- **Code:** branch `5-5-shorten-oversized-text` at `554b502`. `main` at `cd22d63`. Both measured in one session in `outbox-dev`, with `main`'s three relay classes deployed over the branch for the `main` runs and the whole branch `force-app` deployed again afterwards.
- **Logging:** the only trace flag still expired at 00:40:02 UTC when checked at 02:53 UTC. All figures were taken without a debug log.
- **Heap:** run heap is 61 bytes higher on the branch at 1, 10 and 100 messages. The gap is the same at every size and does not grow with the number of messages.
- **Cause:** not verified. The branch read 9,823 bytes at `8ba0ef5`, which gave a 29 byte gap. Main read the same figures as its earlier session this time, so the extra 32 bytes come from code committed after `8ba0ef5`. The likely source is the four static surrogate constants added to `TB_OutboxRelayContext`.

| Messages | Code | Run CPU (ms) | Run heap (bytes) |
|---|---|---|---|
| 1 | main | 23 | 9,794 |
| 1 | branch | 34 | 9,855 |
| 10 | main | 21 | 15,824 |
| 10 | branch | 32 | 15,885 |
| 100 | main | 44, 50, 53, 57, 62; median 53 | 76,214 in every sample |
| 100 | branch | 60, 61, 50, 51, 60; median 60 | 76,275 in every sample |

The branch read higher run CPU than main at every size in this session. The 1 and 10 message figures are single samples. At 100 messages the medians are 60 and 53 ms over five samples each, and main's own samples span 18 ms. An earlier run of the same code on the same day read 21, 23 and 50 ms at 1, 10 and 100 messages. The order of the samples is not recorded, so whether main and the branch were alternated or run in blocks is not known. Whether the first sample after each deploy was kept is not recorded either. A small fixed CPU cost per run is therefore not ruled out.

`RunLocalTests` on this code in `outbox-dev`: 189 run, 189 passed, 0 failed.

Every `reproduce.js` scenario matched the Reproduce table above. `oversized-text` stored the error with its start and a shortened notice at its end. It stored the log with a shortened notice at its start and `OVERSIZED-END` at its end. The after-relay action printed one context.

`RunLocalTests` on the code that was merged in `7ba5df0`, in `outbox-dev`: 191 run, 191 passed, 0 failed, in test run `707Ru00002LxlAD`.
