// A subscription whose Config__c is not valid JSON, followed by a healthy message.
insert new List<TB_Outbox_Message__c>{
    new TB_Outbox_Message__c(Type__c = 'repro_badjson', Message__c = 'first, subscription has malformed JSON config'),
    new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'second, healthy subscription')
};
