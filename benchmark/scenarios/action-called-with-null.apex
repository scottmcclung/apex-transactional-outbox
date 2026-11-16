// Two subscriptions with after-relay actions. A is isolated, so B is not attempted in the first run.
insert new List<TB_Outbox_Message__c>{
    new TB_Outbox_Message__c(Type__c = 'repro_action_a', Message__c = 'A, isolated relay'),
    new TB_Outbox_Message__c(Type__c = 'repro_action_b', Message__c = 'B')
};
