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
        subscription.Config__c = JSON.serialize(new Map<String, String>{ 'uri' => ENDPOINT });
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

    static final String ENDPOINT = 'https://subscriber.example.com/messages';

    // Unlike anything else an attempt logs, so each can be counted or found in the log.
    static final String REQUEST_BODY = 'request-body-of-this-message';
    static final String SUBSCRIBER_ANSWER = 'answer-from-the-subscriber';

    /** Answers every request with the given status code and body. */
    public class AnsweringSubscriber implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        public AnsweringSubscriber(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    /**
     * Publishes one message for an HTTP subscription and lets the relay run and its finalizer
     * finish, so the log and error read back are the ones an operator would see.
     */
    static TB_Subscription_Outbox__c relayOverHttp(String requestBody, Integer statusCode, String answer) {
        TB_Message_Subscription__mdt subscription = addHttpSubscription('http_feed');
        subscription.Retry_BackOff__c = '5';
        Test.setMock(HttpCalloutMock.class, new AnsweringSubscriber(statusCode, answer));

        Test.startTest();
        insert new TB_Outbox_Message__c(Type__c = 'test.message1', Message__c = requestBody);
        Test.stopTest();

        return [
            SELECT
                Relay_Attempts__c,
                Last_Error_Message__c,
                Log__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c
            FROM TB_Subscription_Outbox__c
        ];
    }

    /**
     * The line the client logs once the subscriber answers. It names the method and the endpoint
     * again, so a log shortened to its end still says where the request went.
     */
    static String statusLine(Integer statusCode) {
        return 'POST ' + ENDPOINT + ' answered with status ' + statusCode;
    }

    /** A text's length and both its ends, for a failure message that stays readable. */
    static String describe(String text) {
        if (text == null) {
            return 'null';
        }
        return text.length() + ' characters, from [' + text.left(120) + '] to [' + text.right(120) + ']';
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

    @isTest
    static void testWhenSubscriberAcceptsThenRequestBodyIsLoggedOnce() {
        TB_Subscription_Outbox__c outbox = relayOverHttp(REQUEST_BODY, 200, SUBSCRIBER_ANSWER);

        System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'The outbox should be delivered');
        // The log has to fit one field, and the body can be as long as that field by itself.
        System.assertEquals(
            1,
            outbox.Log__c.countMatches(REQUEST_BODY),
            'One attempt should log the request body once: ' + outbox.Log__c
        );
        System.assert(outbox.Log__c.contains('POST'), 'The log should hold the method: ' + outbox.Log__c);
        System.assert(outbox.Log__c.contains(ENDPOINT), 'The log should hold the endpoint: ' + outbox.Log__c);
        System.assert(
            outbox.Log__c.contains(statusLine(200)),
            'The log should hold the status line: ' + outbox.Log__c
        );
        System.assert(
            outbox.Log__c.contains(SUBSCRIBER_ANSWER),
            'The log of a delivery should hold the response body: ' + outbox.Log__c
        );
    }

    @isTest
    static void testWhenSubscriberRejectsThenRequestBodyIsLoggedOnce() {
        TB_Subscription_Outbox__c outbox = relayOverHttp(REQUEST_BODY, 500, SUBSCRIBER_ANSWER);

        System.assertEquals(1, outbox.Relay_Attempts__c, 'The failed attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertEquals(
            1,
            outbox.Log__c.countMatches(REQUEST_BODY),
            'One attempt should log the request body once: ' + outbox.Log__c
        );
        System.assert(outbox.Log__c.contains('POST'), 'The log should hold the method: ' + outbox.Log__c);
        System.assert(outbox.Log__c.contains(ENDPOINT), 'The log should hold the endpoint: ' + outbox.Log__c);
        System.assert(
            outbox.Log__c.contains(statusLine(500)),
            'The log should hold the status line: ' + outbox.Log__c
        );
    }

    /**
     * A message can be as long as the log field, and the log holds the method, the endpoint and the
     * answer as well, so one attempt for the longest message cannot fit however few times the body
     * is logged. The subscriber has the message by then, so the delivery must still be saved.
     */
    @isTest
    static void testWhenRequestBodyFillsTheLogThenDeliveryIsSavedAndLogKeepsTheAnswer() {
        TB_Subscription_Outbox__c outbox = relayOverHttp('b'.repeat(LONGEST_BODY_LENGTH), 200, SUBSCRIBER_ANSWER);

        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The subscriber accepted the message, so the outbox should be marked delivered'
        );
        // The method and endpoint logged before the send are in the part dropped, so these come from
        // the status line logged after it.
        System.assert(
            outbox.Log__c.contains(statusLine(200)),
            'The log should keep its end, which names the method, the endpoint and the status, but is ' +
            describe(outbox.Log__c)
        );
        System.assert(
            outbox.Log__c.contains(SUBSCRIBER_ANSWER),
            'The log should keep its end, which holds the response body, but is ' + describe(outbox.Log__c)
        );
        System.assert(
            TB_TransactionOutboxTestUtils.saysItWasShortened(outbox.Log__c),
            'The log should say it was shortened, but is ' + describe(outbox.Log__c)
        );
    }

    /**
     * A response can be as long as the log field by itself. The log keeps its end, so whatever is
     * logged after the response is what survives, and the method, endpoint and status must be there.
     */
    @isTest
    static void testWhenResponseBodyFillsTheLogThenDeliveryIsSavedAndLogKeepsTheStatusLine() {
        TB_Subscription_Outbox__c outbox = relayOverHttp(REQUEST_BODY, 200, 'r'.repeat(LONGEST_BODY_LENGTH));

        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The subscriber accepted the message, so the outbox should be marked delivered'
        );
        System.assert(
            outbox.Log__c.length() <= LONGEST_BODY_LENGTH,
            'The log should fit its field, but is ' + describe(outbox.Log__c)
        );
        System.assert(
            TB_TransactionOutboxTestUtils.saysItWasShortened(outbox.Log__c),
            'The log should say it was shortened, but is ' + describe(outbox.Log__c)
        );
        System.assert(
            outbox.Log__c.contains(statusLine(200)),
            'The log should keep its end, which names the method, the endpoint and the status, but is ' +
            describe(outbox.Log__c)
        );
    }

    /**
     * The client puts the whole response body in its failure message, so a subscriber that answers
     * a failure with a long body makes an error longer than its field.
     */
    @isTest
    static void testWhenSubscriberRejectsWithLongBodyThenFailedAttemptIsSavedAndErrorKeepsItsStart() {
        TB_Subscription_Outbox__c outbox = relayOverHttp(REQUEST_BODY, 500, 'r'.repeat(LONGEST_BODY_LENGTH));

        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The failed attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(
            null,
            outbox.Next_Attempt_Timestamp__c,
            'The failed attempt should wait on its subscription backoff'
        );
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason for the failure should be saved');
        // The status code is at the start of the client's message, ahead of the response body.
        System.assert(
            outbox.Last_Error_Message__c.startsWith('Request Failed with status 500. Response Body: '),
            'The error should keep its start, which holds the status code, but is ' +
            describe(outbox.Last_Error_Message__c)
        );
        System.assert(
            TB_TransactionOutboxTestUtils.saysItWasShortened(outbox.Last_Error_Message__c),
            'The error should say it was shortened, but is ' + describe(outbox.Last_Error_Message__c)
        );
    }
}
