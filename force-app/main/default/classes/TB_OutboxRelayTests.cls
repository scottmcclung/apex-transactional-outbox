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

    @isTest
    static void testAfterRelayActionFailureIsSwallowed() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt throwingSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        throwingSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        throwingSub.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.ThrowingAction';

        TB_Message_Subscription__mdt recordingSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription2'
        );
        recordingSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        recordingSub.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.RecordingAction';

        Test.startTest();
        insert newMessage(msgDef);
        Test.stopTest();

        // Actions run in the order their subscriptions were added, so the failing one runs first.
        System.assertEquals(1, TB_TransactionOutboxTestUtils.throwingActionCalls, 'The failing action should have run');
        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.actionCalls.size(),
            'The other subscription\'s action should still run'
        );

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(2, outboxes.size());
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
    @isTest
    static void testWhenSubscriptionWithNoAttemptNamesAnActionClassThatDoesNotExistThenTheRunIsNotStopped() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        addTestClientSubscription(app, msgDef, 'subscription1');
        // A disabled subscription gets no outbox when a message is published.
        TB_Message_Subscription__mdt disabledSub = addTestClientSubscription(app, msgDef, 'subscription2');
        disabledSub.Enabled__c = false;
        disabledSub.After_Relay_Action__c = 'TB_OutboxRelayTests.NoSuchAction';

        Test.startTest();
        insert newMessage(msgDef);
        stopTestExpectingNoFailedJob();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(1, outboxes.size(), 'Only the enabled subscription should have an outbox');
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The outbox should be attempted');
        System.assertNotEquals(null, outboxes[0].Completed_Timestamp__c, 'The outbox should be delivered');
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

    @isTest
    static void testWhenSubscriptionNamesNoAfterRelayActionThenItIsRelayedAndNoActionRunsForIt() {
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
            'Only the subscription that names an action should have one called'
        );
    }
}
