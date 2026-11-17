// An example of activating the framework. Change the job names and schedules to suit your org.
// Both jobs start out hourly. One schedule expression fires at most once an hour, so a finer
// schedule needs several jobs at different minutes.

// The relay sweep starts a relay run when nothing else does, for example when an outbox's retry
// wait has ended and no new message has been published. Its interval is the longest such an
// outbox waits.
System.schedule('TB Outbox Relay', '0 0 * * * ?', new TB_ScheduleRelay());

// Cleanup removes delivered outboxes whose TTL has passed, and messages with no outboxes left
// whose definition asks for that. Until it is scheduled, no record is removed.
System.schedule('TB Outbox Cleanup', '0 0 * * * ?', new TB_RecordCleanup());
