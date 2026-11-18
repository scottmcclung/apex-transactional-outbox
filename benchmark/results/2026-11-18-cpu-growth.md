# CPU growth with the number of outboxes in one run

- **Date:** 2026-11-18, between 00:20 and 00:40 UTC
- **Code:** `main` at `da41ad9`. The relay classes in the org were compared with the repository before measuring and matched.
- **Org:** scratch org `outbox-dev`
- **Setup:** `bench_noop`, one subscription per message, max attempts 3, retry backoff 0

These are scratch org figures. They are for comparing versions and do not predict production.

## Question

GitHub #34 measured run CPU of 48 ms at 200 outboxes, 648 ms at 1,000 and 19,006 ms at 5,000, in uncapped runs on `aad6e5f`. A run is now capped at `Relay_Batch_Size__c`. Does CPU per outbox still grow with the number of outboxes in one run, across the range the setting allows (1 to 1,000)?

## Method

- `Relay_Batch_Size__c` on the `Default` record was set to 1,000 in the org only, by deploying a copy of the record from outside the repository. Each size below then ran as one relay job, which `bench.js` confirmed for every sample. The record was redeployed from `force-app` afterwards, and the org reads 100 again.
- "Run CPU" is the maximum printed by `bench.js`: `Limits.getCpuTime()` as `BenchClient` reads it at the last send. It leaves out the save and the finalizer.
- Commands: `node bench.js bench_noop 100,250,500,1000 180`, three times with the committed `BenchClient`, then three times with a temporary `BenchClient` described below.
- A throwaway script using `benchmark/lib/org.js` published the same messages as `bench.js` and printed each outbox's CPU reading in send order, for single runs of 500 and 1,000.

**Debug logging.** The org's only trace flag, a `DEVELOPER_LOG` flag at ApexCode `FINEST` on the running user, had expired at 00:15:50 UTC, before the first run. It was checked after each set of runs and was still expired. `sf apex run` did not renew it. Every figure below was taken without a debug log on the relay job, except the two rows marked as logged, for which the flag was renewed for those runs only and then set to expire.

## Results

Run CPU in ms. Three samples per size, each one run.

| Outboxes in the run | Committed `BenchClient` | Median | ms per outbox | Client without its heap read | Median | ms per outbox |
|---|---|---|---|---|---|---|
| 100 | 52, 49, 53 | 52 | 0.52 | 45, 42, 40 | 42 | 0.42 |
| 250 | 135, 141, 138 | 138 | 0.55 | 103, 99, 114 | 103 | 0.41 |
| 500 | 396, 366, 369 | 369 | 0.74 | 240, 224, 232 | 232 | 0.46 |
| 1,000 | 1,386, 1,330, 1,328 | 1,330 | 1.33 | 774, 805, 730 | 774 | 0.77 |

With the committed client, twice the outboxes cost 2.7 times the CPU from 250 to 500, and 3.6 times from 500 to 1,000. So the growth is still there in capped runs. Run heap at the last send was 75,079 bytes at 100, 176,168 to 176,183 at 250, 344,798 to 344,805 at 500 and 682,099 to 682,120 at 1,000.

With FINEST logging on the relay job, one sample each with the committed client: 84 ms and 76,458 bytes at 100, and 1,768 ms and 692,686 bytes at 1,000. The run heap of 76,458 bytes at 100 matches `2026-11-17-budget-check.md`, which recorded its figures with the same flag active. With and without logging, run heap at 100 differs by 76,458 − 75,079 = 1,379 bytes. That file found main at 76,041 bytes against 74,662 in `2026-11-17-send-cost.md`, also 1,379 bytes apart, and could not explain the gap between sessions. The two differences are equal, which points to debug logging as the cause of that gap.

### Where the time goes

**The time is spent in the send loop.** In one run of 1,000, the first send came at 68 ms and each 100 sends after it took 102 to 135 ms. In one run of 500, the first send came at 53 ms and each 50 sends took 27 to 34 ms, about 0.6 ms per send. The cost of a send depends on how many outboxes the run holds.

**`Limits.getHeapSize()` costs CPU in proportion to the number of objects on the heap.** Timed in anonymous Apex in this org, 200 calls took the times below. The debug log level of those anonymous Apex runs was not recorded.

| Heap held | Heap bytes | 200 calls of `getHeapSize()` | 200 calls of `getCpuTime()` |
|---|---|---|---|
| nothing | 1,139 | 1 ms | 0 ms |
| 1,000 outbox records | 113,096 | 38 ms | 1 ms |
| 2,000 outbox records | 226,166 | 77 ms | 1 ms |
| 3,000 outbox records | 339,236 | 107 ms | 0 ms |
| 4,000 outbox records | 452,307 | 153 ms | 0 ms |
| one 700,000 character String | 701,506 | 1 ms | |

A relay run holds more objects the more outboxes it loaded, and reads the heap once per send, so the total grows with the square of the run size.

**Two calls are made per send in the benchmark.** The room check reads the heap before each attempt (`RunBudget.left()`). `BenchClient` reads it again for its log line. A temporary `BenchClient` that wrote `heap=0` instead of reading the heap gave the right-hand columns above. It was deployed only for those runs, and the committed fixture was redeployed and compared with the repository afterwards. The difference between the two medians, one heap read per send, is 10 ms at 100, 35 ms at 250, 137 ms at 500 and 556 ms at 1,000. From 250 to 500 and from 500 to 1,000 it grows about four times for twice the outboxes.

**Timed inside real relay runs.** A second temporary `BenchClient` timed 20 calls of `getHeapSize()` on every 50th send:

| Outboxes in the run | 20 calls | One call |
|---|---|---|
| 100 | 1 to 2 ms | 0.05 to 0.1 ms |
| 500 | 5 to 7 ms | 0.25 to 0.35 ms |
| 1,000 | 9 to 13 ms | 0.45 to 0.65 ms |

At 1,000 sends that is about 450 to 650 ms for one read per send. The 556 ms difference above falls inside that range.

**The figures in #34 and the benchmark client.** #34 measured `force-app` at `aad6e5f` with the `BenchClient` committed in `2010245`, the next commit, which does not change `force-app`. `git grep getHeapSize aad6e5f` finds nothing, so the framework did not call it. `BenchClient` at `2010245` called it on every send for its log line, as it does now. Since the room check was added, the framework makes one such call per attempt as well.

Scaling today's cost accounts for most of the growth #34 measured. Each read costs in proportion to the outboxes the run holds, and the run reads once per send, so the total goes with the square of the run size. One read cost 0.45 to 0.65 ms at 1,000 outboxes, so at 5,000 it would cost 2.25 to 3.25 ms, and 5,000 reads would cost 11,250 to 16,250 ms. Scaling the 556 ms difference at 1,000 by 25 gives 13,900 ms. Against the 19,006 ms #34 measured at 5,000, that is about 11 to 16 s, or about 14 s by the difference.

These figures are derived. `aad6e5f` was not measured again without the client's heap read. Its run held 5,000 outboxes, five times the largest run measured here, so the cost of one read at that size is extrapolated. Its code also sorted the outboxes in Apex, through a wrapper object per outbox. Neither is ruled out as the cause of the rest.

**Without heap reads the run is close to linear.** Taking one read's measured cost from the right-hand column leaves about 32 ms at 100 and about 220 ms at 1,000. In the 1,000 run without the client's read, each 100 sends took 60 to 76 ms, of which 45 to 65 ms is the framework's heap read. These two figures are derived, not measured: the framework's own read cannot be removed without changing production code.

## Conclusion

- CPU per outbox still grows with the number of outboxes in a capped run. The cause is `Limits.getHeapSize()`, which costs CPU in proportion to the objects on the heap, called once per send.
- In the framework, the room check makes that call before every attempt from the second on. It costs about 0.05 to 0.1 ms per attempt at the shipped batch size of 100, or 5 to 10 ms per run. At the largest batch size the setting allows, 1,000, it costs about 0.45 to 0.65 ms per attempt, or about 450 to 650 ms of the 774 ms the run had used by its last send. The 774 ms leaves out the save and the finalizer, and is about 1.3% of the 60,000 ms CPU limit.
- These runs held small objects: short payloads, one short log line per outbox, no message resolver. A resolver that returns many objects, or a client that keeps many objects until the run saves, would make each read cost more. That has not been measured.
- `BenchClient`'s own heap read adds the same amount again to every `bench_noop` figure. It does not change counts. It skews comparisons between run sizes, and between versions at the same run size when the code under test changes how many objects a run holds.
- At each size, the highest and lowest of the three samples differ by 4% to 8% of the median with the committed client, and by 7% to 15% with the client without its heap read, the most at 250. The direct timings inside the runs and the difference between the two clients agree with each other. The figures are good enough to name the cause and its size. The derived figures without any heap read are rougher.

No fix is part of this work. The cause is recorded here, and a follow-up issue tracks whether to reduce the cost.

## Limits a queueable reports in this org

A throwaway queueable that allows callouts, like the relay, wrote what `Limits` reports into a record. It read: heap 25,000,000 bytes, CPU 60,000 ms, 100 callouts, 200 queries, 50,000 query rows, 150 DML statements, 10,000 DML rows, 150 immediate event publishes. Anonymous Apex in the same org reports a heap limit of 10,000,000 bytes.

The 25,000,000 byte heap limit agrees with the heap measurements in #34: a run holding 13.2 MB of payloads completed, and a run holding 26.4 MB failed with `Apex heap size too large: 26358965`. `2026-11-16-baseline.md` and #34 describe the 13.2 MB run as over a 12 MB heap limit. That does not describe this org, where a queueable reports 25,000,000 bytes.

## Org state afterwards

- `Relay_Batch_Size__c` back to 100, read from the org after redeploying the record from `force-app`.
- `BenchClient` redeployed from `benchmark/fixtures` and compared with the repository.
- No outbox messages left. The throwaway queueable and the record it wrote were deleted.
- The trace flag was renewed for the two logged runs, from 00:38:04 to 00:40:02 UTC, and has expired again.
