@isTest
public class TB_RecordCleanupTests {
    static final String PURGED_TYPE = 'cleanup.purged';
    static final String RETAINED_TYPE = 'cleanup.retained';

    // One transaction may change 10,000 rows. The backlog test builds one row more than that.
    static final Integer ROWS_ONE_TRANSACTION_CAN_DELETE = 10000;

    /**
     * Injects a message definition and an empty subscription list.
     * With no subscriptions the message trigger creates no outboxes, so each test controls
     * exactly which outboxes exist and what state they are in.
     */
    static TB_Message_Definition__mdt addDefinition(String type, Boolean deleteWhenOutboxEmpty) {
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition(type);
        msgDef.Delete_When_Outbox_Empty__c = deleteWhenOutboxEmpty;
        if (TB_OutboxMetadataProvider.subscriptions == null) {
            TB_OutboxMetadataProvider.subscriptions = new List<TB_Message_Subscription__mdt>();
        }
        return msgDef;
    }

    static TB_Outbox_Message__c insertMessage(String type) {
        // Publishing queues a relay run, and a queued job runs when the test method ends. That run
        // would attempt the undelivered outboxes these tests build by hand, which belong to no
        // real subscription. Marking the relay as already queued keeps it out of these tests.
        TB_OutboxRelayQueuable.alreadyQueuedInContext = true;
        TB_Outbox_Message__c message = new TB_Outbox_Message__c(Type__c = type, Message__c = 'Test Payload');
        insert message;
        return message;
    }

    static TB_Subscription_Outbox__c buildOutbox(Id messageId, Datetime completedTimestamp, Datetime ttl) {
        return new TB_Subscription_Outbox__c(
            Outbox_Message__c = messageId,
            Subscription__c = 'CleanupSubscription',
            Application__c = 'CleanupApp',
            Max_Attempts__c = 3,
            Completed_Timestamp__c = completedTimestamp,
            TTL__c = ttl
        );
    }

    static TB_Subscription_Outbox__c insertOutbox(Id messageId, Datetime completedTimestamp, Datetime ttl) {
        TB_Subscription_Outbox__c outbox = buildOutbox(messageId, completedTimestamp, ttl);
        insert outbox;
        return outbox;
    }

    static Boolean outboxExists(Id outboxId) {
        return [SELECT COUNT() FROM TB_Subscription_Outbox__c WHERE Id = :outboxId] == 1;
    }

    static Boolean messageExists(Id messageId) {
        return [SELECT COUNT() FROM TB_Outbox_Message__c WHERE Id = :messageId] == 1;
    }

    @isTest
    static void testWhenDeliveredOutboxTtlPassedAnHourAgoThenItIsRemoved() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c outbox = insertOutbox(message.Id, now.addHours(-2), now.addHours(-1));

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            false,
            outboxExists(outbox.Id),
            'A delivered outbox whose TTL passed an hour ago should be removed'
        );
    }

    @isTest
    static void testWhenDeliveredOutboxTtlPassedDaysAgoThenItIsRemoved() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c outbox = insertOutbox(message.Id, now.addDays(-4), now.addDays(-3));

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            false,
            outboxExists(outbox.Id),
            'A delivered outbox whose TTL passed three days ago should be removed'
        );
    }

    @isTest
    static void testWhenDeliveredOutboxHasFutureTtlThenItIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c inAnHour = insertOutbox(message.Id, now.addHours(-1), now.addHours(1));
        TB_Subscription_Outbox__c inFiveDays = insertOutbox(message.Id, now.addHours(-1), now.addDays(5));

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            true,
            outboxExists(inAnHour.Id),
            'A delivered outbox whose TTL is an hour ahead should be kept'
        );
        System.assertEquals(
            true,
            outboxExists(inFiveDays.Id),
            'A delivered outbox whose TTL is five days ahead should be kept'
        );
    }

    @isTest
    static void testWhenDeliveredOutboxHasNoTtlThenItIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        TB_Subscription_Outbox__c outbox = insertOutbox(message.Id, System.now().addDays(-10), null);

        new TB_RecordCleanup().cleanup();

        System.assertEquals(true, outboxExists(outbox.Id), 'A delivered outbox with no TTL should be kept');
    }

    @isTest
    static void testWhenUndeliveredOutboxTtlHasPassedThenItIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c anHourAgo = insertOutbox(message.Id, null, now.addHours(-1));
        TB_Subscription_Outbox__c daysAgo = insertOutbox(message.Id, null, now.addDays(-3));

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            true,
            outboxExists(anHourAgo.Id),
            'An undelivered outbox whose TTL passed an hour ago should be kept'
        );
        System.assertEquals(
            true,
            outboxExists(daysAgo.Id),
            'An undelivered outbox whose TTL passed three days ago should be kept'
        );
    }

    @isTest
    static void testWhenUndeliveredOutboxHasFutureTtlThenItIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        TB_Subscription_Outbox__c outbox = insertOutbox(message.Id, null, System.now().addDays(5));

        new TB_RecordCleanup().cleanup();

        System.assertEquals(true, outboxExists(outbox.Id), 'An undelivered outbox with a future TTL should be kept');
    }

    @isTest
    static void testWhenDeadLetteredOutboxTtlHasPassedThenItIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c outOfAttempts = buildOutbox(message.Id, null, now.addDays(-3));
        outOfAttempts.Relay_Attempts__c = outOfAttempts.Max_Attempts__c;
        TB_Subscription_Outbox__c manuallyDeadLettered = buildOutbox(message.Id, null, now.addDays(-3));
        manuallyDeadLettered.Manual_Deadletter__c = true;
        insert new List<TB_Subscription_Outbox__c>{ outOfAttempts, manuallyDeadLettered };

        Integer deadLetteredBeforeRun = [
            SELECT COUNT()
            FROM TB_Subscription_Outbox__c
            WHERE Id IN (:outOfAttempts.Id, :manuallyDeadLettered.Id) AND Dead_Lettered__c = TRUE
        ];
        System.assertEquals(2, deadLetteredBeforeRun, 'Both outboxes should be dead lettered before cleanup runs');

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            true,
            outboxExists(outOfAttempts.Id),
            'An outbox dead lettered by running out of attempts should be kept after its TTL has passed'
        );
        System.assertEquals(
            true,
            outboxExists(manuallyDeadLettered.Id),
            'An outbox dead lettered by hand should be kept after its TTL has passed'
        );
    }

    @isTest
    static void testWhenMessageHasNoOutboxesAndDefinitionPurgesThenMessageIsRemoved() {
        addDefinition(PURGED_TYPE, true);
        TB_Outbox_Message__c message = insertMessage(PURGED_TYPE);

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            false,
            messageExists(message.Id),
            'A message with no outboxes should be removed when its definition deletes on empty'
        );
    }

    @isTest
    static void testWhenCleanupRemovesTheLastOutboxThenPurgingMessageIsRemoved() {
        addDefinition(PURGED_TYPE, true);
        TB_Outbox_Message__c message = insertMessage(PURGED_TYPE);
        Datetime now = System.now();
        insertOutbox(message.Id, now.addDays(-4), now.addDays(-3));

        // Outboxes are removed before drained messages are looked for, so the run that removes
        // the last outbox also removes the message.
        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            false,
            messageExists(message.Id),
            'A message should be removed once cleanup has removed its last outbox'
        );
    }

    @isTest
    static void testWhenMessageHasNoOutboxesAndDefinitionDoesNotPurgeThenMessageIsKept() {
        addDefinition(RETAINED_TYPE, false);
        TB_Message_Definition__mdt unsetDef = TB_TransactionOutboxTestUtils.addEventDefinition('cleanup.unset');
        TB_Outbox_Message__c explicitlyRetained = insertMessage(RETAINED_TYPE);
        TB_Outbox_Message__c flagNeverSet = insertMessage(unsetDef.DeveloperName);

        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            true,
            messageExists(explicitlyRetained.Id),
            'A drained message should be kept when its definition has delete on empty set to false'
        );
        System.assertEquals(
            true,
            messageExists(flagNeverSet.Id),
            'A drained message should be kept when its definition has no value for delete on empty'
        );
    }

    @isTest
    static void testWhenMessageStillHasAnOutboxThenMessageIsKept() {
        addDefinition(PURGED_TYPE, true);
        TB_Outbox_Message__c message = insertMessage(PURGED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c delivered = insertOutbox(message.Id, now.addDays(-4), now.addDays(-3));
        TB_Subscription_Outbox__c undelivered = insertOutbox(message.Id, null, null);

        new TB_RecordCleanup().cleanup();
        new TB_RecordCleanup().cleanup();

        System.assertEquals(
            false,
            outboxExists(delivered.Id),
            'The delivered outbox whose TTL has passed should be removed'
        );
        System.assertEquals(true, outboxExists(undelivered.Id), 'The undelivered outbox should be kept');
        System.assertEquals(
            true,
            messageExists(message.Id),
            'A message that still has an outbox should be kept even when its definition deletes on empty'
        );
    }

    @isTest
    static void testWhenDefinitionsAreReadFromTheOrgThenCleanupDoesNotThrow() {
        // Injected definitions hold every field in memory, so only records read by the provider's
        // own query can show a field the query forgot to select. This test therefore depends on
        // the org having at least one message definition and proves nothing in an org with none.
        TB_OutboxMetadataProvider.msgDefinitions = null;

        String failure;
        try {
            new TB_RecordCleanup().cleanup();
        } catch (SObjectException e) {
            failure = e.getMessage();
        }

        System.assertEquals(null, failure, 'Cleanup should read message definitions from the org without throwing');
    }

    @isTest
    static void testWhenScheduledThenExecuteRemovesWhatCleanupRemoves() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c removable = insertOutbox(message.Id, now.addDays(-4), now.addDays(-3));
        TB_Subscription_Outbox__c notYetDue = insertOutbox(message.Id, now.addHours(-1), now.addDays(5));

        Test.startTest();
        System.schedule('TB_RecordCleanupTests schedulable', '0 0 23 * * ?', new TB_RecordCleanup());
        Test.stopTest();

        System.assertEquals(
            false,
            outboxExists(removable.Id),
            'The scheduled job should remove a delivered outbox whose TTL has passed'
        );
        System.assertEquals(
            true,
            outboxExists(notYetDue.Id),
            'The scheduled job should keep a delivered outbox whose TTL is ahead'
        );
    }

    @isTest
    static void testWhenBacklogExceedsOneTransactionThenRunSucceedsAndLaterRunRemovesMore() {
        addDefinition(RETAINED_TYPE, false);
        TB_Outbox_Message__c message = insertMessage(RETAINED_TYPE);
        Datetime now = System.now();

        // The message insert has used one row of this transaction's allowance. The rest goes on
        // outboxes here, and the remainder of the backlog is inserted after Test.startTest().
        Integer firstPart = ROWS_ONE_TRANSACTION_CAN_DELETE - 1;
        List<TB_Subscription_Outbox__c> backlog = new List<TB_Subscription_Outbox__c>();
        for (Integer i = 0; i < firstPart; i++) {
            backlog.add(buildOutbox(message.Id, now.addDays(-4), now.addDays(-3)));
        }
        insert backlog;
        backlog = null;

        Test.startTest();
        insert new List<TB_Subscription_Outbox__c>{
            buildOutbox(message.Id, now.addDays(-4), now.addDays(-3)),
            buildOutbox(message.Id, now.addDays(-4), now.addDays(-3))
        };
        Integer backlogSize = firstPart + 2;

        // Deleting the whole backlog at once would end this transaction with an error that
        // cannot be caught, so reaching the next line shows the run stayed inside its limits.
        new TB_RecordCleanup().cleanup();
        Integer leftAfterFirstRun = [SELECT COUNT() FROM TB_Subscription_Outbox__c];

        // A scheduled job runs at Test.stopTest() with its own limits, as a later run would.
        System.schedule('TB_RecordCleanupTests backlog', '0 0 23 * * ?', new TB_RecordCleanup());
        Test.stopTest();
        Integer leftAfterLaterRun = [SELECT COUNT() FROM TB_Subscription_Outbox__c];

        System.assert(
            leftAfterFirstRun < backlogSize,
            'The first run should remove part of the backlog. Left: ' + leftAfterFirstRun + ' of ' + backlogSize
        );
        System.assert(
            leftAfterLaterRun < leftAfterFirstRun,
            'A later run should remove more of the backlog. Left after first run: ' +
                leftAfterFirstRun +
                ', after later run: ' +
                leftAfterLaterRun
        );
    }

    @isTest
    static void testWhenMoreMessagesAreDrainedThanTheCapThenOneRunRemovesTheCap() {
        addDefinition(PURGED_TYPE, true);
        TB_OutboxRelayQueuable.alreadyQueuedInContext = true;
        Integer cap = TB_RecordCleanup.MAX_RECORDS_PER_DELETE;
        Integer drainedCount = cap + 5;
        List<TB_Outbox_Message__c> drained = new List<TB_Outbox_Message__c>();
        for (Integer i = 0; i < drainedCount; i++) {
            drained.add(new TB_Outbox_Message__c(Type__c = PURGED_TYPE, Message__c = 'Test Payload'));
        }
        insert drained;
        drained = null;

        Test.startTest();
        new TB_RecordCleanup().cleanup();
        Test.stopTest();

        Integer left = [SELECT COUNT() FROM TB_Outbox_Message__c WHERE Type__c = :PURGED_TYPE];
        System.assertEquals(
            drainedCount - cap,
            left,
            'One run should remove ' + cap + ' drained messages and leave the rest for a later run'
        );
    }

    @isTest
    static void testWhenScheduledByUserWhoCannotDeleteTheRecordsThenCleanupStillRemovesThem() {
        addDefinition(PURGED_TYPE, true);
        TB_Outbox_Message__c message = insertMessage(PURGED_TYPE);
        Datetime now = System.now();
        TB_Subscription_Outbox__c outbox = insertOutbox(message.Id, now.addDays(-4), now.addDays(-3));

        // A standard user has no Modify All on these objects and does not own records the test
        // user inserted, so record sharing alone would not let this user delete them.
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueName = 'cleanup' + System.currentTimeMillis() + '@example.com';
        User scheduler = new User(
            Alias = 'cleanup',
            Email = uniqueName,
            Username = uniqueName,
            LastName = 'Cleanup',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert scheduler;

        System.runAs(scheduler) {
            new TB_RecordCleanup().cleanup();
        }

        System.assertEquals(
            false,
            outboxExists(outbox.Id),
            'Cleanup should remove a delivered outbox whose TTL has passed whoever scheduled it'
        );
        System.assertEquals(
            false,
            messageExists(message.Id),
            'Cleanup should remove a drained message whoever scheduled it'
        );
    }
}
