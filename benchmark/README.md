# Benchmark and fault reproduction

Scripts for measuring what the outbox framework costs, and for reproducing known faults, in a scratch org.

**These scripts delete every outbox message in the org they are pointed at.** They refuse to run against anything that is not a scratch org.

## What is here

| Path | What it is |
|---|---|
| `fixtures/` | Test relay clients, after-relay actions, message definitions, subscriptions, remote site settings and a permission set. Deployed to the scratch org only. |
| `bench.js` | Publishes N messages and reports limits used, relay jobs and delivery delay. |
| `heap.js` | Finds how many outboxes one relay run can load when payloads are large. |
| `reproduce.js` | Runs one fault scenario and prints what happened. |
| `scenarios/` | One anonymous Apex script per fault. |
| `results/` | Recorded results, one file per run. |
| `lib/org.js` | Shared helpers that call the Salesforce CLI. |

`sfdx-project.json` in this folder makes it a small project of its own, so the fixtures never deploy with the package.

## Setup

You need Node and the Salesforce CLI, with a dev hub authenticated.

```sh
# From the repo root: create a scratch org and deploy the package.
sf org create scratch --definition-file config/project-scratch-def.json --alias outbox-dev --duration-days 7
sf project deploy start --source-dir force-app --target-org outbox-dev

# From this folder: deploy the fixtures.
cd benchmark
sf project deploy start --source-dir fixtures --target-org outbox-dev

# Give the scratch org user access. TB_Admin leaves out three fields, which ReproAccess adds.
sf org assign permset --name TB_Admin --target-org outbox-dev
sf org assign permset --name ReproAccess --target-org outbox-dev
```

Every script reads the org alias from `OUTBOX_ORG`. There is no fallback, so a script never runs against an org you did not name.

## Measuring cost

```sh
OUTBOX_ORG=outbox-dev node bench.js bench_noop 1,10,100,200,1000,5000 180
```

The arguments are the message type, the sizes to run, and how many seconds to wait for each size to drain.

| Message type | Relay client | Endpoint |
|---|---|---|
| `bench_noop` | `BenchClient`, which calls nothing and logs the limits used so far | none |
| `bench_http_ok` | generic HTTP client | `postman-echo.com/post` |
| `bench_http_503` | generic HTTP client | `httpbin.org/status/503` |
| `bench_http_slow` | generic HTTP client | `httpbin.org/delay/8` |
| `bench_http_down` | generic HTTP client | `httpstat.us`, which was not answering when this was written |

Use `bench_noop` for volume. The HTTP types call free public services that other people rely on. Keep those runs small, a little over 100 requests at most, and send only made-up payloads.

For payload size:

```sh
OUTBOX_ORG=outbox-dev node heap.js 131072 200 20,40,80,100,200
```

The arguments are the payload size in characters, how many outboxes to build, and how many to make due at once for each measurement.

## Reproducing a fault

```sh
OUTBOX_ORG=outbox-dev node reproduce.js malformed-config
```

| Scenario | Shows |
|---|---|
| `malformed-config` | A subscription with invalid JSON in `Config__c` stops the relay and re-queues it. |
| `missing-subscription` | An outbox whose subscription is gone does the same. |
| `missing-definition` | A message whose definition is gone fails the run before anything is saved. |
| `bad-action-class` | A wrong after-relay action class name stops every run. |
| `action-called-with-null` | An after-relay action is called for a subscription that had no attempt. |
| `cleanup` | Cleanup removes a delivered outbox whose TTL has passed, keeps one whose TTL is ahead, and runs without an exception. |
| `blank-max-attempts` | An outbox with no max attempts is dead-lettered at once. |
| `oversized-text` | An error and a log each longer than their fields are shortened and the outcome is saved. The failed attempt is counted once, and its error keeps its start. The delivery is saved and not sent again, and its log keeps its end. Both say they were shortened. An ordinary after-relay action still gets its subscription's attempt. |

Each scenario puts the faulty item first and a healthy message behind it, so the effect on other messages is visible.

`oversized-text` uses `ReproOversizedTextClient`. It writes text of the length its subscription's `Config__c` gives. `repro_oversized_error_sub` fails with an error of 136,072 characters, and `repro_oversized_log_sub` logs a line of 136,072 characters and succeeds. Both fields hold 131,072. Each text starts with `OVERSIZED-START` and ends with `OVERSIZED-END`, so the marker still present shows which end was kept. The error subscription waits 60 minutes after a failure, so its outbox stays at one attempt while the scenario watches. The scenario prints the length and both ends of each stored error and log.

To try it by hand, publish one message as anonymous Apex and read its outbox:

```sh
echo "insert new TB_Outbox_Message__c(Type__c = 'repro_oversized_log', Message__c = 'by hand');" | sf apex run --target-org outbox-dev
sf data query --target-org outbox-dev --query "SELECT Subscription__c, Relay_Attempts__c, Completed_Timestamp__c, Last_Error_Message__c, Log__c FROM TB_Subscription_Outbox__c WHERE Subscription__c LIKE 'repro_oversized%'"
```

Use `repro_oversized_error` for the error. Delete those messages afterwards, or run any scenario, which deletes every outbox message in the org.

## Reading the numbers

- **Counts are repeatable. Times are not.** Queries, DML and relay jobs come out the same on every run. Elapsed time and CPU vary with what else the Salesforce instance is doing.
- **Do not fail a build on time.** Report it as a median and a 95th percentile.
- **To compare two versions for speed**, run them alternately in the same org in the same session and compare medians.
- **Scratch org figures are for comparison.** They do not predict production.
- **CPU, heap and queries "inside the run" are read at the last send**, so they leave out the cost of saving results and of the finalizer.

Record each run in `results/`, with the date, the commit and the org type.
