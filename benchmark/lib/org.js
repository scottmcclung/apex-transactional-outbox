// Helpers for driving a scratch org from the benchmark and reproduction scripts.
// Everything here goes through the Salesforce CLI, so the org must already be authenticated.

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const ORG = process.env.OUTBOX_ORG;
if (!ORG) {
    console.error("Set OUTBOX_ORG to the alias of the scratch org to use, for example: OUTBOX_ORG=outbox-dev");
    process.exit(2);
}

const RELAY_CLASS = "TB_OutboxRelayQueuable";
const ACTIVE_STATUSES = "('Queued','Preparing','Processing','Holding')";

// Query results that include payloads run to tens of megabytes.
const MAX_OUTPUT_BYTES = 256 * 1024 * 1024;

function sf(args) {
    const result = spawnSync("sf", [...args, "--target-org", ORG, "--json"], {
        encoding: "utf8",
        maxBuffer: MAX_OUTPUT_BYTES
    });
    try {
        return JSON.parse(result.stdout);
    } catch (error) {
        throw new Error("The Salesforce CLI did not return JSON: " + (result.stdout || result.stderr).slice(0, 400));
    }
}

// These scripts delete every outbox message in the org they are pointed at.
// A scratch org is the only kind that reports the dev hub it was created from.
function assertScratchOrg() {
    const info = sf(["org", "display"]).result || {};
    if (!info.devHubId) {
        console.error(`'${ORG}' is not a scratch org. These scripts delete data and only run against scratch orgs.`);
        process.exit(2);
    }
}

function query(soql) {
    const response = sf(["data", "query", "-q", soql]);
    if (response.status !== 0) {
        throw new Error("Query failed: " + String(response.message).replace(/\s+/g, " ").slice(0, 300));
    }
    return response.result.records.map((record) => {
        delete record.attributes;
        for (const value of Object.values(record)) {
            if (value && typeof value === "object") {
                delete value.attributes;
            }
        }
        return record;
    });
}

function count(soql) {
    return query(soql)[0].n;
}

// Runs anonymous Apex and returns whether it compiled and ran, any exception, and its System.debug lines.
function apex(code) {
    const file = path.join(os.tmpdir(), `outbox-benchmark-${process.pid}.apex`);
    fs.writeFileSync(file, code);
    const response = sf(["apex", "run", "-f", file]);
    fs.unlinkSync(file);
    const result = response.result || response.data || {};
    const debug = ((result.logs || "").match(/USER_DEBUG\|[^\n]*/g) || []).map((line) =>
        line.replace(/^USER_DEBUG\|\[\d+\]\|DEBUG\|/, "")
    );
    return {
        success: result.success === true,
        compileProblem: result.compileProblem || undefined,
        exception: result.exceptionMessage || undefined,
        stack: result.exceptionStackTrace || undefined,
        debug
    };
}

// Blocks without spinning the CPU. The scripts are synchronous throughout.
function wait(milliseconds) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function activeRelayJobs() {
    return count(
        `SELECT COUNT(Id) n FROM AsyncApexJob WHERE ApexClass.Name = '${RELAY_CLASS}' AND Status IN ${ACTIVE_STATUSES}`
    );
}

// A relay run queues its successor from a finalizer, so there is a short gap with no active job
// between two runs. Two quiet checks in a row are taken to mean the chain has ended.
function waitForRelayToSettle(maxSeconds) {
    const deadline = Date.now() + maxSeconds * 1000;
    let quietChecks = 0;
    while (Date.now() < deadline) {
        wait(5000);
        if (activeRelayJobs() === 0) {
            quietChecks += 1;
            if (quietChecks >= 2) {
                return true;
            }
        } else {
            quietChecks = 0;
        }
    }
    return false;
}

// A SOQL datetime literal for a moment just before now, to select jobs created from here on.
function startMarker() {
    return new Date(Date.now() - 2000).toISOString().replace(/\.\d+Z$/, "Z");
}

function relayJobsSince(marker) {
    return query(
        `SELECT Status, NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE ApexClass.Name = '${RELAY_CLASS}' AND CreatedDate >= ${marker} ORDER BY CreatedDate`
    );
}

// Groups jobs by status and error text, so a long chain prints as a few lines.
function summariseJobs(jobs) {
    const summary = {};
    for (const job of jobs) {
        const key = job.Status + (job.ExtendedStatus ? ` (${job.ExtendedStatus.slice(0, 90)})` : "");
        summary[key] = (summary[key] || 0) + 1;
    }
    return summary;
}

function remainingDailyAsyncExecutions() {
    const limits = sf(["org", "list", "limits"]).result;
    return limits.find((limit) => limit.name === "DailyAsyncApexExecutions").remaining;
}

// Removes every outbox message, which also removes its outboxes, and the records the test
// after-relay actions write. Waits for running relay jobs to finish so they do not touch the next test.
function reset() {
    const result = apex(
        "delete [SELECT Id FROM TB_Outbox_Message__c]; delete [SELECT Id FROM Account WHERE Name LIKE 'ReproAction%'];"
    );
    if (!result.success) {
        throw new Error("Reset failed: " + JSON.stringify(result));
    }
    for (let attempt = 0; attempt < 15; attempt += 1) {
        if (activeRelayJobs() === 0) {
            return;
        }
        wait(3000);
    }
    console.log("WARNING: relay jobs were still active after the reset");
}

module.exports = {
    ORG,
    assertScratchOrg,
    query,
    count,
    apex,
    wait,
    activeRelayJobs,
    waitForRelayToSettle,
    startMarker,
    relayJobsSince,
    summariseJobs,
    remainingDailyAsyncExecutions,
    reset
};
