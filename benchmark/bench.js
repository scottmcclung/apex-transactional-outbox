// Publishes N messages of one type, waits for the relay to drain them, and reports what it cost.
//
// Usage: OUTBOX_ORG=<alias> node bench.js <message type> <sizes, comma separated> <seconds to wait per size>
// Example: OUTBOX_ORG=outbox-dev node bench.js bench_noop 1,10,100,200 90

const org = require("./lib/org.js");

const [messageType, sizesArgument, waitArgument] = process.argv.slice(2);
if (!messageType || !sizesArgument || !waitArgument) {
    console.error("Usage: node bench.js <message type> <sizes, comma separated> <seconds to wait per size>");
    process.exit(2);
}

function percentile(sortedValues, fraction) {
    if (sortedValues.length === 0) {
        return null;
    }
    return sortedValues[Math.min(sortedValues.length - 1, Math.floor(fraction * sortedValues.length))];
}

// The publish is measured inside the same anonymous block, so the figures cover the insert,
// the trigger's fan-out and the queueing of the relay, and nothing else.
function publish(type, size) {
    const result = org.apex(`
List<TB_Outbox_Message__c> messages = new List<TB_Outbox_Message__c>();
for (Integer i = 0; i < ${size}; i++) {
    messages.add(new TB_Outbox_Message__c(Type__c = '${type}', Message__c = '{"bench":' + i + '}'));
}
Integer queries = Limits.getQueries(), statements = Limits.getDmlStatements(), rows = Limits.getDmlRows(), cpu = Limits.getCpuTime();
insert messages;
System.debug('publish queries=' + (Limits.getQueries() - queries) + ' dmlStatements=' + (Limits.getDmlStatements() - statements) + ' dmlRows=' + (Limits.getDmlRows() - rows) + ' cpuMs=' + (Limits.getCpuTime() - cpu));`);
    return result.debug.find((line) => line.startsWith("publish")) || JSON.stringify(result).slice(0, 300);
}

function waitForDrain(maxSeconds) {
    const started = Date.now();
    let pending = -1;
    while (Date.now() - started < maxSeconds * 1000) {
        org.wait(5000);
        pending = org.count(
            "SELECT COUNT(Id) n FROM TB_Subscription_Outbox__c WHERE Completed_Timestamp__c = NULL AND Dead_Lettered__c = FALSE"
        );
        if (pending === 0 && org.activeRelayJobs() === 0) {
            break;
        }
        // Outboxes can stay pending with no job running, for example while waiting on a backoff.
        // After a grace period, two quiet checks end the wait.
        if (org.activeRelayJobs() === 0 && Date.now() - started > 25000) {
            org.wait(6000);
            if (org.activeRelayJobs() === 0) {
                break;
            }
        }
    }
    return { pending, seconds: Math.round((Date.now() - started) / 1000) };
}

function run(type, size, maxSeconds) {
    org.reset();
    const marker = org.startMarker();
    const publishCost = publish(type, size);
    const drain = waitForDrain(maxSeconds);

    const jobs = org.relayJobsSince(marker);
    const outboxes = org.query(
        "SELECT CreatedDate, Completed_Timestamp__c, Dead_Lettered__c, Relay_Attempts__c, Log__c, Last_Error_Message__c FROM TB_Subscription_Outbox__c"
    );
    const completed = outboxes.filter((outbox) => outbox.Completed_Timestamp__c);
    const delays = completed
        .map((outbox) => (new Date(outbox.Completed_Timestamp__c) - new Date(outbox.CreatedDate)) / 1000)
        .sort((a, b) => a - b);

    const attempts = {};
    for (const outbox of outboxes) {
        attempts[outbox.Relay_Attempts__c] = (attempts[outbox.Relay_Attempts__c] || 0) + 1;
    }

    // BenchClient writes the limits used so far into each outbox's log at the moment of its send.
    const insideRun = { queries: [], cpu: [], heap: [] };
    for (const outbox of outboxes) {
        const match = /bench q=(\d+) dml=(\d+) cpu=(\d+) heap=(\d+)/.exec(outbox.Log__c || "");
        if (match) {
            insideRun.queries.push(Number(match[1]));
            insideRun.cpu.push(Number(match[3]));
            insideRun.heap.push(Number(match[4]));
        }
    }

    const errors = {};
    for (const outbox of outboxes.filter((candidate) => candidate.Last_Error_Message__c)) {
        const firstLine = outbox.Last_Error_Message__c.split("\n")[0].slice(0, 110);
        errors[firstLine] = (errors[firstLine] || 0) + 1;
    }

    console.log(`\n===== ${type} x ${size}`);
    console.log("  " + publishCost);
    console.log(
        `  outboxes: ${outboxes.length} total, ${completed.length} completed, ` +
            `${outboxes.filter((outbox) => outbox.Dead_Lettered__c).length} dead-lettered; ` +
            `attempts per outbox: ${JSON.stringify(attempts)}`
    );
    console.log(`  relay jobs: ${jobs.length} -> ${JSON.stringify(org.summariseJobs(jobs))}`);
    if (delays.length > 0) {
        console.log(
            `  delay from publish to completed (s): min=${delays[0]} median=${percentile(delays, 0.5)} ` +
                `p95=${percentile(delays, 0.95)} max=${delays[delays.length - 1]}`
        );
    }
    if (insideRun.queries.length > 0) {
        console.log(
            `  inside the run, as seen at each send: queries min=${Math.min(...insideRun.queries)} ` +
                `max=${Math.max(...insideRun.queries)}; cpu ms max=${Math.max(...insideRun.cpu)}; ` +
                `heap bytes max=${Math.max(...insideRun.heap)}`
        );
    }
    if (Object.keys(errors).length > 0) {
        console.log("  last errors: " + JSON.stringify(errors));
    }
    console.log(`  watched for ${drain.seconds}s`);
}

org.assertScratchOrg();
for (const size of sizesArgument.split(",").map(Number)) {
    run(messageType, size, Number(waitArgument));
}
org.reset();
console.log("(data reset)");
