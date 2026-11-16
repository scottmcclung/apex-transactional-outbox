// Finds how many outboxes one relay run can load when payloads are large.
// It builds outboxes with a payload of a chosen size, then makes K of them due at once and starts one run.
//
// Usage: OUTBOX_ORG=<alias> node heap.js <payload characters> <outboxes to build> <due counts, comma separated>
// Example: OUTBOX_ORG=outbox-dev node heap.js 131072 200 20,40,80,100,200

const org = require("./lib/org.js");

const [sizeArgument, totalArgument, dueArgument] = process.argv.slice(2);
if (!sizeArgument || !totalArgument || !dueArgument) {
    console.error("Usage: node heap.js <payload characters> <outboxes to build> <due counts, comma separated>");
    process.exit(2);
}
const payloadSize = Number(sizeArgument);
const total = Number(totalArgument);
const dueCounts = dueArgument.split(",").map(Number);

// Anonymous Apex has half the heap of a relay run, so large payloads are inserted a few at a time.
const INSERT_BATCH = 20;

function build() {
    for (let done = 0; done < total; done += INSERT_BATCH) {
        const batch = Math.min(INSERT_BATCH, total - done);
        const result = org.apex(`
String payload = 'x'.repeat(${payloadSize});
List<TB_Outbox_Message__c> messages = new List<TB_Outbox_Message__c>();
for (Integer i = 0; i < ${batch}; i++) {
    messages.add(new TB_Outbox_Message__c(Type__c = 'bench_noop', Message__c = payload));
}
insert messages;`);
        if (!result.success) {
            throw new Error(`Insert failed after ${done}: ` + JSON.stringify(result).slice(0, 300));
        }
    }
    const settled = org.waitForRelayToSettle(120);
    const built = org.count("SELECT COUNT(Id) n FROM TB_Subscription_Outbox__c");
    console.log(`built ${built} outboxes with a payload of ${payloadSize} characters (relay settled: ${settled})`);
}

// Marks every outbox delivered, then makes exactly dueCount of them due again with empty logs.
// Updating an outbox does not start a relay, so the run is started explicitly at the end.
function makeDue(dueCount) {
    return org.apex(`
List<TB_Subscription_Outbox__c> outboxes = [SELECT Id FROM TB_Subscription_Outbox__c ORDER BY Name];
Integer position = 0;
for (TB_Subscription_Outbox__c outbox : outboxes) {
    outbox.Log__c = null;
    outbox.Last_Error_Message__c = null;
    outbox.Relay_Attempts__c = 0;
    outbox.Next_Attempt_Timestamp__c = null;
    outbox.Completed_Timestamp__c = (position < ${dueCount}) ? null : System.now();
    position++;
}
update outboxes;
TB_OutboxRelayQueuable.enqueue();`);
}

function measure(dueCount) {
    org.waitForRelayToSettle(60);
    const marker = org.startMarker();
    const setup = makeDue(dueCount);
    if (!setup.success) {
        console.log(`due=${dueCount}: setup failed ` + JSON.stringify(setup).slice(0, 300));
        return;
    }
    org.wait(12000);
    org.waitForRelayToSettle(90);

    const jobs = org.relayJobsSince(marker);
    const attempted = org.query("SELECT Log__c FROM TB_Subscription_Outbox__c WHERE Relay_Attempts__c > 0");
    const heaps = attempted.map((outbox) => {
        const match = /heap=(\d+)/.exec(outbox.Log__c || "");
        return match ? Number(match[1]) : 0;
    });
    const undelivered = org.count("SELECT COUNT(Id) n FROM TB_Subscription_Outbox__c WHERE Completed_Timestamp__c = NULL");
    const peak = heaps.length > 0 ? Math.max(...heaps) : null;

    console.log(
        `due=${dueCount}: jobs=${JSON.stringify(org.summariseJobs(jobs))} attempted=${attempted.length} ` +
            `still undelivered=${undelivered} heap at last send=${peak === null ? "n/a" : peak}` +
            (peak === null ? "" : ` (${Math.round(peak / dueCount)} bytes per due outbox)`)
    );
}

org.assertScratchOrg();
org.reset();
build();
for (const dueCount of dueCounts) {
    measure(dueCount);
}
org.reset();
console.log("(data reset)");
