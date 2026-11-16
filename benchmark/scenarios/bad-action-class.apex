// A healthy message, then one whose subscription names an after-relay action class that does not exist.
insert new List<TB_Outbox_Message__c>{
    new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'first, healthy subscription'),
    new TB_Outbox_Message__c(Type__c = 'repro_badaction', Message__c = 'second, action class name is wrong')
};
