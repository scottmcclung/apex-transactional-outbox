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
     * An action is built for every subscription of the message types in the run,
     * so a subscription whose outbox was passed over still has its action called.
     */
    @isTest
    static void testAfterRelayActionIsCalledWithNullWhenSubscriptionHadNoAttempt() {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt firstSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'subscription1'
        );
        firstSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';

        // A second message type, so the isolated outbox has a later sequence number and is never first in the run.
        TB_Message_Definition__mdt isolatedDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message2');
        TB_Message_Subscription__mdt isolatedSub = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            isolatedDef,
            'subscription2'
        );
        isolatedSub.Relay_Client__c = 'TB_TransactionOutboxTestUtils.TestClient';
        isolatedSub.Isolate_Relay__c = true;
        isolatedSub.After_Relay_Action__c = 'TB_TransactionOutboxTestUtils.RecordingAction';

        Test.startTest();
        insert new List<TB_Outbox_Message__c>{ newMessage(msgDef), newMessage(isolatedDef) };
        Test.stopTest();

        List<TB_Subscription_Outbox__c> outboxes = outboxesInOrder();
        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'The isolated outbox should have been passed over');
        System.assertEquals(1, TB_TransactionOutboxTestUtils.actionCalls.size(), 'The action should still be called');
        System.assertEquals(null, TB_TransactionOutboxTestUtils.actionCalls[0], 'The action should be given null');
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
    static Boolean configurationRestored = false;

    /**
     * Stands in for what happens between two runs: the removed configuration is put back under
     * the same name, the retry wait passes, and a later run starts.
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
}
