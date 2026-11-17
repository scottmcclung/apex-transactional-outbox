/**
 * The most that one send by a relay client will use of the limits a relay run works within.
 * A relay run compares this with what it has left before it starts an attempt, so a value that is
 * too low lets the run start an attempt it has no room for.
 *
 * Every field must be set. A send that uses none of something states 0. A cost with any field left
 * null is not a valid declaration, and null does not mean 0.
 */
public class TB_SendCost {
    /** Outbound calls. Counted by Limits.getCallouts(). */
    public Integer callouts;

    /**
     * The longest the outbound calls may take in total, in milliseconds. The platform has no Limits
     * method for the callout time a transaction has used, so a run has to keep its own total.
     */
    public Integer calloutTimeMs;

    /** SOQL queries, including any the client runs to look up records before sending. Counted by Limits.getQueries(). */
    public Integer queries;

    /** Rows those queries return. Counted by Limits.getQueryRows(). */
    public Integer queryRows;

    /** DML statements. Counted by Limits.getDmlStatements(). */
    public Integer dmlStatements;

    /** Rows those DML statements write. Counted by Limits.getDmlRows(). */
    public Integer dmlRows;

    /** Platform events published immediately. Counted by Limits.getPublishImmediateDML(). */
    public Integer eventPublishes;

    /** CPU time, in milliseconds. Counted by Limits.getCpuTime(). */
    public Integer cpuTimeMs;

    /**
     * Heap, in bytes, as counted by Limits.getHeapSize(). This is the highest the send can raise the
     * heap above where it stood when the send began, at any point during the send. It includes what
     * the send leaves held afterwards, such as log lines and the relay result, which stay until the
     * run saves.
     */
    public Integer heapBytes;
}
