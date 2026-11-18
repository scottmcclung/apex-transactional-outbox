// Reproduces a known fault in a scratch org and prints what happened to the outboxes and relay jobs.
//
// Usage: OUTBOX_ORG=<alias> node reproduce.js <scenario> [seconds to watch]
// Scenarios are the file names in ./scenarios, without the extension.

const fs = require("fs");
const path = require("path");
const org = require("./lib/org.js");

const SCENARIO_FOLDER = path.join(__dirname, "scenarios");
const available = fs
    .readdirSync(SCENARIO_FOLDER)
    .filter((file) => file.endsWith(".apex"))
    .map((file) => file.replace(/\.apex$/, ""));

const [scenario, watchArgument] = process.argv.slice(2);
if (!available.includes(scenario)) {
    console.error("Usage: node reproduce.js <scenario> [seconds to watch]");
    console.error("Scenarios: " + available.join(", "));
    process.exit(2);
}
const watchSeconds = Number(watchArgument || 48);

// Scenarios that only run Apex and report through System.debug. They start no relay worth watching.
const DEBUG_ONLY = ["cleanup", "blank-max-attempts"];

// The cleanup scenario needs two delivered outboxes to work on.
function publishTwoDelivered() {
    const result = org.apex(
        "insert new List<TB_Outbox_Message__c>{ new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'one'), new TB_Outbox_Message__c(Type__c = 'repro_good', Message__c = 'two') };"
    );
    if (!result.success) {
        throw new Error("Could not publish the two messages: " + JSON.stringify(result));
    }
    org.waitForRelayToSettle(90);
}

function printApexResult(result) {
    if (result.compileProblem) {
        console.log("did not compile: " + result.compileProblem);
    }
    if (result.exception) {
        console.log("exception: " + result.exception);
        console.log(result.stack);
    }
    result.debug.forEach((line) => console.log("  " + line));
}

function printOutboxes() {
    const outboxes = org.query(
        "SELECT Outbox_Message__r.Type__c, Subscription__c, Relay_Attempts__c, Completed_Timestamp__c, Dead_Lettered__c, Last_Error_Message__c FROM TB_Subscription_Outbox__c ORDER BY Outbox_Message__r.Sequence_Number__c, Subscription__c"
    );
    console.log("outboxes, in publish order:");
    for (const outbox of outboxes) {
        const error = outbox.Last_Error_Message__c
            ? String(outbox.Last_Error_Message__c).split("\n")[0].slice(0, 90)
            : "none";
        console.log(
            `  type=${outbox.Outbox_Message__r.Type__c} subscription=${outbox.Subscription__c} ` +
                `attempts=${outbox.Relay_Attempts__c} completed=${outbox.Completed_Timestamp__c ? "yes" : "no"} ` +
                `deadLettered=${outbox.Dead_Lettered__c} error=${error}`
        );
    }
}

// The length of each stored error and log, and both its ends, so a person can see which end was kept.
function printTextEnds() {
    const outboxes = org.query(
        "SELECT Subscription__c, Last_Error_Message__c, Log__c FROM TB_Subscription_Outbox__c WHERE Subscription__c LIKE 'repro_oversized%' ORDER BY Subscription__c"
    );
    console.log("stored text, with line breaks shown as \\n:");
    for (const outbox of outboxes) {
        for (const field of ["Last_Error_Message__c", "Log__c"]) {
            const text = outbox[field];
            if (!text) {
                continue;
            }
            const shown = (part) => part.replace(/\n/g, "\\n");
            console.log(
                `  ${outbox.Subscription__c} ${field}: ${text.length} characters, ` +
                    `from [${shown(text.slice(0, 100))}] to [${shown(text.slice(-110))}]`
            );
        }
    }
}

function printActionRecords() {
    const records = org.query("SELECT Name FROM Account WHERE Name LIKE 'ReproAction%' ORDER BY CreatedDate, Name");
    if (records.length > 0) {
        console.log("records written by the after-relay actions:");
        records.forEach((record) => console.log("  " + record.Name));
    }
}

org.assertScratchOrg();
org.reset();
console.log(`===== ${scenario}`);

if (scenario === "cleanup") {
    publishTwoDelivered();
}

const marker = org.startMarker();
const result = org.apex(fs.readFileSync(path.join(SCENARIO_FOLDER, scenario + ".apex"), "utf8"));
printApexResult(result);
if (scenario === "cleanup") {
    console.log("outboxes left after the real cleanup: " + org.count("SELECT COUNT(Id) n FROM TB_Subscription_Outbox__c"));
}

if (!DEBUG_ONLY.includes(scenario)) {
    // A faulty outbox can make the relay re-queue itself, so the job count is sampled as it grows.
    const jobCounts = [];
    const deadline = Date.now() + watchSeconds * 1000;
    while (Date.now() < deadline) {
        org.wait(8000);
        jobCounts.push(org.relayJobsSince(marker).length);
    }
    console.log("relay job count, sampled every 8 seconds: " + jobCounts.join(", "));
    console.log("relay jobs: " + JSON.stringify(org.summariseJobs(org.relayJobsSince(marker))));
    printOutboxes();
    if (scenario === "oversized-text") {
        printTextEnds();
    }
    printActionRecords();
}

org.reset();
console.log("(data reset)");
