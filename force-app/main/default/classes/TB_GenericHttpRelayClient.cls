/**
 * A basic Http relay that can be used for many simple use cases.
 * Will send the resolvedMessage (or raw Message__c) in body.
 * Config Params:
 * - "uri" (required): URL or Named credential
 * - "method": http method (GET, POST, PUT, DELETE, etc). Defaults to POST
 * - "headers": A map of headers to send with the request. Can use Named Credentials parameters binding syntax
 * Example:
  {
     "uri": "CALLOUT:MyServiceEndpoint"
     "method": "PUT"
     "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer {!$Credential.Token}"
     }
  }
 */
public class TB_GenericHttpRelayClient implements TB_IOutboxRelayClient {
    // How long one request waits for the subscriber, in milliseconds. Set on every request and
    // declared by costOfSend from this one value, so the declaration cannot drift from the wait.
    // It equals the platform's default of 10 seconds, the wait a request gets when it sets none.
    // PLANNED: the wait comes from a required timeout setting on each subscription, and costOfSend
    // declares that subscription's value.
    private static final Integer CALLOUT_TIMEOUT_MS = 10000;

    // The most CPU one send was measured to use in a scratch org was 19 ms, for a 64 KB body with a
    // 128 KB response. CPU time varies between runs, so this allows more than twice that.
    private static final Integer SEND_CPU_TIME_MS = 50;

    // The longest body the message field holds, at about one byte of heap per character.
    private static final Integer LONGEST_BODY_BYTES = 131072;

    // Until the run saves, a send keeps the body twice in the attempt's log, and the response twice:
    // once in the log or the error, and once in the relay result. The response cannot be known
    // before sending, so it is assumed to be no longer than the longest body. The extra 4 KB covers
    // the log's other lines. A longer response, or a resolved message longer than the message field,
    // uses more than this.
    private static final Integer SEND_HEAP_BYTES = 4 * LONGEST_BODY_BYTES + 4096;

    public TB_SendCost costOfSend(TB_Message_Subscription__mdt subscription) {
        TB_SendCost cost = new TB_SendCost();
        cost.callouts = 1;
        cost.calloutTimeMs = CALLOUT_TIMEOUT_MS;
        cost.queries = 0;
        cost.queryRows = 0;
        cost.dmlStatements = 0;
        cost.dmlRows = 0;
        cost.eventPublishes = 0;
        cost.cpuTimeMs = SEND_CPU_TIME_MS;
        cost.heapBytes = SEND_HEAP_BYTES;
        return cost;
    }

    public void send(TB_OutboxRelayContext ctx) {
        Object bodyObj = ctx.resolvedMessage != null ? ctx.resolvedMessage : ctx.outbox.Outbox_Message__r.Message__c;
        String bodyStr = bodyObj instanceof String ? String.valueof(bodyObj) : JSON.serialize(bodyObj);
        String uri = String.valueof(ctx.subscriptionConfig.get('uri'));
        String method = ctx.subscriptionConfig.containsKey('method')
            ? String.valueof(ctx.subscriptionConfig.get('method'))
            : 'POST';

        ctx.log('Processing Record: ' + ctx.outbox.Id);
        ctx.log(new List<String>{ method, uri, bodyStr });
        // replace with carrier
        HttpRequest req = new HttpRequest();

        Map<String, Object> headers = (Map<String, Object>) ctx.subscriptionConfig.get('headers');
        if (headers != null) {
            for (String header : headers.keySet()) {
                req.setHeader(header, String.valueOf(headers.get(header)));
            }
        }


        ctx.log('body: ' + bodyStr);

        req.setEndpoint(uri);
        req.setBody(bodyStr);
        req.setMethod(method);
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        ctx.setResult(new GenericRelayResult(res));
        ctx.log('Status Code: ' + res.getStatusCode());
        if (res.getStatusCode() > 300) {
            throw new HttpRelayException(
                'Request Failed with status ' + res.getStatusCode() + '. Response Body: ' + res.getBody()
            );
        }
        ctx.log('Success. Response:' + res.getBody());
    }

    public class HttpRelayException extends Exception {
    }

    public class GenericRelayResult {
        public HttpResponseResult response;
        //TODO: Add request details?
        public GenericRelayResult(HttpResponse res) {
            response = new HttpResponseResult(res);
        }
    }

    public class HttpResponseResult {
        public Integer statusCode;
        public string status;
        public String body;
        //TODO: Add headers?
        public HttpResponseResult(HttpResponse res){
            this.statusCode = res.getStatusCode();
            this.status = res.getStatus();
            this.body = res.getBody();
        }
    }
}