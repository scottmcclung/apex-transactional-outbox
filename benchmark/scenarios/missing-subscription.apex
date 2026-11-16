// An outbox whose subscription no longer exists, ahead of a healthy message.
TB_Outbox_Message__c first = new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'first');
insert first;
delete [SELECT Id FROM TB_Subscription_Outbox__c WHERE Outbox_Message__c = :first.Id];
insert new TB_Subscription_Outbox__c(Outbox_Message__c = first.Id, Subscription__c = 'subscription_that_was_deleted', Application__c = 'ReproApp', Max_Attempts__c = 3);
insert new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'second, healthy subscription');
