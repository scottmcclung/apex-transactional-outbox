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
     * TestClient clear the run's guard during its first send.
     *
     * A test using this depends on three things:
     * - The run reaches TestClient at least once. Otherwise the run's guard is never cleared.
     * - The run does not read executeStart after its first send. It would read null.
     * - Nothing in the run publishes a message. That would queue a job from inside the run,
     *   and the test could not tell it from one the finalizer queued.
     */
    public static void letFinalizerQueueNextRun() {
        TB_OutboxRelayQueuable.alreadyQueuedInContext = false;
        finalizerMayQueueNextRun = true;
    }

    // One entry per call to TestClient.send, holding the resolved message the client was given.
    @testVisible
    static List<Object> sentMessages = new List<Object>();
    public class TestClient implements TB_IOutboxRelayClient {
        public void send(TB_OutboxRelayContext ctx) {
            sentMessages.add(ctx.resolvedMessage);
            if (finalizerMayQueueNextRun) {
                // Cleared once, so the tests are about the first run's finalizer only.
                finalizerMayQueueNextRun = false;
                TB_OutboxRelayQueuable.executeStart = null;
            }
            if (ctx.subscriptionConfig.containsKey('log')) {
                ctx.log(ctx.subscriptionConfig.get('log'));
            }
            if (ctx.subscriptionConfig.get('throwError') == true) {
                throw new TestException('Test Error');
            }
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