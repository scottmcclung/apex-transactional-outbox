/**
 * What a relay run stores when an attempt's error or log is too long for its field.
 *
 * The outbox is saved with one update, and the platform rejects the whole update when either text
 * is longer than its field. The attempt count, the delivery and the retry wait are in that same
 * update, so a text that is not shortened first loses the outcome of the attempt.
 *
 * The error keeps its start, because the message comes before the stack trace. The log keeps its
 * end, because it ends with what the subscriber answered. Both say they were shortened.
 */
@isTest
public class TB_OversizedTextTests {
    static final Integer FIELD_LENGTH = TB_TransactionOutboxTestUtils.LONG_TEXT_FIELD_LENGTH;

    // Far enough over the field that the dropped end holds the last characters of the message or
    // of the logged line, whatever the notice takes.
    static final Integer WELL_OVER_FIELD_LENGTH = FIELD_LENGTH + 5000;

    // What the log puts in front of each line: a timestamp to the second, a colon and a space.
    // After the line it adds one line break. Kept in step with the log by hand, and checked by
    // the test of a log that exactly fills its field.
    static final Integer LOG_LINE_PREFIX_LENGTH = 21;
    static final Integer LOG_LINE_BREAK_LENGTH = 1;

    // A failed attempt waits this many minutes, so a saved failure shows a next attempt time.
    static final String RETRY_BACKOFF = '5';

    /**
     * One subscription whose client logs a line and fails with an error of the given lengths.
     * A null length leaves that part out, and no error length means the send succeeds.
     */
    static TB_Message_Subscription__mdt addLongTextSubscription(Integer logLength, Integer errorLength) {
        TB_Application__mdt app = TB_TransactionOutboxTestUtils.addApplication('TestApp');
        TB_Message_Definition__mdt msgDef = TB_TransactionOutboxTestUtils.addEventDefinition('test.message1');
        TB_Message_Subscription__mdt subscription = TB_TransactionOutboxTestUtils.addSubscription(
            app,
            msgDef,
            'long_text_feed'
        );
        subscription.Relay_Client__c = 'TB_TransactionOutboxTestUtils.LongTextClient';
        subscription.Retry_BackOff__c = RETRY_BACKOFF;
        Map<String, Integer> settings = new Map<String, Integer>();
        if (logLength != null) {
            settings.put('logLength', logLength);
        }
        if (errorLength != null) {
            settings.put('errorLength', errorLength);
        }
        subscription.Config__c = JSON.serialize(settings);
        return subscription;
    }

    /** Publishes one message and lets the relay run and its finalizer finish. */
    static TB_Subscription_Outbox__c relayOneMessage() {
        Test.startTest();
        insert new TB_Outbox_Message__c(Type__c = 'test.message1', Message__c = 'Test Payload');
        Test.stopTest();

        System.assertEquals(
            1,
            TB_TransactionOutboxTestUtils.sentMessages.size(),
            'The client should have been asked to send once'
        );
        return [
            SELECT
                Relay_Attempts__c,
                Last_Attempt__c,
                Last_Error_Message__c,
                Log__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c,
                Dead_Lettered__c
            FROM TB_Subscription_Outbox__c
        ];
    }

    /** A text's length and both its ends, for a failure message that stays readable. */
    static String describe(String text) {
        if (text == null) {
            return 'null';
        }
        return text.length() + ' characters, from [' + text.left(120) + '] to [' + text.right(120) + ']';
    }

    static void assertFailedAttemptIsSaved(TB_Subscription_Outbox__c outbox) {
        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The failed attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertNotEquals(null, outbox.Last_Attempt__c, 'The time of the attempt should be saved');
        System.assertEquals(null, outbox.Completed_Timestamp__c, 'A failed attempt should not be marked delivered');
        System.assertNotEquals(
            null,
            outbox.Next_Attempt_Timestamp__c,
            'The failed attempt should wait on its subscription backoff'
        );
        System.assert(String.isNotBlank(outbox.Last_Error_Message__c), 'The reason for the failure should be saved');
    }

    static void assertDeliveryIsSaved(TB_Subscription_Outbox__c outbox) {
        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertNotEquals(
            null,
            outbox.Completed_Timestamp__c,
            'The subscriber got the message, so the outbox should be marked delivered'
        );
        System.assertEquals(null, outbox.Last_Error_Message__c, 'A delivery should record no error');
    }

    /** The stored error is the start of what was thrown, with a notice, and uses the room it has. */
    static void assertErrorKeepsItsStartAndSaysItWasShortened(String stored) {
        String thrown = TB_TransactionOutboxTestUtils.longTextClientError;
        System.assertNotEquals(null, stored, 'An error should be saved');
        System.assert(
            stored.length() <= FIELD_LENGTH,
            'The shortened error should fit its field, notice included, but is ' + stored.length() + ' characters'
        );
        System.assert(
            stored.startsWith(
                thrown.left(FIELD_LENGTH - TB_TransactionOutboxTestUtils.SHORTENED_NOTICE_ALLOWANCE)
            ),
            'The error should keep its start and as much as fits, but is ' + describe(stored)
        );
        System.assert(
            TB_TransactionOutboxTestUtils.saysItWasShortened(stored),
            'The error should say it was shortened, but is ' + describe(stored)
        );
    }

    /** The stored log is the end of what was logged, with a notice, and uses the room it has. */
    static void assertLogKeepsItsEndAndSaysItWasShortened(String stored) {
        String logged = TB_TransactionOutboxTestUtils.longTextClientLogged;
        System.assertNotEquals(null, stored, 'A log should be saved');
        System.assert(
            stored.length() <= FIELD_LENGTH,
            'The shortened log should fit its field, notice included, but is ' + stored.length() + ' characters'
        );
        // The platform drops a line break at the very end of a text when it stores it, so the
        // stored log ends with the last characters that were logged.
        System.assert(
            stored.endsWith(
                logged.right(FIELD_LENGTH - TB_TransactionOutboxTestUtils.SHORTENED_NOTICE_ALLOWANCE)
            ),
            'The log should keep its end and as much as fits, but is ' + describe(stored)
        );
        System.assert(
            TB_TransactionOutboxTestUtils.saysItWasShortened(stored),
            'The log should say it was shortened, but is ' + describe(stored)
        );
    }

    @isTest
    static void testWhenErrorIsLongerThanItsFieldThenFailedAttemptIsSaved() {
        addLongTextSubscription(null, WELL_OVER_FIELD_LENGTH);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertFailedAttemptIsSaved(outbox);
        System.assertEquals(false, outbox.Dead_Lettered__c, 'An outbox with attempts left should stay pending');
    }

    @isTest
    static void testWhenErrorIsLongerThanItsFieldThenItsStartIsKeptAndItSaysItWasShortened() {
        addLongTextSubscription(null, WELL_OVER_FIELD_LENGTH);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertErrorKeepsItsStartAndSaysItWasShortened(outbox.Last_Error_Message__c);
        System.assert(
            outbox.Last_Error_Message__c.startsWith(TB_TransactionOutboxTestUtils.LONG_TEXT_START),
            'The error should begin with the start of the message'
        );
        System.assert(
            !outbox.Last_Error_Message__c.contains(TB_TransactionOutboxTestUtils.LONG_TEXT_END),
            'The end of the message is past the field length, so it should be the part dropped'
        );
    }

    @isTest
    static void testWhenErrorIsLongerThanItsFieldOnLastAttemptThenOutboxIsDeadLettered() {
        addLongTextSubscription(null, WELL_OVER_FIELD_LENGTH).Max_Attempts__c = 1;

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        System.assertEquals(
            1,
            outbox.Relay_Attempts__c,
            'The failed attempt should be counted. A count of 0 means the outcome was not saved'
        );
        System.assertEquals(
            true,
            outbox.Dead_Lettered__c,
            'An outbox that failed its last attempt should be dead-lettered, however long its error'
        );
    }

    @isTest
    static void testWhenErrorIsOneCharacterLongerThanItsFieldThenItIsShortenedAndSaved() {
        addLongTextSubscription(null, FIELD_LENGTH + 1);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertFailedAttemptIsSaved(outbox);
        assertErrorKeepsItsStartAndSaysItWasShortened(outbox.Last_Error_Message__c);
    }

    @isTest
    static void testWhenErrorIsExactlyAsLongAsItsFieldThenItIsSavedUnchanged() {
        addLongTextSubscription(null, FIELD_LENGTH);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertFailedAttemptIsSaved(outbox);
        System.assertEquals(
            FIELD_LENGTH,
            TB_TransactionOutboxTestUtils.longTextClientError.length(),
            'The client should have thrown an error that exactly fills the field'
        );
        // Compared as a Boolean so a failure does not print two texts of this length.
        System.assert(
            outbox.Last_Error_Message__c == TB_TransactionOutboxTestUtils.longTextClientError,
            'An error that fits its field should be stored as it was thrown, but is ' +
            describe(outbox.Last_Error_Message__c)
        );
        System.assert(
            !TB_TransactionOutboxTestUtils.saysItWasShortened(outbox.Last_Error_Message__c),
            'An error that fits its field should not say it was shortened'
        );
    }

    @isTest
    static void testWhenLogIsLongerThanItsFieldAndSendSucceedsThenOutboxIsMarkedDelivered() {
        addLongTextSubscription(WELL_OVER_FIELD_LENGTH, null);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertDeliveryIsSaved(outbox);
    }

    @isTest
    static void testWhenLogIsLongerThanItsFieldThenItsEndIsKeptAndItSaysItWasShortened() {
        addLongTextSubscription(WELL_OVER_FIELD_LENGTH, null);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertLogKeepsItsEndAndSaysItWasShortened(outbox.Log__c);
        System.assert(
            !outbox.Log__c.contains(TB_TransactionOutboxTestUtils.LONG_TEXT_START),
            'The start of the logged line is what does not fit, so it should be the part dropped'
        );
    }

    @isTest
    static void testWhenLogIsOneCharacterLongerThanItsFieldThenItIsShortenedAndDeliveryIsSaved() {
        // The line break that ends the log is not counted here, because the platform drops it
        // before it checks the length. Without it this log is one character more than the field holds.
        addLongTextSubscription(FIELD_LENGTH + 1 - LOG_LINE_PREFIX_LENGTH, null);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertDeliveryIsSaved(outbox);
        assertLogKeepsItsEndAndSaysItWasShortened(outbox.Log__c);
    }

    @isTest
    static void testWhenLogIsExactlyAsLongAsItsFieldThenItIsSavedUnchanged() {
        // Sized so the whole log, with its timestamp and its closing line break, is the field length.
        addLongTextSubscription(FIELD_LENGTH - LOG_LINE_PREFIX_LENGTH - LOG_LINE_BREAK_LENGTH, null);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertDeliveryIsSaved(outbox);
        // The platform drops the closing line break when it stores the log. Any other length means
        // the log was changed, or that this test no longer sizes its line the way the log does.
        System.assertEquals(
            FIELD_LENGTH - LOG_LINE_BREAK_LENGTH,
            outbox.Log__c.length(),
            'A log that fits its field should be stored whole'
        );
        System.assert(
            outbox.Log__c.endsWith(TB_TransactionOutboxTestUtils.longTextClientLogged),
            'A log that fits its field should hold the whole line that was logged, but is ' + describe(outbox.Log__c)
        );
        System.assert(
            !TB_TransactionOutboxTestUtils.saysItWasShortened(outbox.Log__c),
            'A log that fits its field should not say it was shortened'
        );
    }

    @isTest
    static void testWhenLogAndErrorAreBothLongerThanTheirFieldsThenFailedAttemptIsSavedWithBothShortened() {
        addLongTextSubscription(WELL_OVER_FIELD_LENGTH, WELL_OVER_FIELD_LENGTH);

        TB_Subscription_Outbox__c outbox = relayOneMessage();

        assertFailedAttemptIsSaved(outbox);
        assertErrorKeepsItsStartAndSaysItWasShortened(outbox.Last_Error_Message__c);
        assertLogKeepsItsEndAndSaysItWasShortened(outbox.Log__c);
    }
}
