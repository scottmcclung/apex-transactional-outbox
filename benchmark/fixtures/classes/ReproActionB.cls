// Scratch-org only. Records what the framework passed to an after-relay action.
public class ReproActionB implements TB_IAfterRelayAction {
    public void execute(TB_OutboxRelayContext[] ctxs) {
        insert new Account(Name = 'ReproActionB got ' + (ctxs == null ? 'null' : ctxs.size() + ' context(s)'));
    }
}
