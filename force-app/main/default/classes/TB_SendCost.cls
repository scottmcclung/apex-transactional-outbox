/**
 * The most that one send by a relay client will use of the limits a relay run works within.
 * A relay run compares this with what it has left before it starts an attempt, so a value that is
 * too low lets the run start an attempt it has no room for.
 *
 * Each field is named after the `Limits` method it is compared with. Every field must be set.
 * A send that uses none of something states 0.
 */
public class TB_SendCost {
    /** Outbound calls. */
    public Integer callouts;

    /** The longest the outbound calls may take in total, in milliseconds. */
    public Integer calloutTimeMs;

    /** SOQL queries, including any the client runs to look up records before sending. */
    public Integer queries;

    /** Rows those queries return. */
    public Integer queryRows;

    /** DML statements. */
    public Integer dmlStatements;

    /** Rows those DML statements write. */
    public Integer dmlRows;

    /** Platform events published immediately. */
    public Integer eventPublishes;

    /** CPU time, in milliseconds. */
    public Integer cpuTimeMs;

    /** Heap, in bytes. */
    public Integer heapBytes;
}