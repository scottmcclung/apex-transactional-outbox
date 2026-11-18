// Scratch-org only. A relay client that writes text longer than the outbox's fields, so a person can
// see which end of a shortened error or log was kept. It calls nothing outside the org.
//
// Settings, in the subscription's Config__c:
// - "logLength": logs one line of this many characters, then succeeds unless "errorLength" is set.
// - "errorLength": fails with an exception whose message is this many characters.
// At least one is required. Each text begins with START_MARKER and ends with END_MARKER.
public class ReproOversizedTextClient implements TB_IOutboxRelayClient {
    public static final String START_MARKER = 'OVERSIZED-START';
    public static final String END_MARKER = 'OVERSIZED-END';

    // Each text is built in one pass, and the log copies its line a few times while it appends it,
    // so eight copies of everything the send writes covers it. The CPU figure is a generous guess for
    // building strings of a few hundred thousand characters, and was not measured.
    public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
        Map<String, Object> config = TB_OutboxMetadataProvider.getSubscriptionConfig(subscription);
        Integer logLength = (Integer) config.get('logLength');
        Integer errorLength = (Integer) config.get('errorLength');
        Integer written = (logLength == null ? 0 : logLength) + (errorLength == null ? 0 : errorLength);

        TB_SendCost cost = new TB_SendCost();
        cost.callouts = 0;
        cost.calloutTimeMs = 0;
        cost.queries = 0;
        cost.queryRows = 0;
        cost.dmlStatements = 0;
        cost.dmlRows = 0;
        cost.eventPublishes = 0;
        cost.cpuTimeMs = 50;
        cost.heapBytes = 8 * written + 4096;
        return cost;
    }

    public void send(TB_OutboxRelayContext ctx) {
        Integer logLength = (Integer) ctx.subscriptionConfig.get('logLength');
        Integer errorLength = (Integer) ctx.subscriptionConfig.get('errorLength');
        if (logLength == null && errorLength == null) {
            throw new OversizedTextException('Set "logLength", "errorLength" or both in Config__c.');
        }
        if (logLength != null) {
            ctx.log(markedText(logLength));
        }
        if (errorLength != null) {
            throw new OversizedTextException(markedText(errorLength));
        }
    }

    private static String markedText(Integer length) {
        Integer fillerLength = length - START_MARKER.length() - END_MARKER.length();
        if (fillerLength < 0) {
            throw new OversizedTextException(
                'A length of ' + length + ' leaves no room for the start and end markers.'
            );
        }
        return START_MARKER + '.'.repeat(fillerLength) + END_MARKER;
    }

    public class OversizedTextException extends Exception {
    }
}
