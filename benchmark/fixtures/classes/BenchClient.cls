// Scratch-org only. Succeeds without calling out, and logs the limits used so far in the run.
public class BenchClient implements TB_IOutboxRelayClient {
    public void send(TB_OutboxRelayContext ctx) {
        ctx.log('bench q=' + Limits.getQueries() + ' dml=' + Limits.getDmlStatements() + ' cpu=' + Limits.getCpuTime() + ' heap=' + Limits.getHeapSize());
    }
}
