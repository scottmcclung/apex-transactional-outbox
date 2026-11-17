public interface TB_IOutboxRelayClient {
    /**
     * Must throw exception on failure
     */
    void send(TB_OutboxRelayContext ctx);

    /**
     * The most that one call to send for this subscription will use. A client that looks up records
     * before sending counts those queries and rows here.
     */
    TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription);
}