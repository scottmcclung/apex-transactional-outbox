# Apex Transactional Outbox

A lightweight framework for external message communication with transactional guarantee. Ideal for webhooks or other "directed event driven communication".

Implemented using a ["Transactional Outbox"](https://microservices.io/patterns/data/transactional-outbox.html) pattern.

## Features:

-   **Transactional Guarantee**: Messages cannot be "lost" if they fail delivery `*`
-   **Fan Out**: Support delivering a message to `n` subscribers
-   **Low Code**: Many use-cases can be achieved with 100% configuration or only a few lines of additional code
-   **Retry Back-off**: Configure retry back-offs to give the downstream system time to come back up
-   **Automatic Retries**: Control over automatic retries
-   **Efficient**: Carefully optimized in it's consumption of limits (Daily AsyncJobs, SOQL Queries, DML)
-   **"Dead-Lettering"**: Message "Dead-lettering" to prevent endless retries and make it easy to find failures
-   **"Message Groups"**: support for sequential delivery of a set of messages when required
-   **Logging**: Built-in logging capabilities make it easy to observe when things go wrong
-   **Message TTL (time-to-live)**: Automatically remove messages & outbox records after they have been completed

### Planned improvements:
- **Automatic Circuit Breaking**: If relay fails, a "Circuit Breaker" can be triggered to prevent other attempts for a period of time.
- **Unique Message Controls**: Add ability to control message uniqueness.  
    - Only allowing a specific message to be queued once:
        - Per Execution Context
        - Ever (must be considered with message TTL)
        - While outbox already active (to increase efficiency)

*`*`: This framework provides a [delivery guarantee of "At Least Once"](https://aws.plainenglish.io/message-delivery-and-processing-guarantees-in-message-driven-and-event-driven-systems-8f17338763c2). Measures have been put in place to prevent duplicate message delivery, but it is possible in rare circumstances.*


## Framework Design

![Transactional Outbox Abstraction](https://user-images.githubusercontent.com/5217568/211720999-0ba7a702-278e-471f-a1ca-e68a4ac30faa.png)

_The above diagram is a conceptual abstraction for the key aspects of the framework_

1.  Some _"Domain Event"_ (trigger, event, flow, etc) creates a "Message" (eg: event), specifying it's `type` & `payload`.
    -   A "outbox" record is created for each "Subscription" of the Message to track the status of the message delivery.
    -   These records are all part of the atomic "Domain Transaction"
2.  In a new context (in "Near Real Time"), the "Outbox Relay" runs to process the outbox. It will attempt to send each pending item in the outbox.
3.  If the message is successful, the "Outbox" record is marked as complete. If it fails, the exception is logged, and it will be retried at some point in the future. If failures continued, it will be "Dead-Lettered" for manual review.

### Definitions:

-   **Application** (`TB_Application__mdt`): An system/entity that receives messages. Used to group subscriptions76.
-   **Message Definition** (`TB_Message_Definition__mdt`): Defines the message type and how it's payload is processed
-   **Message Subscription** (`TB_Message_Subscription__mdt`): Defines who will receive each message.
-   **Message** (`TB_Outbox_Message__c`): An instance of message to be sent to each subscriber. Tracks the payload of the message.
-   **Subscription Outbox** (`TB_Subscription_Outbox__c`): The Outbox records tracking that status of the Outbox.
-   **Outbox Relay** (`TB_OutboxRelayQueuable.cls`): The process responsible for ensuring all outbox messages are sent.
-   **Relay Client** (`TB_IRelayClient.cls`): The process responsible for getting the message to the subscriber.
-   **Message Resolver** (`TB_IMessageResolver.cls`): An optional process to "enhance" or modify the message payload just before the relay.
-   **Relay Context** (`TB_OutboxRelayContext.cls`): The context passed to the "Relay Client" for each outbox item. Contains the Message Payload, information on previous attempts, ability to log, etc.

## Usage

### 0. Install & Activate

Installing and activating are separate steps. The framework can be installed without being activated.

To install:

1. git clone project
2. `sf project deploy start -x manifest/package.xml -o your_org_alias`
3. Add `TB_Admin` permission set to Users or Permission Set Groups

Activating means scheduling two jobs: the relay sweep (`TB_ScheduleRelay`) and the cleanup job (`TB_RecordCleanup`). The team that activates the framework chooses how often each job runs. That team also checks that both jobs are in place. The framework has no setting for either interval and does not check for the jobs.

Until the sweep is scheduled, a relay run starts only when a message is published, a run hands over to the next, or someone runs `TB_OutboxRelayQueuable.enqueue(null)` as anonymous Apex. See "Dead-Lettered" below. The sweep is what picks up an outbox whose retry wait has ended when nothing else starts a run. The sweep interval is the longest that outbox waits.

Until cleanup is scheduled, no record is removed.

`post-install/schedule.apex` is an example that schedules both jobs to run every hour. Change it to suit your org, then run it:

`sf apex run -f post-install/schedule.apex -o your_org_alias`

If a job with either name already exists, the script fails and schedules nothing. Remove that job, or delete its line from the script, then run it again.

A Salesforce scheduled job fires at most once an hour from one schedule expression. A schedule finer than hourly needs several jobs at different minutes. For example, a sweep every 15 minutes needs four jobs, at minutes 0, 15, 30 and 45.

To confirm both jobs are scheduled, run this query. It should return at least one row for `TB_ScheduleRelay` and one for `TB_RecordCleanup`.

`sf data query -o your_org_alias -q "SELECT ApexClass.Name, CronTrigger.CronExpression, CronTrigger.NextFireTime FROM AsyncApexJob WHERE JobType = 'ScheduledApex' AND Status = 'Queued'"`

### 1. Create an "Application"
`Custom Metadata Types -> TB Application -> Manage Records -> New`

The Application serves as the container for a set of subscriptions. How you split out multiple Applications depends on the scenario, but typically you would have 1 Application per external service.

### 1. Define a "Message"
`Custom Metadata Types -> TB Message Definition -> Manage Records -> New`

All messages must be defined via `TB_Message_Definition__mdt` with the following properties:

-   Message Type (`Label`): Required. Recommended to use a pattern like `{object}_{event}`.
-   `Message_Resolver__c`: Optional class type used to "enhance" the event message during the message "relay". See "Runtime Messages Resolution" below.

_NOTE: Messages of the same type should always have the same "Payload". However, "Relay Clients" may process that state in different ways for different subscriptions_

### 2. Define Subscriptions

Each Event may have multiple subscriptions (`TB_Message_Subscription__mdt`). For each subscription, an "Outbox" record will be created to ensure the message is successfully sent. Each subscription has control over how the message is sent.

Properties:

-   `Application__c`: The Application this subscription is a part of
-   `Message_Definition__c`: The message definition to send on
-   `Enabled__c`: Enables/Disables the subscription. NOTE: This only impacts if Outbox records are created or not. Items already in the outbox will continue to be relayed regardless of this flag.
-   `Relay_Client__c`: The class of the client to instantiate. Must implement `TB_IOutboxRelayClient`. The included `TB_GenericHttpRelayClient` will serve the needs of many use cases.
-   `Config__c`: (Optional) JSON string that will be added to the context that is passed into the `TB_IOutboxRelayClient.send` method. Allows a Relay Client to be configured for different subscriptions. See documentation for `TB_GenericHttpRelayClient` for example.
-   `Max_Attempts__c`: Maximum number of times to attempt this message before dead lettering it

### 3. Insert a Message

Construct and insert a `TB_Outbox_Message__c`:

```cs
TB_Outbox_Message__c[] msgs = new TB_Outbox_Message__c[]{};
for(Case c : Trigger.new){
    msgs.add(new TB_Outbox_Message__c(
        Type__c='case_created', // must match a TB_Message_Definition__mdt DeveloperName
        Message__c = c.Id       // whatever you want to send
    ));
}

insert msgs;
```

When a `TB_Outbox_Message__c` is inserted, a `TB_Subscription_Outbox__c` record will be created for each Active subscription related to the message definition.

See the code in `example/main/default` for a full working example.

## Advanced

### Custom TB_IRelayClient

The package comes with a `TB_GenericHttpRelayClient` which can be configured for many simple use cases. However, you may need to write a custom relay client.

_NOTES:_

-   The execution of Relay Clients is not bulkified. The `send` method will be executed once per outbox.
-   The client must not perform DML itself. This will cause the subsequent Relays to fail. **It may fire a Immediate Platform Event**.
-   The same instance is used to send all messages for a given subscription. Keep this in mind if the client is stateful

#### Stating the cost of one send

A relay client must implement `costOfSend` as well as `send`:

```java
TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription);
```

It returns the most that one call to `send` for that subscription will use. The relay run asks for it before every attempt. From the run's second attempt on, it compares it with what the run has left, and passes over an outbox it has no room for. See "Relay Limits" below for what the run does with it.

Set every field of `TB_SendCost`. Use 0 for anything a send does not use. A cost with a field left null is not a valid declaration, and null does not mean 0.

| Field | What it counts |
|---|---|
| `callouts` | Outbound calls |
| `calloutTimeMs` | The longest those calls may take in total, in milliseconds. For an HTTP request this is its timeout. |
| `queries` | SOQL queries, including any that look up records before sending |
| `queryRows` | Rows those queries return |
| `dmlStatements` | DML statements |
| `dmlRows` | Rows those statements write |
| `eventPublishes` | Platform events published immediately |
| `cpuTimeMs` | CPU time, in milliseconds |
| `heapBytes` | Heap, in bytes. This is the highest the send raises the heap above where it stood when the send began, at any point during the send, including what it still holds when it returns. |

Declare at least 262,144 bytes more than the send still holds when it returns, because the run then shortens a log or error longer than its 131,072-character field and briefly holds up to two field lengths on top of the original text, as counted from the code.

A declaration the run cannot use fails the attempt. That covers `costOfSend` throwing, returning null, or returning a cost with a field that is null or negative. The attempt is counted, nothing is sent, and `Last_Error_Message__c` names the relay client and, for a bad field, the field. The outbox then waits on its subscription's retry backoff like any failed attempt.

`TB_GenericHttpRelayClient` declares:

| Field | Value | Where it comes from |
|---|---|---|
| `callouts` | 1 | One request per send |
| `calloutTimeMs` | 10,000 | The timeout it sets on every request |
| `queries`, `queryRows`, `dmlStatements`, `dmlRows`, `eventPublishes` | 0 | It does none of these |
| `cpuTimeMs` | 100 | Measured sends of the longest body used 3 to 6 ms, with one first send at 63 ms |
| `heapBytes` | 1,445,888 | 11 copies of the longest body the payload field holds (131,072 characters), plus 4 KB. An upper bound counted from the code, for a body and a response each no longer than 131,072 characters. A longer body or response uses more |

**This is a breaking change.** `costOfSend` was added to `TB_IOutboxRelayClient`. A relay client written before this change no longer compiles until it adds the method. To upgrade, add `costOfSend` to each of your relay clients and return the cost of what its `send` does. Deploy your updated relay clients in the same deployment as this version, so the interface and every class that implements it change together.

Measure your own client with the largest message and response you expect. For CPU, read `Limits.getCpuTime()` before and after a send. For heap, a reading of `Limits.getHeapSize()` before and after a send shows only what the send still holds when it returns. The heap can be higher partway through the send, for example while it holds a response and copies of the response body at once. Read `Limits.getHeapSize()` inside `send` at the point where it holds the most. Then add the size of any large strings a single statement builds, such as joining a body onto a log line, because a reading taken after that statement does not show them.

The example below is for a client that sends one HTTP request with a 30 second timeout and runs one query that returns one row before sending. Its CPU and heap figures are only an example.

```java
public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
    TB_SendCost cost = new TB_SendCost();
    cost.callouts = 1;
    cost.calloutTimeMs = 30000;
    cost.queries = 1;
    cost.queryRows = 1;
    cost.dmlStatements = 0;
    cost.dmlRows = 0;
    cost.eventPublishes = 0;
    cost.cpuTimeMs = 50;
    cost.heapBytes = 100000;
    return cost;
}
```

### Message "enhancement"

Messages can be "Enhanced" during Relay. This allows additional capabilities and behavior.

For example, if you always wanted to pass the most recent data from a record, you could store only the "Record Id" into a `Event.Message__c`. A custom `TB_IOutboxMessageResolver` could then be used to query additional details about the record.

NOTE: A custom `TB_IRelayClient` also has the opportunity to change the message. This should be used when different subscription need different messages. This operation is NOT bulkified!

### Dead-Lettered

A Outbox is "Dead-Lettered" when the "Relay Attempts" exceeds the "Max Attempts" OR the "Manual Dead-Letter" flag has been set.

Once a message has been "Dead-Lettered" relay attempts will stop. To remove a Outboxed Message from the dead letter the `TB_Subscription_Outbox__c` record to:

-   Increase the `Max_Attempts__c` to some value greater than the `Relay_Attempts__c`
-   Uncheck `Manual_Deadletter__c`

The message will be retried again when the next relay is run.  You can manually kick off the relay by running the `TB_OutboxRelayQueuable` class.

```java
TB_OutboxRelayQueuable.enqueue(null);
```

### Message Groups

A "Group Identifier" (`Group_Id__c`) can be assigned to a Outbox Message when it is created. For each Application, group messages are guaranteed to be delivered successfully in sequential order. This is useful when you need to ensure temporal consistency of messages.

For example, you might assign all messages related to a group via the record id to ensure messages are delivered in order.

_WARNING: If a message is dead lettered, processing for the Group can not continue until that message is marked as delivered (or deleted)._

### Retry Back-off

Often it is desired to have a "backoff" strategy for retrying messages. This can allow the downstream systems time to come back up and process the message. 

This can be configured via the `Message Subscription -> Retry Backoff` field by passing a comma separate array of minutes to back off on each subsequent attempt.  

For example, `0,15,60,720` would retry immediately once, then after 15 minutes, 1 hr and then continue to retry every 12 hours until there are no remaining attempts.

The Relay Client may also call `ctx.setNextAttemptTimestamp()` directly to set the next attempt time. This will override the configured backoff strategy.

*NOTE: The retry will not run until AFTER the specified timeout.  The actual timeout will depend on when the next relay request is queued or the timing of other new events that trigger the relay to run*

### Isolated Relay

In some cases, you may want the Relay of a single outbox record to happen in it's own Execution Context.  This is most commonly used when DML must be preformed by the Relay Client (Use Immediate Platform Events when possible!)

This can be enabled by checking the `Message Subscription -> Isolate Relay` box.  

*WARNING: This should be only used when absolutely needed as it may impact performance and consumes additional resources*

### Relay Limits

A relay run works inside the limits of one asynchronous Apex transaction. It takes a capped number of outboxes. From its second attempt on, it checks before each attempt that it has room for one more send, and it ends normally when it does not. Its finalizer then queues the next run if an outbox that can go is left. Some limits can still end a run part-way. They are listed at the end of this section.

#### Batch size

A run takes at most `Relay Batch Size` outboxes, in publish order, and leaves the rest for the next run. The value is set on the `TB Framework Settings` custom metadata record named `Default`. The record ships with 100. The relay does not assume a value. If the record is missing, or the value is not from 1 to 1,000, every relay run fails at its start with an error that says so.

The run chooses its batch without payloads and without a lock. It reads due outboxes a page at a time, each page twice the batch size, for up to 10 pages. It skips an outbox that is held because an earlier message in its group is dead-lettered or waiting on its retry backoff. A held outbox does not count toward the batch size. The run then loads the chosen outboxes with their payloads, locked.

An outbox that becomes held during the run, because an earlier message in its group failed or was passed over, has already been chosen. It is not attempted, and its place is not given to another outbox.

#### The room check

Before every attempt, the run asks the relay client for `costOfSend` and checks that the declaration is usable. From the run's second attempt on, it also compares the declaration with what the run has left. It compares nine limits: callouts, callout time, queries, query rows, DML statements, DML rows, immediate event publishes, CPU time and heap. A send fits when it needs no more than what is left of every one of them.

For eight of the limits, what is left comes from the `Limits` class at the moment of the check: the limit less what the transaction has used. The platform has no counter for callout time. The run counts time on the clock from just before it calls the message resolvers, against 120,000 ms. That time includes resolver work and all other processing as well as callouts, so it can only overstate the time callouts have taken.

The heap limit is read from `Limits.getLimitHeapSize()`. The heap figures in this section come from one scratch org, where a queueable reported 25,000,000 bytes. Read `Limits.getLimitHeapSize()` in a queueable in your own org to see what it reports. Where a figure depends on the limit, the figure for an org that reports 12,000,000 bytes is given as well. Those figures are derived and were not measured.

The run always starts its first attempt, without the room check. A run that could attempt nothing would leave every outbox as it was, and its finalizer would queue the next run in the same state, without end. An attempt counts as the first once its relay client is built and its cost is read and usable. An outbox failed before that, for missing configuration, a client that cannot be built or a declaration that cannot be used, leaves the first attempt still to come. At worst the first send goes past a limit, with the results described under "Abandoned attempts" and "What can still stop a run". The outboxes of a client whose declared cost never fits in a run are still attempted, at most one per run, and only as a run's first attempt.

An outbox the run has no room for is passed over. It is not attempted, not charged an attempt and not saved, so it stays exactly as it was and stays due. For the rest of the run it holds the later messages in its group, the same as a failed send. The run goes on to the next outbox, because another client's send may still fit. A later run takes the passed-over outbox up.

#### A batch larger than the callout limit

Once a run has made 100 callouts, it passes over every remaining outbox whose client declares a callout. So a batch size above 100 does not make a run of HTTP outboxes fail. But before its first send the run has already loaded every outbox in its batch, with its payload, and passed the message of every outbox it planned to attempt to the message resolvers. The outboxes it passes over cost that heap and resolver work for nothing, and the next run loads them again.

#### Abandoned attempts

A send can still reach a limit when it is the run's first attempt or when its client uses more than it declared. When the run can catch the platform's error, it abandons the attempt. Total callout time is the only limit it handles this way. The callout that goes past 120 seconds throws a `System.CalloutException` whose message starts with `Exceeded maximum time allotted for callout`, and the run recognises the limit by that type and message together. A message resolver that reaches this limit has the exception kept as its resolved message, and the first attempt that uses it is abandoned the same way.

The run recognises the limit only in the `System.CalloutException` the platform throws. A relay client that catches that exception and throws its own has the attempt counted as failed. If that was the outbox's last attempt, the outbox is dead-lettered.

An abandoned attempt is not counted. No error is recorded, no retry wait is set, not even one the client asked for, and a TTL the client set during the attempt is put back. An outbox on its last attempt is therefore not dead-lettered. The outbox keeps the attempt time in `Last_Attempt__c`, and `Log__c` holds what the attempt logged. The run starts nothing more, saves its outcomes, and its finalizer queues the next run, which takes the outbox up again. If the request had already reached the subscriber, the next run sends it again.

The reason is written only to the debug log, as `Relay attempt abandoned at a run limit for outbox <Id>: <message>`. It is there only when a debug log is being recorded for the user the relay runs as.

An attempt that reaches the callout time limit the same way on every run is abandoned on every run and never charged. It is never dead-lettered, and the outboxes after it in each of those runs are not started. To an operator it looks like this: `Last_Attempt__c` moves forward while `Relay_Attempts__c` stays the same, `Last_Error_Message__c` does not change, `Next_Attempt_Timestamp__c` stays empty, `Dead_Lettered__c` stays false, and relay jobs keep completing one after another without errors.

#### What can still stop a run or slow it

**The load.** The run loads the payloads of its whole batch in one query, before it attaches its finalizer. `Message__c` holds up to 131,072 characters. The load also reads `Last_Error_Message__c`, which holds as many.

Megabytes here are millions of bytes of heap. In the measurements below, a full long text field of 131,072 characters took about 132,000 bytes of heap, and the figures for full fields use that rate. A full last error is taken to cost the same, which was not measured. Derived figures assume one byte of heap per character. Only payloads of single-byte characters were measured.

Measured in one scratch org, on code that also loaded an empty `Log__c`, with full payloads and no last errors (GitHub #34 and `benchmark/results/2026-11-16-baseline.md`): a run with 200 payloads, about 26.4 MB, got past the load. A run with 400, about 53 MB, failed in the load query with `Query of LOB fields caused heap usage to exceed limit.` Sizes between those two were not measured. Both sizes come from that one org.

Derived from those figures:

- A batch whose payloads and last errors together come to more than about 26.4 MB may end the run at the load. One of about 53 MB did.
- At the shipped batch size of 100, full payloads come to about 13.2 MB. With a full last error on every outbox as well, the load is about 26.4 MB. What follows from that is described below.
- At the largest batch size, 1,000, payloads and last errors that together average more than about 26 KB per outbox go past the largest load measured to pass. An average of about 53 KB reaches the size that failed.
- Only full payloads were measured. The per-outbox figures assume the failure depends on the total size of long text in the load and not on the number of rows.

When a run ends at the load, nothing is attempted, nothing is saved, and no next run is queued. The next run starts only when a message is published or the relay sweep runs. It chooses the same oldest outboxes and fails the same way. Delivery stops for every outbox until the batch holds less, through a lower batch size or fewer of those outboxes being due.

A load over the heap limit does not always fail at once. In the same measurements, the 200-payload run sent every outbox and then failed with `Apex heap size too large: 26358965`, and its finalizer saved every outcome. That was before the room check. How a run behaves past the heap limit now has not been measured.

A batch of 100 with a full payload and a full last error on every outbox loads about 26.4 MB, derived. That is the size of the 200-payload run, which got past the load. It is over 25,000,000 bytes before any send, so the room check finds no heap left, and the run sends only its first outbox. That send may end the job with a heap error. The 200-payload run ended with one, after its sends. A send that ends the job this way leads to what is described under "A limit the platform does not let code catch, during a send".

**Little heap left after the load.** The room check counts the heap the load used. When the load leaves less heap than a client declares, the run sends only its first outbox and passes over the rest. When that first send completes, such a backlog drains one outbox per run. When it ends the job instead, the backlog does not drain, as described under "A limit the platform does not let code catch, during a send".

`TB_GenericHttpRelayClient` declares 1,445,888 bytes. Its sends stop after the first once the heap in use passes 25,000,000 − 1,445,888 = 23,554,112 bytes, which is about 178 full payloads. In an org that reports 12,000,000, they stop after the first at 12,000,000 − 1,445,888 = 10,554,112 bytes, about 80 full payloads. There a batch of 100 full payloads, about 13.2 MB, leaves no heap after the load. If the load gets through, the run sends one outbox at most. The figures for 12,000,000 are derived.

Each send also raises the heap until the run saves. Measured against a mock in a test, with a response as long as the body, a successful HTTP send of the longest body keeps about 3 copies of it, 393,509 bytes. Once the run shortens its log to fit the field, it keeps about 2, 262,198 bytes. A failed send keeps about 4, 525,651 bytes once the run has stored the error, and shortening leaves that about the same. Derived from those, a batch of 100 full payloads in an org that reports 25,000,000 has room for about 40 HTTP sends when every send succeeds, and about 20 when every send fails.

**A limit inside a message resolver.** Message resolvers run before the finalizer is attached. A limit the platform does not let code catch, such as CPU time, heap or queries, ends the job there. Nothing is saved and no next run is queued. The next run starts when a message is published or the relay sweep runs. It chooses the same outboxes, plans the same attempts and passes the same messages to the same resolvers, so a resolver that does the same work reaches the same limit again. This repeats until the run's batch is smaller or the resolver uses less.

**A limit the platform does not let code catch, during a send.** The job ends. The finalizer saves the outcomes the run already has and queues the next run. The outbox whose attempt was cut off is not handed to the finalizer. It is left exactly as it was, so the attempt is not counted, and it stays due.

When the same send reaches the limit on every run, this repeats. The next run takes the outbox up again, as its first attempt when nothing due comes before it, and a first attempt has no room check. The outbox is never charged an attempt and never dead-lettered, and each run ends as a failed job. The platform's documented rule, as cited in GitHub #34, is that a finalizer can queue a queueable that failed with an unhandled exception again only five times in a row. After that the chain stops until a message is published or the relay sweep runs, and the next run meets the same send.

To an operator it looks like this: relay jobs that end as failed, and an outbox whose `Relay_Attempts__c` does not move. Its `Last_Attempt__c`, `Log__c` and `Last_Error_Message__c` do not change either, because nothing about it is saved. The common cause is a run's unchecked first send when the load has left too little heap, as under "Little heap left after the load".

**A client that declares too little.** The room check knows only what the client declares. A client that uses more can still take the run past a limit. Callout time ends in an abandoned attempt, and any other limit ends the job as described above.

**Nothing is kept back for the run's own work after the last send.** The run saves its outcomes in one DML statement at the end, and the room check reserves nothing for it. If that save goes past a limit the platform does not let code catch, the finalizer saves the outcomes in its own transaction. After-relay actions also run in the finalizer's transaction.

#### What the check costs

Before every attempt the run gets the relay client, which is built once per subscription per run, calls `costOfSend` and checks the nine fields. From the second attempt on, it also reads nine limits and the clock and compares them with the declaration. At 100 messages the check added about 0.2 ms of CPU per attempt, measured with debug logging on, which inflates CPU figures (`benchmark/results/2026-11-17-budget-check.md`).

Part of that grows with the size of the run. `Limits.getHeapSize()` costs CPU in proportion to the number of objects on the heap. Measured without debug logging, that one reading took about 0.05 to 0.1 ms per attempt in a run of 100 outboxes, and about 0.45 to 0.65 ms in a run of 1,000 (`benchmark/results/2026-11-18-cpu-growth.md`). Through a test client that only writes one short log line, a run of 1,000 outboxes used 774 ms of CPU up to its last send, about 1.3% of the 60,000 ms limit. That figure leaves out the save and the finalizer. Message resolvers or relay clients that keep many objects make each reading cost more. That has not been measured.

### Record Cleanup

Record removal is managed via the `Subscription Outbox -> TTL` (time-to-live) field. Cleanup removes a delivered outbox once its TTL has passed. An outbox that has not been delivered is not removed, whatever its TTL. An outbox with no TTL is not removed.

One run removes at most 4,000 outboxes and 4,000 messages, so it stays inside the limits of one transaction. Anything left over is removed by later runs.

This TTL can either be set by the relay client, by using the subscription metadata `TTL Offset` & `Mark TTL Event` or by any other process.

The `TB_RecordCleanup` job removes delivered outboxes whose time to live has passed. It runs only once it is scheduled during activation. See "Install & Activate" above.

An `Outbox_Message__c` is removed by this job when it has no outboxes left and its message definition has `Delete when outbox is empty` checked.

### After Relay Actions

"After Relay Actions" allow you to execute code after a messages have been sent for a subscription.  This may be useful if the results need to be processed in other ways.  

However, these should be used sparingly and with caution:

- Actions do not have a "Transactional Guarantee".  If the action fails, the message will still be marked as "Delivered" and will not be retried.
- Make sure to always check limits for queries, DML & do not make additional callouts. If an action triggers an "uncatchable exception", it could cause the message results to be lost in some cases and may halt the chaining of the relay job.

**It is recommended that your AfterRelayAction publishes an "Immediate Platform Event" to handle additional processing.**

An action sees each outbox's `Log__c` and `Last_Error_Message__c` as they are stored. A log or error too long for its field has already been shortened. The error keeps its start, the log keeps its end, and each says it was shortened. `relayResult` is not shortened. For `TB_GenericHttpRelayClient` it holds the whole response body whenever the subscriber answered, on success and on failure. When the send throws before any answer, such as on a timeout, `relayResult` is null.

