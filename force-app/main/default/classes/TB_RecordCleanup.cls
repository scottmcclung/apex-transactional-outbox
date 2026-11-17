// Runs without sharing because deleting a record needs ownership or Modify All, and messages are
// owned by whoever published them. Cleanup applies fixed rules and is the only way a record leaves
// the outbox, so it must not depend on the record access of the user who scheduled it.
global without sharing class TB_RecordCleanup implements Schedulable {
    // Records, per delete. A run makes two deletes, so it changes at most 8,000 rows. That stays
    // under the 10,000 DML rows one transaction allows and leaves room for a caller's own DML.
    // A backlog larger than this is removed over later runs.
    @TestVisible
    static final Integer MAX_RECORDS_PER_DELETE = 4000;

    global void execute(SchedulableContext sc) {
        cleanup();
    }

    public void cleanup() {
        // PLANNED: remove an outbox once it is settled (delivered, skipped or expired) and its
        // retention period has ended. Today TTL__c is the removal time and only a delivered outbox
        // is removed. An undelivered outbox is never removed, so every outbox that is gone had a
        // recorded outcome first. A blank TTL__c never matches the comparison, so an outbox with
        // no TTL is kept.
        Datetime now = System.now();
        List<TB_Subscription_Outbox__c> expiredRecords = [
            SELECT Id
            FROM TB_Subscription_Outbox__c
            WHERE Completed_Timestamp__c != NULL AND TTL__c <= :now
            LIMIT :MAX_RECORDS_PER_DELETE
        ];
        if (!expiredRecords.isEmpty()) {
            System.debug('Removing Outbox: ' + expiredRecords.size());
            delete expiredRecords;
        }

        // find all Outbox_Message__c records which are configured in the Custom Metadata to purge when the outbox is empty
        Set<String> purgeOutboxOnEmpty = new Set<String>();
        for (TB_Message_Definition__mdt evtDef : TB_OutboxMetadataProvider.getMessageDefintionMap().values()) {
            if (evtDef.Delete_When_Outbox_Empty__c == true) {
                purgeOutboxOnEmpty.add(evtDef.DeveloperName);
            }
        }

        List<TB_Outbox_Message__c> outboxMessages = [
            SELECT Id
            FROM TB_Outbox_Message__c
            WHERE Type__c IN :purgeOutboxOnEmpty AND Id NOT IN (SELECT Outbox_Message__c FROM TB_Subscription_Outbox__c)
            LIMIT :MAX_RECORDS_PER_DELETE
        ];
        if (!outboxMessages.isEmpty()) {
            System.debug('Removing Messages: ' + outboxMessages.size());
            delete outboxMessages;
        }

    }
}