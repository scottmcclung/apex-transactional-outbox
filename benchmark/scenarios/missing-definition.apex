// A message whose definition no longer exists, ahead of a healthy message.
TB_Outbox_Message__c first = new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'first');
insert first;
first.Type__c = 'definition_that_was_deleted';
update first;
insert new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'second, healthy subscription');
