// Scratch-org only. Records what the framework passed to an after-relay action.
public class ReproActionA implements TB_IAfterRelayAction {
    public void execute(TB_OutboxRelayContext[] ctxs) {
        insert new Account(Name = 'ReproActionA got ' + (ctxs == null ? 'null' : ctxs.size() + ' context(s)'));
    }
}
