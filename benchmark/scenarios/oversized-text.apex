// An error and a log each longer than their fields, ahead of an ordinary message with an after-relay
// action. The failed attempt waits 60 minutes, so it stays at one attempt while the scenario watches.
insert new List<TB_Outbox_Message__c>{
    new TB_Outbox_Message__c(Type__c = 'repro_oversized_error', Message__c = 'fails with an error longer than its field'),
    new TB_Outbox_Message__c(Type__c = 'repro_oversized_log', Message__c = 'succeeds after a log longer than its field'),
    new TB_Outbox_Message__c(Type__c = 'repro_action_b', Message__c = 'ordinary, with an after-relay action')
};
