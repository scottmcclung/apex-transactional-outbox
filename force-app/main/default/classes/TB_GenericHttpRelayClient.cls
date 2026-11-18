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

    // Measured in a scratch org with Limits.getCpuTime() around six sends of a 131,072 character
    // String body to an echo service, which answered each with HTTP 500 and a 21 character body.
    // The first send in the transaction used 63 ms and the other five used 3 to 6 ms. Sends against
    // a callout mock returning a 131,072 character body used 5 or 6 ms in 20 samples, half with a
    // String body and half with a one-key Map. This allows half again over the highest seen. A
    // resolved message that is not a String is serialized to JSON first, and a large or deeply
    // nested one can use more than this.
    private static final Integer SEND_CPU_TIME_MS = 100;

    // The longest body the message field holds. A String takes one byte of heap per character
    // plus a few bytes, as measured with Limits.getHeapSize().
    private static final Integer LONGEST_BODY_BYTES = 131072;

    // Counted in copies of the longest body, for a body and a response each no longer than it. The
    // response cannot be known before sending, so that is an assumption. A longer body or response
    // uses more, in proportion to its length.
    //
    // Each log line rebuilds the whole log, so the old and new log are held at once. The worst point
    // is the line that logs the response on success. Before it the send holds the log with the body
    // once (1), the response and the relay result's copy of its body (2), and the JSON body when the
    // resolved message is not a String (1). That line builds the response text through up to five
    // strings (5) and a new log holding the body and the response once each (2). Limits.getHeapSize()
    // cannot be read inside one statement, so all five are counted as held at once. That is 11
    // copies. The status line logged after it holds 7: the response, its copy and the JSON body (3),
    // and the old and the new log with the body and the response in each (4). The extra 4 KB covers
    // the log's other lines, held in the old and the new log at once, and the status line, built
    // before the response is logged. At the worst point they name the endpoint three times, so it
    // covers an endpoint of up to about 1,200 characters.
    //
    // What a send still holds when it returns is lower. In a test against a mock it was 3 copies on
    // success, and 4 on failure once the run stored the error message.
    private static final Integer SEND_HEAP_BYTES = 11 * LONGEST_BODY_BYTES + 4096;

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
        ctx.log('Request body: ' + bodyStr);
        // Logged after the body. A log too long for its field keeps its end, and a send that throws
        // before any answer logs no status line, so with a long body this is the line that still
        // says where the request went.
        ctx.log('Sending ' + method + ' ' + uri);
        // replace with carrier
        HttpRequest req = new HttpRequest();

        Map<String, Object> headers = (Map<String, Object>) ctx.subscriptionConfig.get('headers');
        if (headers != null) {
            for (String header : headers.keySet()) {
                req.setHeader(header, String.valueOf(headers.get(header)));
            }
        }

        req.setEndpoint(uri);
        req.setBody(bodyStr);
        req.setMethod(method);
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        ctx.setResult(new GenericRelayResult(res));
        // Names the method and endpoint again with the status, and is the last line of the attempt. A
        // log too long for its field keeps its end, and with a long response the lines before this
        // one are in the part dropped.
        String statusLine = method + ' ' + uri + ' answered with status ' + res.getStatusCode();
        if (res.getStatusCode() > 300) {
            ctx.log(statusLine);
            throw new HttpRelayException(
                'Request Failed with status ' + res.getStatusCode() + '. Response Body: ' + res.getBody()
            );
        }
        ctx.log('Success. Response:' + res.getBody());
        ctx.log(statusLine);
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