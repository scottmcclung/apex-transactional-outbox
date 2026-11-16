// Two delivered outboxes, one expired three days ago and one due to expire in five days.
// Shows which the cleanup query selects, what its delete alone would remove, and what the real cleanup does.
// Expects two delivered outboxes to exist already. reproduce.js publishes them first.
List<TB_Subscription_Outbox__c> outboxes = [
    SELECT Id FROM TB_Subscription_Outbox__c ORDER BY Outbox_Message__r.Sequence_Number__c LIMIT 2
];
outboxes[0].TTL__c = System.now().addDays(-3);
outboxes[1].TTL__c = System.now().addDays(5);
update outboxes;

System.debug('user time zone ' + UserInfo.getTimeZone().getID() + ', Date.today() = ' + Date.today() + ', now = ' + System.now());
for (TB_Subscription_Outbox__c outbox : [SELECT TTL__c FROM TB_Subscription_Outbox__c WHERE TTL__c > :Date.today()]) {
    System.debug('cleanup query selects the outbox with TTL ' + outbox.TTL__c);
}
for (TB_Subscription_Outbox__c outbox : [SELECT TTL__c FROM TB_Subscription_Outbox__c WHERE NOT (TTL__c > :Date.today())]) {
    System.debug('cleanup query does not select the outbox with TTL ' + outbox.TTL__c);
}

Savepoint beforeDelete = Database.setSavepoint();
delete [SELECT Id FROM TB_Subscription_Outbox__c WHERE TTL__c > :Date.today()];
System.debug('outboxes left if only the delete ran: ' + [SELECT COUNT() FROM TB_Subscription_Outbox__c]);
Database.rollback(beforeDelete);

// Left uncaught on purpose. The scheduled job does not catch it either, so the whole transaction,
// including the delete inside cleanup, is rolled back. reproduce.js counts the outboxes afterwards.
new TB_RecordCleanup().cleanup();
