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

It returns the most that one call to `send` for that subscription will use. Set every field of `TB_SendCost`. Use 0 for anything a send does not use. A cost with a field left null is not a valid declaration, and null does not mean 0.

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

The relay run uses this to decide whether it has room for another attempt before it starts one.

`TB_GenericHttpRelayClient` states one callout lasting up to its 10 second timeout, and no queries, writes or event publishes.

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

A relay run attempts at most `Relay Batch Size` outboxes, oldest first, and leaves the rest for the next run. When a run ends and an outbox that can go is left, the next run is queued at once.

The value is set on the `TB Framework Settings` custom metadata record named `Default`. The record ships with a value of 100. The relay does not assume a value: if the record is missing, or the value is not from 1 to 1000, every relay run fails with an error that says so.

A run stops by itself when it has no callouts left, so a batch size above 100 does not make a run fail when relay clients make one callout per send. Such a run still loads every outbox in its batch, and the ones it passes over cost heap for nothing.

An outbox that is already held when the run starts does not count toward the batch size. An outbox that becomes held during the run, because an earlier message in its group failed, has already been chosen. It is not attempted and its place is not given to another outbox. A run reads up to 10 pages of due outboxes, each twice the batch size, while it looks for outboxes it can attempt.

Before each attempt the run compares the relay client's `costOfSend` with what it has left of each limit. An outbox it has no room for is left as it is, without being charged an attempt, and the next run takes it up.

The platform does not report how much callout time a transaction has used, so the run counts time on the clock from just before it calls the message resolvers. Time spent in resolvers and in any other processing from then on counts against the 120 seconds, as well as time spent waiting on callouts.

A send or a message resolver can still reach a limit. When the platform's error can be caught, as it can for the 120 seconds of callout time, the attempt is abandoned. It is not counted, no error or wait is recorded against the outbox, and a TTL the relay client set during the attempt is put back. The outbox keeps its attempt time and whatever the attempt logged. The run starts nothing more, saves its outcomes, and the next run takes the outbox up. An abandoned attempt leaves no error on the outbox, and for now the only record of why it was abandoned is the debug log. A limit the platform does not let code catch ends the job. When that happens during a send, the run's finalizer saves the outcomes it already has, and the outbox whose attempt was cut off is left as it was.

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

