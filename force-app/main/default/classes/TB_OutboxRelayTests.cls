@isTest
public class TB_OutboxRelayTests {
    @isTest
    static void testRelayProcessingSuccess() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.TestResolver';
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'EnabledSubscription'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();

        // set type & message
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';

        Test.startTest();
        insert outboxMessage;
        Test.stopTest();
        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c
            FROM TB_Subscription_Outbox__c
            WHERE Outbox_Message__c = :outboxMessage.Id
        ];
        System.assertEquals(1, subscriptionOutboxes.size());

        System.assertEquals(1, subscriptionOutboxes[0].Relay_Attempts__c, 'The outbox should have been attempted once');

        System.assertEquals(null, subscriptionOutboxes[0].Last_Error_Message__c, 'There should be no error message');

        System.assertNotEquals(
            null,
            subscriptionOutboxes[0].Completed_Timestamp__c,
            'The completed timestamp should not be null'
        );

        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.testExecuted,
            'The TestMessageResolver should have been executed once'
        );
    }

    @isTest
    static void testRelayProcessingFailure() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'EnabledSubscription'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        //setup client to fail
        subscription.Config__c = '{"throwError":true, "log": "hello"}';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();

        // set type & message
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';

        Test.startTest();
        insert outboxMessage;
        Test.stopTest();
        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            WHERE Outbox_Message__c = :outboxMessage.Id
        ];
        System.assertEquals(1, subscriptionOutboxes.size());

        System.assertEquals(1, subscriptionOutboxes[0].Relay_Attempts__c, 'The outbox should have been attempted once');

        System.assertNotEquals(null, subscriptionOutboxes[0].Last_Error_Message__c, 'There should be an error message');

        System.assertEquals(
            null,
            subscriptionOutboxes[0].Completed_Timestamp__c,
            'The completed timestamp should be null'
        );

        System.assert(subscriptionOutboxes[0].Log__c.contains('hello'), 'Log should contain "hello"');
    }

    @isTest
    static void testRelayProcessingGroup() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        //setup client to fail
        subscription.Config__c = '{"throwError":true, "log": "hello"}';

        TB_Message_Definition__mdt msgDef2 = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt subscription2 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef2,
            'subscription2'
        );
        subscription2.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';
        outboxMessage.Group_Id__c = 'group1';

        TB_Outbox_Message__c outboxMessage2 = new TB_Outbox_Message__c();
        outboxMessage2.Type__c = msgDef2.DeveloperName;
        outboxMessage2.Message__c = 'Test Payload';
        outboxMessage2.Group_Id__c = 'group1';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ outboxMessage, outboxMessage2 };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c
        ];
        System.assertEquals(2, subscriptionOutboxes.size());

        System.assertEquals(
            subscriptionOutboxes[0].Group_Id__c,
            subscriptionOutboxes[1].Group_Id__c,
            'Both outbox should have the same group'
        );

        System.assertEquals(1, subscriptionOutboxes[0].Relay_Attempts__c, 'The outbox should have been attempted once');

        System.assertNotEquals(null, subscriptionOutboxes[0].Last_Error_Message__c, 'There should be an error message');

        System.assertEquals(0, subscriptionOutboxes[1].Relay_Attempts__c, 'The outbox should not have been attempted');
    }

    @isTest
    static void testRelayProcessingWithRetryBackoff() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        //setup client to fail
        subscription.Config__c = '{"throwError":true, "log": "hello"}';

        subscription.Retry_BackOff__c = '30,60';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ outboxMessage };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c
        ];
        System.assertEquals(1, subscriptionOutboxes.size());

        System.assertEquals(1, subscriptionOutboxes[0].Relay_Attempts__c, 'The outbox should have been attempted once');

        System.assertNotEquals(null, subscriptionOutboxes[0].Last_Error_Message__c, 'There should be an error message');

        System.assert(
            Datetime.now().addMinutes(29) < subscriptionOutboxes[0].Next_Attempt_Timestamp__c &&
                Datetime.now().addMinutes(31) > subscriptionOutboxes[0].Next_Attempt_Timestamp__c,
            'Next attempt timestamp should be 30 minutes from now'
        );
    }

    @isTest
    static void testRelayProcessingGroupBlockedByBackoff() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        //setup client to fail
        subscription.Config__c = '{"throwError":true, "log": "hello"}';

        TB_Message_Definition__mdt msgDef2 = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt subscription2 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef2,
            'subscription2'
        );
        subscription2.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';
        outboxMessage.Group_Id__c = 'group1';

        TB_Outbox_Message__c outboxMessage2 = new TB_Outbox_Message__c();
        outboxMessage2.Type__c = msgDef2.DeveloperName;
        outboxMessage2.Message__c = 'Test Payload';
        outboxMessage2.Group_Id__c = 'group1';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ outboxMessage, outboxMessage2 };
        TB_Subscription_Outbox__c outbox1 = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            WHERE Outbox_Message__r.Type__c = :outboxMessage.Type__c
        ];
        outbox1.Next_Attempt_Timestamp__c = System.now().addMinutes(30);
        update outbox1;

        Test.stopTest();

        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c
        ];
        System.assertEquals(2, subscriptionOutboxes.size());

        System.assertEquals(
            subscriptionOutboxes[0].Group_Id__c,
            subscriptionOutboxes[1].Group_Id__c,
            'Both outbox should have the same group'
        );

        System.assertEquals(0, subscriptionOutboxes[0].Relay_Attempts__c, 'The outbox should have been attempted once');

        System.assertEquals(null, subscriptionOutboxes[0].Last_Error_Message__c, 'There should be an error message');

        System.assertEquals(0, subscriptionOutboxes[1].Relay_Attempts__c, 'The outbox should not have been attempted');
    }

    @isTest
    static void testRelayProcessingIsolatedRelayFirst() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');

        // setup isolated sub
        TB_Message_Subscription__mdt subscription1 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription1.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        subscription1.Isolate_Relay__c = true;

        TB_Message_Subscription__mdt subscription2 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription2'
        );
        subscription2.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ outboxMessage };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c, Subscription__c
        ];
        System.assertEquals(2, subscriptionOutboxes.size());

        System.assertEquals(
            subscription1.DeveloperName,
            subscriptionOutboxes[0].Subscription__c,
            'The first outbox should be for subscription1'
        );

        System.assertEquals(
            1,
            subscriptionOutboxes[0].Relay_Attempts__c,
            'The first outbox should have been attempted once'
        );

        System.assertEquals(
            0,
            subscriptionOutboxes[1].Relay_Attempts__c,
            'The second outbox should not have been attempted'
        );
    }

    @isTest
    static void testRelayProcessingIsolatedRelaySecond() {
        //Setup an Application & Message Definition
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');

        // setup isolated sub
        TB_Message_Subscription__mdt subscription1 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription1.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // setup isolated sub
        TB_Message_Subscription__mdt subscription2 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription2'
        );
        subscription2.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        subscription2.Isolate_Relay__c = true;

        TB_Message_Subscription__mdt subscription3 = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription3'
        );
        subscription3.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
       

        // setup an TB_Outbox_Message__c record
        TB_Outbox_Message__c outboxMessage = new TB_Outbox_Message__c();
        outboxMessage.Type__c = msgDef.DeveloperName;
        outboxMessage.Message__c = 'Test Payload';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ outboxMessage };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> subscriptionOutboxes = [
            SELECT
                Id,
                Outbox_Message__c,
                Group_Id__c,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c,
                Log__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c, Subscription__c
        ];
        System.assertEquals(3, subscriptionOutboxes.size());

        System.assertEquals(
            subscription1.DeveloperName,
            subscriptionOutboxes[0].Subscription__c,
            'The first outbox should be for subscription1'
        );

        System.assertEquals(
            1,
            subscriptionOutboxes[0].Relay_Attempts__c,
            'The first outbox should have been attempted once'
        );

        System.assertEquals(
            0,
            subscriptionOutboxes[1].Relay_Attempts__c,
            'The second outbox should not been attempted'
        );

        System.assertEquals(
            1,
            subscriptionOutboxes[2].Relay_Attempts__c,
            'The third outbox should have been attempted once'
        );
    }

    static TB_Outbox_Message__c newMessage(TB_Message_Definition__mdt msgDef) {
        return new TB_Outbox_Message__c(Type__c = msgDef.DeveloperName, Message__c = 'Test Payload');
    }

    static List<TB_Subscription_Outbox__c> outboxesInOrder() {
        return [
            SELECT
                Id,
                Subscription__c,
                Relay_Attempts__c,
                Last_Error_Message__c,
                Last_Attempt__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c,
                Dead_Lettered__c
            FROM TB_Subscription_Outbox__c
            ORDER BY Outbox_Message__r.Sequence_Number__c, Subscription__c
        ];
    }

    @isTest
    static void testResolvedMessageReachesClient() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.TestResolver';
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        System.assertEquals(
            new List<Object>{ 'resolved:Test Payload' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The client should be given what the resolver returned for the message'
        );
    }

    @isTest
    static void testClientGetsNullWhenNoResolverIsConfigured() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        System.assertEquals(
            new List<Object>{ null },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The client should be called once with no resolved message'
        );
    }

    @isTest
    static void testResolverFailureIsRecordedAsFailedAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes.size());
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'A resolver failure should count as an attempt');
        System.assert(
            outboxes[0].Last_Error_Message__c.startsWith('Resolver Error'),
            'The outbox should carry the resolver error, but has: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should not be completed');
        System.assertEquals(
            0,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The client should not be called for a message that failed to resolve'
        );
    }

    @isTest
    static void testResolverThatCannotBeBuiltIsRecordedAsFailedAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.NoSuchResolver';
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'A resolver that cannot be built should count as an attempt');
        System.assert(
            outboxes[0].Last_Error_Message__c.startsWith('TB_TransactionOutboxTestUtils.NoSuchResolver does not exist'),
            'The outbox should carry the construction error, but has: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The client should not be called');
    }

    @isTest
    static void testResolverFailureDoesNotAffectOtherMessageTypes() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt failingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        failingDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        TB_Message_Subscription__mdt failingSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            failingDef,
            'subscription1'
        );
        failingSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        TB_Message_Definition__mdt workingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        workingDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.TestResolver';
        TB_Message_Subscription__mdt workingSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            workingDef,
            'subscription2'
        );
        workingSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(failingDef), newMessage(workingDef) };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size());
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The message that failed to resolve should not be completed');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The other message type should be delivered');
        System.assertEquals(
            new List<Object>{ 'resolved:Test Payload' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'Only the message that resolved should reach the client'
        );
    }

    @isTest
    static void testAfterRelayActionGetsEachSubscriptionsResults() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt deliveringSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        deliveringSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        deliveringSub.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.RecordingAction';

        TB_Message_Subscription__mdt failingSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription2'
        );
        failingSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        failingSub.Config__c = '{"throwError":true}';
        failingSub.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.RecordingAction';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size());
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.actionCalls.size(),
            'The action should be called once for each subscription'
        );

        Map<String, TB_OutboxRelayContext> resultBySubscription = new Map<String, TB_OutboxRelayContext>();
        for (List<TB_OutboxRelayContext> call : TB_TransactionOutboxTestUtils.actionCalls) {
            System.assertEquals(1, call.size(), 'Each call should hold only its own subscription\'s result');
            resultBySubscription.put(call[0].outbox.Subscription__c, call[0]);
        }

        TB_OutboxRelayContext delivered = resultBySubscription.get('subscription1');
        System.assertEquals(outboxes[0].Id, delivered.outbox.Id);
        System.assertEquals('subscription1', delivered.subscription.DeveloperName);
        System.assert(delivered.isComplete(), 'The delivered result should be complete');

        TB_OutboxRelayContext failed = resultBySubscription.get('subscription2');
        System.assertEquals(outboxes[1].Id, failed.outbox.Id);
        System.assert(!failed.isComplete(), 'A failed attempt should also be passed to the action');
        System.assert(failed.outbox.Last_Error_Message__c.startsWith('Test Error'));

        System.assertEquals(
            new List<Integer>{ 1, 1 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The attempts should be stored before the action runs'
        );
    }

    /**
     * An action is for the attempts its subscription had in the run. A subscription whose outbox was
     * passed over had none, so there is nothing to give its action and it is not called.
     */
    @isTest
    static void testWhenIsolatedOutboxIsPassedOverThenItsAfterRelayActionIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt firstSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        firstSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        firstSub.After_Relay_Action__c = RECORDING_ACTION;

        // A second message type, so the isolated outbox has a later sequence number and is never first in the run.
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt isolatedSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            isolatedDef,
            'subscription2'
        );
        isolatedSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        isolatedSub.Isolate_Relay__c = true;
        isolatedSub.After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(isolatedDef) };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'The isolated outbox should have been passed over');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'subscription1' => new Set<Id>{ outboxes[0].Id } },
            actionCallsBySubscription(),
            'Only the subscription that had an attempt should have its action called'
        );
    }

    // Records its call like RecordingAction and then throws.
    public class RecordsThenThrowsAction implements TB_IAfterRelayAction {
        public void execute(TB_OutboxRelayContext[] ctx) {
            new TB_TransactionOutboxTestUtils.RecordingAction().execute(ctx);
            throw new TB_TransactionOutboxTestUtils.TestException('Action Error');
        }
    }

    /**
     * Both subscriptions' actions throw, so whichever is called first throws before the other is
     * called. The test does not depend on which one that is.
     */
    @isTest
    static void testAfterRelayActionFailureIsSwallowed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.RecordsThenThrowsAction';
        addTestClientSubscription(app, msgDef, 'subscription2')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.RecordsThenThrowsAction';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size());
        System.assertEquals(
            new Map<String, Set<Id>>{
                outboxes[0].Subscription__c => new Set<Id>{ outboxes[0].Id },
                outboxes[1].Subscription__c => new Set<Id>{ outboxes[1].Id }
            },
            actionCallsBySubscription(),
            'Each action should be called with its attempt even though the other one threw'
        );

        for (TB_Subscription_Outbox__c outbox : outboxes) {
            System.assertNotEquals(
                null,
                outbox.Completed_Timestamp__c,
                'A failed action should not change the delivery for ' + outbox.Subscription__c
            );
            System.assertEquals(
                null,
                outbox.Last_Error_Message__c,
                'A failed action should leave no error on the outbox for ' + outbox.Subscription__c
            );
        }
    }

    static TB_Message_Subscription__mdt addTestClientSubscription(
        TB_Application__mdt app,
        TB_Message_Definition__mdt msgDef,
        String name
    ) {
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, name);
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        return subscription;
    }

    static Integer allRelayJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'TB_OutboxRelayQueuable'
        ];
    }

    // A test can see the org's own job records, so jobs that were there before the test are left out of the count.
    static final Integer RELAY_JOBS_BEFORE_TEST = allRelayJobs();

    // The first job is the run the publish queued. A second job means that run's finalizer queued another.
    static Integer relayJobCount() {
        return allRelayJobs() - RELAY_JOBS_BEFORE_TEST;
    }

    /**
     * For a test that expects no further run. One job is also what a test sees when the guards were never
     * cleared, so this shows the finalizer was free to queue and chose not to. Both guards are set again
     * by a second run, so they are only clear when the first run's finalizer queued nothing.
     */
    static void assertFinalizerWasFreeToQueue() {
        System.assertEquals(null, TB_OutboxRelayQueuable.executeStart, 'The run\'s guard should have been cleared');
        System.assertEquals(false, TB_OutboxRelayQueuable.alreadyQueuedInContext, 'Nothing should have been queued');
    }

    @isTest
    static void testNextRunIsNotQueuedWhenEverythingWasDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertNotEquals(null, outboxesInOrder()[0].Completed_Timestamp__c, 'The outbox should be delivered');
        assertFinalizerWasFreeToQueue();
        System.assertEquals(1, relayJobCount(), 'No further run should be queued');
    }

    @isTest
    static void testNextRunIsQueuedWhenAnOutboxWasPassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').Isolate_Relay__c = true;
        addTestClientSubscription(app, msgDef, 'subscription2');

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertEquals(2, relayJobCount(), 'A second run should be queued for the outbox the isolated run left');
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'Both outboxes should be delivered across the two runs');
        }
    }

    @isTest
    static void testNextRunIsQueuedAtOnceForFailureWithoutBackoff() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').Config__c = '{"throwError":true}';

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertEquals(2, relayJobCount(), 'A failed outbox with no backoff is still due, so a second run is queued');
        System.assertEquals(2, outboxesInOrder()[0].Relay_Attempts__c, 'The second run should attempt it again');
    }

    @isTest
    static void testNextRunIsNotQueuedForFailureWithBackoff() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'subscription1');
        subscription.Config__c = '{"throwError":true}';
        subscription.Retry_BackOff__c = '30';

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        assertFinalizerWasFreeToQueue();
        System.assertEquals(1, relayJobCount(), 'An outbox waiting on its backoff should not start another run');
        System.assertEquals(1, outboxesInOrder()[0].Relay_Attempts__c);
    }

    /**
     * A grouped outbox that failed with no backoff is still due, and nothing earlier holds it,
     * so it starts another run just as the same failure without a group does.
     */
    @isTest
    static void testNextRunIsQueuedForGroupedFailureWithoutBackoff() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt failingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, failingDef, 'subscription1').Config__c = '{"throwError":true}';
        TB_Message_Definition__mdt workingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, workingDef, 'subscription2');

        TB_Outbox_Message__c first = newMessage(failingDef);
        first.Group_Id__c = 'group1';
        TB_Outbox_Message__c second = newMessage(workingDef);
        second.Group_Id__c = 'group1';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ first, second };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, relayJobCount(), 'The failed outbox is still due, so a second run is queued');
        System.assertEquals(2, outboxes[0].Relay_Attempts__c, 'The second run should attempt the failed outbox again');
        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'The later outbox in the group should not be attempted');
    }

    /**
     * An isolated outbox that is not first in the run is passed over, and it holds the messages after it
     * in its group. It is still due itself, so another run is queued and delivers it.
     */
    @isTest
    static void testNextRunIsQueuedForGroupedIsolatedOutboxThatWasPassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        // A second message type, so the isolated outbox has a later sequence number and is never first in the run.
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'subscription2').Isolate_Relay__c = true;

        TB_Outbox_Message__c first = newMessage(msgDef);
        first.Group_Id__c = 'group1';
        TB_Outbox_Message__c isolated = newMessage(isolatedDef);
        isolated.Group_Id__c = 'group1';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ first, isolated };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first outbox should be delivered');
        System.assertEquals(2, relayJobCount(), 'A second run should be queued for the isolated outbox');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The second run should deliver the isolated outbox');
    }

    static final Integer SHIPPED_RELAY_BATCH_SIZE = 100;
    // In minutes. 12 hours.
    static final Integer SHIPPED_FALLBACK_RETRY_WAIT = 720;

    // Every test starts from the shipped settings, whatever the org's own settings record holds.
    static {
        setFrameworkSettings(SHIPPED_RELAY_BATCH_SIZE, SHIPPED_FALLBACK_RETRY_WAIT);
    }

    static void setFrameworkSettings(Integer batchSize, Integer fallbackRetryWait) {
        TB_OutboxMetadataProvider.frameworkSettings = new List<TB_Framework_Settings__mdt>{
            new TB_Framework_Settings__mdt(
                DeveloperName = 'Default',
                Relay_Batch_Size__c = batchSize,
                Fallback_Retry_Wait__c = fallbackRetryWait
            )
        };
    }

    static void setRelayBatchSize(Integer batchSize) {
        setFrameworkSettings(batchSize, SHIPPED_FALLBACK_RETRY_WAIT);
    }

    static void setFallbackRetryWait(Integer minutes) {
        setFrameworkSettings(SHIPPED_RELAY_BATCH_SIZE, minutes);
    }

    static TB_Outbox_Message__c newGroupedMessage(TB_Message_Definition__mdt msgDef, String groupId) {
        TB_Outbox_Message__c message = newMessage(msgDef);
        message.Group_Id__c = groupId;
        return message;
    }

    static void makeOutboxWaitOnBackoff(Integer position) {
        TB_Subscription_Outbox__c outbox = outboxesInOrder()[position];
        outbox.Next_Attempt_Timestamp__c = System.now().addMinutes(30);
        update outbox;
    }

    static List<Integer> attemptsInOrder() {
        List<Integer> attempts = new List<Integer>();
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            attempts.add((Integer) outbox.Relay_Attempts__c);
        }
        return attempts;
    }

    @isTest
    static void testRunAttemptsNoMoreThanTheBatchSize() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef), newMessage(msgDef) };
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 1, 1, 0 },
            attemptsInOrder(),
            'The two oldest outboxes should be attempted and the third left alone'
        );
        System.assertEquals(2, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The client should be called twice');
    }

    @isTest
    static void testNextRunTakesWhatTheBatchSizeLeftBehind() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef), newMessage(msgDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertEquals(2, relayJobCount(), 'The first run should queue a second for the outbox it left');
        System.assertEquals(new List<Integer>{ 1, 1, 1 }, attemptsInOrder(), 'Each outbox should be attempted once');
    }

    @isTest
    static void testHeldGroupDoesNotUseUpTheBatchSize() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newMessage(msgDef),
            newMessage(msgDef)
        };
        makeOutboxWaitOnBackoff(0);
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 0, 0, 1, 1 },
            attemptsInOrder(),
            'The run should pass over the held group and attempt the two outboxes behind it'
        );
    }

    /**
     * The run looks at due outboxes a page at a time, and a page is twice the batch size.
     * Here the first page holds nothing but outboxes of one held group.
     */
    @isTest
    static void testRunLooksPastAPageOfHeldOutboxes() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newMessage(msgDef),
            newMessage(msgDef)
        };
        makeOutboxWaitOnBackoff(0);
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 0, 0, 0, 0, 0, 1, 1 },
            attemptsInOrder(),
            'The run should reach the two outboxes behind the held group'
        );
    }

    @isTest
    static void testRunFailsWhenFrameworkSettingsAreMissing() {
        TB_OutboxMetadataProvider.frameworkSettings = new List<TB_Framework_Settings__mdt>();
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('TB_Framework_Settings__mdt'), 'The error should name the settings type: ' + failure);
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder(), 'Nothing should be attempted on an assumed batch size');
    }

    @isTest
    static void testRunFailsWhenBatchSizeIsBelowOne() {
        setRelayBatchSize(0);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('Relay_Batch_Size__c'), 'The error should name the setting: ' + failure);
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder());
    }

    @isTest
    static void testNextRunIsQueuedForUngroupedOutboxWhileAGroupIsHeld() {
        setRelayBatchSize(1);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newMessage(msgDef),
            newMessage(msgDef)
        };
        makeOutboxWaitOnBackoff(0);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertEquals(2, relayJobCount(), 'The ungrouped outbox the first run left should start a second run');
        System.assertEquals(new List<Integer>{ 0, 0, 1, 1 }, attemptsInOrder());
    }

    @isTest
    static void testLaterMessageDoesNotHoldAnEarlierOneInItsGroup() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        makeOutboxWaitOnBackoff(1);
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 1, 0, 0 },
            attemptsInOrder(),
            'The first message should go. The second is waiting, and it holds only the third'
        );
    }

    /**
     * Group order is shared by an application's subscriptions. When one subscription cannot take a message,
     * the others still get that message, and every subscription waits for the messages after it.
     */
    @isTest
    static void testEarlierBackoffDoesNotHoldAnotherSubscriptionsOutboxForTheSameMessage() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        addTestClientSubscription(app, msgDef, 'subscription2');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        makeOutboxWaitOnBackoff(0);
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 0, 1, 0, 0 },
            attemptsInOrder(),
            'subscription2 should get the first message. Both wait for the second'
        );
    }

    // The failing subscription is added first, so its outbox for each message is created first
    // and is the one the run takes first.
    @isTest
    static void testFailureDoesNotHoldAnotherSubscriptionsOutboxForTheSameMessage() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').Config__c = '{"throwError":true}';
        addTestClientSubscription(app, msgDef, 'subscription2');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1, 0, 0 }, attemptsInOrder());
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'subscription1 should fail the first message');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'subscription2 should still get the first message');
    }

    @isTest
    static void testLogHoldsOnlyTheMostRecentAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').Config__c = '{"throwError":true, "log": "hello"}';

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = [SELECT Relay_Attempts__c, Log__c FROM TB_Subscription_Outbox__c];
        System.assertEquals(2, outbox.Relay_Attempts__c, 'The outbox should have been attempted twice');
        System.assertEquals(1, outbox.Log__c.countMatches('hello'), 'The log should hold the second attempt only: ' + outbox.Log__c);
    }

    @isTest
    static void testCompletedOutboxDoesNotHoldItsGroup() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        // What is left behind when a relay client sets a next attempt time and the send then succeeds.
        TB_Subscription_Outbox__c delivered = outboxesInOrder()[0];
        delivered.Completed_Timestamp__c = System.now();
        delivered.Next_Attempt_Timestamp__c = System.now().addMinutes(30);
        update delivered;
        Test.stopTest();

        System.assertEquals(new List<Integer>{ 0, 1 }, attemptsInOrder(), 'The second message should go');
    }

    /**
     * With a batch size of 1 a search reads 10 pages of 2. One held group has 25 due outboxes,
     * more than the search can read, so the outbox behind them is only reached because later pages
     * leave the held group out.
     */
    @isTest
    static void testLongHeldGroupDoesNotUseUpTheSearch() {
        setRelayBatchSize(1);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        List<TB_Outbox_Message__c> messages = new List<TB_Outbox_Message__c>();
        for (Integer i = 0; i < 26; i++) {
            messages.add(newGroupedMessage(msgDef, 'group1'));
        }
        messages.add(newMessage(msgDef));

        Test.startTest();
        insert messages;
        makeOutboxWaitOnBackoff(0);
        Test.stopTest();

        List<Integer> attempts = attemptsInOrder();
        System.assertEquals(1, attempts[26], 'The outbox behind the held group should be attempted');
        attempts.remove(26);
        System.assertEquals(new Set<Integer>{ 0 }, new Set<Integer>(attempts), 'Nothing in the held group should be attempted');
    }

    /**
     * A page can end between two subscriptions' outboxes for one message.
     * With a batch size of 2 a page is 4. Three held outboxes come first, so the page ends after
     * subscription1's outbox for the last message, and subscription2's is the first row of the next page.
     */
    @isTest
    static void testPageCanEndBetweenTwoOutboxesOfOneMessage() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt twoSubscriptions = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, twoSubscriptions, 'subscription1');
        addTestClientSubscription(app, twoSubscriptions, 'subscription2');
        TB_Message_Definition__mdt oneSubscription = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, oneSubscription, 'subscription3');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(oneSubscription, 'group1'),
            newGroupedMessage(twoSubscriptions, 'group1'),
            newGroupedMessage(oneSubscription, 'group1'),
            newMessage(twoSubscriptions)
        };
        makeOutboxWaitOnBackoff(0);
        Test.stopTest();

        System.assertEquals(
            new List<Integer>{ 0, 0, 0, 0, 1, 1 },
            attemptsInOrder(),
            'Both outboxes of the last message should be attempted, one from each page'
        );
    }

    /**
     * A hold later in a group does not hide the messages before it from the check for remaining work.
     */
    @isTest
    static void testNextRunIsQueuedForMessagesBeforeAHoldInTheirGroup() {
        setRelayBatchSize(2);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        makeOutboxWaitOnBackoff(3);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        Test.stopTest();

        System.assertEquals(2, relayJobCount(), 'The third message is left by the first run and should start a second');
        System.assertEquals(new List<Integer>{ 1, 1, 1, 0 }, attemptsInOrder());
    }

    @isTest
    static void testRunFailsWhenBatchSizeIsAboveTheMaximum() {
        setRelayBatchSize(1001);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('from 1 to 1000'), 'The error should give the allowed range: ' + failure);
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder());
    }

    static void removeSubscription(TB_Message_Subscription__mdt subscription) {
        for (Integer i = 0; i < TB_OutboxMetadataProvider.subscriptions.size(); i++) {
            if (TB_OutboxMetadataProvider.subscriptions[i].DeveloperName == subscription.DeveloperName) {
                TB_OutboxMetadataProvider.subscriptions.remove(i);
                return;
            }
        }
        System.assert(false, 'There is no subscription named ' + subscription.DeveloperName + ' to remove');
    }

    static void removeMessageDefinition(TB_Message_Definition__mdt msgDef) {
        for (Integer i = 0; i < TB_OutboxMetadataProvider.msgDefinitions.size(); i++) {
            if (TB_OutboxMetadataProvider.msgDefinitions[i].DeveloperName == msgDef.DeveloperName) {
                TB_OutboxMetadataProvider.msgDefinitions.remove(i);
                return;
            }
        }
        System.assert(false, 'There is no message definition named ' + msgDef.DeveloperName + ' to remove');
    }

    // Stands in for attempts made by earlier runs.
    static void setRelayAttempts(Integer position, Integer attempts) {
        TB_Subscription_Outbox__c outbox = outboxesInOrder()[position];
        outbox.Relay_Attempts__c = attempts;
        update outbox;
    }

    // A minute either side, because the run and the test read the clock at different moments.
    static void assertNextAttemptIsInMinutes(TB_Subscription_Outbox__c outbox, Integer minutes, String why) {
        System.assertNotEquals(null, outbox.Next_Attempt_Timestamp__c, why + ' No next attempt time was set.');
        System.assert(
            Datetime.now().addMinutes(minutes - 1) < outbox.Next_Attempt_Timestamp__c &&
                Datetime.now().addMinutes(minutes + 1) > outbox.Next_Attempt_Timestamp__c,
            why +
                ' Expected about ' +
                minutes +
                ' minutes from now, but the next attempt is at ' +
                outbox.Next_Attempt_Timestamp__c
        );
    }

    /**
     * A publisher cannot create an outbox for a subscription or definition that does not exist,
     * so each of these tests publishes first and takes the configuration away before the run starts.
     */
    @isTest
    static void testWhenSubscriptionIsMissingThenOneAttemptFailsAndWaitsForTheFallback() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        // Its own backoff goes with it, so this must not be the wait that is used.
        subscription.Retry_BackOff__c = '5';

        Test.startTest();
        insert newMessage(msgDef);
        removeSubscription(subscription);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertNotEquals(null, outbox.Last_Attempt__c, 'The time of the attempt should be recorded');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason should be recorded on the outbox');
        System.assert(
            outbox.Last_Error_Message__c.contains('billing_feed'),
            'The error should name the missing subscription, but is: ' + outbox.Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outbox, 45, 'A missing subscription should wait for the fallback retry wait.');
        System.assertEquals(false, outbox.Dead_Lettered__c, 'One failed attempt of three should not dead-letter the outbox');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    @isTest
    static void testWhenSubscriptionIsRenamedThenOneAttemptFailsUnderTheOldName() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');

        Test.startTest();
        insert newMessage(msgDef);
        subscription.DeveloperName = 'billing_feed_v2';
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered under another name');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason should be recorded on the outbox');
        System.assert(
            outbox.Last_Error_Message__c.contains('billing_feed'),
            'The error should name the subscription the outbox was created for, but is: ' + outbox.Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outbox, 45, 'No subscription has the old name, so the fallback retry wait applies.');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    @isTest
    static void testWhenMessageDefinitionIsMissingThenOneAttemptFailsAndWaitsForTheSubscriptionBackoff() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.Retry_BackOff__c = '30,60';

        Test.startTest();
        insert newMessage(msgDef);
        removeMessageDefinition(msgDef);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertNotEquals(null, outbox.Last_Attempt__c, 'The time of the attempt should be recorded');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason should be recorded on the outbox');
        System.assert(
            outbox.Last_Error_Message__c.contains('test.message1'),
            'The error should name the message type that has no definition, but is: ' + outbox.Last_Error_Message__c
        );
        System.assert(
            outbox.Last_Error_Message__c.containsIgnoreCase('definition'),
            'The error should say a message definition is what is missing, but is: ' + outbox.Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(
            outbox,
            30,
            'The subscription still exists, so its own backoff applies and the fallback does not.'
        );
        System.assertEquals(false, outbox.Dead_Lettered__c, 'One failed attempt of three should not dead-letter the outbox');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    @isTest
    static void testWhenSubscriptionAndDefinitionAreBothMissingThenOneAttemptFailsAndWaitsForTheFallback() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');

        Test.startTest();
        insert newMessage(msgDef);
        removeSubscription(subscription);
        removeMessageDefinition(msgDef);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted once, not once for each missing part');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason should be recorded on the outbox');
        assertNextAttemptIsInMinutes(outbox, 45, 'With no subscription there is no backoff, so the fallback applies.');
    }

    @isTest
    static void testWhenSubscriptionIsMissingThenOtherOutboxesInTheRunAreRelayed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The outbox with the missing subscription is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(healthyDef) };
        removeSubscription(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with no subscription should not be delivered');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox behind it should be delivered');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    @isTest
    static void testWhenMessageDefinitionIsMissingThenOtherOutboxesInTheRunAreRelayed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, removed, 'billing_feed');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The outbox with the missing definition is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removed), newMessage(healthyDef) };
        removeMessageDefinition(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with no definition should not be delivered');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox behind it should be delivered');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    @isTest
    static void testWhenSubscriptionIsMissingThenOutboxDeadLettersAtMaxAttempts() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');

        // The outbox is created with the subscription's maximum of three attempts.
        Test.startTest();
        insert newMessage(msgDef);
        setRelayAttempts(0, 2);
        removeSubscription(subscription);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(3, outbox.Relay_Attempts__c, 'The third attempt should be counted');
        System.assertEquals(true, outbox.Dead_Lettered__c, 'The outbox should be dead-lettered at its maximum attempts');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
    }

    @isTest
    static void testWhenMessageDefinitionIsMissingThenOutboxDeadLettersAtMaxAttempts() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'billing_feed');

        // The outbox is created with the subscription's maximum of three attempts.
        Test.startTest();
        insert newMessage(msgDef);
        setRelayAttempts(0, 2);
        removeMessageDefinition(msgDef);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(3, outbox.Relay_Attempts__c, 'The third attempt should be counted');
        System.assertEquals(true, outbox.Dead_Lettered__c, 'The outbox should be dead-lettered at its maximum attempts');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
    }

    /**
     * An outbox is tied to its subscription by the subscription's name alone.
     * The message it carries keeps its own type, and that type still has a definition.
     * The subscription is no longer on that type, and its after-relay action is still given the attempt.
     */
    @isTest
    static void testWhenSubscriptionIsMovedToAnotherDefinitionThenItsOutboxIsRelayed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Definition__mdt otherDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.RecordingAction';

        Test.startTest();
        insert newMessage(msgDef);
        subscription.Message_Definition__r = otherDef;
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The outbox should be attempted once');
        System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'The outbox should be delivered');
        System.assertEquals(null, outbox.Last_Error_Message__c, 'No error should be recorded');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The message should be sent once');

        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.actionCalls.size(),
            'The moved subscription\'s action should run once'
        );
        List<TB_OutboxRelayContext> results = TB_TransactionOutboxTestUtils.actionCalls[0];
        System.assertNotEquals(null, results, 'The action should be given the outbox\'s attempt, not null');
        System.assertEquals(1, results.size(), 'The action should be given one attempt');
        System.assertEquals(outbox.Id, results[0].outbox.Id, 'The action should be given this outbox\'s attempt');
        System.assert(results[0].isComplete(), 'The attempt the action is given should be the delivered one');
    }

    static TB_Message_Subscription__mdt subscriptionToRestore;
    static TB_Message_Definition__mdt definitionToRestore;
    static TB_Message_Subscription__mdt subscriptionToCorrect;
    static String correctedSettings;
    static Boolean configurationRestored = false;

    /**
     * Stands in for what happens between two runs: the removed configuration is put back under
     * the same name or the faulty settings are corrected, the retry wait passes, and a later run starts.
     *
     * A test cannot act between two runs itself, because every queued job runs inside Test.stopTest().
     * An after-relay action is called once the first run's outcomes are stored, so a test puts this
     * action on a healthy subscription that has an outbox in the first run.
     */
    public class RestoreConfigurationAction implements TB_IAfterRelayAction {
        public void execute(TB_OutboxRelayContext[] ctx) {
            // The second run may call the action again, and it must not start a third.
            if (configurationRestored) {
                return;
            }
            configurationRestored = true;

            if (subscriptionToRestore != null) {
                TB_OutboxMetadataProvider.subscriptions.add(subscriptionToRestore);
            }
            if (definitionToRestore != null) {
                TB_OutboxMetadataProvider.msgDefinitions.add(definitionToRestore);
            }
            if (subscriptionToCorrect != null) {
                subscriptionToCorrect.Config__c = correctedSettings;
            }

            List<TB_Subscription_Outbox__c> waiting = [
                SELECT Id
                FROM TB_Subscription_Outbox__c
                WHERE Completed_Timestamp__c = NULL AND Next_Attempt_Timestamp__c != NULL
            ];
            for (TB_Subscription_Outbox__c outbox : waiting) {
                outbox.Next_Attempt_Timestamp__c = null;
            }
            update waiting;

            System.enqueueJob(new TB_OutboxRelayQueuable());
        }
    }

    @isTest
    static void testWhenMissingSubscriptionIsRestoredThenOutboxIsDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.RestoreConfigurationAction';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(healthyDef) };
        removeSubscription(removed);
        subscriptionToRestore = removed;
        Test.stopTest();

        System.assert(configurationRestored, 'The first run should finish and the subscription should be put back');
        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals('billing_feed', outbox.Subscription__c);
        System.assertEquals(
            2,
            outbox.Relay_Attempts__c,
            'The first run should fail one attempt and the second should make another'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The outbox should be delivered once a subscription has its name again'
        );
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The healthy outbox is sent in the first run and the restored one in the second'
        );
    }

    @isTest
    static void testWhenMissingMessageDefinitionIsRestoredThenOutboxIsDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        // With a backoff the first run leaves the outbox waiting, so only the restoring action starts the second run.
        addTestClientSubscription(app, removed, 'billing_feed').Retry_BackOff__c = '30';
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.RestoreConfigurationAction';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removed), newMessage(healthyDef) };
        removeMessageDefinition(removed);
        definitionToRestore = removed;
        Test.stopTest();

        System.assert(configurationRestored, 'The first run should finish and the definition should be put back');
        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals('billing_feed', outbox.Subscription__c);
        System.assertEquals(
            2,
            outbox.Relay_Attempts__c,
            'The first run should fail one attempt and the second should make another'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The outbox should be delivered once a definition has the message type\'s name again'
        );
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The healthy outbox is sent in the first run and the restored one in the second'
        );
    }

    /**
     * The fallback retry wait is only used when a subscription is missing, but it is checked before
     * anything is attempted. Here every outbox is healthy, and the run must still refuse to start.
     */
    @isTest
    static void testWhenFallbackRetryWaitIsBlankThenRunFailsBeforeAnyAttempt() {
        setFallbackRetryWait(null);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('Fallback_Retry_Wait__c'), 'The error should name the setting: ' + failure);
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder(), 'Nothing should be attempted on an assumed wait');
    }

    @isTest
    static void testWhenFallbackRetryWaitIsNegativeThenRunFailsBeforeAnyAttempt() {
        setFallbackRetryWait(-1);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('Fallback_Retry_Wait__c'), 'The error should name the setting: ' + failure);
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder(), 'Nothing should be attempted');
    }

    @isTest
    static void testWhenFallbackRetryWaitIsAboveTheMaximumThenRunFailsBeforeAnyAttempt() {
        setFallbackRetryWait(TB_OutboxMetadataProvider.MAX_FALLBACK_RETRY_WAIT + 1);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        String failure;
        Test.startTest();
        insert newMessage(msgDef);
        try {
            Test.stopTest();
        } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
            failure = e.getMessage();
        }

        System.assertNotEquals(null, failure, 'The run should fail and say why');
        System.assert(failure.contains('Fallback_Retry_Wait__c'), 'The error should name the setting: ' + failure);
        System.assert(
            failure.contains('from 0 to ' + TB_OutboxMetadataProvider.MAX_FALLBACK_RETRY_WAIT),
            'The error should give the allowed range: ' + failure
        );
        System.assertEquals(new List<Integer>{ 0 }, attemptsInOrder(), 'Nothing should be attempted');
    }

    // The longest allowed wait still gives a next attempt time the outbox can be saved with.
    @isTest
    static void testWhenFallbackRetryWaitIsTheMaximumThenItIsUsed() {
        setFallbackRetryWait(TB_OutboxMetadataProvider.MAX_FALLBACK_RETRY_WAIT);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');

        Test.startTest();
        insert newMessage(msgDef);
        removeSubscription(subscription);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted and saved');
        assertNextAttemptIsInMinutes(
            outbox,
            TB_OutboxMetadataProvider.MAX_FALLBACK_RETRY_WAIT,
            'The longest allowed fallback retry wait should be used.'
        );
    }

    // A wait of zero asks for the next attempt at once, so the outbox is already due again when the run ends.
    @isTest
    static void testWhenFallbackRetryWaitIsZeroThenTheNextAttemptIsDueAtOnce() {
        setFallbackRetryWait(0);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');

        Test.startTest();
        insert newMessage(msgDef);
        removeSubscription(subscription);
        Test.stopTest();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outbox.Next_Attempt_Timestamp__c, 'A next attempt time should be set');
        System.assert(
            outbox.Next_Attempt_Timestamp__c <= Datetime.now(),
            'The outbox should be due again already, but its next attempt is at ' + outbox.Next_Attempt_Timestamp__c
        );
    }

    /**
     * Nothing is sent for an outbox without configuration, so an isolated attempt earlier in the run
     * does not keep it from being failed.
     */
    @isTest
    static void testWhenSubscriptionIsMissingBehindAnIsolatedOutboxThenItStillFailsOneAttempt() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');

        // The isolated outbox is published first, so it is the run's first attempt.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(isolatedDef), newMessage(msgDef) };
        removeSubscription(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The isolated outbox should be delivered');
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox with no subscription should not be delivered');
        System.assert(
            outboxes[1].Last_Error_Message__c.contains('billing_feed'),
            'The error should name the missing subscription, but is: ' + outboxes[1].Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outboxes[1], 45, 'A missing subscription should wait for the fallback retry wait.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the isolated outbox should be sent');
    }

    // The failed attempt is one of the run's attempts, so the isolated outbox behind it is not first.
    @isTest
    static void testWhenSubscriptionIsMissingAheadOfAnIsolatedOutboxThenTheIsolatedOneIsPassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;

        // The outbox with the missing subscription is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(isolatedDef) };
        removeSubscription(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The missing subscription should fail one attempt and the isolated outbox should be passed over'
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with no subscription should not be delivered');
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The isolated outbox should wait for a later run');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    /**
     * The subscription is still there and is isolated, so its failed attempt ends what the run attempts,
     * just as a sent isolated attempt would.
     */
    @isTest
    static void testWhenIsolatedSubscriptionHasNoDefinitionThenItFailsAndLaterOutboxesArePassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, removed, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The outbox with the missing definition is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removed), newMessage(healthyDef) };
        removeMessageDefinition(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The isolated outbox should fail one attempt and the healthy one should be passed over'
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with no definition should not be delivered');
        System.assert(
            outboxes[0].Last_Error_Message__c.containsIgnoreCase('definition'),
            'The error should say a message definition is missing, but is: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The healthy outbox should wait for a later run');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    @isTest
    static void testWhenSubscriptionIsMissingThenLaterMessagesInItsGroupAreHeld() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        removeSubscription(removed);
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The first message should fail one attempt and the later one in its group should not be attempted'
        );
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The later message should not be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The later message should carry no error');
    }

    // Cut off part-way, so it cannot be parsed as JSON at all.
    static final String MALFORMED_SETTINGS = '{"throwError":';

    /**
     * Runs the queued relay job. A job that ends with an unhandled exception is thrown out of
     * Test.stopTest(), so reaching the end of this method means the run finished as a completed job.
     */
    static void stopTestExpectingNoFailedJob() {
        try {
            Test.stopTest();
        } catch (Exception e) {
            System.assert(
                false,
                'The run should end without a failed job, but it failed with ' + e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }

    static void assertErrorSaysSettingsCannotBeRead(TB_Subscription_Outbox__c outbox) {
        System.assertNotEquals(
            null,
            outbox.Last_Error_Message__c,
            'The reason should be recorded on the outbox for ' + outbox.Subscription__c
        );
        System.assert(
            outbox.Last_Error_Message__c.contains('Config__c'),
            'The error should name the field whose settings cannot be read, but is: ' + outbox.Last_Error_Message__c
        );
        System.assert(
            outbox.Last_Error_Message__c.contains(outbox.Subscription__c),
            'The error should name the subscription whose settings cannot be read, but is: ' + outbox.Last_Error_Message__c
        );
    }

    /**
     * Settings that cannot be read are found when the outbox is attempted, not when it is published,
     * so each of these tests can publish with the faulty settings already in place.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenOneAttemptFailsAndWaitsForTheSubscriptionBackoff() {
        // Differs from the subscription's backoff, so the two waits cannot be mistaken for each other.
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.Config__c = MALFORMED_SETTINGS;
        subscription.Retry_BackOff__c = '25,50';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertNotEquals(null, outbox.Last_Attempt__c, 'The time of the attempt should be recorded');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outbox);
        assertNextAttemptIsInMinutes(
            outbox,
            25,
            'The subscription exists, so its own backoff applies and the fallback does not.'
        );
        System.assertEquals(false, outbox.Dead_Lettered__c, 'One failed attempt of three should not dead-letter the outbox');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenOutboxDeadLettersAtMaxAttempts() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'billing_feed').Config__c = MALFORMED_SETTINGS;

        // The outbox is created with the subscription's maximum of three attempts.
        Test.startTest();
        insert newMessage(msgDef);
        setRelayAttempts(0, 2);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(3, outbox.Relay_Attempts__c, 'The third attempt should be counted');
        System.assertEquals(true, outbox.Dead_Lettered__c, 'The outbox should be dead-lettered at its maximum attempts');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outbox);
    }

    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenLaterOutboxesInTheRunAreRelayed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, faultyDef, 'billing_feed').Config__c = MALFORMED_SETTINGS;
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The outbox with the faulty settings is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(faultyDef), newMessage(healthyDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with faulty settings should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outboxes[0]);
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox behind it should be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The healthy outbox should carry no error');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenEarlierOutboxesInTheRunAreRelayed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, faultyDef, 'billing_feed').Config__c = MALFORMED_SETTINGS;

        // The healthy outbox is published first, so the run reaches the faulty settings after a delivery.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(healthyDef), newMessage(faultyDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox ahead of it should be delivered');
        System.assertEquals(null, outboxes[0].Last_Error_Message__c, 'The healthy outbox should carry no error');
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox with faulty settings should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outboxes[1]);
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    /**
     * An outbox that failed on its settings and is waiting on its backoff is not due, so the run's
     * finalizer has nothing to start another run for. The healthy outbox goes first so the run
     * reaches the test client, which is what frees the finalizer to queue.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenTheWaitingOutboxDoesNotStartAnotherRun() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Retry_BackOff__c = '25';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(healthyDef), newMessage(faultyDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        assertFinalizerWasFreeToQueue();
        System.assertEquals(1, relayJobCount(), 'An outbox waiting on its backoff should not start another run');
        System.assertEquals(
            new List<Integer>{ 1, 1 },
            attemptsInOrder(),
            'Each outbox should have exactly one attempt, from the one run'
        );
    }

    /**
     * With the definition gone nothing can be sent, whatever the settings say, so the missing
     * definition is the reason given and the subscription's own backoff still decides the wait.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedAndDefinitionIsMissingThenOneAttemptFailsAndTheRunCarriesOn() {
        setFallbackRetryWait(45);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, removed, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Retry_BackOff__c = '25,50';
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The outbox with the faulty settings and no definition is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removed), newMessage(healthyDef) };
        removeMessageDefinition(removed);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 1 },
            attemptsInOrder(),
            'The faulty outbox should be counted once, not once for each fault, and the healthy one attempted'
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The faulty outbox should not be delivered');
        System.assertNotEquals(null, outboxes[0].Last_Attempt__c, 'The time of the attempt should be recorded');
        System.assertNotEquals(null, outboxes[0].Last_Error_Message__c, 'The reason should be recorded on the outbox');
        System.assert(
            outboxes[0].Last_Error_Message__c.contains('test.message1') &&
                outboxes[0].Last_Error_Message__c.containsIgnoreCase('definition'),
            'The error should say the message type has no definition, but is: ' + outboxes[0].Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(
            outboxes[0],
            25,
            'The subscription exists, so its own backoff applies and the fallback does not.'
        );
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox behind it should be delivered');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    @isTest
    static void testWhenMalformedSubscriptionSettingsAreCorrectedThenOutboxIsDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        // With a backoff the first run leaves the outbox waiting, so only the correcting action starts the second run.
        faulty.Retry_BackOff__c = '30';
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.RestoreConfigurationAction';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(faultyDef), newMessage(healthyDef) };
        subscriptionToCorrect = faulty;
        correctedSettings = '{"log": "hello"}';
        stopTestExpectingNoFailedJob();

        System.assert(configurationRestored, 'The first run should finish and the settings should be corrected');
        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals('billing_feed', outbox.Subscription__c);
        System.assertEquals(
            2,
            outbox.Relay_Attempts__c,
            'The first run should fail one attempt and the second should make another'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The outbox should be delivered once its subscription\'s settings can be read'
        );
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The healthy outbox is sent in the first run and the corrected one in the second'
        );
    }

    /**
     * A relay client is handed the settings as a set of named values. JSON that parses but is a list,
     * a text, a number or the literal null cannot be handed over that way, so it is as unreadable as
     * JSON that does not parse. The literal null differs from a field left empty, which means no settings.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreNotAJsonObjectThenOneAttemptFailsForEach() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        // Named so that the outboxes of the one message come back in this order.
        addTestClientSubscription(app, msgDef, 'feed1_list').Config__c = '["throwError"]';
        addTestClientSubscription(app, msgDef, 'feed2_text').Config__c = '"throwError"';
        addTestClientSubscription(app, msgDef, 'feed3_number').Config__c = '7';
        addTestClientSubscription(app, msgDef, 'feed4_null').Config__c = 'null';
        addTestClientSubscription(app, msgDef, 'feed5_healthy');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 1, 1, 1, 1 },
            attemptsInOrder(),
            'Every outbox should be attempted once in the one run'
        );
        for (Integer i = 0; i < 4; i++) {
            System.assertEquals(
                null,
                outboxes[i].Completed_Timestamp__c,
                'The outbox for ' + outboxes[i].Subscription__c + ' should not be delivered'
            );
            assertErrorSaysSettingsCannotBeRead(outboxes[i]);
        }
        System.assertNotEquals(null, outboxes[4].Completed_Timestamp__c, 'The healthy outbox should be delivered');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outbox should be sent');
    }

    /**
     * An attempt that fails on its settings is an ordinary attempt of the run. For an isolated
     * subscription it is the run's isolated attempt, so the run attempts nothing after it.
     */
    @isTest
    static void testWhenIsolatedSubscriptionSettingsAreMalformedThenItFailsAndLaterOutboxesArePassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'isolated_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Isolate_Relay__c = true;
        // With a backoff the failed outbox is not due again, so a later run cannot add to its attempts.
        faulty.Retry_BackOff__c = '25';
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // The isolated outbox with the faulty settings is published first, so it is the run's first attempt.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(faultyDef), newMessage(healthyDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The isolated outbox should fail one attempt and the healthy one should be passed over'
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with faulty settings should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outboxes[0]);
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The healthy outbox should wait for a later run');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    // The failed attempt is one of the run's attempts, so the isolated outbox behind it is not first.
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedAheadOfAnIsolatedOutboxThenTheIsolatedOneIsPassedOver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Retry_BackOff__c = '25';
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;

        // The outbox with the faulty settings is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(faultyDef), newMessage(isolatedDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The faulty settings should fail one attempt and the isolated outbox should be passed over'
        );
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with faulty settings should not be delivered');
        assertErrorSaysSettingsCannotBeRead(outboxes[0]);
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The isolated outbox should wait for a later run');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    /**
     * Settings are only judged once an attempt has started, and no attempt starts after the run's
     * isolated attempt. This is where faulty settings differ from missing configuration, which is
     * failed even behind an isolated attempt.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedBehindAnIsolatedOutboxThenItIsNotAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, faultyDef, 'billing_feed').Config__c = MALFORMED_SETTINGS;

        // The isolated outbox is published first, so it is the run's first attempt.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(isolatedDef), newMessage(faultyDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The isolated outbox should be attempted and the one with faulty settings should be passed over'
        );
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The isolated outbox should be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'An outbox that was not attempted should carry no error');
        System.assertEquals(null, outboxes[1].Next_Attempt_Timestamp__c, 'An outbox that was not attempted should not wait');
    }

    // An isolated outbox that is not first is passed over before its settings are looked at.
    @isTest
    static void testWhenIsolatedSubscriptionSettingsAreMalformedAndItIsNotFirstThenItIsNotAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'isolated_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Isolate_Relay__c = true;

        // The healthy outbox is published first, so the isolated one is not the run's first attempt.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(healthyDef), newMessage(faultyDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The healthy outbox should be attempted and the isolated one should be passed over'
        );
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The healthy outbox should be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'An outbox that was not attempted should carry no error');
        System.assertEquals(null, outboxes[1].Next_Attempt_Timestamp__c, 'An outbox that was not attempted should not wait');
    }

    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenLaterMessagesInItsGroupAreHeld() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, msgDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Retry_BackOff__c = '25';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1'),
            newGroupedMessage(msgDef, 'group1')
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The first message should fail one attempt and the later one in its group should not be attempted'
        );
        assertErrorSaysSettingsCannotBeRead(outboxes[0]);
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The later message should not be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The later message should carry no error');
    }

    // Settings that cannot be read are judged again for each outbox, so a failure is never handed on to the next one.
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenEachOfItsOutboxesInTheRunFailsItsOwnAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, faultyDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.Retry_BackOff__c = '25';
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        // Published alternately, so a healthy outbox sits between the two faulty ones.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(faultyDef),
            newMessage(healthyDef),
            newMessage(faultyDef),
            newMessage(healthyDef)
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 1, 1, 1 },
            attemptsInOrder(),
            'Every outbox should be attempted once in the one run'
        );
        for (Integer i : new List<Integer>{ 0, 2 }) {
            System.assertEquals(
                null,
                outboxes[i].Completed_Timestamp__c,
                'The outbox at position ' + i + ' with faulty settings should not be delivered'
            );
            assertErrorSaysSettingsCannotBeRead(outboxes[i]);
            assertNextAttemptIsInMinutes(
                outboxes[i],
                25,
                'The outbox at position ' + i + ' should wait on its subscription\'s backoff.'
            );
        }
        for (Integer i : new List<Integer>{ 1, 3 }) {
            System.assertNotEquals(
                null,
                outboxes[i].Completed_Timestamp__c,
                'The healthy outbox at position ' + i + ' should be delivered'
            );
            System.assertEquals(null, outboxes[i].Last_Error_Message__c, 'The healthy outbox should carry no error');
        }
        System.assertEquals(2, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the healthy outboxes should be sent');
    }

    // The message is resolved before anything is sent, and settings are only judged for a send.
    @isTest
    static void testWhenResolverFailsAndSubscriptionSettingsAreMalformedThenTheResolverFailureIsRecorded() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        addTestClientSubscription(app, msgDef, 'billing_feed').Config__c = MALFORMED_SETTINGS;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted once');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assert(
            outbox.Last_Error_Message__c.startsWith('Resolver Error'),
            'The outbox should carry the resolver error, but has: ' + outbox.Last_Error_Message__c
        );
    }

    // Only the relay client can judge its settings, so a client that cannot be built is the reason given.
    @isTest
    static void testWhenRelayClientCannotBeBuiltAndSubscriptionSettingsAreMalformedThenTheClientFailureIsRecorded() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.NoSuchClient';
        subscription.Config__c = MALFORMED_SETTINGS;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted once');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assert(
            outbox.Last_Error_Message__c.startsWith('TB_TransactionOutboxTestUtils.NoSuchClient does not exist'),
            'The outbox should carry the construction error, but has: ' + outbox.Last_Error_Message__c
        );
    }

    // A subscription may have no settings at all. That is left for its relay client to judge, and the test client needs none.
    @isTest
    static void testWhenSubscriptionHasNoSettingsThenOutboxIsDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.Config__c = null;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'The outbox should be delivered');
        System.assertEquals(null, outbox.Last_Error_Message__c, 'The outbox should carry no error');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The outbox should be sent');
    }

    static final String RECORDING_ACTION = 'TB_TransactionOutboxTestUtils.RecordingAction';

    /**
     * The outboxes each call to the recording action was given, by the subscription they belong to.
     *
     * An action exists to be told about attempts, so a call that carries none is a fault wherever it
     * shows up. This fails on a call given null or an empty list, on a call that mixes subscriptions,
     * and on a second call for one subscription. A test that spans two runs can use it as long as no
     * subscription has attempts in both.
     */
    static Map<String, Set<Id>> actionCallsBySubscription() {
        Integer callCount = TB_TransactionOutboxTestUtils.actionCalls.size();
        Map<String, Set<Id>> outboxIdsBySubscription = new Map<String, Set<Id>>();
        for (List<TB_OutboxRelayContext> call : TB_TransactionOutboxTestUtils.actionCalls) {
            System.assertNotEquals(
                null,
                call,
                'An action should never be given null, but one of the ' + callCount + ' action calls was'
            );
            System.assert(
                !call.isEmpty(),
                'An action should never be called with no attempts, but one of the ' + callCount + ' action calls was'
            );

            String subscriptionName = call[0].outbox.Subscription__c;
            System.assert(
                !outboxIdsBySubscription.containsKey(subscriptionName),
                'The action for ' + subscriptionName + ' should be called once, with all of its attempts together'
            );
            Set<Id> outboxIds = new Set<Id>();
            for (TB_OutboxRelayContext attempt : call) {
                System.assertEquals(
                    subscriptionName,
                    attempt.outbox.Subscription__c,
                    'An action should be given its own subscription\'s attempts and no other\'s'
                );
                outboxIds.add(attempt.outbox.Id);
            }
            outboxIdsBySubscription.put(subscriptionName, outboxIds);
        }
        return outboxIdsBySubscription;
    }

    /**
     * The passed-over outbox gets its attempt in the second run, and that is the run its action belongs to.
     */
    @isTest
    static void testWhenPassedOverOutboxIsDeliveredByTheNextRunThenItsAfterRelayActionIsCalledForThatRunOnly() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').After_Relay_Action__c = RECORDING_ACTION;
        // A second message type, so the isolated outbox has a later sequence number and is never first in the run.
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt isolatedSub = addTestClientSubscription(app, isolatedDef, 'subscription2');
        isolatedSub.Isolate_Relay__c = true;
        isolatedSub.After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(isolatedDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, relayJobCount(), 'A second run should be queued for the isolated outbox');
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Each outbox should be attempted once');
        System.assertEquals(
            new Map<String, Set<Id>>{
                'subscription1' => new Set<Id>{ outboxes[0].Id },
                'subscription2' => new Set<Id>{ outboxes[1].Id }
            },
            actionCallsBySubscription(),
            'Each action should be called once, by the run that attempted its subscription\'s outbox'
        );
        System.assertEquals(
            outboxes[0].Id,
            TB_TransactionOutboxTestUtils.actionCalls[0][0].outbox.Id,
            'The first run should call only the action of the subscription it attempted'
        );
    }

    @isTest
    static void testWhenOutboxIsHeldByItsGroupThenItsAfterRelayActionIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt failingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt failingSub = addTestClientSubscription(app, failingDef, 'subscription1');
        failingSub.Config__c = '{"throwError":true}';
        failingSub.After_Relay_Action__c = RECORDING_ACTION;
        TB_Message_Definition__mdt heldDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, heldDef, 'subscription2').After_Relay_Action__c = RECORDING_ACTION;

        // The first message fails in the run, so the one after it in the group is held and not attempted.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(failingDef, 'group1'),
            newGroupedMessage(heldDef, 'group1')
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The first outbox should fail one attempt and the held one should not be attempted'
        );
        System.assertEquals(
            new Map<String, Set<Id>>{ 'subscription1' => new Set<Id>{ outboxes[0].Id } },
            actionCallsBySubscription(),
            'Only the subscription that had an attempt should have its action called'
        );
    }

    /**
     * Two subscriptions take the same message type. One of them has nothing due in this run, which is
     * the ordinary state of a subscription whose outbox is waiting or was settled by an earlier run.
     */
    @isTest
    static void testWhenSubscriptionHasNoDueOutboxThenItsAfterRelayActionIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').After_Relay_Action__c = RECORDING_ACTION;
        addTestClientSubscription(app, msgDef, 'subscription2').After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        makeOutboxWaitOnBackoff(1);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals('subscription2', outboxes[1].Subscription__c);
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The outbox waiting on its backoff should not be attempted'
        );
        System.assertEquals(
            new Map<String, Set<Id>>{ 'subscription1' => new Set<Id>{ outboxes[0].Id } },
            actionCallsBySubscription(),
            'Only the subscription that had an attempt should have its action called'
        );
    }

    @isTest
    static void testWhenSubscriptionHasNoOutboxThenItsAfterRelayActionIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').After_Relay_Action__c = RECORDING_ACTION;
        // A disabled subscription gets no outbox when a message is published.
        TB_Message_Subscription__mdt disabledSub = addTestClientSubscription(app, msgDef, 'subscription2');
        disabledSub.Enabled__c = false;
        disabledSub.After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes.size(), 'Only the enabled subscription should have an outbox');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should be delivered');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'subscription1' => new Set<Id>{ outboxes[0].Id } },
            actionCallsBySubscription(),
            'Only the subscription that had an attempt should have its action called'
        );
    }

    static final String FAILING_PAYLOAD = 'Payload the subscriber refuses';

    // Lets one subscription have a delivered attempt and a failed attempt in the same run.
    public class RefusesOnePayloadClient implements TB_IOutboxRelayClient {
        public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
            return TB_TransactionOutboxTestUtils.inMemorySendCost();
        }

        public void send(TB_OutboxRelayContext ctx) {
            if (ctx.outbox.Outbox_Message__r.Message__c == FAILING_PAYLOAD) {
                throw new TB_TransactionOutboxTestUtils.TestException('Test Error');
            }
        }
    }

    @isTest
    static void testAfterRelayActionIsGivenEveryAttemptItsSubscriptionHadInTheRun() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt mixedSub = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'billing_feed');
        mixedSub.Relay_Client__c = 'TB_OutboxRelayTests.RefusesOnePayloadClient';
        mixedSub.After_Relay_Action__c = RECORDING_ACTION;
        addTestClientSubscription(app, msgDef, 'shipping_feed').After_Relay_Action__c = RECORDING_ACTION;

        TB_Outbox_Message__c refused = newMessage(msgDef);
        refused.Message__c = FAILING_PAYLOAD;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), refused };
        stopTestExpectingNoFailedJob();

        // Each message has one outbox per subscription, so the order is billing, shipping, billing, shipping.
        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1, 1, 1 }, attemptsInOrder(), 'Every outbox should be attempted once');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first billing outbox should be delivered');
        System.assertEquals(null, outboxes[2].Completed_Timestamp__c, 'The refused billing outbox should not be delivered');

        System.assertEquals(
            new Map<String, Set<Id>>{
                'billing_feed' => new Set<Id>{ outboxes[0].Id, outboxes[2].Id },
                'shipping_feed' => new Set<Id>{ outboxes[1].Id, outboxes[3].Id }
            },
            actionCallsBySubscription(),
            'Each action should be called once with its own subscription\'s attempts, delivered and failed alike'
        );

        for (List<TB_OutboxRelayContext> call : TB_TransactionOutboxTestUtils.actionCalls) {
            for (TB_OutboxRelayContext attempt : call) {
                System.assertEquals(
                    attempt.outbox.Id != outboxes[2].Id,
                    attempt.isComplete(),
                    'Only the refused attempt should reach its action as not delivered'
                );
            }
        }
        System.assertEquals(
            new List<Integer>{ 2, 2 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The attempts should be stored before the actions run'
        );
    }

    // A class that exists and can be built, but is not an after-relay action.
    public class NotAnAfterRelayAction {
    }

    public class UnbuildableAction implements TB_IAfterRelayAction {
        public UnbuildableAction() {
            throw new TB_TransactionOutboxTestUtils.TestException('Constructor Error');
        }

        public void execute(TB_OutboxRelayContext[] ctx) {
        }
    }

    /**
     * An action that cannot be built is an action that failed, and a failed action changes nothing
     * about delivery. So the subscription naming it is relayed like any other, the rest of the run
     * goes on, the outcomes are stored, and the other subscriptions' actions still run.
     */
    static void assertRunIsUnaffectedByAfterRelayAction(String actionClassName) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt faultyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, faultyDef, 'billing_feed').After_Relay_Action__c = actionClassName;
        TB_Message_Definition__mdt recordedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, recordedDef, 'shipping_feed').After_Relay_Action__c = RECORDING_ACTION;
        TB_Message_Definition__mdt plainDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message3');
        addTestClientSubscription(app, plainDef, 'audit_feed');

        // The outbox whose subscription names the faulty action is published first, so the run reaches it first.
        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(faultyDef), newMessage(recordedDef), newMessage(plainDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(3, outboxes.size());
        System.assertEquals(
            new List<Integer>{ 1, 1, 1 },
            attemptsInOrder(),
            'Every outbox should be attempted in the one run and the attempts stored'
        );
        for (TB_Subscription_Outbox__c outbox : outboxes) {
            System.assertNotEquals(
                null,
                outbox.Completed_Timestamp__c,
                'The outbox for ' + outbox.Subscription__c + ' should be delivered'
            );
            System.assertEquals(
                null,
                outbox.Last_Error_Message__c,
                'A faulty action is not a failed delivery, so no outbox should carry an error, but ' +
                    outbox.Subscription__c +
                    ' does'
            );
        }
        System.assertEquals(3, TB_TransactionOutboxTestUtils.sentMessages.size(), 'All three messages should be sent');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'shipping_feed' => new Set<Id>{ outboxes[1].Id } },
            actionCallsBySubscription(),
            'The other subscription\'s action should still be called with its attempt'
        );
        System.assertEquals(
            new List<Integer>{ 1 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The attempt should be stored before the other subscription\'s action runs'
        );
    }

    @isTest
    static void testWhenAfterRelayActionClassDoesNotExistThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByAfterRelayAction('TB_OutboxRelayTests.NoSuchAction');
    }

    @isTest
    static void testWhenAfterRelayActionClassIsNotAnActionThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByAfterRelayAction('TB_OutboxRelayTests.NotAnAfterRelayAction');
    }

    @isTest
    static void testWhenAfterRelayActionConstructorThrowsThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByAfterRelayAction('TB_OutboxRelayTests.UnbuildableAction');
    }

    /**
     * A subscription keeps its faulty action name from one run to the next, so every run meets it.
     * The batch size leaves the second outbox for a second run.
     */
    @isTest
    static void testWhenAfterRelayActionClassDoesNotExistThenLaterRunsStillRelay() {
        setRelayBatchSize(1);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'billing_feed')
            .After_Relay_Action__c = 'TB_OutboxRelayTests.NoSuchAction';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        System.assertEquals(2, relayJobCount(), 'The first run should queue a second for the outbox it left');
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Each run should attempt one outbox');
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'Both outboxes should be delivered across the two runs');
        }
    }

    /**
     * The faulty name is on a subscription that has nothing in the run at all. It takes the same
     * message type as the outbox being relayed, which is all it has to do with this run.
     */
    static void assertRunIsUnaffectedByActionOfSubscriptionWithNoAttempt(String actionClassName) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        // A disabled subscription gets no outbox when a message is published.
        TB_Message_Subscription__mdt disabledSub = addTestClientSubscription(app, msgDef, 'subscription2');
        disabledSub.Enabled__c = false;
        disabledSub.After_Relay_Action__c = actionClassName;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes.size(), 'Only the enabled subscription should have an outbox');
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should be delivered');
    }

    @isTest
    static void testWhenSubscriptionWithNoAttemptNamesAnActionClassThatDoesNotExistThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByActionOfSubscriptionWithNoAttempt('TB_OutboxRelayTests.NoSuchAction');
    }

    @isTest
    static void testWhenSubscriptionWithNoAttemptNamesAClassThatIsNotAnActionThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByActionOfSubscriptionWithNoAttempt('TB_OutboxRelayTests.NotAnAfterRelayAction');
    }

    @isTest
    static void testWhenSubscriptionWithNoAttemptNamesAnActionWhoseConstructorThrowsThenTheRunIsNotStopped() {
        assertRunIsUnaffectedByActionOfSubscriptionWithNoAttempt('TB_OutboxRelayTests.UnbuildableAction');
    }

    /**
     * The subscription is still there when its message definition is missing, so the failed attempt
     * is one of that subscription's attempts and its action is told about it.
     */
    @isTest
    static void testWhenMessageDefinitionIsMissingThenTheSubscriptionsAfterRelayActionIsGivenTheFailedAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'billing_feed').After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        removeMessageDefinition(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'billing_feed' => new Set<Id>{ outbox.Id } },
            actionCallsBySubscription(),
            'The action should be called once with the attempt that failed for want of a definition'
        );
        TB_OutboxRelayContext attempt = TB_TransactionOutboxTestUtils.actionCalls[0][0];
        System.assert(!attempt.isComplete(), 'The attempt the action is given should be the failed one');
        System.assert(
            attempt.outbox.Last_Error_Message__c.contains('test.message1'),
            'The attempt should carry the reason it failed, but has: ' + attempt.outbox.Last_Error_Message__c
        );
        System.assertEquals(
            new List<Integer>{ 1 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The failed attempt should be stored before the action runs'
        );
    }

    /**
     * An outbox is tied to its subscription by name. After a rename no subscription has that name,
     * so the failed attempt belongs to no subscription. The renamed subscription takes the same
     * message type, but it had no attempt of its own and its action is not called.
     */
    @isTest
    static void testWhenSubscriptionIsRenamedThenItsAfterRelayActionIsNotCalledForTheOrphanedOutbox() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt renamed = addTestClientSubscription(app, msgDef, 'billing_feed');
        renamed.After_Relay_Action__c = RECORDING_ACTION;
        TB_Message_Definition__mdt healthyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed').After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(healthyDef) };
        renamed.DeveloperName = 'billing_feed_v2';
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals('billing_feed', outboxes[0].Subscription__c);
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted in the one run');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox under the old name should not be delivered');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'shipping_feed' => new Set<Id>{ outboxes[1].Id } },
            actionCallsBySubscription(),
            'Only the subscription that had an attempt of its own should have its action called'
        );
    }

    /**
     * Settings that cannot be read fail an ordinary attempt for a subscription that exists,
     * so its action is told about that attempt like any other failure.
     */
    @isTest
    static void testWhenSubscriptionSettingsAreMalformedThenItsAfterRelayActionIsGivenTheFailedAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = addTestClientSubscription(app, msgDef, 'billing_feed');
        faulty.Config__c = MALFORMED_SETTINGS;
        faulty.After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertEquals(
            new Map<String, Set<Id>>{ 'billing_feed' => new Set<Id>{ outbox.Id } },
            actionCallsBySubscription(),
            'The action should be called once with the attempt that failed on the settings'
        );
        TB_OutboxRelayContext attempt = TB_TransactionOutboxTestUtils.actionCalls[0][0];
        System.assert(!attempt.isComplete(), 'The attempt the action is given should be the failed one');
        System.assert(
            attempt.outbox.Last_Error_Message__c.contains('Config__c'),
            'The attempt should carry the reason it failed, but has: ' + attempt.outbox.Last_Error_Message__c
        );
        System.assertEquals(
            new List<Integer>{ 1 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The failed attempt should be stored before the action runs'
        );
    }

    /**
     * Whether an action is built for a subscription that names none cannot be seen from a test, because
     * a failed build is caught and only written to the debug log. This checks what can be seen.
     */
    @isTest
    static void testWhenSubscriptionNamesNoAfterRelayActionThenItIsRelayedAndItsAttemptsGoToNoOtherAction() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'billing_feed').After_Relay_Action__c = null;
        addTestClientSubscription(app, msgDef, 'shipping_feed').After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted');
        for (TB_Subscription_Outbox__c outbox : outboxes) {
            System.assertNotEquals(
                null,
                outbox.Completed_Timestamp__c,
                'The outbox for ' + outbox.Subscription__c + ' should be delivered'
            );
        }
        System.assertEquals(
            new Map<String, Set<Id>>{ 'shipping_feed' => new Set<Id>{ outboxes[1].Id } },
            actionCallsBySubscription(),
            'Only the subscription that names an action should have one called, with only its own attempt'
        );
    }

    static final String RECORDING_RESOLVER = 'TB_TransactionOutboxTestUtils.RecordingResolver';

    static TB_Message_Definition__mdt addRecordingResolverDefinition(String type) {
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition(type);
        msgDef.Message_Resolver__c = RECORDING_RESOLVER;
        return msgDef;
    }

    // Each message in these tests has its own payload, so a payload says which message a resolver was given.
    static TB_Outbox_Message__c newMessage(TB_Message_Definition__mdt msgDef, String payload) {
        return new TB_Outbox_Message__c(Type__c = msgDef.DeveloperName, Message__c = payload);
    }

    static TB_Outbox_Message__c newGroupedMessage(TB_Message_Definition__mdt msgDef, String groupId, String payload) {
        TB_Outbox_Message__c message = newMessage(msgDef, payload);
        message.Group_Id__c = groupId;
        return message;
    }

    /**
     * The payloads of the messages each call to the recording resolver was given, by message type.
     * A message type whose resolver was not called has no entry.
     *
     * The payloads are sorted, because a resolver is given its messages in no promised order.
     * A message passed twice in one call appears twice.
     *
     * A resolver exists to resolve messages that are being relayed, so a call that carries none is a
     * fault wherever it shows up. This fails on a call given null or an empty list, on a call that
     * mixes message types, and on a second call for one message type. It is for tests with one run.
     */
    static Map<String, List<String>> resolverCallsByType() {
        Integer callCount = TB_TransactionOutboxTestUtils.resolverCalls.size();
        Map<String, List<String>> payloadsByType = new Map<String, List<String>>();
        for (List<TB_Outbox_Message__c> call : TB_TransactionOutboxTestUtils.resolverCalls) {
            System.assertNotEquals(
                null,
                call,
                'A resolver should never be given null, but one of the ' + callCount + ' resolver calls was'
            );
            System.assert(
                !call.isEmpty(),
                'A resolver should never be called with no messages, but one of the ' + callCount + ' resolver calls was'
            );

            String messageType = call[0].Type__c;
            System.assert(
                !payloadsByType.containsKey(messageType),
                'The resolver for ' + messageType + ' should be called once in a run, with all of its messages together'
            );
            List<String> payloads = new List<String>();
            for (TB_Outbox_Message__c message : call) {
                System.assertEquals(
                    messageType,
                    message.Type__c,
                    'A resolver should be given messages of its own type and no other'
                );
                payloads.add(message.Message__c);
            }
            payloads.sort();
            payloadsByType.put(messageType, payloads);
        }
        return payloadsByType;
    }

    static void assertErrorIsTheResolverFailure(TB_Subscription_Outbox__c outbox) {
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The outbox should carry the resolver error, but has none');
        System.assert(
            outbox.Last_Error_Message__c.startsWith('Resolver Error'),
            'The outbox should carry the resolver error, but has: ' + outbox.Last_Error_Message__c
        );
    }

    // Each message has an outbox for each subscription, and the resolver works on messages, not outboxes.
    @isTest
    static void testWhenMessagesHaveTwoOutboxesInTheRunThenTheResolverIsGivenEachMessageOnce() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        addTestClientSubscription(app, msgDef, 'subscription2');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef, 'first'), newMessage(msgDef, 'second') };
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first', 'second' } },
            resolverCallsByType(),
            'The resolver should be called once and given each message once'
        );
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(
                null,
                outbox.Completed_Timestamp__c,
                'Every outbox of both messages should be delivered, but this one was not: ' + outbox.Subscription__c
            );
        }
        List<Object> sent = TB_TransactionOutboxTestUtils.sentMessages.clone();
        sent.sort();
        System.assertEquals(
            new List<Object>{ 'resolved:first', 'resolved:first', 'resolved:second', 'resolved:second' },
            sent,
            'Each outbox should be sent what the resolver returned for its message'
        );
    }

    // The message types are published alternately, so a call for each outbox or each message would show as several calls.
    @isTest
    static void testWhenRunHasTwoMessageTypesThenEachResolverIsCalledOnceWithItsOwnMessages() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt firstDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, firstDef, 'subscription1');
        TB_Message_Definition__mdt secondDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, secondDef, 'subscription2');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(firstDef, 'first'),
            newMessage(secondDef, 'second'),
            newMessage(firstDef, 'third'),
            newMessage(secondDef, 'fourth')
        };
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new Map<String, List<String>>{
                'test.message1' => new List<String>{ 'first', 'third' },
                'test.message2' => new List<String>{ 'fourth', 'second' }
            },
            resolverCallsByType(),
            'Each message type should be resolved in one call that holds all of its messages in the run'
        );
        System.assertEquals(new List<Integer>{ 1, 1, 1, 1 }, attemptsInOrder(), 'Every outbox should be attempted once');
        System.assertEquals(4, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Every outbox should be sent');
    }

    /**
     * An isolated outbox that is not the run's first attempt is passed over, whatever happens to the
     * attempts before it. A message with no other outbox in the run is then not being relayed, so it
     * must not reach the resolver, where it could fail the messages that are.
     *
     * A disabled subscription gets no new outboxes and its existing ones are still relayed. That is
     * how each message here comes to have an outbox for one subscription only.
     */
    @isTest
    static void testWhenIsolatedOutboxIsNotFirstThenItsMessageCannotFailTheResolutionOfAttemptedMessages() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt ordinary = addTestClientSubscription(app, msgDef, 'shipping_feed');

        Test.startTest();
        insert newMessage(msgDef, 'first');
        ordinary.Enabled__c = false;
        addTestClientSubscription(app, msgDef, 'isolated_feed').Isolate_Relay__c = true;
        insert newMessage(msgDef, TB_TransactionOutboxTestUtils.UNRESOLVABLE_PAYLOAD);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size(), 'Each message should have one outbox');
        System.assertEquals('shipping_feed', outboxes[0].Subscription__c, 'The ordinary outbox should be first in the run');
        System.assertEquals('isolated_feed', outboxes[1].Subscription__c, 'The isolated outbox should be second in the run');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first' } },
            resolverCallsByType(),
            'The resolver should be given the attempted message only'
        );
        System.assertEquals(new List<Integer>{ 1, 0 }, attemptsInOrder(), 'Only the ordinary outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The attempted message should be delivered');
        System.assertEquals(null, outboxes[0].Last_Error_Message__c, 'The attempted message should carry no error');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The message passed over should carry no error');
        System.assertEquals(
            new List<Object>{ 'resolved:first' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The attempted message should be sent as the resolver returned it'
        );
    }

    /**
     * After an isolated first attempt the run attempts nothing else. The isolated outbox's message is
     * still resolved, and a message behind it with no attempted outbox must not reach the resolver.
     */
    @isTest
    static void testWhenIsolatedOutboxIsFirstThenMessagesAfterItCannotFailItsResolution() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt isolated = addTestClientSubscription(app, msgDef, 'isolated_feed');
        isolated.Isolate_Relay__c = true;

        Test.startTest();
        insert newMessage(msgDef, 'first');
        isolated.Enabled__c = false;
        addTestClientSubscription(app, msgDef, 'shipping_feed');
        insert newMessage(msgDef, TB_TransactionOutboxTestUtils.UNRESOLVABLE_PAYLOAD);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size(), 'Each message should have one outbox');
        System.assertEquals('isolated_feed', outboxes[0].Subscription__c, 'The isolated outbox should be first in the run');
        System.assertEquals('shipping_feed', outboxes[1].Subscription__c, 'The ordinary outbox should be second in the run');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first' } },
            resolverCallsByType(),
            'The resolver should be given the isolated outbox\'s message only'
        );
        System.assertEquals(new List<Integer>{ 1, 0 }, attemptsInOrder(), 'Only the isolated outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The isolated outbox should be delivered');
        System.assertEquals(null, outboxes[0].Last_Error_Message__c, 'The isolated outbox should carry no error');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The message passed over should carry no error');
        System.assertEquals(
            new List<Object>{ 'resolved:first' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The isolated outbox should be sent as the resolver returned it'
        );
    }

    /**
     * An outbox whose subscription is missing fails its attempt without being sent, so its message is
     * never resolved for it. A message with no other outbox in the run must not reach the resolver.
     */
    @isTest
    static void testWhenSubscriptionIsMissingThenItsMessageCannotFailTheResolutionOfAttemptedMessages() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, msgDef, 'billing_feed');

        // The second subscription is added after the first message is published, so the first message
        // only has an outbox for the subscription that is then taken away.
        Test.startTest();
        insert newMessage(msgDef, TB_TransactionOutboxTestUtils.UNRESOLVABLE_PAYLOAD);
        removeSubscription(removed);
        addTestClientSubscription(app, msgDef, 'shipping_feed');
        insert newMessage(msgDef, 'second');
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size(), 'Each message should have one outbox');
        System.assertEquals('billing_feed', outboxes[0].Subscription__c, 'The outbox with no subscription should be first');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'second' } },
            resolverCallsByType(),
            'The resolver should be given the message that is sent and not the one that cannot be'
        );
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should have an attempt counted');
        System.assert(
            outboxes[0].Last_Error_Message__c.contains('billing_feed'),
            'The first outbox should fail for its missing subscription, but has: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The message with a subscription should be delivered');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The delivered message should carry no error');
        System.assertEquals(
            new List<Object>{ 'resolved:second' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The delivered message should be sent as the resolver returned it'
        );
    }

    // No message of the isolated subscription's type is being relayed in this run, so there is nothing to ask its resolver.
    @isTest
    static void testWhenIsolatedOutboxIsNotFirstAndIsTheOnlyOneOfItsTypeThenThatTypesResolverIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt ordinaryDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, ordinaryDef, 'shipping_feed');
        TB_Message_Definition__mdt isolatedDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(ordinaryDef, 'first'), newMessage(isolatedDef, 'second') };
        stopTestExpectingNoFailedJob();

        System.assertEquals(new List<Integer>{ 1, 0 }, attemptsInOrder(), 'Only the ordinary outbox should be attempted');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first' } },
            resolverCallsByType(),
            'Only the attempted message\'s resolver should be called'
        );
    }

    @isTest
    static void testWhenIsolatedOutboxIsFirstThenResolversOfLaterMessageTypesAreNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt isolatedDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt ordinaryDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, ordinaryDef, 'shipping_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(isolatedDef, 'first'), newMessage(ordinaryDef, 'second') };
        stopTestExpectingNoFailedJob();

        System.assertEquals(new List<Integer>{ 1, 0 }, attemptsInOrder(), 'Only the isolated outbox should be attempted');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first' } },
            resolverCallsByType(),
            'Only the isolated outbox\'s resolver should be called'
        );
        System.assertEquals(
            new List<Object>{ 'resolved:first' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'The isolated outbox should be sent as the resolver returned it'
        );
    }

    @isTest
    static void testWhenSubscriptionIsMissingForTheOnlyOutboxOfItsTypeThenThatTypesResolverIsNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt orphanedDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, orphanedDef, 'billing_feed');
        TB_Message_Definition__mdt healthyDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(orphanedDef, 'first'), newMessage(healthyDef, 'second') };
        removeSubscription(removed);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should have an attempt counted');
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message2' => new List<String>{ 'second' } },
            resolverCallsByType(),
            'Only the resolver of the message that is sent should be called'
        );
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The message with a subscription should be delivered');
    }

    // The failed attempt of the outbox with no subscription is one of the run's attempts, so the isolated outbox is not first.
    @isTest
    static void testWhenSubscriptionIsMissingAheadOfAnIsolatedOutboxThenNoResolverIsCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt orphanedDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, orphanedDef, 'billing_feed');
        TB_Message_Definition__mdt isolatedDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(orphanedDef, 'first'), newMessage(isolatedDef, 'second') };
        removeSubscription(removed);
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The missing subscription should fail one attempt and the isolated outbox should be passed over'
        );
        System.assertEquals(
            new Map<String, List<String>>(),
            resolverCallsByType(),
            'Nothing is sent in this run, so no resolver should be called'
        );
    }

    // The isolated subscription is still there, so its failed attempt ends what the run attempts.
    @isTest
    static void testWhenIsolatedSubscriptionHasNoDefinitionThenResolversOfLaterMessageTypesAreNotCalled() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, removed, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt healthyDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removed, 'first'), newMessage(healthyDef, 'second') };
        removeMessageDefinition(removed);
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The isolated outbox should fail one attempt and the healthy one should be passed over'
        );
        System.assertEquals(
            new Map<String, List<String>>(),
            resolverCallsByType(),
            'Nothing is sent in this run, so no resolver should be called'
        );
    }

    /**
     * An outbox without configuration always fails its attempt, so before any attempt is made the run
     * can tell that the later messages in its group will be held.
     */
    @isTest
    static void testWhenGroupIsHeldByAnOutboxWithNoSubscriptionThenLaterMessagesInTheGroupAreNotGivenToTheResolver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt orphanedDef = addRecordingResolverDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, orphanedDef, 'billing_feed');
        TB_Message_Definition__mdt healthyDef = addRecordingResolverDefinition('test.message2');
        addTestClientSubscription(app, healthyDef, 'shipping_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(orphanedDef, 'group1', 'first'),
            newGroupedMessage(healthyDef, 'group1', 'second')
        };
        removeSubscription(removed);
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The first message should fail one attempt and the later one in its group should not be attempted'
        );
        System.assertEquals(
            new Map<String, List<String>>(),
            resolverCallsByType(),
            'Nothing is sent in this run, so no resolver should be called'
        );
    }

    /**
     * An isolated outbox that is not first is always passed over, and it holds the messages after it
     * in its group. The run can tell both before any attempt is made.
     */
    @isTest
    static void testWhenGroupIsHeldByAnIsolatedOutboxThatIsNotFirstThenLaterMessagesInTheGroupAreNotGivenToTheResolver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt ordinaryDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, ordinaryDef, 'shipping_feed');
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, isolatedDef, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt heldDef = addRecordingResolverDefinition('test.message3');
        addTestClientSubscription(app, heldDef, 'billing_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(ordinaryDef, 'first'),
            newGroupedMessage(isolatedDef, 'group1', 'second'),
            newGroupedMessage(heldDef, 'group1', 'third')
        };
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 1, 0, 0 },
            attemptsInOrder(),
            'Only the ungrouped outbox should be attempted. The isolated one is passed over and holds its group'
        );
        System.assertEquals(
            new Map<String, List<String>>(),
            resolverCallsByType(),
            'The held message is not sent in this run, so its resolver should not be called'
        );
    }

    /**
     * Giving the held message to the resolver is not wanted for its own sake. It follows from how
     * resolvers are called. The second message is held only because the first one's send fails, and
     * the run cannot know that before it attempts the send. A resolver is called once per run, before
     * any attempt, so the second message is given to it with the first and is then not sent.
     */
    @isTest
    static void testWhenGroupIsHeldByAFailedSendThenTheResolverWasStillGivenTheLaterMessagesInTheGroup() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1').Config__c = '{"throwError":true}';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1', 'first'),
            newGroupedMessage(msgDef, 'group1', 'second')
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 0 },
            attemptsInOrder(),
            'The first message should fail one attempt and the later one in its group should not be attempted'
        );
        System.assert(
            outboxes[0].Last_Error_Message__c.startsWith('Test Error'),
            'The first message should fail in the relay client, but has: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first', 'second' } },
            resolverCallsByType(),
            'Both messages could be attempted when the run started, so both should be resolved together'
        );
        System.assertEquals(
            new List<Object>{ 'resolved:first' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'Only the first message should be sent. The held one should not reach the client'
        );
    }

    /**
     * Before any attempt, the run plans for each send failing, but a send that could fail is not a
     * hold. Every message in the group is attempted when every send succeeds, so each must have
     * been given to the resolver.
     */
    @isTest
    static void testWhenEverySendInAGroupSucceedsThenEachMessageInTheGroupIsSentResolved() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1', 'first'),
            newGroupedMessage(msgDef, 'group1', 'second'),
            newGroupedMessage(msgDef, 'group1', 'third')
        };
        stopTestExpectingNoFailedJob();

        System.assertEquals(new List<Integer>{ 1, 1, 1 }, attemptsInOrder(), 'Every message in the group should be attempted once');
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(
                null,
                outbox.Completed_Timestamp__c,
                'Every message in the group should be delivered, but one carries: ' + outbox.Last_Error_Message__c
            );
        }
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'first', 'second', 'third' } },
            resolverCallsByType(),
            'The resolver should be called once and given each message in the group once'
        );
        System.assertEquals(
            new List<Object>{ 'resolved:first', 'resolved:second', 'resolved:third' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'Each message should be sent as the resolver returned it'
        );
    }

    /**
     * An isolated subscription's outbox with no message definition ends what the run attempts, but
     * only if the run reaches it. Here it is in a group behind a send that fails, so the group holds
     * it and the run goes on to the ungrouped message after it. The run cannot know before attempting
     * that the send will fail, so that later message must have been given to its resolver.
     */
    @isTest
    static void testWhenAnIsolatedOutboxWithNoDefinitionIsHeldByAFailedSendThenTheMessageAfterItIsSentResolved() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt failingDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, failingDef, 'billing_feed').Config__c = '{"throwError":true}';
        TB_Message_Definition__mdt removed = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, removed, 'isolated_feed').Isolate_Relay__c = true;
        TB_Message_Definition__mdt laterDef = addRecordingResolverDefinition('test.message3');
        addTestClientSubscription(app, laterDef, 'shipping_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(failingDef, 'group1', 'first'),
            newGroupedMessage(removed, 'group1', 'second'),
            newMessage(laterDef, 'third')
        };
        removeMessageDefinition(removed);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(3, outboxes.size(), 'Each message should have one outbox');
        System.assertEquals('billing_feed', outboxes[0].Subscription__c, 'The failing outbox should be first in the run');
        System.assertEquals('isolated_feed', outboxes[1].Subscription__c, 'The isolated outbox should be second in the run');
        System.assertEquals('shipping_feed', outboxes[2].Subscription__c, 'The ungrouped outbox should be last in the run');
        System.assertEquals(
            new List<Integer>{ 1, 0, 1 },
            attemptsInOrder(),
            'The first send should fail, the isolated outbox should be held by it, and the last outbox should be attempted'
        );
        System.assert(
            outboxes[0].Last_Error_Message__c.startsWith('Test Error'),
            'The first message should fail in the relay client, but has: ' + outboxes[0].Last_Error_Message__c
        );
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'The held outbox should carry no error');
        System.assertNotEquals(null, outboxes[2].Completed_Timestamp__c, 'The last message should be delivered');
        System.assertEquals(null, outboxes[2].Last_Error_Message__c, 'The last message should carry no error');
        System.assertEquals(
            new Map<String, List<String>>{
                'test.message1' => new List<String>{ 'first' },
                'test.message3' => new List<String>{ 'third' }
            },
            resolverCallsByType(),
            'Each sent message should be given to its type\'s resolver'
        );
        System.assertEquals(
            new List<Object>{ 'resolved:first', 'resolved:third' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'Each sent message should be sent as its resolver returned it'
        );
    }

    // A group that was already held when the run started is known to be held, so its messages are not resolved.
    @isTest
    static void testWhenGroupIsHeldBeforeTheRunStartsThenItsMessagesAreNotGivenToTheResolver() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newGroupedMessage(msgDef, 'group1', 'first'),
            newGroupedMessage(msgDef, 'group1', 'second'),
            newMessage(msgDef, 'third')
        };
        makeOutboxWaitOnBackoff(0);
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 0, 0, 1 },
            attemptsInOrder(),
            'The run should pass over the held group and attempt the outbox behind it'
        );
        System.assertEquals(
            new Map<String, List<String>>{ 'test.message1' => new List<String>{ 'third' } },
            resolverCallsByType(),
            'The resolver should be given the attempted message only'
        );
    }

    /**
     * One message that cannot be resolved fails the whole call, so every outbox of every message in
     * that call fails its attempt. Another message type has its own call and is not affected.
     */
    @isTest
    static void testWhenResolverFailsThenEveryOutboxOfEveryMessageItWasGivenFailsAndOtherTypesAreDelivered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt failingDef = addRecordingResolverDefinition('test.message1');
        addTestClientSubscription(app, failingDef, 'subscription1');
        addTestClientSubscription(app, failingDef, 'subscription2');
        TB_Message_Definition__mdt workingDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        workingDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.TestResolver';
        addTestClientSubscription(app, workingDef, 'subscription3');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(failingDef, 'first'),
            newMessage(failingDef, TB_TransactionOutboxTestUtils.UNRESOLVABLE_PAYLOAD),
            newMessage(workingDef, 'third')
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(5, outboxes.size(), 'The failing type should have four outboxes and the working type one');
        System.assertEquals(
            new List<Integer>{ 1, 1, 1, 1, 1 },
            attemptsInOrder(),
            'A resolver failure should count as an attempt for every outbox it fails'
        );
        for (Integer i = 0; i < 4; i++) {
            System.assertEquals(
                null,
                outboxes[i].Completed_Timestamp__c,
                'The outbox at position ' + i + ' should not be delivered, because its message was in the failed call'
            );
            assertErrorIsTheResolverFailure(outboxes[i]);
        }
        System.assertNotEquals(null, outboxes[4].Completed_Timestamp__c, 'The other message type should be delivered');
        System.assertEquals(null, outboxes[4].Last_Error_Message__c, 'The other message type should carry no error');
        System.assertEquals(
            new List<Object>{ 'resolved:third' },
            TB_TransactionOutboxTestUtils.sentMessages,
            'Only the other message type should reach the client'
        );
    }

    static final String DECLARED_COST_CLIENT = 'TB_TransactionOutboxTestUtils.DeclaredCostClient';

    static TB_Message_Subscription__mdt addDeclaredCostSubscription(
        TB_Application__mdt app,
        TB_Message_Definition__mdt msgDef,
        String name,
        TB_SendCost cost
    ) {
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, name);
        subscription.Relay_Client__c = DECLARED_COST_CLIENT;
        subscription.Config__c = JSON.serialize(new Map<String, Object>{ 'cost' => cost });
        return subscription;
    }

    static void assertOutboxIsUntouched(TB_Subscription_Outbox__c outbox, String why) {
        System.assertEquals(0, outbox.Relay_Attempts__c, why + ' It should not be charged an attempt.');
        System.assertEquals(null, outbox.Last_Attempt__c, why + ' No attempt time should be recorded.');
        System.assertEquals(null, outbox.Last_Error_Message__c, why + ' It should get no error.');
        System.assertEquals(null, outbox.Next_Attempt_Timestamp__c, why + ' It should get no wait.');
        System.assertEquals(null, outbox.Completed_Timestamp__c, why + ' It should not be delivered.');
        System.assertEquals(false, outbox.Dead_Lettered__c, why + ' It should not be dead-lettered.');
    }

    /**
     * One send that needs more of a limit than any transaction is allowed can never fit, whatever
     * the run has used. The outbox ahead of it is affordable, so the run has an outcome to save, and
     * the costly one is not the run's first attempt, which is not checked for room.
     */
    static void assertOutboxIsPassedOverWhenOneSendNeeds(String field, Integer amount) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'affordable_feed');
        // A backoff, so a wait would show if the outbox were failed instead of passed over.
        addDeclaredCostSubscription(
                app,
                msgDef,
                'costly_feed',
                TB_TransactionOutboxTestUtils.sendCostWith(field, amount)
            )
            .Retry_BackOff__c = '30';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The affordable outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The outcome of the attempt the run made should be saved');
        assertOutboxIsUntouched(
            outboxes[1],
            'The run has no room for a send that declares ' + amount + ' ' + field + '.'
        );
        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'Only the affordable outbox should reach its client'
        );
    }

    @isTest
    static void testWhenOneSendNeedsMoreCalloutsThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('callouts', 101);
    }

    @isTest
    static void testWhenOneSendNeedsMoreCalloutTimeThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('calloutTimeMs', 120001);
    }

    @isTest
    static void testWhenOneSendNeedsMoreQueriesThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('queries', 201);
    }

    @isTest
    static void testWhenOneSendNeedsMoreQueryRowsThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('queryRows', 50001);
    }

    @isTest
    static void testWhenOneSendNeedsMoreDmlStatementsThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('dmlStatements', 151);
    }

    @isTest
    static void testWhenOneSendNeedsMoreDmlRowsThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('dmlRows', 10001);
    }

    @isTest
    static void testWhenOneSendNeedsMoreEventPublishesThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('eventPublishes', 151);
    }

    @isTest
    static void testWhenOneSendNeedsMoreCpuTimeThanARunHasThenOutboxIsPassedOverUntouched() {
        assertOutboxIsPassedOverWhenOneSendNeeds('cpuTimeMs', 60001);
    }

    @isTest
    static void testWhenOneSendNeedsMoreHeapThanARunHasThenOutboxIsPassedOverUntouched() {
        // The heap a transaction is allowed differs between orgs, so this is far above any of them.
        assertOutboxIsPassedOverWhenOneSendNeeds('heapBytes', 1000000000);
    }

    static TB_SendCost moreCalloutsThanARunHas() {
        return TB_TransactionOutboxTestUtils.sendCostWith('callouts', 101);
    }

    /**
     * A run that could attempt nothing would leave everything as it was, and be queued again in the
     * same state. So a run always starts its first attempt, whatever the send declares.
     */
    @isTest
    static void testWhenTheOnlyOutboxNeedsMoreThanARunHasThenItIsStillAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(app, msgDef, 'costly_feed', moreCalloutsThanARunHas());

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The run\'s first attempt should start without a room check');
        System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'The send went through, so it should be delivered');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The client should be called once');
    }

    /**
     * An outbox failed for missing configuration starts no send, so it does not use up the run's
     * first attempt. The first outbox that can be sent still gets it.
     */
    @isTest
    static void testWhenFirstSendableOutboxNeedsMoreThanARunHasThenItIsStillAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt removedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt removed = addTestClientSubscription(app, removedDef, 'billing_feed');
        TB_Message_Definition__mdt costlyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addDeclaredCostSubscription(app, costlyDef, 'costly_feed', moreCalloutsThanARunHas());

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(removedDef), newMessage(costlyDef) };
        removeSubscription(removed);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1 }, attemptsInOrder(), 'Both outboxes should be attempted');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with no subscription should not be delivered');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The costly outbox should be delivered');
    }

    /** The first attempt is not checked for room, and once started it ends like any other attempt. */
    @isTest
    static void testWhenFirstAttemptNeedsMoreThanARunHasAndItsResolverFailedThenTheFailureIsRecorded() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        addDeclaredCostSubscription(app, msgDef, 'costly_feed', moreCalloutsThanARunHas()).Retry_BackOff__c = '30';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The resolver failure should be recorded');
        System.assert(
            outbox.Last_Error_Message__c.contains('Resolver Error'),
            'The error should be the resolver failure, but is: ' + outbox.Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outbox, 30, 'A failed attempt should wait on its subscription\'s backoff.');
    }

    /** Only the first attempt goes ahead without room. Every outbox after it is checked. */
    @isTest
    static void testWhenLaterOutboxesNeedMoreThanARunHasThenTheyArePassedOverAfterTheFirstAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(app, msgDef, 'a_costly_feed', moreCalloutsThanARunHas());
        addDeclaredCostSubscription(app, msgDef, 'b_costly_feed', moreCalloutsThanARunHas()).Retry_BackOff__c = '30';
        addDeclaredCostSubscription(app, msgDef, 'c_costly_feed', moreCalloutsThanARunHas()).Retry_BackOff__c = '30';
        addTestClientSubscription(app, msgDef, 'd_affordable_feed');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The run\'s first attempt should start without a room check');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first attempt should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run has no room for a second costly send.');
        assertOutboxIsUntouched(outboxes[2], 'The run has no room for a third costly send.');
        System.assertNotEquals(null, outboxes[3].Completed_Timestamp__c, 'The affordable outbox should still be delivered');
        System.assertEquals(2, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only two outboxes should reach a client');
    }

    /**
     * Every send declares more than a run can have. Each run attempts one outbox, its first, so the
     * backlog shrinks by one per run and the runs end when nothing is left.
     */
    @isTest
    static void testWhenEverySendNeedsMoreThanARunHasThenEachRunAttemptsOneAndTheRunsEnd() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(app, msgDef, 'costly_feed', moreCalloutsThanARunHas());

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        System.assertEquals(
            new List<Integer>{ 1, 1 },
            attemptsInOrder(),
            'Each of the two runs should attempt one outbox'
        );
        System.assertEquals(2, relayJobCount(), 'The first run should queue a second for the outbox it passed over');
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'Every outbox should be delivered across the two runs');
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM TB_Subscription_Outbox__c WHERE Completed_Timestamp__c = NULL],
            'No outbox should be left due, so no further run is queued'
        );
    }

    /**
     * An isolated outbox at the front of the run is the run's first attempt, so it is attempted even
     * when it declares more than the run has. The outbox behind it is passed over for isolation.
     */
    @isTest
    static void testWhenIsolatedOutboxAtTheFrontNeedsMoreThanARunHasThenItIsAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(app, msgDef, 'a_isolated_feed', moreCalloutsThanARunHas()).Isolate_Relay__c = true;
        addTestClientSubscription(app, msgDef, 'b_affordable_feed');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The isolated outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The isolated outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run attempts nothing after an isolated outbox.');
    }

    /**
     * The first attempt skips only the room check. A cost declaration that cannot be used still fails
     * a counted attempt, and starts no send, so the next outbox is the first to start one.
     */
    @isTest
    static void testWhenFirstOutboxHasAnUnusableCostThenTheNextIsAttemptedWithoutARoomCheck() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'a_faulty_feed');
        faulty.Relay_Client__c = DECLARED_COST_CLIENT;
        faulty.Config__c = '{}';
        faulty.Retry_BackOff__c = '25';
        addDeclaredCostSubscription(app, msgDef, 'b_costly_feed', moreCalloutsThanARunHas());
        addDeclaredCostSubscription(app, msgDef, 'c_costly_feed', moreCalloutsThanARunHas());

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The attempt with the unusable cost should be counted');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox with the unusable cost should not be delivered');
        System.assert(
            outboxes[0].Last_Error_Message__c != null && outboxes[0].Last_Error_Message__c.contains(DECLARED_COST_CLIENT),
            'The error should name the relay client, but is: ' + outboxes[0].Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outboxes[0], 25, 'The outbox should wait on its subscription\'s backoff.');
        System.assertEquals(1, outboxes[1].Relay_Attempts__c, 'The first outbox to start a send should not be checked for room');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The first outbox to start a send should be delivered');
        assertOutboxIsUntouched(outboxes[2], 'The run has no room for a second costly send.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only one outbox should reach its client');
    }

    /**
     * The first attempt is used up once a send starts, whether or not it is delivered. After a send
     * that failed, the next outbox is checked for room like any other.
     */
    @isTest
    static void testWhenFirstSendStartsAndFailsThenTheNextOutboxIsCheckedForRoom() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt failing = addTestClientSubscription(app, msgDef, 'a_failing_feed');
        failing.Config__c = '{"throwError":true}';
        failing.Retry_BackOff__c = '25';
        // A backoff, so a wait would show if the outbox were failed instead of passed over.
        addDeclaredCostSubscription(app, msgDef, 'b_costly_feed', moreCalloutsThanARunHas()).Retry_BackOff__c = '30';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The failed send should be counted');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The failed send should not be delivered');
        System.assert(
            outboxes[0].Last_Error_Message__c != null && outboxes[0].Last_Error_Message__c.contains('Test Error'),
            'The error should be the client failure, but is: ' + outboxes[0].Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outboxes[0], 25, 'The failed send should wait on its subscription\'s backoff.');
        assertOutboxIsUntouched(outboxes[1], 'The run has no room for the costly send after a send has started.');
        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'Only the failing outbox should reach its client'
        );
    }

    /** An abandoned first attempt ends the run like any abandoned attempt. */
    @isTest
    static void testWhenFirstAttemptNeedsMoreThanARunHasAndHitsTheCalloutTimeLimitThenNothingMoreIsStarted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt limitDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(app, limitDef, 'costly_feed', moreCalloutsThanARunHas()).Retry_BackOff__c = '30';
        TB_Message_Definition__mdt otherDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, otherDef, 'other_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(limitDef, TB_TransactionOutboxTestUtils.CALLOUT_TIME_LIMIT_PAYLOAD),
            newMessage(otherDef)
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertNotEquals(null, outboxes[0].Last_Attempt__c, 'The first attempt should have started');
        System.assertEquals(0, outboxes[0].Relay_Attempts__c, 'An attempt that hit a run limit should not be counted');
        System.assertEquals(null, outboxes[0].Last_Error_Message__c, 'No error should be recorded against the outbox');
        System.assertEquals(null, outboxes[0].Next_Attempt_Timestamp__c, 'No wait should be added');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should not be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run reached a limit before this outbox\'s turn.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the abandoned attempt should reach a client');
    }

    /**
     * Each outbox is judged on its own cost when its turn comes. One that does not fit does not end
     * the run for a later one that does. An affordable outbox goes first, because a run's first
     * attempt is not checked for room.
     */
    @isTest
    static void testWhenOutboxWithNoRoomIsAheadOfOneWithRoomThenTheLaterOneIsStillAttempted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'a_affordable_feed');
        addDeclaredCostSubscription(
            app,
            msgDef,
            'b_costly_feed',
            TB_TransactionOutboxTestUtils.sendCostWith('callouts', 101)
        );
        addTestClientSubscription(app, msgDef, 'c_affordable_feed');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first affordable outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run has no room for the costly send.');
        System.assertEquals(1, outboxes[2].Relay_Attempts__c, 'The affordable outbox behind it should be attempted');
        System.assertNotEquals(null, outboxes[2].Completed_Timestamp__c, 'The affordable outbox behind it should be delivered');
    }

    /**
     * An outbox passed over for lack of room is still undelivered, so the messages after it in its
     * group wait for it, even when the run has room for them. An affordable message goes first,
     * because a run's first attempt is not checked for room.
     */
    @isTest
    static void testWhenGroupedOutboxIsPassedOverForLackOfRoomThenLaterMessagesInItsGroupAreHeld() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt firstDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message0');
        addTestClientSubscription(app, firstDef, 'first_feed');
        TB_Message_Definition__mdt costlyDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addDeclaredCostSubscription(
            app,
            costlyDef,
            'costly_feed',
            TB_TransactionOutboxTestUtils.sendCostWith('callouts', 101)
        );
        TB_Message_Definition__mdt affordableDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, affordableDef, 'affordable_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(firstDef),
            newGroupedMessage(costlyDef, 'group1'),
            newGroupedMessage(affordableDef, 'group1')
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run has no room for the costly send.');
        assertOutboxIsUntouched(outboxes[2], 'The message before it in its group was passed over.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the first outbox should be sent');
    }

    /**
     * The first send leaves too few queries for another, so the run stops there. It saves what it
     * did and queues the next run, which has all its queries again and takes one more outbox.
     */
    @isTest
    static void testWhenRunHasTooFewQueriesLeftThenItStopsAndTheNextRunTakesTheNextOutbox() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'query_feed')
            .Relay_Client__c = 'TB_TransactionOutboxTestUtils.QueryShareClient';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef), newMessage(msgDef) };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(
            new List<Integer>{ 1, 1, 0 },
            attemptsInOrder(),
            'Each of the two runs should attempt one outbox and pass over the rest'
        );
        System.assertEquals(2, relayJobCount(), 'The first run should queue a second for the outboxes it had no room for');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first run should save its delivery');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The second run should save its delivery');
        assertOutboxIsUntouched(outboxes[2], 'Neither run had room for a third send.');
    }

    @isTest
    static void testWhenRunHasTooLittleHeapLeftThenOutboxIsPassedOverUntouched() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'heap_feed')
            .Relay_Client__c = 'TB_TransactionOutboxTestUtils.HeapShareClient';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The first outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The first send left too little heap for a second.');
    }

    /**
     * The platform does not report how much callout time a transaction has used, so the run has to
     * keep count. Here one send takes over a second of it, which leaves less than the next declares.
     */
    @isTest
    static void testWhenRunHasTooLittleCalloutTimeLeftThenOutboxIsPassedOverUntouched() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'slow_feed')
            .Relay_Client__c = 'TB_TransactionOutboxTestUtils.SlowCalloutClient';
        Test.setMock(
            HttpCalloutMock.class,
            new TB_TransactionOutboxTestUtils.TestSubscriber(TB_TransactionOutboxTestUtils.SLOW_ANSWER_MS)
        );

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(msgDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The first outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The first send left too little callout time for a second.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.subscriberRequests, 'The subscriber should be called once');
    }

    /**
     * A transaction allows 100 callouts. The shipped HTTP client declares one per send, so a run
     * with more outboxes than that has to stop by itself instead of failing at the 101st.
     */
    @isTest
    static void testWhenBacklogNeedsMoreCalloutsThanARunHasThenTheRunStopsWithoutAFailedJob() {
        // Above the callout limit, so the batch size is not what stops the run.
        setRelayBatchSize(150);
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'http_feed');
        subscription.Relay_Client__c = 'TB_GenericHttpRelayClient';
        subscription.Config__c = '{"uri": "https://subscriber.example.com/messages"}';
        Test.setMock(HttpCalloutMock.class, new TB_TransactionOutboxTestUtils.TestSubscriber(0));

        List<TB_Outbox_Message__c> messages = new List<TB_Outbox_Message__c>();
        for (Integer i = 0; i < 101; i++) {
            messages.add(newMessage(msgDef));
        }

        Test.startTest();
        insert messages;
        stopTestExpectingNoFailedJob();

        Integer attempted = 0;
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            if (outbox.Relay_Attempts__c == 0) {
                assertOutboxIsUntouched(outbox, 'The run had no room for this outbox.');
            } else {
                attempted++;
                System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'Every attempt the run made should be saved as delivered');
            }
        }
        // The bodies are small and the subscriber answers at once, so callouts run out before any
        // other limit does.
        System.assertEquals(100, attempted, 'The run should stop when its 100 callouts are used');
        System.assertEquals(
            attempted,
            TB_TransactionOutboxTestUtils.subscriberRequests,
            'Each attempt should reach the subscriber once'
        );
    }

    /**
     * Sets up one subscription whose client's cost declaration cannot be used, ahead of a working
     * one, and runs the relay. A declaration that cannot be used is the client's fault, so it is
     * treated like any other client fault: that one attempt fails and is counted, nothing is sent
     * for it, the outbox waits on its backoff, and the run carries on.
     * Returns the outbox of the faulty subscription.
     */
    static TB_Subscription_Outbox__c relayWithACostDeclarationThatCannotBeUsed(String relayClient, String settings) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt faulty = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'faulty_feed');
        faulty.Relay_Client__c = relayClient;
        faulty.Config__c = settings;
        faulty.Retry_BackOff__c = '25';
        addTestClientSubscription(app, msgDef, 'working_feed');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The attempt should be counted');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertNotEquals(null, outboxes[0].Last_Error_Message__c, 'The reason should be recorded on the outbox');
        assertNextAttemptIsInMinutes(outboxes[0], 25, 'The outbox should wait on its subscription\'s backoff.');
        System.assertNotEquals(null, outboxes[1].Completed_Timestamp__c, 'The other subscription should still be delivered');
        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'Only the working subscription should reach its client'
        );
        return outboxes[0];
    }

    /**
     * A cost field left unset does not mean the send uses none of that limit, so the run cannot
     * tell whether the send fits. One subscription per field, all in one run.
     */
    @isTest
    static void testWhenDeclaredCostLeavesAFieldUnsetThenOneAttemptFailsNamingTheClientAndTheField() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        for (String field : TB_TransactionOutboxTestUtils.SEND_COST_FIELDS) {
            addDeclaredCostSubscription(
                    app,
                    msgDef,
                    'unset_' + field,
                    TB_TransactionOutboxTestUtils.sendCostWith(field, null)
                )
                .Retry_BackOff__c = '25';
        }
        addTestClientSubscription(app, msgDef, 'working_feed');

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(10, outboxes.size(), 'There should be one outbox per cost field and one for the working subscription');
        for (TB_Subscription_Outbox__c outbox : outboxes) {
            if (outbox.Subscription__c == 'working_feed') {
                System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'The working subscription should still be delivered');
                continue;
            }
            String field = outbox.Subscription__c.removeStart('unset_');
            System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted when ' + field + ' is unset');
            System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered when ' + field + ' is unset');
            System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason should be recorded when ' + field + ' is unset');
            System.assert(
                outbox.Last_Error_Message__c.contains(DECLARED_COST_CLIENT),
                'The error should name the relay client, but is: ' + outbox.Last_Error_Message__c
            );
            System.assert(
                outbox.Last_Error_Message__c.contains(field),
                'The error should name the unset field ' + field + ', but is: ' + outbox.Last_Error_Message__c
            );
            assertNextAttemptIsInMinutes(outbox, 25, 'The outbox should wait on its subscription\'s backoff.');
        }
        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'Only the working subscription should reach its client'
        );
    }

    @isTest
    static void testWhenClientDeclaresNoCostThenOneAttemptFailsNamingTheClient() {
        TB_Subscription_Outbox__c outbox = relayWithACostDeclarationThatCannotBeUsed(DECLARED_COST_CLIENT, '{}');

        System.assert(
            outbox.Last_Error_Message__c.contains(DECLARED_COST_CLIENT),
            'The error should name the relay client, but is: ' + outbox.Last_Error_Message__c
        );
    }

    /**
     * A negative amount would add to what the run thinks it has left.
     */
    @isTest
    static void testWhenDeclaredCostHasANegativeFieldThenOneAttemptFailsNamingTheClientAndTheField() {
        TB_Subscription_Outbox__c outbox = relayWithACostDeclarationThatCannotBeUsed(
            DECLARED_COST_CLIENT,
            JSON.serialize(
                new Map<String, Object>{ 'cost' => TB_TransactionOutboxTestUtils.sendCostWith('queries', -1) }
            )
        );

        System.assert(
            outbox.Last_Error_Message__c.contains(DECLARED_COST_CLIENT),
            'The error should name the relay client, but is: ' + outbox.Last_Error_Message__c
        );
        System.assert(
            outbox.Last_Error_Message__c.contains('queries'),
            'The error should name the negative field, but is: ' + outbox.Last_Error_Message__c
        );
    }

    @isTest
    static void testWhenCostOfSendThrowsThenOneAttemptFailsAndTheRunCarriesOn() {
        TB_Subscription_Outbox__c outbox = relayWithACostDeclarationThatCannotBeUsed(
            'TB_TransactionOutboxTestUtils.ThrowingCostClient',
            null
        );

        System.assert(
            outbox.Last_Error_Message__c.contains('Cost Error'),
            'The error should say what the client raised, but is: ' + outbox.Last_Error_Message__c
        );
    }

    static TB_Message_Subscription__mdt addCalloutFaultSubscription(
        TB_Application__mdt app,
        TB_Message_Definition__mdt msgDef
    ) {
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'callout_feed');
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.CalloutFaultClient';
        return subscription;
    }

    /**
     * Running out of callout time is the run's doing and says nothing about the subscriber, so the
     * outbox it happened to is put back as it was. Every callout after it in the same run would
     * fail the same way, so the run starts nothing more.
     */
    @isTest
    static void testWhenSendHitsTheCalloutTimeLimitThenAttemptIsNotCountedAndNothingMoreIsStarted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        // A backoff, so a wait would show if the attempt were recorded as a failure.
        addCalloutFaultSubscription(app, msgDef).Retry_BackOff__c = '30';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(msgDef),
            newMessage(msgDef, TB_TransactionOutboxTestUtils.CALLOUT_TIME_LIMIT_PAYLOAD),
            newMessage(msgDef)
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The outbox before the limit should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The delivery made before the limit should be saved');

        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'An attempt that hit a run limit should not be counted');
        System.assertEquals(null, outboxes[1].Last_Error_Message__c, 'No error should be recorded against the outbox');
        System.assertEquals(null, outboxes[1].Next_Attempt_Timestamp__c, 'No wait should be added');
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertEquals(false, outboxes[1].Dead_Lettered__c, 'The outbox should not be dead-lettered');
        System.assertNotEquals(null, outboxes[1].Last_Attempt__c, 'The time the abandoned attempt started should be kept');

        assertOutboxIsUntouched(outboxes[2], 'The run reached a limit before this outbox\'s turn.');
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The client should not be called again after the limit was reached'
        );
    }

    /**
     * Running out of callout time is the run's doing, and the subscriber has not turned the message
     * down. Counting the attempt would dead-letter the message for a reason that has nothing to do
     * with the subscriber, so the outbox keeps its last attempt for a run that has room to make it.
     */
    @isTest
    static void testWhenLastAttemptHitsTheCalloutTimeLimitThenOutboxIsNotDeadLettered() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addCalloutFaultSubscription(app, msgDef).Retry_BackOff__c = '30';

        Test.startTest();
        insert newMessage(msgDef, TB_TransactionOutboxTestUtils.CALLOUT_TIME_LIMIT_PAYLOAD);
        // Two of its three attempts were used by earlier runs, and the second left an error.
        TB_Subscription_Outbox__c earlier = outboxesInOrder()[0];
        earlier.Relay_Attempts__c = 2;
        earlier.Last_Error_Message__c = 'Earlier failure';
        update earlier;
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(2, outbox.Relay_Attempts__c, 'The attempts used before this run should be all that is counted');
        System.assertEquals(false, outbox.Dead_Lettered__c, 'The outbox should keep its last attempt');
        System.assertEquals(
            'Earlier failure',
            outbox.Last_Error_Message__c,
            'The limit should not be recorded as an error against the outbox'
        );
        System.assertEquals(null, outbox.Next_Attempt_Timestamp__c, 'No wait should be added');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
    }

    @isTest
    static void testWhenAttemptWasAbandonedAtARunLimitThenTheNextRunTakesTheOutboxUpAgain() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addCalloutFaultSubscription(app, msgDef);

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(msgDef),
            newMessage(msgDef, TB_TransactionOutboxTestUtils.CALLOUT_TIME_LIMIT_PAYLOAD),
            newMessage(msgDef)
        };
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        System.assertEquals(2, relayJobCount(), 'The run that reached a limit should queue the next run');
        System.assertEquals(
            new List<Integer>{ 1, 1, 1 },
            attemptsInOrder(),
            'Only the attempts that were not abandoned should be counted'
        );
        for (TB_Subscription_Outbox__c outbox : outboxesInOrder()) {
            System.assertNotEquals(null, outbox.Completed_Timestamp__c, 'Every outbox should be delivered across the two runs');
            System.assertEquals(null, outbox.Last_Error_Message__c, 'No outbox should carry an error');
        }
    }

    /**
     * A subscriber that does not answer in time also fails with a callout error. That one is the
     * subscriber's failure, so it is charged as an attempt and the run carries on.
     */
    @isTest
    static void testWhenSendFailsWithAnOrdinaryCalloutErrorThenAttemptIsCountedAndTheRunCarriesOn() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addCalloutFaultSubscription(app, msgDef).Retry_BackOff__c = '30';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{
            newMessage(msgDef),
            newMessage(msgDef, TB_TransactionOutboxTestUtils.READ_TIMEOUT_PAYLOAD),
            newMessage(msgDef)
        };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(new List<Integer>{ 1, 1, 1 }, attemptsInOrder(), 'Every outbox should be attempted once');
        System.assertEquals(null, outboxes[1].Completed_Timestamp__c, 'The outbox whose subscriber did not answer should not be delivered');
        System.assertNotEquals(null, outboxes[1].Last_Error_Message__c, 'The failure should be recorded on the outbox');
        System.assert(
            outboxes[1].Last_Error_Message__c.contains(TB_TransactionOutboxTestUtils.READ_TIMEOUT_ERROR),
            'The error should be the subscriber\'s failure, but is: ' + outboxes[1].Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outboxes[1], 30, 'A failed attempt should wait on its subscription\'s backoff.');
        System.assertNotEquals(null, outboxes[2].Completed_Timestamp__c, 'The outbox after the failure should still be delivered');
    }

    /**
     * The run needs the relay client to know what a send costs, and it checks that before an attempt
     * starts. A failed resolution only fails an attempt that has started, so a client that cannot be
     * built is found first and is the reason given.
     */
    @isTest
    static void testWhenResolverFailsAndRelayClientCannotBeBuiltThenTheClientFailureIsRecorded() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        TB_Message_Subscription__mdt subscription = addTestClientSubscription(app, msgDef, 'billing_feed');
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.NoSuchClient';
        subscription.Retry_BackOff__c = '25';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(1, outbox.Relay_Attempts__c, 'The attempt should be counted once');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assert(
            outbox.Last_Error_Message__c.startsWith('TB_TransactionOutboxTestUtils.NoSuchClient does not exist'),
            'The outbox should carry the construction error, but has: ' + outbox.Last_Error_Message__c
        );
        assertNextAttemptIsInMinutes(outbox, 25, 'The outbox should wait on its subscription\'s backoff.');
    }

    /**
     * The room check comes before the attempt, and a failed resolution only fails an attempt that has
     * started. An outbox the run has no room for is passed over, whatever its resolver did. An
     * affordable message goes first, because a run's first attempt is not checked for room.
     */
    @isTest
    static void testWhenResolverFailsAndRunHasNoRoomForTheSendThenOutboxIsUntouched() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt firstDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message0');
        addTestClientSubscription(app, firstDef, 'first_feed');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        msgDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.ThrowingResolver';
        // A backoff, so a wait would show if the resolver failure were recorded.
        addDeclaredCostSubscription(
                app,
                msgDef,
                'costly_feed',
                TB_TransactionOutboxTestUtils.sendCostWith('callouts', 101)
            )
            .Retry_BackOff__c = '30';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(firstDef), newMessage(msgDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The first outbox should be delivered');
        assertOutboxIsUntouched(outboxes[1], 'The run has no room for the send.');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Only the first outbox should be sent');
    }

    /**
     * Relays one outbox whose client logs, asks for a next attempt time and replaces the TTL before
     * it runs out of callout time. With createdWithTtl the outbox gets a TTL of an hour when it is
     * created. Without it the outbox has no TTL until the client sets one.
     */
    static TB_Subscription_Outbox__c relayToAClientThatShapesItsOutcomeThenHitsTheCalloutTimeLimit(
        Boolean createdWithTtl
    ) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'shaping_feed');
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.ShapesOutcomeThenHitsCalloutTimeLimitClient';
        subscription.Retry_BackOff__c = '30';
        if (createdWithTtl) {
            subscription.Mark_TTL_Event__c = 'created';
            subscription.TTL_Offset__c = 60;
        }

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = [
            SELECT Relay_Attempts__c, Last_Error_Message__c, Next_Attempt_Timestamp__c, Log__c, TTL__c
            FROM TB_Subscription_Outbox__c
        ];
        System.assertEquals(0, outbox.Relay_Attempts__c, 'An attempt that hit a run limit should not be counted');
        System.assertEquals(null, outbox.Last_Error_Message__c, 'No error should be recorded against the outbox');
        return outbox;
    }

    /** A wait the client asked for is part of how the attempt turned out, and the attempt does not count. */
    @isTest
    static void testWhenAbandonedAttemptAskedForANextAttemptTimeThenItIsCleared() {
        TB_Subscription_Outbox__c outbox = relayToAClientThatShapesItsOutcomeThenHitsTheCalloutTimeLimit(true);

        System.assertEquals(null, outbox.Next_Attempt_Timestamp__c, 'The wait the client asked for should not be kept');
    }

    /** What the attempt logged shows how far it got before the run reached its limit. */
    @isTest
    static void testWhenAbandonedAttemptLoggedThenTheLogIsKept() {
        TB_Subscription_Outbox__c outbox = relayToAClientThatShapesItsOutcomeThenHitsTheCalloutTimeLimit(true);

        System.assertNotEquals(null, outbox.Log__c, 'What the attempt logged should be kept');
        System.assert(
            outbox.Log__c.contains(TB_TransactionOutboxTestUtils.LOGGED_BEFORE_LIMIT),
            'The log should hold what the client wrote, but is: ' + outbox.Log__c
        );
    }

    /**
     * Only a delivered or failed attempt keeps the TTL its client chose. A TTL left behind by an
     * abandoned attempt would also stop a later delivery from setting its own.
     */
    @isTest
    static void testWhenAbandonedAttemptReplacedTheTtlThenTheEarlierTtlIsKept() {
        TB_Subscription_Outbox__c outbox = relayToAClientThatShapesItsOutcomeThenHitsTheCalloutTimeLimit(true);

        System.assertNotEquals(null, outbox.TTL__c, 'The TTL the outbox was created with should be kept');
        // A minute either side, because the trigger and the test read the clock at different moments.
        System.assert(
            Datetime.now().addMinutes(59) < outbox.TTL__c && Datetime.now().addMinutes(61) > outbox.TTL__c,
            'The TTL should be the hour the outbox was created with, not the ' +
                TB_TransactionOutboxTestUtils.REQUESTED_TTL_DAYS +
                ' days the client asked for, but it is ' +
                outbox.TTL__c
        );
    }

    /** An outbox that had no TTL before the abandoned attempt has none after it. */
    @isTest
    static void testWhenAbandonedAttemptSetATtlOnAnOutboxWithoutOneThenTheOutboxStillHasNoTtl() {
        TB_Subscription_Outbox__c outbox = relayToAClientThatShapesItsOutcomeThenHitsTheCalloutTimeLimit(false);

        System.assertEquals(
            null,
            outbox.TTL__c,
            'The TTL the client set during the abandoned attempt should not be kept'
        );
    }

    /**
     * A resolver's callouts use the same callout time as the sends. Running out of it there is the
     * run's doing too, so the attempt is abandoned the same way and the run starts nothing more.
     */
    @isTest
    static void testWhenResolverHitsTheCalloutTimeLimitThenAttemptIsAbandonedAndNothingMoreIsStarted() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt limitDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        limitDef.Message_Resolver__c = 'TB_TransactionOutboxTestUtils.CalloutTimeLimitResolver';
        // A backoff, so a wait would show if the attempt were recorded as a failure.
        addTestClientSubscription(app, limitDef, 'resolved_feed').Retry_BackOff__c = '30';
        TB_Message_Definition__mdt otherDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        addTestClientSubscription(app, otherDef, 'other_feed');

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(limitDef), newMessage(otherDef) };
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(0, outboxes[0].Relay_Attempts__c, 'An attempt that hit a run limit should not be counted');
        System.assertEquals(null, outboxes[0].Last_Error_Message__c, 'No error should be recorded against the outbox');
        System.assertEquals(null, outboxes[0].Next_Attempt_Timestamp__c, 'No wait should be added');
        System.assertEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should not be delivered');
        System.assertEquals(false, outboxes[0].Dead_Lettered__c, 'The outbox should not be dead-lettered');
        System.assertNotEquals(null, outboxes[0].Last_Attempt__c, 'The time the abandoned attempt started should be kept');

        assertOutboxIsUntouched(outboxes[1], 'The run reached a limit before this outbox\'s turn.');
        System.assertEquals(0, TB_TransactionOutboxTestUtils.sentMessages.size(), 'Nothing should be sent');
    }

    static final String UNSAVEABLE_OUTBOX_CLIENT = 'TB_TransactionOutboxTestUtils.UnsaveableOutboxClient';

    /**
     * Runs one relay run for these messages in a job that, between the run's save and its finalizer,
     * records what is stored and makes the rejected outboxes saveable again.
     */
    static void relayThenMendBeforeTheFinalizer(List<TB_Outbox_Message__c> messages) {
        Test.startTest();
        // The publish must not queue a run of its own. That run would have nothing after it but its
        // finalizer, and would leave no outbox for the run this test follows.
        TB_OutboxRelayQueuable.alreadyQueuedInContext = true;
        insert messages;
        System.enqueueJob(new TB_TransactionOutboxTestUtils.RelayRunThenMend());
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();
    }

    /** The run's own save left this outbox as it was before its attempt, so the test is about a retry. */
    static void assertRunSaveWasRejected(TB_Subscription_Outbox__c outbox) {
        TB_Subscription_Outbox__c stored = TB_TransactionOutboxTestUtils.storedAfterRunSave.get(outbox.Id);
        System.assertEquals(
            0,
            stored.Relay_Attempts__c,
            'The run\'s save should have been rejected for ' + outbox.Subscription__c + ', leaving no attempt counted'
        );
        System.assertEquals(
            null,
            stored.Completed_Timestamp__c,
            'The run\'s save should have been rejected for ' + outbox.Subscription__c + ', leaving it undelivered'
        );
    }

    /**
     * A run saves its outcomes with one update that keeps the rows the platform accepts. A row it
     * rejects is tried once more by the finalizer. Here the subscriber took the message and the
     * first save of that outcome was rejected, so without the second save the outbox would still
     * look undelivered and the next run would send the message again.
     */
    @isTest
    static void testWhenRunSaveOfADeliveryIsRejectedThenTheFinalizerSavesIt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = UNSAVEABLE_OUTBOX_CLIENT;
        subscription.After_Relay_Action__c = RECORDING_ACTION;

        relayThenMendBeforeTheFinalizer(new List<TB_Outbox_Message__c>{ newMessage(msgDef) });

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        assertRunSaveWasRejected(outbox);
        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The finalizer should save the attempt the run could not. A count of 0 means it was not saved'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The subscriber got the message, so the finalizer should store the outbox as delivered'
        );
        System.assertNotEquals(null, outbox.Last_Attempt__c, 'The time of the attempt should be saved');
        System.assertEquals(null, outbox.Last_Error_Message__c, 'A delivery should record no error');

        System.assertEquals(
            new Map<String, Set<Id>>{ 'subscription1' => new Set<Id>{ outbox.Id } },
            actionCallsBySubscription(),
            'The after-relay action should be called once with the attempt'
        );
        System.assertEquals(
            new List<Integer>{ 1 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The attempt should be stored by the time the action runs'
        );

        assertFinalizerWasFreeToQueue();
        System.assertEquals(0, relayJobCount(), 'A delivery that is stored should not start another run');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.sentMessages.size(), 'The message should be sent once');
    }

    /**
     * The same retry for an attempt that failed. Its count, its error and its wait are all in the
     * rejected update, so without the second save the outbox would be attempted again at once and
     * that failure would never count toward dead-lettering.
     */
    @isTest
    static void testWhenRunSaveOfAFailedAttemptIsRejectedThenTheFinalizerSavesIt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = UNSAVEABLE_OUTBOX_CLIENT;
        subscription.Config__c = '{"throwError":true}';
        subscription.Retry_BackOff__c = '30';

        relayThenMendBeforeTheFinalizer(new List<TB_Outbox_Message__c>{ newMessage(msgDef) });

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        assertRunSaveWasRejected(outbox);
        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The finalizer should save the failed attempt the run could not. A count of 0 means it was not saved'
        );
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'A failed attempt should not be marked delivered');
        System.assertNotEquals(null, outbox.Last_Error_Message__c, 'The reason for the failure should be saved');
        System.assert(
            outbox.Last_Error_Message__c.startsWith('Test Error'),
            'The error should be the one the client threw, but is: ' + outbox.Last_Error_Message__c
        );
        System.assertNotEquals(
            null,
            outbox.Next_Attempt_Timestamp__c,
            'The failed attempt should wait on its subscription backoff'
        );

        assertFinalizerWasFreeToQueue();
        System.assertEquals(0, relayJobCount(), 'An outbox waiting on its backoff should not start another run');
    }

    /**
     * The finalizer's save is for the rows the run's save left unsaved, and for no others. An
     * outbox the run stored may have been changed by something else since, and saving the run's
     * copy again would undo that. Here the stored log is changed between the two saves and has to
     * survive the second.
     */
    @isTest
    static void testWhenRunSaveIsRejectedForOneOutboxThenTheFinalizerLeavesTheOutboxesAlreadySavedAlone() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        TB_TransactionOutboxTestUtils.addSubscription(app, msgDef, 'subscription2')
            .Relay_Client__c = UNSAVEABLE_OUTBOX_CLIENT;

        relayThenMendBeforeTheFinalizer(new List<TB_Outbox_Message__c>{ newMessage(msgDef) });

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size());

        TB_Subscription_Outbox__c savedByRun = TB_TransactionOutboxTestUtils.storedAfterRunSave.get(outboxes[0].Id);
        System.assertEquals(1, savedByRun.Relay_Attempts__c, 'The run should save the outbox the platform accepted');
        System.assertNotEquals(null, savedByRun.Completed_Timestamp__c, 'The run should store that outbox as delivered');
        assertRunSaveWasRejected(outboxes[1]);

        System.assertEquals(
            TB_TransactionOutboxTestUtils.LOG_WRITTEN_BETWEEN_SAVES,
            [SELECT Log__c FROM TB_Subscription_Outbox__c WHERE Id = :outboxes[0].Id].Log__c,
            'The finalizer should not save an outbox the run already saved. Its log was changed after the run\'s save'
        );
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The attempt should still be counted once');
        System.assertEquals(
            savedByRun.Completed_Timestamp__c,
            outboxes[0].Completed_Timestamp__c,
            'The delivery time the run stored should not move'
        );
        System.assertEquals(
            savedByRun.Last_Attempt__c,
            outboxes[0].Last_Attempt__c,
            'The attempt time the run stored should not move'
        );

        System.assertEquals(1, outboxes[1].Relay_Attempts__c, 'The finalizer should save the attempt the run could not');
        System.assertNotEquals(
            null,
            outboxes[1].Completed_Timestamp__c,
            'The finalizer should store the rejected outbox as delivered'
        );
    }

    /**
     * Pins what happens today when the finalizer's save is rejected as well. It is not how this
     * should end up: a row that fails twice is to be reported through the log adapter, and this
     * test is the place to add that expectation.
     *
     * Today the run and its finalizer finish as if nothing went wrong and the outcome is written
     * only to the debug log. The after-relay action is still given the attempt as a delivery. The
     * stored outbox is as it was before the attempt, so it is still due, another run is queued at
     * once, and that run sends the message again. No attempt is ever counted, so the outbox cannot
     * dead-letter.
     */
    @isTest
    static void testWhenBothSavesOfADeliveryAreRejectedThenTodayNothingIsStoredAndTheNextRunSendsAgain() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        subscription.Relay_Client__c = UNSAVEABLE_OUTBOX_CLIENT;
        subscription.After_Relay_Action__c = RECORDING_ACTION;

        Test.startTest();
        insert newMessage(msgDef);
        TB_TransactionOutboxTestUtils.letFinalizerQueueNextRun();
        stopTestExpectingNoFailedJob();

        TB_Subscription_Outbox__c outbox = outboxesInOrder()[0];
        System.assertEquals(0, outbox.Relay_Attempts__c, 'No attempt is counted when neither save is accepted');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'The delivery is not stored');
        System.assertEquals(null, outbox.Last_Attempt__c, 'The time of the attempt is not stored');
        System.assertEquals(null, outbox.Last_Error_Message__c, 'Nothing about the rejected save is put on the outbox');
        System.assertEquals(false, outbox.Dead_Lettered__c, 'The outbox is not dead-lettered');

        System.assertEquals(2, relayJobCount(), 'The outbox is still due, so the finalizer queues another run');
        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The second run sends the message the subscriber already has'
        );

        System.assertEquals(
            2,
            TB_TransactionOutboxTestUtils.actionCalls.size(),
            'The after-relay action is called in each run, whether or not the attempt was stored'
        );
        for (List<TB_OutboxRelayContext> call : TB_TransactionOutboxTestUtils.actionCalls) {
            System.assertEquals(1, call.size());
            System.assertEquals(outbox.Id, call[0].outbox.Id);
            System.assert(call[0].isComplete(), 'The action is told the message was delivered');
        }
        System.assertEquals(
            new List<Integer>{ 0, 0 },
            TB_TransactionOutboxTestUtils.actionSavedCounts,
            'The attempt is not stored when the action runs'
        );
    }
}
