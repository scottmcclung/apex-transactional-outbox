@isTest
public class TB_TransactionOutboxTestUtils {
    public static TB_Application__mdt addApplication(String name) {
        //Setup an Application & Message Definition
        TB_Application__mdt app = new TB_Application__mdt(DeveloperName = name);
        return app;
    }

    public static TB_Message_Definition__mdt addEventDefinition(String type) {
        TB_Message_Definition__mdt msgDef = new TB_Message_Definition__mdt(DeveloperName = type);
        if (TB_OutboxMetadataProvider.msgDefinitions == null) {
            TB_OutboxMetadataProvider.msgDefinitions = new List<TB_Message_Definition__mdt>();
        }

        TB_OutboxMetadataProvider.msgDefinitions.add(msgDef);
        return msgDef;
    }

    public static TB_Message_Subscription__mdt addSubscription(
        TB_Application__mdt app,
        TB_Message_Definition__mdt msgDef,
        String name
    ) {
        TB_Message_Subscription__mdt subscription = new TB_Message_Subscription__mdt(
            DeveloperName = name,
            Max_Attempts__c = 3,
            Message_Definition__r = msgDef,
            Application__r = app,
            Enabled__c = true
        );

        if (TB_OutboxMetadataProvider.subscriptions == null) {
            TB_OutboxMetadataProvider.subscriptions = new List<TB_Message_Subscription__mdt>();
        }

        TB_OutboxMetadataProvider.subscriptions.add(subscription);
        return subscription;
    }

    static Boolean finalizerMayQueueNextRun = false;

    /**
     * Call after publishing and before Test.stopTest().
     *
     * In production a relay run's finalizer has its own transaction, so the two static guards in
     * TB_OutboxRelayQueuable.enqueue start out unset and the finalizer can queue the next run.
     * In a test the publishing code, the run and the finalizer share statics, so both guards are
     * still set when the finalizer gets there. This clears the publisher's guard now, and has
     * the test clients in this class that call clearRunGuardIfAsked clear the run's guard during
     * the first send.
     *
     * A test using this depends on three things:
     * - The run reaches one of those clients at least once. Otherwise the run's guard is never cleared.
     * - The run does not read executeStart after its first send. It would read null.
     * - Nothing in the run publishes a message. That would queue a job from inside the run,
     *   and the test could not tell it from one the finalizer queued.
     */
    public static void letFinalizerQueueNextRun() {
        TB_OutboxRelayQueuable.alreadyQueuedInContext = false;
        finalizerMayQueueNextRun = true;
    }

    static void clearRunGuardIfAsked() {
        if (finalizerMayQueueNextRun) {
            // Cleared once, so the tests are about the first run's finalizer only.
            finalizerMayQueueNextRun = false;
            TB_OutboxRelayQueuable.executeStart = null;
        }
    }

    // One entry per call to send on a test client in this class, holding the resolved message the
    // client was given.
    @testVisible
    static List<Object> sentMessages = new List<Object>();

    /**
     * The cost of a send that only works in memory: no callouts, queries, writes or event publishes.
     * The test clients append a short log line or keep a reference to the message, which stays well
     * under 1 ms of CPU and 1 KB of heap.
     */
    public static TB_SendCost inMemorySendCost() {
        TB_SendCost cost = new TB_SendCost();
        cost.callouts = 0;
        cost.calloutTimeMs = 0;
        cost.queries = 0;
        cost.queryRows = 0;
        cost.dmlStatements = 0;
        cost.dmlRows = 0;
        cost.eventPublishes = 0;
        cost.cpuTimeMs = 1;
        cost.heapBytes = 1024;
        return cost;
    }

    public class TestClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            return inMemorySendCost();
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            clearRunGuardIfAsked();
            if (ctx.subscriptionConfig.containsKey('log')) {
                ctx.log(ctx.subscriptionConfig.get('log'));
            }
            if (ctx.subscriptionConfig.get('throwError') == true) {
                throw new TestException('Test Error');
            }
        }
    }

    public static final List<String> SEND_COST_FIELDS = new List<String>{
        'callouts',
        'calloutTimeMs',
        'queries',
        'queryRows',
        'dmlStatements',
        'dmlRows',
        'eventPublishes',
        'cpuTimeMs',
        'heapBytes'
    };

    /** The in-memory cost with one field changed. A null amount leaves that field unset. */
    public static TB_SendCost sendCostWith(String field, Integer amount) {
        Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(inMemorySendCost()));
        System.assert(fields.containsKey(field), 'TB_SendCost has no field named ' + field);
        fields.put(field, amount);
        return (TB_SendCost) JSON.deserialize(JSON.serialize(fields), TB_SendCost.class);
    }

    /**
     * Declares the cost its subscription's settings hold under "cost", and uses none of it.
     * Settings with no "cost" make it declare nothing at all. Every send of the callout time
     * payload fails the way the platform fails a callout once the run's callout time is used up.
     */
    public class DeclaredCostClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            Object declared = TB_OutboxMetadataProvider.getSubscriptionConfig(subscription).get('cost');
            if (declared == null) {
                return null;
            }
            return (TB_SendCost) JSON.deserialize(JSON.serialize(declared), TB_SendCost.class);
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            clearRunGuardIfAsked();
            if (ctx.outbox.Outbox_Message__r.Message__c == CALLOUT_TIME_LIMIT_PAYLOAD) {
                throw new CalloutException(CALLOUT_TIME_LIMIT_ERROR);
            }
        }
    }

    public class ThrowingCostClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            throw new TestException('Cost Error');
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
        }
    }

    /**
     * Each send declares 90 of every 100 queries the transaction allows and runs 15. A run that has
     * used few queries has room for one send. After it no more than 85 in 100 are left, so a second
     * does not fit. Running far fewer than declared keeps a run that starts every send inside the
     * limit, so that run ends normally too.
     */
    public class QueryShareClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            TB_SendCost cost = inMemorySendCost();
            cost.queries = Limits.getLimitQueries() * 90 / 100;
            cost.cpuTimeMs = 1000;
            return cost;
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            clearRunGuardIfAsked();
            Integer queries = Limits.getLimitQueries() * 15 / 100;
            for (Integer i = 0; i < queries; i++) {
                // Matches no message, so the send reads no rows.
                List<TB_Outbox_Message__c> none = [SELECT Id FROM TB_Outbox_Message__c WHERE Type__c = 'no.such.type'];
            }
        }
    }

    // Kept so the heap a HeapShareClient send takes stays in use for the rest of the run.
    static List<String> heldHeap = new List<String>();

    /**
     * Each send declares 90 of every 100 bytes of heap the transaction allows and keeps 15, in the
     * same way and for the same reasons as QueryShareClient does with queries.
     */
    public class HeapShareClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            TB_SendCost cost = inMemorySendCost();
            cost.heapBytes = Limits.getLimitHeapSize() / 100 * 90;
            cost.cpuTimeMs = 1000;
            return cost;
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            heldHeap.add('x'.repeat(Limits.getLimitHeapSize() / 100 * 15));
        }
    }

    // One entry per request a TestSubscriber answered.
    @testVisible
    static Integer subscriberRequests = 0;

    /** Accepts every request, after keeping the caller waiting for the given time. */
    public class TestSubscriber implements HttpCalloutMock {
        private Integer answerAfterMs;

        public TestSubscriber(Integer answerAfterMs) {
            this.answerAfterMs = answerAfterMs;
        }

        public HttpResponse respond(HttpRequest req) {
            subscriberRequests++;
            // Apex has no sleep, and a mocked callout takes no time by itself. Time has to pass on
            // the clock for a run to see callout time being spent.
            Long answerAt = System.currentTimeMillis() + answerAfterMs;
            while (System.currentTimeMillis() < answerAt) {
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            return res;
        }
    }

    // How long SlowCalloutClient's subscriber should take to answer. One send declares all but one
    // second of the 120 seconds a transaction may spend on callouts, so once a send has taken longer
    // than a second, a second send does not fit.
    public static final Integer SLOW_ANSWER_MS = 1500;

    public class SlowCalloutClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            TB_SendCost cost = inMemorySendCost();
            cost.callouts = 1;
            cost.calloutTimeMs = 119000;
            // The mocked wait is spent on the CPU.
            cost.cpuTimeMs = SLOW_ANSWER_MS + 1000;
            return cost;
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://subscriber.example.com/messages');
            req.setMethod('POST');
            new Http().send(req);
        }
    }

    // What the platform says when a transaction's callouts have taken 120 seconds in total. It
    // raises this as a CalloutException from the callout that goes over, and code can catch it.
    public static final String CALLOUT_TIME_LIMIT_ERROR = 'Exceeded maximum time allotted for callout (120000 ms)';
    // What the platform says when one request gets no answer within its own timeout. This is the
    // subscriber's failure and not a limit of the run.
    public static final String READ_TIMEOUT_ERROR = 'Read timed out';

    public static final String CALLOUT_TIME_LIMIT_PAYLOAD = 'Sent when the callout time has run out';
    public static final String READ_TIMEOUT_PAYLOAD = 'Sent to a subscriber that does not answer';

    static Boolean calloutTimeLimitWasHit = false;

    /**
     * Fails the sends of two payloads the way the platform fails a callout. Only the first send of
     * the callout time payload fails, because the run after the one that ran out of callout time
     * starts with the full 120 seconds again.
     */
    public class CalloutFaultClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            return inMemorySendCost();
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            clearRunGuardIfAsked();
            String payload = ctx.outbox.Outbox_Message__r.Message__c;
            if (payload == CALLOUT_TIME_LIMIT_PAYLOAD && !calloutTimeLimitWasHit) {
                calloutTimeLimitWasHit = true;
                throw new CalloutException(CALLOUT_TIME_LIMIT_ERROR);
            }
            if (payload == READ_TIMEOUT_PAYLOAD) {
                throw new CalloutException(READ_TIMEOUT_ERROR);
            }
        }
    }

    public static final String LOGGED_BEFORE_LIMIT = 'Request sent to the subscriber';
    // Far from any wait or TTL a subscription in these tests sets, so a value the client set cannot
    // be mistaken for one of those.
    public static final Integer REQUESTED_WAIT_DAYS = 3;
    public static final Integer REQUESTED_TTL_DAYS = 10;

    /**
     * Logs a line, asks for a next attempt time and replaces the TTL, the way a client shapes the
     * outcome of its send, and then runs out of callout time.
     */
    public class ShapesOutcomeThenHitsCalloutTimeLimitClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            return inMemorySendCost();
        }

        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            ctx.log(LOGGED_BEFORE_LIMIT);
            ctx.setNextAttemptTimestamp(System.now().addDays(REQUESTED_WAIT_DAYS));
            ctx.setTTL(System.now().addDays(REQUESTED_TTL_DAYS));
            throw new CalloutException(CALLOUT_TIME_LIMIT_ERROR);
        }
    }

    /** A resolver whose own callouts use up the callout time of the run. */
    public class CalloutTimeLimitResolver implements TB_IOutboxMessageResolver {
        public Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages) {
            throw new CalloutException(CALLOUT_TIME_LIMIT_ERROR);
        }
    }

    @testVisible
    static Integer testExecuted = 0;
    public class TestResolver implements TB_IOutboxMessageResolver {
        public Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages) {
            testExecuted++;
            Map<Id, Object> result = new Map<Id, Object>();
            for (TB_Outbox_Message__c msg : messages) {
                result.put(msg.Id, 'resolved:' + msg.Message__c);
            }
            return result;
        }
    }

    public class ThrowingResolver implements TB_IOutboxMessageResolver {
        public Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages) {
            throw new TestException('Resolver Error');
        }
    }

    // A message with this payload makes RecordingResolver fail the whole call the message is in.
    public static final String UNRESOLVABLE_PAYLOAD = 'Cannot Be Resolved';

    // One entry per call to RecordingResolver.resolveMessages, holding the argument as it was passed.
    // It is a list, so a message passed twice in one call shows up twice.
    // The argument is recorded before it is read, so a call that then fails is still recorded.
    @testVisible
    static List<List<TB_Outbox_Message__c>> resolverCalls = new List<List<TB_Outbox_Message__c>>();
    public class RecordingResolver implements TB_IOutboxMessageResolver {
        public Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages) {
            resolverCalls.add(messages);
            Map<Id, Object> result = new Map<Id, Object>();
            for (TB_Outbox_Message__c msg : messages) {
                if (msg.Message__c == UNRESOLVABLE_PAYLOAD) {
                    throw new TestException('Resolver Error');
                }
                result.put(msg.Id, 'resolved:' + msg.Message__c);
            }
            return result;
        }
    }

    // One entry per call to RecordingAction.execute, holding the argument as it was passed.
    // The argument is recorded before it is read, so a null shows up here even though the action
    // then throws on it.
    @testVisible
    static List<List<TB_OutboxRelayContext>> actionCalls = new List<List<TB_OutboxRelayContext>>();
    // For each call, how many of the outboxes it was given were already stored with their attempt counted.
    @testVisible
    static List<Integer> actionSavedCounts = new List<Integer>();
    public class RecordingAction implements TB_IAfterRelayAction {
        public void execute(TB_OutboxRelayContext[] ctx) {
            actionCalls.add(ctx);
            Set<Id> outboxIds = new Set<Id>();
            for (TB_OutboxRelayContext item : ctx) {
                outboxIds.add(item.outbox.Id);
            }
            actionSavedCounts.add(
                [SELECT COUNT() FROM TB_Subscription_Outbox__c WHERE Id IN :outboxIds AND Relay_Attempts__c > 0]
            );
        }
    }

    public class TestException extends Exception {
    }
}