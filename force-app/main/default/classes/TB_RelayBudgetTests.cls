/**
 * The comparison a relay run makes before each attempt, between what one send is declared to need
 * and what the run has left. What is left is given here as a TB_SendCost, one amount per limit,
 * so every limit can be tested at its edge without a run having to use that limit up first.
 */
@isTest
public class TB_RelayBudgetTests {
    // Different for every limit, so an amount compared against the wrong limit shows up.
    static TB_SendCost someAmounts() {
        TB_SendCost amounts = new TB_SendCost();
        amounts.callouts = 3;
        amounts.calloutTimeMs = 30000;
        amounts.queries = 5;
        amounts.queryRows = 700;
        amounts.dmlStatements = 2;
        amounts.dmlRows = 40;
        amounts.eventPublishes = 6;
        amounts.cpuTimeMs = 900;
        amounts.heapBytes = 80000;
        return amounts;
    }

    static TB_SendCost withField(TB_SendCost amounts, String field, Integer amount) {
        Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(amounts));
        fields.put(field, amount);
        return (TB_SendCost) JSON.deserialize(JSON.serialize(fields), TB_SendCost.class);
    }

    static Integer amountOf(TB_SendCost amounts, String field) {
        return (Integer) ((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(amounts))).get(field);
    }

    @isTest
    static void testWhenSendNeedsExactlyWhatIsLeftOfEveryLimitThenThereIsRoom() {
        System.assertEquals(
            true,
            TB_OutboxRelayQueuable.hasBudgetFor(someAmounts(), someAmounts()),
            'A send that uses up exactly what is left stays inside every limit'
        );
    }

    @isTest
    static void testWhenSendNeedsOneMoreThanIsLeftOfAnyLimitThenThereIsNoRoom() {
        for (String field : TB_TransactionOutboxTestUtils.SEND_COST_FIELDS) {
            TB_SendCost cost = withField(someAmounts(), field, amountOf(someAmounts(), field) + 1);

            System.assertEquals(
                false,
                TB_OutboxRelayQueuable.hasBudgetFor(cost, someAmounts()),
                'A send that needs one more than is left of ' + field + ' should not fit'
            );
        }
    }

    /**
     * A limit that is used up only stops the sends that need some of it. A send that makes no
     * callouts still fits in a run that has none left.
     */
    @isTest
    static void testWhenNothingIsLeftOfALimitTheSendDoesNotUseThenThereIsRoom() {
        for (String field : TB_TransactionOutboxTestUtils.SEND_COST_FIELDS) {
            TB_SendCost cost = withField(someAmounts(), field, 0);
            TB_SendCost left = withField(someAmounts(), field, 0);

            System.assertEquals(
                true,
                TB_OutboxRelayQueuable.hasBudgetFor(cost, left),
                'A send that uses no ' + field + ' should fit when none is left'
            );
        }
    }
}
