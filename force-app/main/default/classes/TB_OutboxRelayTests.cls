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
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c
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
     * The finalizer leaves out every group the run held, so a group whose first outbox failed
     * with no backoff does not start another run, although the same failure without a group does.
     */
    @isTest
    static void testNextRunIsNotQueuedForGroupHeldByFailure() {
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
        assertFinalizerWasFreeToQueue();
        System.assertEquals(1, relayJobCount(), 'No further run should be queued for the held group');
        System.assertEquals(1, outboxes[0].Relay_Attempts__c, 'The failed outbox should not be attempted again');
        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'The later outbox in the group should not be attempted');
    }

    /**
     * An isolated outbox that is not first in the run is passed over, and its group is held.
     * The finalizer then leaves that group out, so nothing queues the run that would deliver it.
     */
    @isTest
    static void testNextRunIsNotQueuedForGroupedIsolatedOutboxThatWasPassedOver() {
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
        assertFinalizerWasFreeToQueue();
        System.assertEquals(1, relayJobCount(), 'No further run should be queued');
        System.assertEquals(0, outboxes[1].Relay_Attempts__c, 'The isolated outbox should be left unattempted');
    }

    static void setRelayBatchSize(Integer batchSize) {
        TB_OutboxMetadataProvider.frameworkSettings = new List<TB_Framework_Settings__mdt>{
            new TB_Framework_Settings__mdt(DeveloperName = 'Default', Relay_Batch_Size__c = batchSize)
        };
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
}