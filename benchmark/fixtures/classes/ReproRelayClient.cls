// Scratch-org only. A relay client that always succeeds and calls nothing outside the org.
public class ReproRelayClient implements TB_IOutboxRelayClient {
    public void send(TB_OutboxRelayContext ctx) {
        ctx.log('repro client sent ' + ctx.outbox.Id);
    }
}
