@isTest
public class TB_GenericHttpRelayClientTests {
    // The client waits 10 seconds for the subscriber, the same as the platform's default.
    // The platform gives no way to read the timeout back from a request, so this value has to be
    // kept in step with the client by hand.
    static final Integer WAIT_THE_CLIENT_USES_MS = 10000;

    // The longest body the message field holds. The client assumes no response is longer.
    static final Integer LONGEST_BODY_LENGTH = 131072;

    static TB_Message_Subscription__mdt addHttpSubscription(String name) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, name);
        subscription.Relay_Client__c = 'TB_GenericHttpRelayClient';
        subscription.Config__c = '{"uri": "https://subscriber.example.com/messages"}';
        return subscription;
    }

    public class AcceptingSubscriber implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('r'.repeat(LONGEST_BODY_LENGTH));
            return res;
        }
    }

    @isTest
    static void testWhenCostOfSendIsAskedThenHttpClientDeclaresOneCalloutLastingUpToItsWait() {
        TB_Message_Subscription__mdt subscription = addHttpSubscription('HttpCostCallout');
        // Asked through the interface, because that is how a relay run reaches a client.
        TB_IOutboxRelayClient client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(subscription);

        Test.startTest();
        TB_SendCost cost = client.costOfSend(subscription);
        Test.stopTest();

        System.assertNotEquals(null, cost, 'The client should state a cost');
        System.assertEquals(1, cost.callouts, 'One send makes one request');
        System.assertEquals(
            WAIT_THE_CLIENT_USES_MS,
            cost.calloutTimeMs,
            'The callout time should be the longest the client waits for the subscriber'
        );
    }

    @isTest
    static void testWhenCostOfSendIsAskedThenHttpClientDeclaresNoQueriesWritesOrEventPublishes() {
        TB_Message_Subscription__mdt subscription = addHttpSubscription('HttpCostNothingElse');
        TB_IOutboxRelayClient client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(subscription);

        Test.startTest();
        TB_SendCost cost = client.costOfSend(subscription);
        Test.stopTest();

        System.assertEquals(0, cost.queries, 'The client runs no queries');
        System.assertEquals(0, cost.queryRows, 'The client reads no rows');
        System.assertEquals(0, cost.dmlStatements, 'The client writes nothing');
        System.assertEquals(0, cost.dmlRows, 'The client writes no rows');
        System.assertEquals(0, cost.eventPublishes, 'The client publishes no events');
    }

    @isTest
    static void testWhenCostOfSendIsAskedThenHttpClientStatesProcessingTimeAndMemory() {
        TB_Message_Subscription__mdt subscription = addHttpSubscription('HttpCostCpuAndHeap');
        TB_IOutboxRelayClient client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(subscription);

        Test.startTest();
        TB_SendCost cost = client.costOfSend(subscription);
        Test.stopTest();

        // A run adds these to what it has already used, so a missing, zero or negative value would
        // make the run think it has more room than it has.
        System.assertNotEquals(null, cost.cpuTimeMs, 'The cost should state processing time');
        System.assert(cost.cpuTimeMs > 0, 'Every send uses some processing time');
        System.assertNotEquals(null, cost.heapBytes, 'The cost should state memory');
        System.assert(cost.heapBytes > 0, 'Every send uses some memory');
    }

    @isTest
    static void testWhenHttpClientSendsThenItUsesNoMoreThanItDeclares() {
        TB_Message_Subscription__mdt subscription = addHttpSubscription('HttpCostMatchesSend');
        TB_GenericHttpRelayClient client = new TB_GenericHttpRelayClient();
        TB_SendCost cost = client.costOfSend(subscription);
        // Given a resolved message so the client has a body without the outbox being saved first.
        // A save here would count against the limits being measured. The body and the response are
        // the longest the client allows for, which is where it uses the most heap.
        TB_OutboxRelayContext ctx = new TB_OutboxRelayContext(
            new TB_Subscription_Outbox__c(),
            'b'.repeat(LONGEST_BODY_LENGTH),
            subscription
        );
        Test.setMock(HttpCalloutMock.class, new AcceptingSubscriber());

        Test.startTest();
        Integer calloutsBefore = Limits.getCallouts();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();
        Integer dmlStatementsBefore = Limits.getDmlStatements();
        Integer dmlRowsBefore = Limits.getDmlRows();
        Integer eventPublishesBefore = Limits.getPublishImmediateDML();
        Integer heapBefore = Limits.getHeapSize();
        client.send(ctx);
        // Read first, so the other readings below do not count towards it.
        Integer heapAdded = Limits.getHeapSize() - heapBefore;
        Integer calloutsUsed = Limits.getCallouts() - calloutsBefore;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer queryRowsUsed = Limits.getQueryRows() - queryRowsBefore;
        Integer dmlStatementsUsed = Limits.getDmlStatements() - dmlStatementsBefore;
        Integer dmlRowsUsed = Limits.getDmlRows() - dmlRowsBefore;
        Integer eventPublishesUsed = Limits.getPublishImmediateDML() - eventPublishesBefore;
        Test.stopTest();

        System.assertEquals(1, calloutsUsed, 'The send should reach the subscriber once');
        System.assert(calloutsUsed <= cost.callouts, 'The send made more callouts than declared');
        System.assert(queriesUsed <= cost.queries, 'The send ran more queries than declared');
        System.assert(queryRowsUsed <= cost.queryRows, 'The send read more rows than declared');
        System.assert(dmlStatementsUsed <= cost.dmlStatements, 'The send made more writes than declared');
        System.assert(dmlRowsUsed <= cost.dmlRows, 'The send wrote more rows than declared');
        System.assert(eventPublishesUsed <= cost.eventPublishes, 'The send published more events than declared');
        // Only what the send still holds can be read here, not its highest point during the send.
        System.assert(
            heapAdded <= cost.heapBytes,
            'The send held more heap than declared: ' + heapAdded + ' bytes against ' + cost.heapBytes
        );
    }
}
