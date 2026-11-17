// Scratch-org only. Succeeds without calling out, and logs the limits used so far in the run.
public class BenchClient implements TB_IOutboxRelayClient {
    // A send reads four limits and appends one short log line, which stays well under 1 ms of CPU
    // and 1 KB of heap. It uses none of the other limits.
    public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
        TB_SendCost cost = new TB_SendCost();
        cost.callouts = 0;
        cost.calloutTimeMs = 0;
        cost.queries = 0;
        cost.queryRows = 0;
        cost.dmlStatements = 0;
        cost.dmlRows = 0;
        cost.eventPublishes = 0;
        cost.cpuTimeMs = 1;
        cost.heapBytes = 1024;
        return cost;
    }

    public void send(TB_OutboxRelayContext ctx) {
        ctx.log('bench q=' + Limits.getQueries() + ' dml=' + Limits.getDmlStatements() + ' cpu=' + Limits.getCpuTime() + ' heap=' + Limits.getHeapSize());
    }
}
