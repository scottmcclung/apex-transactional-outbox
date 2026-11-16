// Blanking max attempts on an outbox dead-letters it at once. Runs inside a savepoint and rolls back.
Savepoint sp = Database.setSavepoint();
TB_Outbox_Message__c m = new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'x');
insert m;
TB_Subscription_Outbox__c made = [SELECT Max_Attempts__c, Dead_Lettered__c FROM TB_Subscription_Outbox__c WHERE Outbox_Message__c = :m.Id];
System.debug('created by fan-out: max attempts ' + made.Max_Attempts__c + ', dead-lettered ' + made.Dead_Lettered__c);
made.Max_Attempts__c = null;
update made;
made = [SELECT Max_Attempts__c, Relay_Attempts__c, Dead_Lettered__c FROM TB_Subscription_Outbox__c WHERE Id = :made.Id];
System.debug('after blanking max attempts: max attempts ' + made.Max_Attempts__c + ', attempts ' + made.Relay_Attempts__c + ', dead-lettered ' + made.Dead_Lettered__c);
Database.rollback(sp);
