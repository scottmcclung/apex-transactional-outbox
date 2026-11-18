public class TB_OutboxRelayContext {
    

    /**
     * The Outbox record that is being relayed
     * Contains raw information about the subscription and the message
     */
    public TB_Subscription_Outbox__c outbox;

    /**
     * The subscription metadata.
     * Null when no subscription has the outbox's subscription name. Such an attempt fails without
     * sending and is never given to an after-relay action, because actions belong to subscriptions.
     */
    public TB_Message_Subscription__mdt subscription;

    /**
     * The Configuration field from the subscription after being passed through `JSON.deserializeUntyped`.
     * Null when the subscription is null, or when its Configuration field cannot be read as a JSON object.
     */
    public Map<String, Object> subscriptionConfig;

    // Why the subscription's Configuration field could not be read, or null when it could.
    // Kept as text so the context stays serializable for the finalizer that holds it.
    private String unreadableConfigReason;

    /* 
    * Populated by the IOutboxMessageResolver. Null if no resolver is configured.
    * WARNING: This must be Serializable!
    */ 
    public Object resolvedMessage;

    /* 
    * Generic Object that can be used to store results to be used by an IAfterRelayAction
    * WARNING: This must be Serializable!
    */ 
    public Object relayResult;

    public TB_OutboxRelayContext(
        TB_Subscription_Outbox__c outbox,
        Object resolvedMessage,
        TB_Message_Subscription__mdt subscription
    ) {
        this.outbox = outbox;
        this.resolvedMessage = resolvedMessage;
        this.subscription = subscription;
        // Settings that cannot be read belong to one subscription, so they must fail only the attempt
        // that needs them. Building the context happens before the attempt is counted, so the problem
        // is kept here and raised later by requireReadableConfig.
        if (subscription != null) {
            try {
                this.subscriptionConfig = TB_OutboxMetadataProvider.getSubscriptionConfig(subscription);
            } catch (TB_OutboxMetadataProvider.TB_InvalidConfigException e) {
                this.unreadableConfigReason = e.getMessage();
            }
        }

        // The log holds what was written during the most recent attempt only, so it starts empty.
        // The outbox is loaded without its stored log.
        this.outbox.Log__c = '';
        if (this.outbox.Relay_Attempts__c == null) {
            this.outbox.Relay_Attempts__c = 0;
        }
    }

    /**
     * The context is built before the attempt is counted and outside the attempt's error handling.
     * Raising the failure from the constructor would leave the attempt uncounted and stop the run,
     * so the attempt calls this once it has been counted.
     */
    public void requireReadableConfig() {
        if (unreadableConfigReason != null) {
            throw new TB_OutboxMetadataProvider.TB_InvalidConfigException(unreadableConfigReason);
        }
    }

    public void setAttempt() {
        outbox.Last_Attempt__c = Datetime.Now();
        outbox.Relay_Attempts__c++;
        // reset
        this.outbox.Next_Attempt_Timestamp__c = null;
    }

    public void setResult(Object result) {
        this.relayResult = result;
    }

    /**
     * Adds one line to the log of this attempt. A log too long for its field keeps its end when the
     * attempt's outcome is stored, as shortenTextToFitFields describes.
     */
    public void log(Object trace) {
        outbox.Log__c += System.now() + ': ' + trace.toString() + '\n';
    }

    // Read from the fields, so the shortening follows the fields if either is ever made shorter.
    private static final Integer LOG_FIELD_LENGTH = TB_Subscription_Outbox__c.Log__c.getDescribe().getLength();
    private static final Integer ERROR_FIELD_LENGTH = TB_Subscription_Outbox__c.Last_Error_Message__c.getDescribe()
        .getLength();

    /**
     * Shortens the log and the error so each fits its field. The platform rejects the whole outbox
     * update when either is too long, and that update also carries the attempt count, the delivery
     * and the retry wait, so text that is not shortened loses the outcome of the attempt.
     *
     * The error keeps its start, because the message comes before the stack trace. The log keeps its
     * end, the most recent lines logged. Each says it was shortened and how long it was. Text that
     * fits is left as it is.
     *
     * The length compared is the length of the text as written, line breaks included. In a scratch
     * org, a log of 131,073 characters ending in a line break saved and was stored as 131,072, and
     * 131,073 characters with no whitespace at the end failed. A log over the field length only by
     * a line break at its end is still shortened here.
     */
    public void shortenTextToFitFields() {
        // A field is assigned only when it is shortened. Assigning the log and the error, even to the
        // values they already hold, costs about 25 bytes of heap for each outbox the run holds.
        if (outbox.Log__c != null && outbox.Log__c.length() > LOG_FIELD_LENGTH) {
            outbox.Log__c = keepEnd(outbox.Log__c, LOG_FIELD_LENGTH);
        }
        if (outbox.Last_Error_Message__c != null && outbox.Last_Error_Message__c.length() > ERROR_FIELD_LENGTH) {
            outbox.Last_Error_Message__c = keepStart(outbox.Last_Error_Message__c, ERROR_FIELD_LENGTH);
        }
    }

    // Text is measured and cut in 16-bit units, and a character outside the Basic Multilingual Plane
    // takes two: a high surrogate then a low one. A cut between them keeps half a character, which
    // the platform saves as U+FFFD, so the cut moves by one unit to keep whole characters only. The
    // stored text can then be one unit under the field length.
    private static final Integer FIRST_HIGH_SURROGATE = 55296;
    private static final Integer LAST_HIGH_SURROGATE = 56319;
    private static final Integer FIRST_LOW_SURROGATE = 56320;
    private static final Integer LAST_LOW_SURROGATE = 57343;

    private static String keepStart(String text, Integer fieldLength) {
        String notice = '\n[Shortened from ' + text.length() + ' characters to fit its field. The end was dropped.]';
        Integer kept = fieldLength - notice.length();
        Integer lastKept = text.charAt(kept - 1);
        if (lastKept >= FIRST_HIGH_SURROGATE && lastKept <= LAST_HIGH_SURROGATE) {
            kept--;
        }
        return text.left(kept) + notice;
    }

    private static String keepEnd(String text, Integer fieldLength) {
        String notice = '[Shortened from ' + text.length() + ' characters to fit its field. The start was dropped.]\n';
        Integer kept = fieldLength - notice.length();
        Integer firstKept = text.charAt(text.length() - kept);
        if (firstKept >= FIRST_LOW_SURROGATE && firstKept <= LAST_LOW_SURROGATE) {
            kept--;
        }
        return notice + text.right(kept);
    }

    // will be called by OutboxRelay
    public void setError(Exception e) {
        outbox.Last_Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
        // set next attempt backoff (if not already set by client)
        if(outbox.Next_Attempt_Timestamp__c == null){
            outbox.Next_Attempt_Timestamp__c = TB_OutboxMetadataProvider.getSubscriptionNextAttemptTimeStamp(subscription, (Integer) outbox.Relay_Attempts__c);
        }
    }

    // will be called by OutboxRelay
    public void setSuccess() {
         // set TTL if configured and not already set 
        if(subscription.Mark_TTL_Event__c == 'completed' && subscription.TTL_Offset__c != null && outbox.TTL__c == null){
            outbox.TTL__c = System.now().addMinutes((Integer) subscription.TTL_Offset__c);
        }

        outbox.Completed_Timestamp__c = Datetime.Now();
    }

    public boolean isComplete() {
       
        return outbox.Completed_Timestamp__c != null;
    }

    public DateTime getNextAttemptTimestamp() {
        return outbox.Next_Attempt_Timestamp__c;
    }

    public void setNextAttemptTimestamp(Datetime nextAttemptTimestamp) {
        outbox.Next_Attempt_Timestamp__c = nextAttemptTimestamp;
    }

    public DateTime getTTL() {
        return outbox.TTL__c;
    }

    public void setTTL(Datetime expirationTimestamp) {
        outbox.TTL__c = expirationTimestamp;
    }
}