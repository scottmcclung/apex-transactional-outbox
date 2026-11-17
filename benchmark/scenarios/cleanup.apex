// Two delivered outboxes, one whose TTL passed three days ago and one whose TTL is five days ahead.
// Shows which outboxes match what cleanup selects, then runs the real cleanup.
// Expects two delivered outboxes to exist already. reproduce.js publishes them first.
List<TB_Subscription_Outbox__c> outboxes = [
    SELECT Id FROM TB_Subscription_Outbox__c ORDER BY Outbox_Message__r.Sequence_Number__c LIMIT 2
];
outboxes[0].TTL__c = System.now().addDays(-3);
outboxes[1].TTL__c = System.now().addDays(5);
update outboxes;

// This repeats the condition in TB_RecordCleanup.cleanup so the output can show what it matches.
Datetime now = System.now();
System.debug('now = ' + now);
for (TB_Subscription_Outbox__c outbox : [
    SELECT TTL__c, Completed_Timestamp__c FROM TB_Subscription_Outbox__c
    WHERE Completed_Timestamp__c != NULL AND TTL__c <= :now
]) {
    System.debug('cleanup selects the outbox with TTL ' + outbox.TTL__c + ', delivered ' + outbox.Completed_Timestamp__c);
}
for (TB_Subscription_Outbox__c outbox : [
    SELECT TTL__c, Completed_Timestamp__c FROM TB_Subscription_Outbox__c
    WHERE Completed_Timestamp__c = NULL OR TTL__c = NULL OR TTL__c > :now
]) {
    System.debug('cleanup keeps the outbox with TTL ' + outbox.TTL__c + ', delivered ' + outbox.Completed_Timestamp__c);
}

// Left uncaught so that any exception shows in the output. reproduce.js counts the outboxes afterwards.
new TB_RecordCleanup().cleanup();
System.debug('cleanup finished without an exception');
