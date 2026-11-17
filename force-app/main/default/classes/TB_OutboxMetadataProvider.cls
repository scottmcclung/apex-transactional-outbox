public class TB_OutboxMetadataProvider {
    @testVisible
    static TB_Message_Definition__mdt[] msgDefinitions;

    public static Map<String, TB_Message_Definition__mdt> getMessageDefintionMap() {
        if (msgDefinitions == null) {
            msgDefinitions = [
                SELECT DeveloperName, QualifiedApiName, Message_Resolver__c, Delete_When_Outbox_Empty__c
                FROM TB_Message_Definition__mdt
            ];
        }

        Map<String, TB_Message_Definition__mdt> definitionsByLabel = new Map<String, TB_Message_Definition__mdt>();
        for (TB_Message_Definition__mdt def : msgDefinitions) {
            definitionsByLabel.put(def.DeveloperName, def);
        }
        return definitionsByLabel;
    }

    @testVisible
    static TB_Message_Subscription__mdt[] subscriptions;
    public static Map<String, TB_Message_Subscription__mdt> getMessageSubscritionMap(Set<String> msgTypes) {
        Map<String, TB_Message_Subscription__mdt> subscriptionsByLabel = new Map<String, TB_Message_Subscription__mdt>();
        for (TB_Message_Subscription__mdt sub : loadSubscriptions()) {
            if (msgTypes.contains(sub.Message_Definition__r.DeveloperName)) {
                subscriptionsByLabel.put(sub.DeveloperName, sub);
            }
        }
        return subscriptionsByLabel;
    }

    /**
     * The subscriptions with these names, whatever message definition each is on now.
     * An outbox is tied to its subscription by name alone, so a name with no subscription is
     * left out and the caller treats that outbox as having no subscription.
     */
    public static Map<String, TB_Message_Subscription__mdt> getSubscriptionsByName(Set<String> names) {
        Map<String, TB_Message_Subscription__mdt> subscriptionsByName = new Map<String, TB_Message_Subscription__mdt>();
        for (TB_Message_Subscription__mdt sub : loadSubscriptions()) {
            if (names.contains(sub.DeveloperName)) {
                subscriptionsByName.put(sub.DeveloperName, sub);
            }
        }
        return subscriptionsByName;
    }

    private static TB_Message_Subscription__mdt[] loadSubscriptions() {
        if (subscriptions == null) {
            subscriptions = [
                SELECT
                    DeveloperName,
                    Application__r.DeveloperName,
                    Message_Definition__r.DeveloperName,
                    Relay_Client__c,
                    Config__c,
                    Max_Attempts__c,
                    Enabled__c,
                    After_Relay_Action__c,
                    Isolate_Relay__c,
                    Retry_Backoff__c,
                    Mark_TTL_Event__c,
                    TTL_Offset__c
                FROM TB_Message_Subscription__mdt
            ];
        }
        return subscriptions;
    }

    @testVisible
    static TB_Framework_Settings__mdt[] frameworkSettings;

    // A run can read 20 outboxes per unit of batch size while it searches, and a transaction
    // may read 50,000 rows in all. This keeps the search to 20,000 and leaves the rest for
    // relay clients and message resolvers.
    static final Integer MAX_RELAY_BATCH_SIZE = 1000;

    /**
     * The most relay attempts one relay run makes.
     * It is read from the framework settings record named Default and from nowhere else,
     * so a missing record or value is an error and never a silently assumed number.
     */
    public static Integer getRelayBatchSize() {
        Decimal batchSize = defaultFrameworkSettings().Relay_Batch_Size__c;
        if (batchSize == null || batchSize < 1 || batchSize > MAX_RELAY_BATCH_SIZE) {
            throw new TB_InvalidConfigException(
                'Relay_Batch_Size__c on the TB_Framework_Settings__mdt record named Default must be from 1 to ' +
                    MAX_RELAY_BATCH_SIZE +
                    '. It is ' +
                    batchSize +
                    '.'
            );
        }
        return batchSize.intValue();
    }

    // In minutes, one year. The next attempt time is the attempt time plus this wait, and it must stay
    // a date the platform can store. A later date fails the outbox's save, so the outbox stays due and
    // every run tries it again.
    @testVisible
    static final Integer MAX_FALLBACK_RETRY_WAIT = 525600;

    /**
     * Minutes an outbox waits before its next attempt when its subscription is missing,
     * because there is then no retry backoff to read.
     * It is read and checked at the start of every run, even a run with no such outbox,
     * so a bad value stops the run before anything is attempted and never part-way through.
     * Zero is accepted and means the next run may try again at once.
     */
    public static Integer getFallbackRetryWait() {
        Decimal wait = defaultFrameworkSettings().Fallback_Retry_Wait__c;
        if (wait == null || wait < 0 || wait > MAX_FALLBACK_RETRY_WAIT) {
            throw new TB_InvalidConfigException(
                'Fallback_Retry_Wait__c on the TB_Framework_Settings__mdt record named Default must be a number of minutes from 0 to ' +
                    MAX_FALLBACK_RETRY_WAIT +
                    '. It is ' +
                    wait +
                    '.'
            );
        }
        return wait.intValue();
    }

    private static TB_Framework_Settings__mdt defaultFrameworkSettings() {
        if (frameworkSettings == null) {
            frameworkSettings = [
                SELECT DeveloperName, Relay_Batch_Size__c, Fallback_Retry_Wait__c
                FROM TB_Framework_Settings__mdt
                WHERE DeveloperName = 'Default'
            ];
        }
        if (frameworkSettings.isEmpty()) {
            throw new TB_InvalidConfigException(
                'No TB_Framework_Settings__mdt record named Default was found. The relay needs it for Relay_Batch_Size__c and Fallback_Retry_Wait__c.'
            );
        }
        return frameworkSettings[0];
    }

    static Map<String, Map<String, Object>> configCache = new Map<String, Map<String, Object>>();
    public static Map<String, Object> getSubscriptionConfig(TB_Message_Subscription__mdt subscriptionDef) {
        if (configCache.containsKey(subscriptionDef.DeveloperName)) {
            return configCache.get(subscriptionDef.DeveloperName);
        }

        // A field left empty means the subscription has no settings, which is valid.
        Map<String, Object> config = new Map<String, Object>();
        if (subscriptionDef.Config__c != null) {
            Object parsed;
            try {
                parsed = JSON.deserializeUntyped(subscriptionDef.Config__c);
            } catch (Exception e) {
                parsed = null;
            }
            // The JSON literal null parses without error to null, so it fails this check like any other non-object.
            if (!(parsed instanceof Map<String, Object>)) {
                throw new TB_InvalidConfigException('Invalid Config__c for subscription ' + subscriptionDef.DeveloperName + '. Must be a valid JSON object.');
            }
            config = (Map<String, Object>) parsed;
        }
        configCache.put(subscriptionDef.DeveloperName, config);
        return config;
    }

    static Map<String, Integer[]> retryBackOffCache = new Map<String, Integer[]>();
    public static DateTime getSubscriptionNextAttemptTimeStamp(TB_Message_Subscription__mdt subscriptionDef, Integer attempt) {
        if(subscriptionDef.Retry_BackOff__c == null) {
            return null;
        }

        Integer[] backoffList = retryBackOffCache.get(subscriptionDef.DeveloperName);

        // setup backoff list
        if (backoffList == null) {
            backoffList = new Integer[]{};
            for(String backOff : subscriptionDef.Retry_BackOff__c.split(',')){
                backoffList.add(Integer.valueOf(backOff));
            }
            retryBackOffCache.put(subscriptionDef.DeveloperName, backoffList);
        }

        // get current backoff and return new date that many minutes in the future
        return System.now().addMinutes(backoffList[Math.min(backoffList.size() - 1, attempt - 1)]);
    }

    static Map<String, TB_IOutboxRelayClient> clientCache = new Map<String, TB_IOutboxRelayClient>();
    public static TB_IOutboxRelayClient getSubscriptionRelayClient(TB_Message_Subscription__mdt subscriptionDef) {
        if (clientCache.containsKey(subscriptionDef.DeveloperName)) {
            return clientCache.get(subscriptionDef.DeveloperName);
        }

        TB_IOutboxRelayClient client = (TB_IOutboxRelayClient) TB_OutboxUtils.constructFromName(
            subscriptionDef.Relay_Client__c
        );
        clientCache.put(subscriptionDef.DeveloperName, client);
        return client;
    }

    public static TB_IOutboxMessageResolver getMessageResolver(TB_Message_Definition__mdt def) {
        return (TB_IOutboxMessageResolver) TB_OutboxUtils.constructFromName(def.Message_Resolver__c);
    }

    public static Map<String, TB_IAfterRelayAction> getAfterRelayActionsMap(TB_Message_Subscription__mdt[] subsMdt) {
        Map<String, TB_IAfterRelayAction> afterRelayActions = new Map<String, TB_IAfterRelayAction>();
        for (TB_Message_Subscription__mdt sub : subsMdt) {
            if (sub.After_Relay_Action__c != null) {
                afterRelayActions.put(sub.DeveloperName, (TB_IAfterRelayAction) TB_OutboxUtils.constructFromName(sub.After_Relay_Action__c));
            }
        }
        return afterRelayActions;
    }

    public class TB_InvalidConfigException extends Exception {}
}
