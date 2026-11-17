public class TB_OutboxRelayQueuable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    static DateTime executeStart;
    public TB_OutboxRelayQueuable() {
    }
  
    /**
     * One relay run. It attempts at most the configured batch size and leaves the rest for the next run.
     *
     * Before each attempt it asks the relay client what one send needs, and compares that with what the
     * run has left of each limit it works within. An outbox it has no room for is passed over: it is not
     * charged an attempt and is left as it is, and the run goes on to the next outbox. The run's first
     * attempt is not checked for room. A run that could attempt nothing would leave every outbox as it
     * was, and its finalizer would queue the next run in the same state, without end. If a send reaches
     * a limit anyway and the platform's error can be caught, that attempt is abandoned and the run starts
     * nothing more. Either way the run ends normally, saves its outcomes, and its finalizer queues the
     * next run. A limit the platform does not let code catch still ends the run part-way, and the
     * finalizer stores what was done.
     */
    public void execute(QueueableContext ctx) {
      executeStart = System.now();
  
      Integer batchSize = TB_OutboxMetadataProvider.getRelayBatchSize();
      Integer fallbackRetryWait = TB_OutboxMetadataProvider.getFallbackRetryWait();
      GroupHolds holds = new GroupHolds();
      List<TB_Subscription_Outbox__c> outboxRecords = loadForAttempt(
        chooseAttemptable(batchSize, scanPageSize(batchSize), holds, executeStart),
        holds,
        executeStart
      );
  
      Map<String, TB_Message_Definition__mdt> definitionsByName = TB_OutboxMetadataProvider.getMessageDefintionMap();

      // An outbox finds its subscription by name, whichever message definition that subscription is on now.
      Map<String, TB_Message_Subscription__mdt> subscriptionsByName = TB_OutboxMetadataProvider.getSubscriptionsByName(
        subscriptionNamesOf(outboxRecords)
      );

      Map<String, TB_Outbox_Message__c[]> msgsByType = groupMessagesByType(
        plannedAttempts(
          outboxRecords,
          holds,
          subscriptionsByName,
          definitionsByName
        )
      );

      // Begun just before the message resolvers, the first code in the run that may make a callout.
      RunBudget budget = new RunBudget();

      // transform DTO's
      Map<Id, Object> allResolvedMessages = resolveMessages(
        msgsByType,
        definitionsByName
      );

      OutboxFinalizer finalizer = attachFinalizer(
        holds,
        scanPageSize(batchSize)
      );
  
      RelayTurns turns = new RelayTurns(holds);
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        TB_Message_Subscription__mdt subDef = subscriptionsByName.get(
          item.Subscription__c
        );
        TB_Message_Definition__mdt msgDef = definitionsByName.get(
          item.Outbox_Message__r.Type__c
        );

        TurnOutcome turn = turns.take(item, subDef, msgDef);
        if (turn == TurnOutcome.NO_CONFIGURATION) {
          failWithoutConfiguration(
            item,
            subDef,
            msgDef,
            fallbackRetryWait,
            finalizer
          );
        } else if (turn == TurnOutcome.ATTEMPT) {
          Object resolvedEvt = allResolvedMessages.get(item.Outbox_Message__c);
          AttemptOutcome outcome = attemptRelay(
            item,
            resolvedEvt,
            subDef,
            finalizer,
            budget
          );
          if (outcome == AttemptOutcome.FAILED) {
            turns.sendFailed(item);
          } else if (outcome == AttemptOutcome.NO_ROOM) {
            turns.noRoom(item);
          } else if (outcome == AttemptOutcome.ABANDONED) {
            // A run that has reached one of its limits starts nothing more. The outboxes after this
            // one are left as they are for the next run.
            break;
          }
        }
      }
  
      // attempt to save results with Lock
      finalizer.save();
    }
  
    /**
     * The outboxes this run will attempt, as far as that is known before the first attempt.
     * Any outbox the run attempts is in it, so its message reaches its resolver.
     *
     * It takes the same turns the run takes, starting from the holds the run has now. Whether a send
     * fails is not known yet, so each planned attempt is counted as one that may fail. An outbox a
     * failed send would hold is still planned, and the run may then not attempt it. The same goes for
     * an outbox the run turns out to have no room for, and for one after an abandoned attempt.
     */
    private static List<TB_Subscription_Outbox__c> plannedAttempts(
      List<TB_Subscription_Outbox__c> outboxRecords,
      GroupHolds holds,
      Map<String, TB_Message_Subscription__mdt> subscriptionsByName,
      Map<String, TB_Message_Definition__mdt> definitionsByName
    ) {
      RelayTurns plan = new RelayTurns(holds.copy());
      List<TB_Subscription_Outbox__c> attempts = new List<TB_Subscription_Outbox__c>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        TurnOutcome turn = plan.take(
          item,
          subscriptionsByName.get(item.Subscription__c),
          definitionsByName.get(item.Outbox_Message__r.Type__c)
        );
        if (turn == TurnOutcome.ATTEMPT) {
          attempts.add(item);
          plan.sendMayFail(item);
        }
      }
      return attempts;
    }

    /**
     * Message resolvers work on one message type at a time, in the order the outboxes will be processed.
     * A message appears once, however many of its outboxes there are.
     */
    private Map<String, TB_Outbox_Message__c[]> groupMessagesByType(
      List<TB_Subscription_Outbox__c> outboxRecords
    ) {
      Map<String, TB_Outbox_Message__c[]> msgsByType = new Map<String, TB_Outbox_Message__c[]>();
      Set<Id> grouped = new Set<Id>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        if (!grouped.add(item.Outbox_Message__c)) {
          continue;
        }
        if (!msgsByType.containsKey(item.Outbox_Message__r.Type__c)) {
          msgsByType.put(
            item.Outbox_Message__r.Type__c,
            new List<TB_Outbox_Message__c>{}
          );
        }
  
        msgsByType.get(item.Outbox_Message__r.Type__c)
          .add(item.Outbox_Message__r);
      }
      return msgsByType;
    }
  
    /**
     * Attaches the finalizer before any attempt is made, so results are stored even if the run
     * is stopped by a limit.
     */
    private OutboxFinalizer attachFinalizer(
      GroupHolds holds,
      Integer scanPageSize
    ) {
      OutboxFinalizer finalizer = new OutboxFinalizer(holds, scanPageSize);
      System.attachFinalizer(finalizer);
      return finalizer;
    }
  
    /** How one relay attempt ended, or why none was made. */
    private enum AttemptOutcome {
      DELIVERED,
      FAILED,
      // Nothing was attempted, because the run has too little left for what one send needs.
      NO_ROOM,
      // The run reached one of its own limits during the attempt, so the attempt is not counted.
      ABANDONED
    }

    /**
     * Makes one relay attempt for an outbox when the run has room for it or has not started an attempt
     * yet, and hands the outcome to the finalizer. The attempt is delivered when it finished without an exception, and failed otherwise.
     *
     * The relay client is built and asked what one send needs before the attempt is counted. When the
     * run has too little left of any limit for that, nothing is attempted and the outbox is not handed
     * to the finalizer, so it stays as it is. The run's first attempt goes ahead without that check,
     * so a run that reaches an outbox it could send never ends having sent nothing for lack of room.
     * A client that cannot be built, or whose cost cannot be used, fails the counted attempt before
     * anything is sent, like any other fault of the client. That attempt never reached the room
     * check, so the run's first attempt is still to come.
     *
     * A subscription config that cannot be read fails the counted attempt before anything is sent,
     * and the outbox waits on its subscription's backoff like any failed attempt.
     */
    private AttemptOutcome attemptRelay(
      TB_Subscription_Outbox__c item,
      Object resolvedEvt,
      TB_Message_Subscription__mdt subDef,
      OutboxFinalizer finalizer,
      RunBudget budget
    ) {
      TB_OutboxRelayContext obCtx = new TB_OutboxRelayContext(
        item,
        resolvedEvt,
        subDef
      );

      TB_IOutboxRelayClient client;
      try {
        client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(subDef);
        // Read before the first-attempt rule is applied, so a declaration that cannot be used fails
        // the first attempt too.
        TB_SendCost cost = declaredCostOfSend(client, subDef);
        if (budget.hasStartedAnAttempt() && !budget.hasRoomFor(cost)) {
          return AttemptOutcome.NO_ROOM;
        }
      } catch (Exception e) {
        obCtx.setAttempt();
        obCtx.setError(e);
        finalizer.addResult(obCtx);
        return AttemptOutcome.FAILED;
      }
      budget.attemptStarted();

      // A client may replace the TTL during its send, and an abandoned attempt must not keep that.
      Datetime ttlBeforeAttempt = item.TTL__c;
      AttemptOutcome outcome = AttemptOutcome.FAILED;
      try {
        obCtx.setAttempt();
  
        // rethrow if we failed to resolve the message!
        if (resolvedEvt != null && resolvedEvt instanceof Exception) {
          throw (Exception) resolvedEvt;
        }
  
        obCtx.requireReadableConfig();
        client.send(obCtx);
        obCtx.setSuccess();
        outcome = AttemptOutcome.DELIVERED;
      } catch (Exception e) {
        if (isRunLimitError(e)) {
          abandon(obCtx, ttlBeforeAttempt, e);
          outcome = AttemptOutcome.ABANDONED;
        } else {
          obCtx.setError(e);
        }
      } finally {
        // A limit raised as System.LimitException cannot be caught and ends the transaction without
        // reaching here, so that outbox is left as it was and the finalizer saves the others.
        finalizer.addResult(obCtx);
      }
      return outcome;
    }

    // The start of the message the platform gives when the callouts of one transaction have taken
    // longer in total than it allows. The limit's value follows in the message and is left out, so
    // the match does not depend on it.
    private static final String CALLOUT_TIME_LIMIT_MESSAGE = 'Exceeded maximum time allotted for callout';

    /**
     * Whether an exception caught during an attempt means the run reached one of its own limits.
     *
     * The platform raises most limits as System.LimitException, which no catch block receives, so
     * they never get here. Total callout time is different: the callout that goes over it throws a
     * System.CalloutException, which can be caught. A subscriber that does not answer in time also
     * throws a CalloutException, and that is a real failure of the attempt, so the limit is
     * recognised by the type and the start of the message together. A client that catches the error
     * and throws its own exception instead has its attempt counted as failed.
     */
    private static Boolean isRunLimitError(Exception e) {
      return e instanceof System.CalloutException &&
        e.getMessage() != null &&
        e.getMessage().startsWith(CALLOUT_TIME_LIMIT_MESSAGE);
    }

    /**
     * Undoes the parts of an attempt that would charge the outbox for a limit the run reached. That is
     * the run's doing and says nothing about the subscriber, so the attempt is not counted, no error is
     * recorded and no wait is added, not even one the client asked for. An outbox on its last attempt
     * is therefore not dead-lettered. A TTL the client set during the attempt is put back to what the
     * outbox had before it, because only a delivered or failed attempt keeps what the client chose.
     * The attempt time and whatever the attempt logged are kept, so the outbox still shows that an
     * attempt was started and how far it got.
     */
    private static void abandon(
      TB_OutboxRelayContext obCtx,
      Datetime ttlBeforeAttempt,
      Exception e
    ) {
      obCtx.outbox.Relay_Attempts__c--;
      obCtx.outbox.Next_Attempt_Timestamp__c = null;
      obCtx.outbox.TTL__c = ttlBeforeAttempt;
      // PLANNED: report the abandoned attempt through the subscription's log adapter, so a client that
      // uses more than it declares gets noticed. Until then the debug log is the only record of why.
      System.debug(
        'Relay attempt abandoned at a run limit for outbox ' +
          obCtx.outbox.Id +
          ': ' +
          e.getMessage()
      );
    }

    /**
     * What the relay client says one send for this subscription needs, checked so it can be compared
     * with what the run has left. A cost that is missing, or has a field that is unset or negative,
     * cannot be compared, and is the client's fault. An unset field is never taken to mean 0.
     */
    private static TB_SendCost declaredCostOfSend(
      TB_IOutboxRelayClient client,
      TB_Message_Subscription__mdt subDef
    ) {
      String clientName = subDef.Relay_Client__c;
      TB_SendCost cost;
      try {
        cost = client.costOfSend(subDef);
      } catch (Exception e) {
        throw new SendCostException(
          'Relay client ' +
            clientName +
            ' could not state the cost of a send, so nothing was sent. It raised ' +
            e.getTypeName() +
            ': ' +
            e.getMessage(),
          e
        );
      }
      if (cost == null) {
        throw new SendCostException(
          'Relay client ' +
            clientName +
            ' stated no cost for a send, so the run could not tell whether it had room for one. Nothing was sent.'
        );
      }
      // The fields are checked one by one, without building a map, because this runs before every
      // attempt.
      requireUsableAmount(clientName, 'callouts', cost.callouts);
      requireUsableAmount(clientName, 'calloutTimeMs', cost.calloutTimeMs);
      requireUsableAmount(clientName, 'queries', cost.queries);
      requireUsableAmount(clientName, 'queryRows', cost.queryRows);
      requireUsableAmount(clientName, 'dmlStatements', cost.dmlStatements);
      requireUsableAmount(clientName, 'dmlRows', cost.dmlRows);
      requireUsableAmount(clientName, 'eventPublishes', cost.eventPublishes);
      requireUsableAmount(clientName, 'cpuTimeMs', cost.cpuTimeMs);
      requireUsableAmount(clientName, 'heapBytes', cost.heapBytes);
      return cost;
    }

    private static void requireUsableAmount(
      String clientName,
      String field,
      Integer amount
    ) {
      if (amount == null || amount < 0) {
        throw new SendCostException(
          'Relay client ' +
            clientName +
            ' stated ' +
            (amount == null ? 'no value' : 'a negative value') +
            ' for ' +
            field +
            ' in the cost of a send. Every field must be 0 or more. Nothing was sent.'
        );
      }
    }

    private class SendCostException extends Exception {
    }

    /**
     * Whether a send that needs this cost fits in what is left. It fits when it needs no more than is
     * left of every limit. A send that needs exactly what is left fits, and so does a send that needs
     * none of a limit that is used up.
     */
    @TestVisible
    static Boolean hasBudgetFor(TB_SendCost cost, TB_SendCost left) {
      return cost.callouts <= left.callouts &&
        cost.calloutTimeMs <= left.calloutTimeMs &&
        cost.queries <= left.queries &&
        cost.queryRows <= left.queryRows &&
        cost.dmlStatements <= left.dmlStatements &&
        cost.dmlRows <= left.dmlRows &&
        cost.eventPublishes <= left.eventPublishes &&
        cost.cpuTimeMs <= left.cpuTimeMs &&
        cost.heapBytes <= left.heapBytes;
    }

    // The most time the callouts of one transaction may take in total, in milliseconds. Salesforce
    // documents it as 120 seconds. It is a platform limit and not a setting. The Limits class has no
    // method for it or for the time used against it, so it is stated here and the run keeps its own
    // count.
    private static final Integer CALLOUT_TIME_LIMIT_MS = 120000;

    /**
     * What one run has left of the limits it works within, read at the moment of each check.
     * It belongs to one run, so a later run starts with the full amounts again.
     *
     * Eight of the limits come from the Limits class. Callout time does not, so the run counts the time
     * on the clock since the budget began. Apex makes callouts one at a time and waits for each, so that
     * time is never less than what callouts have taken. It also counts CPU time and queries, which only
     * makes the run stop sooner. Adding up what each send declared would stop it much sooner: the HTTP
     * client declares its whole timeout of 10 seconds, which would allow 12 sends where most take a
     * fraction of a second. Timing only the sends would miss callouts made by a message resolver.
     *
     * Nothing is kept back for the save at the end of the run. If that save goes over a limit, the
     * finalizer saves the outcomes in its own transaction.
     *
     * The room check applies from the run's second attempt on. The first attempt goes ahead whatever
     * is left, because a run that attempted nothing would be queued again in the same state. At worst
     * that one send overruns a limit, and the attempt is abandoned or the job fails.
     */
    private class RunBudget {
      // System.currentTimeMillis() when the budget began.
      private Long startedAtMs = System.currentTimeMillis();
      // Whether this run has started an attempt that got past the room check, whatever then became
      // of its send. An outbox failed before that point, because its client could not be built or
      // its cost could not be used, leaves the first attempt still to come.
      private Boolean anAttemptHasStarted = false;

      public Boolean hasStartedAnAttempt() {
        return anAttemptHasStarted;
      }

      public void attemptStarted() {
        anAttemptHasStarted = true;
      }

      public Boolean hasRoomFor(TB_SendCost cost) {
        return hasBudgetFor(cost, left());
      }

      private TB_SendCost left() {
        TB_SendCost left = new TB_SendCost();
        left.callouts = Limits.getLimitCallouts() - Limits.getCallouts();
        left.calloutTimeMs =
          CALLOUT_TIME_LIMIT_MS -
          (System.currentTimeMillis() - startedAtMs).intValue();
        left.queries = Limits.getLimitQueries() - Limits.getQueries();
        left.queryRows = Limits.getLimitQueryRows() - Limits.getQueryRows();
        left.dmlStatements =
          Limits.getLimitDmlStatements() - Limits.getDmlStatements();
        left.dmlRows = Limits.getLimitDmlRows() - Limits.getDmlRows();
        left.eventPublishes =
          Limits.getLimitPublishImmediateDML() -
          Limits.getPublishImmediateDML();
        left.cpuTimeMs = Limits.getLimitCpuTime() - Limits.getCpuTime();
        left.heapBytes = Limits.getLimitHeapSize() - Limits.getHeapSize();
        return left;
      }
    }
  
    private static Set<String> subscriptionNamesOf(
      List<TB_Subscription_Outbox__c> outboxRecords
    ) {
      Set<String> names = new Set<String>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        names.add(item.Subscription__c);
      }
      return names;
    }
  
    /**
     * Fails one attempt for an outbox whose subscription or message definition is missing.
     * The attempt is counted and nothing is sent, so the outbox is retried like any failure and
     * dead-letters at its own max attempts. A subscription or definition put back under the same
     * name lets a later attempt deliver.
     *
     * While the subscription is there its own backoff decides the wait. Without it there is no
     * backoff to read, so the fallback retry wait, in minutes, is used.
     */
    private void failWithoutConfiguration(
      TB_Subscription_Outbox__c item,
      TB_Message_Subscription__mdt subDef,
      TB_Message_Definition__mdt msgDef,
      Integer fallbackRetryWait,
      OutboxFinalizer finalizer
    ) {
      TB_OutboxRelayContext obCtx = new TB_OutboxRelayContext(item, null, subDef);
      obCtx.setAttempt();
      item.Last_Error_Message__c = missingConfigurationReason(
        item,
        subDef,
        msgDef
      );
      if (subDef == null) {
        obCtx.setNextAttemptTimestamp(
          System.now().addMinutes(fallbackRetryWait)
        );
      } else {
        obCtx.setNextAttemptTimestamp(
          TB_OutboxMetadataProvider.getSubscriptionNextAttemptTimeStamp(
            subDef,
            (Integer) item.Relay_Attempts__c
          )
        );
      }
      finalizer.addResult(obCtx);
    }
  
    private static String missingConfigurationReason(
      TB_Subscription_Outbox__c item,
      TB_Message_Subscription__mdt subDef,
      TB_Message_Definition__mdt msgDef
    ) {
      List<String> missing = new List<String>();
      if (subDef == null) {
        missing.add(
          'no TB_Message_Subscription__mdt named ' + item.Subscription__c
        );
      }
      if (msgDef == null) {
        missing.add(
          'no TB_Message_Definition__mdt named ' + item.Outbox_Message__r.Type__c
        );
      }
      return 'Nothing was sent because there is ' +
        String.join(missing, ' and ') +
        '.';
    }
  
    // The most pages of due outboxes one search reads while looking for outboxes that can be attempted.
    private static final Integer MAX_SCAN_PAGES = 10;
  
    private static Integer scanPageSize(Integer batchSize) {
      return batchSize * 2;
    }
  
    /**
     * Finds the oldest due outboxes that are not held, up to the number wanted.
     * The run uses it to choose what to attempt. The finalizer uses it to see whether anything is left
     * that a new run could attempt, so both go by the same rule.
     *
     * Due outboxes are read a page at a time in publish order, with small fields and no lock.
     * Holds found on the way are recorded, and later pages leave out a group once the search has
     * passed the message holding it, so a long held group does not use up the pages.
     *
     * The search gives up after MAX_SCAN_PAGES pages. If more held outboxes from distinct groups
     * than that covers sit ahead of an outbox that could go, the search does not reach it.
     */
    private static List<TB_Subscription_Outbox__c> chooseAttemptable(
      Integer wanted,
      Integer pageSize,
      GroupHolds holds,
      DateTime asOf
    ) {
      List<TB_Subscription_Outbox__c> chosen = new List<TB_Subscription_Outbox__c>();
      TB_Subscription_Outbox__c lastSeen = null;
  
      for (
        Integer page = 0;
        page < MAX_SCAN_PAGES && chosen.size() < wanted;
        page++
      ) {
        List<TB_Subscription_Outbox__c> candidates = loadDuePage(
          pageSize,
          lastSeen,
          holds,
          asOf
        );
        findBlockedMembers(candidates, holds, asOf);
  
        for (TB_Subscription_Outbox__c candidate : candidates) {
          if (chosen.size() < wanted && !holds.isHeld(candidate)) {
            chosen.add(candidate);
          }
        }
  
        if (candidates.size() < pageSize) {
          break;
        }
        lastSeen = candidates[candidates.size() - 1];
      }
  
      return chosen;
    }
  
    /**
     * One page of due outboxes in publish order, starting after the last one already seen.
     * Outboxes of one message share a sequence number, so the record id settles the order
     * between them and lets the next page start in the right place.
     */
    private static List<TB_Subscription_Outbox__c> loadDuePage(
      Integer pageSize,
      TB_Subscription_Outbox__c lastSeen,
      GroupHolds holds,
      DateTime asOf
    ) {
      if (lastSeen == null) {
        return [
          SELECT Id, Group_Id__c, Outbox_Message__r.Sequence_Number__c
          FROM TB_Subscription_Outbox__c
          WHERE
            Completed_Timestamp__c = NULL
            AND Dead_Lettered__c = FALSE
            AND (Next_Attempt_Timestamp__c <= :asOf
            OR Next_Attempt_Timestamp__c = NULL)
          ORDER BY Outbox_Message__r.Sequence_Number__c, Id
          LIMIT :pageSize
        ];
      }
  
      String lastSequence = lastSeen.Outbox_Message__r.Sequence_Number__c;
      Id lastId = lastSeen.Id;
      Set<String> heldGroupIds = holds.groupIdsHeldBefore(lastSeen);
      return [
        SELECT Id, Group_Id__c, Outbox_Message__r.Sequence_Number__c
        FROM TB_Subscription_Outbox__c
        WHERE
          Completed_Timestamp__c = NULL
          AND Dead_Lettered__c = FALSE
          AND (Next_Attempt_Timestamp__c <= :asOf
          OR Next_Attempt_Timestamp__c = NULL)
          AND Group_Id__c NOT IN :heldGroupIds
          AND (Outbox_Message__r.Sequence_Number__c > :lastSequence
          OR (Outbox_Message__r.Sequence_Number__c = :lastSequence
          AND Id > :lastId))
        ORDER BY Outbox_Message__r.Sequence_Number__c, Id
        LIMIT :pageSize
      ];
    }
  
    /**
     * Records a hold for each outbox that is dead-lettered or still waiting on its backoff
     * in the groups these outboxes belong to. The rest of such a group, from that message on,
     * cannot be processed until it is resolved. A completed outbox holds nothing.
     * Each group is looked up once.
     */
    private static void findBlockedMembers(
      List<TB_Subscription_Outbox__c> outboxRecords,
      GroupHolds holds,
      DateTime asOf
    ) {
      Set<String> uncheckedGroupIds = new Set<String>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        if (item.Group_Id__c != null && !holds.hasChecked(item.Group_Id__c)) {
          uncheckedGroupIds.add(item.Group_Id__c);
        }
      }
  
      if (uncheckedGroupIds.size() > 0) {
        for (TB_Subscription_Outbox__c blocked : [
          SELECT Group_Id__c, Outbox_Message__r.Sequence_Number__c
          FROM TB_Subscription_Outbox__c
          WHERE
            Completed_Timestamp__c = NULL
            AND (Dead_Lettered__c = TRUE
            OR Next_Attempt_Timestamp__c > :asOf)
            AND Group_Id__c IN :uncheckedGroupIds
        ]) {
          holds.hold(blocked);
        }
        holds.markChecked(uncheckedGroupIds);
      }
    }
  
    /**
     * Loads the chosen outboxes with their payloads, locked, in the order they were chosen.
     * The lock is released as soon as the first HTTP callout is made.
     *
     * The outboxes were chosen without a lock, so one may have stopped being due before the lock
     * was taken, for example when another run got to it first. It is left out, and it holds the
     * messages after it in its group for this run, because the reason it changed is not known here.
     */
    private static List<TB_Subscription_Outbox__c> loadForAttempt(
      List<TB_Subscription_Outbox__c> chosen,
      GroupHolds holds,
      DateTime asOf
    ) {
      Map<Id, TB_Subscription_Outbox__c> loaded = new Map<Id, TB_Subscription_Outbox__c>(
        [
          SELECT
            Subscription__c,
            Group_Id__c,
            Outbox_Message__c,
            Outbox_Message__r.Sequence_Number__c,
            Outbox_Message__r.Message__c,
            Outbox_Message__r.Type__c,
            Last_Error_Message__c,
            Relay_Attempts__c,
            Completed_Timestamp__c,
            Next_Attempt_Timestamp__c,
            TTL__c
          FROM TB_Subscription_Outbox__c
          WHERE
            Id IN :chosen
            AND Completed_Timestamp__c = NULL
            AND Dead_Lettered__c = FALSE
            AND (Next_Attempt_Timestamp__c <= :asOf
            OR Next_Attempt_Timestamp__c = NULL)
          FOR UPDATE
        ]
      );
  
      List<TB_Subscription_Outbox__c> inChosenOrder = new List<TB_Subscription_Outbox__c>();
      for (TB_Subscription_Outbox__c candidate : chosen) {
        if (loaded.containsKey(candidate.Id)) {
          inChosenOrder.add(loaded.get(candidate.Id));
        } else {
          holds.hold(candidate);
        }
      }
      return inChosenOrder;
    }
  
    /**
     * Which outboxes this run must not attempt because of their message group.
     *
     * An outbox holds the messages published after it in its group when it is dead-lettered,
     * waiting on a backoff, failed in this run, or passed over in this run. It never holds a message
     * published before it, and never another subscription's outbox for the same message.
     * Group order is shared by all of an application's subscriptions.
     *
     * The finalizer carries the holds over, so its search for remaining work goes by them too.
     */
    private class GroupHolds {
      // For each held group, the lowest sequence number of an outbox holding it.
      private Map<String, Long> heldFromSequence = new Map<String, Long>();
      // Groups whose dead-lettered and backing-off outboxes have already been looked up.
      private Set<String> checkedGroupIds = new Set<String>();
  
      public Boolean hasChecked(String groupId) {
        return checkedGroupIds.contains(groupId);
      }
  
      public void markChecked(Set<String> groupIds) {
        checkedGroupIds.addAll(groupIds);
      }
  
      public Boolean isHeld(TB_Subscription_Outbox__c item) {
        if (item.Group_Id__c == null) {
          return false;
        }
        Long heldFrom = heldFromSequence.get(item.Group_Id__c);
        return heldFrom != null && heldFrom < sequenceOf(item);
      }
  
      /** Holds the messages after this outbox in its group. An outbox with no group holds nothing. */
      public void hold(TB_Subscription_Outbox__c item) {
        if (item.Group_Id__c == null) {
          return;
        }
        Long heldFrom = heldFromSequence.get(item.Group_Id__c);
        Long sequence = sequenceOf(item);
        if (heldFrom == null || sequence < heldFrom) {
          heldFromSequence.put(item.Group_Id__c, sequence);
        }
      }
  
      /**
       * The groups held by a message published before this outbox's message.
       * Everything after this outbox in publish order is held in those groups.
       */
      public Set<String> groupIdsHeldBefore(TB_Subscription_Outbox__c item) {
        Long sequence = sequenceOf(item);
        Set<String> groupIds = new Set<String>();
        for (String groupId : heldFromSequence.keySet()) {
          if (heldFromSequence.get(groupId) < sequence) {
            groupIds.add(groupId);
          }
        }
        return groupIds;
      }
  
      /**
       * The same holds, to be added to without changing these.
       * It does not carry which groups have been looked up, so it is not for searching.
       */
      public GroupHolds copy() {
        GroupHolds copied = new GroupHolds();
        copied.heldFromSequence = heldFromSequence.clone();
        return copied;
      }

      private Long sequenceOf(TB_Subscription_Outbox__c item) {
        return Long.valueOf(item.Outbox_Message__r.Sequence_Number__c);
      }
    }

    /** What an outbox's turn in a run comes to. */
    private enum TurnOutcome {
      HELD,
      NO_CONFIGURATION,
      PASSED_OVER,
      ATTEMPT
    }

    /**
     * Decides what each outbox's turn in a run comes to, with the outboxes taken one at a time in
     * publish order, and keeps what each turn leaves for the turns after it.
     *
     * The decision rests on what came before in the run and on configuration, and not on how a send
     * turns out or whether the run has room for it. Two outcomes change later turns, and the caller
     * reports both: a failed send, and an outbox passed over because the run had no room for its send.
     *
     * Turns taken before any attempt, to plan the run, report each planned send as one that may fail
     * instead. A turn that a failed send could hold may then come out differently in the run, so it
     * is only allowed to rule out later attempts in ways that do not depend on it being reached.
     */
    private class RelayTurns {
      private GroupHolds holds;
      // The holds that sends which may still fail would add. Only a plan has any.
      private GroupHolds possibleHolds = new GroupHolds();
      // An attempt that fails for missing configuration is still one of the run's attempts, so it
      // keeps an isolated outbox after it from being first.
      private Boolean isFirst = true;
      // Once an isolated subscription has had an attempt, no outbox with configuration is attempted in this run.
      private Boolean isolatedAttempted = false;

      private RelayTurns(GroupHolds holds) {
        this.holds = holds;
      }

      public TurnOutcome take(
        TB_Subscription_Outbox__c item,
        TB_Message_Subscription__mdt subDef,
        TB_Message_Definition__mdt msgDef
      ) {
        if (holds.isHeld(item)) {
          return TurnOutcome.HELD;
        }

        // Nothing is sent for an outbox without configuration, so isolation does not keep it from
        // being failed. Its attempt still counts as one of the run's attempts, so an isolated outbox
        // behind it is not first, and an isolated subscription it belongs to still ends normal attempts.
        if (subDef == null || msgDef == null) {
          holds.hold(item);
          isFirst = false;
          // If a failed send holds this outbox instead, the run has already made an attempt and the
          // group is already held from an earlier message, so the two lines above change nothing the
          // run does not already have. Ending normal attempts is different, so a plan only does it
          // when no send that may fail could hold this outbox.
          if (
            subDef != null &&
            subDef.Isolate_Relay__c &&
            !possibleHolds.isHeld(item)
          ) {
            isolatedAttempted = true;
          }
          return TurnOutcome.NO_CONFIGURATION;
        }

        // An isolated outbox is attempted only as the run's first attempt.
        if (isolatedAttempted || (!isFirst && subDef.Isolate_Relay__c)) {
          holds.hold(item);
          return TurnOutcome.PASSED_OVER;
        }

        // This counts toward isolation even when the run then has no room for the send, although an
        // outbox passed over is not an attempt. The plan cannot know about room, and counting it the
        // same way keeps the run to outboxes the plan resolved messages for. It changes nothing in
        // practice: the run's first attempt is not checked for room, so an outbox passed over for
        // lack of room always comes after a started attempt, which had already ended isFirst. For
        // the same reason an isolated outbox, which gets here only while isFirst holds, is never
        // passed over for lack of room.
        isFirst = false;
        if (subDef.Isolate_Relay__c) {
          isolatedAttempted = true;
        }
        return TurnOutcome.ATTEMPT;
      }

      /** A send that fails holds the messages after its outbox in its group. */
      public void sendFailed(TB_Subscription_Outbox__c item) {
        holds.hold(item);
      }

      /**
       * An outbox passed over because the run had no room for its send is still undelivered, so it
       * holds the messages after it in its group, the same as a failed send.
       */
      public void noRoom(TB_Subscription_Outbox__c item) {
        holds.hold(item);
      }

      /** For a plan: this outbox's send has not happened yet and may fail. */
      public void sendMayFail(TB_Subscription_Outbox__c item) {
        possibleHolds.hold(item);
      }
    }
  
    /**
     * Bulk Resolve Messages.
     */
    private static Map<Id, Object> resolveMessages(
      Map<String, TB_Outbox_Message__c[]> msgsByType,
      Map<String, TB_Message_Definition__mdt> definitionsByLabel
    ) {
      //resolve Message DTO
      Map<Id, Object> allResolvedMessages = new Map<Id, Object>();
      for (String msgType : msgsByType.keySet()) {
        TB_Message_Definition__mdt def = definitionsByLabel.get(msgType);
        TB_Outbox_Message__c[] msgs = msgsByType.get(msgType);
        // Only outboxes whose message type has a definition are planned, so def is never null here.
        if (def.Message_Resolver__c != null) {
          try {
            TB_IOutboxMessageResolver resolver = TB_OutboxMetadataProvider.getMessageResolver(
              def
            );
            Map<Id, Object> resolvedMessages = resolver.resolveMessages(msgs);
            allResolvedMessages.putAll(resolvedMessages);
          } catch (Exception e) {
            System.debug('Exception resolving messages for ' + msgType);
            System.debug(e);
  
            // Add an error for the message
            for (TB_Outbox_Message__c msg : msgs) {
              allResolvedMessages.put(msg.Id, e);
            }
          }
        }
      }
      return allResolvedMessages;
    }
  
    /**
     * Finalizer repsonsible for tracking state of outbox requests and persisting it.
     * Even if we run into a limit exception, the finalizer should ensure the outbox results get persisted.
     * WARNING: There is perhaps a small chance that a new TB_OutboxRelayQueuable job could start up in the time between the origional job and the finalizer execution...
     */
    private class OutboxFinalizer implements Finalizer {
      // Id -> Success Timestamp
      private Map<Id, TB_OutboxRelayContext> results;
      private Set<Id> saved;
  
      private GroupHolds holds;
      // The page size the run searched with, so the search for remaining work covers the same ground.
      private Integer scanPageSize;
  
      private OutboxFinalizer(GroupHolds holds, Integer scanPageSize) {
        this.holds = holds;
        this.scanPageSize = scanPageSize;
        saved = new Set<Id>();
        results = new Map<Id, TB_OutboxRelayContext>();
      }
  
      public void addResult(TB_OutboxRelayContext ctx) {
        results.put(ctx.outbox.id, ctx);
      }
  
      public Map<Id, TB_OutboxRelayContext> getUnsavedResults() {
        Map<Id, TB_OutboxRelayContext> unsaved = new Map<Id, TB_OutboxRelayContext>(
          results
        );
        for (Id savedId : saved) {
          unsaved.remove(savedId);
        }
        return unsaved;
      }
  
      /**
       * Save Result and remove them if successful
       */
      public void save() {
        Map<Id, TB_OutboxRelayContext> unsaved = getUnsavedResults();
        System.debug('Attempting to save results: ' + unsaved.size());
  
        List<TB_Subscription_Outbox__c> outboxRecordsToUpdate = new List<TB_Subscription_Outbox__c>();
        for (TB_OutboxRelayContext ctx : unsaved.values()) {
          outboxRecordsToUpdate.add(ctx.outbox);
        }
  
        // Remove all successes from the state
        List<Database.SaveResult> results = Database.update(
          outboxRecordsToUpdate,
          false
        );
        for (Database.SaveResult sr : results) {
          if (sr.isSuccess()) {
            saved.add(sr.getId());
          } else {
            System.debug('Failed to save result');
            System.debug(sr.getErrors());
          }
        }
      }
  
      public void execute(FinalizerContext ctx) {
        // Should we get a new query lock?
        Exception e = ctx.getException();
        if (e != null) {
          System.debug(
            'Queueable Terminated with Error! ' +
              e.getMessage() +
              '\\n' +
              e.getStackTraceString()
          );
        }
  
        save();
  
        try {
          TB_Subscription_Outbox__c[] activeOutboxItems = TB_OutboxRelayQueuable.chooseAttemptable(
            1,
            scanPageSize,
            holds,
            System.now()
          );
          // more work to be done
          if (activeOutboxItems.size() > 0) {
            TB_OutboxRelayQueuable.enqueue(ctx.getAsyncApexJobId());
          }
        } catch (Exception ex) {
          System.debug('Exception prevented enqueue TB_OutboxRelayQueuable');
          System.debug(ex);
        }
        executeAfterActions();
      }
  
      /**
       * Calls the after-relay action of each subscription that had at least one attempt in this run,
       * once, with that subscription's attempts. A subscription with no attempt gets no call, and
       * its action is not built.
       *
       * An exception thrown while building or calling an action is caught and written to the debug
       * log, and the other subscriptions' actions are still called.
       *
       * Actions run in the finalizer's transaction, after the results are saved and the next run is
       * queued. A failure that cannot be caught, such as a governor limit, ends that transaction. The
       * remaining actions are not called, and the saved results and the queued run are rolled back.
       */
      private void executeAfterActions() {
        Map<String, List<TB_OutboxRelayContext>> resultsBySubscription = new Map<String, List<TB_OutboxRelayContext>>();
        for (TB_OutboxRelayContext item : results.values()) {
          if (resultsBySubscription.containsKey(item.outbox.Subscription__c)) {
            resultsBySubscription.get(item.outbox.Subscription__c).add(item);
          } else {
            resultsBySubscription.put(
              item.outbox.Subscription__c,
              new List<TB_OutboxRelayContext>{ item }
            );
          }
        }
  
        for (String subscriptionName : resultsBySubscription.keySet()) {
          List<TB_OutboxRelayContext> attempts = resultsBySubscription.get(
            subscriptionName
          );
          // Every attempt in the group carries the same subscription, or none when no subscription
          // has the outbox's subscription name. An action belongs to a subscription, so none runs then.
          TB_Message_Subscription__mdt subscription = attempts[0].subscription;
          if (subscription == null || subscription.After_Relay_Action__c == null) {
            continue;
          }
          String actionClassName = subscription.After_Relay_Action__c;

          TB_IAfterRelayAction action;
          try {
            action = TB_OutboxMetadataProvider.getAfterRelayAction(actionClassName);
          } catch (Exception e) {
            System.debug(
              'Could not build after relay action ' +
                actionClassName +
                ' for subscription ' +
                subscriptionName +
                ': ' +
                e.getTypeName() +
                ': ' +
                e.getMessage() +
                '\n' +
                e.getStackTraceString()
            );
            continue;
          }

          try {
            action.execute(attempts);
          } catch (Exception e) {
            System.debug(
              'Exception executing after relay action ' +
                actionClassName +
                ' for subscription ' +
                subscriptionName +
                ': ' +
                e.getTypeName() +
                ': ' +
                e.getMessage() +
                '\n' +
                e.getStackTraceString()
            );
          }
        }
      }
    }
  
    @testvisible
    static boolean alreadyQueuedInContext = false;
  
    public static void enqueue() {
      enqueue(null);
    }
    public static void enqueue(Id currentAsyncJobId) {
      if (alreadyQueuedInContext) {
        System.debug('Relay Queuable Skipped: Already enqueue from this context');
        return;
      }
  
      if (executeStart != null) {
        System.debug('Relay Queuable Skipped: In Relay Queuable Excute context');
        return;
      }
  
      Integer maxAllowedJobs = System.isBatch() ||
        System.isFuture() ||
        System.isQueueable()
        ? 1
        : Limits.getLimitQueueableJobs();
  
      if (Limits.getQueueableJobs() >= maxAllowedJobs) {
        System.debug(
          'Relay Queuable Skipped: Exceeded Max Allowed Jobs of ' + maxAllowedJobs
        );
        return;
      }
  
      AsyncApexJob[] currentJobs = [
        SELECT Id, ApexClass.Name, ExtendedStatus, Status
        FROM AsyncApexJob
        WHERE
          JobType = 'Queueable'
          AND ApexClass.Name = 'TB_OutboxRelayQueuable'
          AND Status IN ('Preparing', 'Processing', 'Queued')
          AND Id != :currentAsyncJobId
        ORDER BY CreatedDate DESC
      ];
  
      if (currentJobs.size() > 0) {
        System.debug(
          'Relay Queuable Skipped: Relay Job already in progress - ' +
          currentJobs[0].Id
        );
        return;
      }
  
      System.enqueueJob(new TB_OutboxRelayQueuable());
      alreadyQueuedInContext = true;
    }
  }