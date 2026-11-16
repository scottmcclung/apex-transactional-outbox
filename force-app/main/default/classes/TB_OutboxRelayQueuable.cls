public class TB_OutboxRelayQueuable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    static DateTime executeStart;
    public TB_OutboxRelayQueuable() {
    }
  
    /**
     * One relay run. It attempts at most the configured batch size and leaves the rest for the next run.
     * It does not check the remaining platform limits before an attempt. A run cut short by a limit
     * relies on the finalizer to store what was done.
     */
    public void execute(QueueableContext ctx) {
      executeStart = System.now();
  
      GroupHolds holds = new GroupHolds();
      List<TB_Subscription_Outbox__c> outboxRecords = selectAttemptable(
        TB_OutboxMetadataProvider.getRelayBatchSize(),
        holds
      );
  
      Map<String, TB_Outbox_Message__c[]> msgsByType = groupMessagesByType(
        outboxRecords
      );
  
      // transform DTO's
      Map<Id, Object> allResolvedMessages = resolveMessages(msgsByType);
  
      Map<String, TB_Message_Subscription__mdt> subscriptionsMetadataMap = TB_OutboxMetadataProvider.getMessageSubscritionMap(
        msgsByType.keySet()
      );
  
      OutboxFinalizer finalizer = attachFinalizer(
        subscriptionsMetadataMap.values(),
        holds
      );
  
      Boolean isFirst = true;
      // Process Each Outbox
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        if (holds.isHeld(item)) {
          continue;
        }
  
        TB_Message_Subscription__mdt subDef = subscriptionsMetadataMap.get(
          item.Subscription__c
        );
  
        // DO NOT process isolated outbox unless it's first
        if (!isFirst && subDef.Isolate_Relay__c) {
          holds.hold(item);
          continue;
        }
  
        Object resolvedEvt = allResolvedMessages.get(item.Outbox_Message__c);
  
        isFirst = false;
        Boolean delivered = attemptRelay(item, resolvedEvt, subDef, finalizer);
        if (!delivered) {
          holds.hold(item);
        }
  
        // do not process any additional records
        if (subDef.Isolate_Relay__c) {
          break;
        }
      }
  
      // attempt to save results with Lock
      finalizer.save();
    }
  
    /**
     * Message resolvers work on one message type at a time, in the order the outboxes will be processed.
     * A message appears once for each of its outboxes.
     */
    private Map<String, TB_Outbox_Message__c[]> groupMessagesByType(
      List<TB_Subscription_Outbox__c> outboxRecords
    ) {
      Map<String, TB_Outbox_Message__c[]> msgsByType = new Map<String, TB_Outbox_Message__c[]>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
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
     * Builds the after-relay actions and attaches the finalizer before any attempt is made,
     * so results are stored even if the run is stopped by a limit.
     * An after-relay action class that cannot be built is thrown from here.
     */
    private OutboxFinalizer attachFinalizer(
      List<TB_Message_Subscription__mdt> subscriptions,
      GroupHolds holds
    ) {
      Map<String, TB_IAfterRelayAction> afterRelayActions = TB_OutboxMetadataProvider.getAfterRelayActionsMap(
        subscriptions
      );
  
      OutboxFinalizer finalizer = new OutboxFinalizer(
        afterRelayActions,
        holds
      );
      System.attachFinalizer(finalizer);
      return finalizer;
    }
  
    /**
     * Makes one relay attempt for an outbox and hands the outcome to the finalizer.
     * Returns whether the attempt finished without an exception.
     * A subscription config that cannot be read is thrown from here before the attempt is counted.
     */
    private Boolean attemptRelay(
      TB_Subscription_Outbox__c item,
      Object resolvedEvt,
      TB_Message_Subscription__mdt subDef,
      OutboxFinalizer finalizer
    ) {
      TB_OutboxRelayContext obCtx = new TB_OutboxRelayContext(
        item,
        resolvedEvt,
        subDef
      );
  
      Boolean delivered = false;
      try {
        obCtx.setAttempt();
  
        // rethrow if we failed to resolve the message!
        if (resolvedEvt != null && resolvedEvt instanceof Exception) {
          throw (Exception) resolvedEvt;
        }
  
        TB_IOutboxRelayClient client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(
          subDef
        );
        client.send(obCtx);
        obCtx.setSuccess();
        delivered = true;
      } catch (Exception e) {
        obCtx.setError(e);
      } finally {
        //TODO: should this be added before? What happens if limit exception is thrown?
        finalizer.addResult(obCtx);
      }
      return delivered;
    }
  
    // The most pages of due outboxes one run reads while looking for outboxes it can attempt.
    private static final Integer MAX_SCAN_PAGES = 10;
  
    /**
     * Chooses the outboxes this run will attempt: the oldest due outboxes that are not held,
     * up to the batch size. Everything else is left for a later run.
     *
     * Due outboxes are read a page at a time in publish order, with small fields and no lock.
     * Holds found on the way are recorded, and later pages leave out a group once the search
     * has passed the message holding it, so a long held group does not use up the pages. Only the chosen outboxes are then
     * loaded with their payloads and locked.
     *
     * The search gives up after MAX_SCAN_PAGES pages. If more distinct held groups than that
     * covers sit ahead of an outbox that could go, this run does not reach it.
     */
    private List<TB_Subscription_Outbox__c> selectAttemptable(
      Integer batchSize,
      GroupHolds holds
    ) {
      Integer pageSize = batchSize * 2;
      List<Id> chosenIds = new List<Id>();
      TB_Subscription_Outbox__c lastSeen = null;
      Set<String> checkedGroupIds = new Set<String>();
  
      for (
        Integer page = 0;
        page < MAX_SCAN_PAGES && chosenIds.size() < batchSize;
        page++
      ) {
        List<TB_Subscription_Outbox__c> candidates = loadDuePage(
          pageSize,
          lastSeen,
          holds
        );
        findBlockedMembers(candidates, checkedGroupIds, holds);
  
        for (TB_Subscription_Outbox__c candidate : candidates) {
          if (chosenIds.size() < batchSize && !holds.isHeld(candidate)) {
            chosenIds.add(candidate.Id);
          }
        }
  
        if (candidates.size() < pageSize) {
          break;
        }
        lastSeen = candidates[candidates.size() - 1];
      }
  
      return loadForAttempt(chosenIds);
    }
  
    /**
     * One page of due outboxes in publish order, starting after the last one already seen.
     * Outboxes of one message share a sequence number, so the record id settles the order
     * between them and lets the next page start in the right place.
     */
    private List<TB_Subscription_Outbox__c> loadDuePage(
      Integer pageSize,
      TB_Subscription_Outbox__c lastSeen,
      GroupHolds holds
    ) {
      if (lastSeen == null) {
        return [
          SELECT Id, Group_Id__c, Outbox_Message__r.Sequence_Number__c
          FROM TB_Subscription_Outbox__c
          WHERE
            Completed_Timestamp__c = NULL
            AND Dead_Lettered__c = FALSE
            AND (Next_Attempt_Timestamp__c <= :executeStart
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
          AND (Next_Attempt_Timestamp__c <= :executeStart
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
     * cannot be processed until it is resolved. Each group is looked up once per run.
     */
    private void findBlockedMembers(
      List<TB_Subscription_Outbox__c> outboxRecords,
      Set<String> checkedGroupIds,
      GroupHolds holds
    ) {
      Set<String> uncheckedGroupIds = new Set<String>();
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        if (item.Group_Id__c != null && !checkedGroupIds.contains(item.Group_Id__c)) {
          uncheckedGroupIds.add(item.Group_Id__c);
        }
      }
  
      if (uncheckedGroupIds.size() > 0) {
        for (TB_Subscription_Outbox__c blocked : [
          SELECT Group_Id__c, Outbox_Message__r.Sequence_Number__c
          FROM TB_Subscription_Outbox__c
          WHERE
            (Dead_Lettered__c = TRUE
            OR Next_Attempt_Timestamp__c > :executeStart)
            AND Group_Id__c IN :uncheckedGroupIds
        ]) {
          holds.hold(blocked);
        }
        checkedGroupIds.addAll(uncheckedGroupIds);
      }
    }
  
    /**
     * Loads the chosen outboxes with their payloads, locked, in the order they were chosen.
     * The lock is released as soon as the first HTTP callout is made.
     * An outbox that stopped being due since it was chosen is left out.
     */
    private List<TB_Subscription_Outbox__c> loadForAttempt(List<Id> chosenIds) {
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
            Id IN :chosenIds
            AND Completed_Timestamp__c = NULL
            AND Dead_Lettered__c = FALSE
            AND (Next_Attempt_Timestamp__c <= :executeStart
            OR Next_Attempt_Timestamp__c = NULL)
          FOR UPDATE
        ]
      );
  
      List<TB_Subscription_Outbox__c> inChosenOrder = new List<TB_Subscription_Outbox__c>();
      for (Id chosenId : chosenIds) {
        if (loaded.containsKey(chosenId)) {
          inChosenOrder.add(loaded.get(chosenId));
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
     * The finalizer reads the held groups when it decides whether to queue another run.
     */
    private class GroupHolds {
      // For each held group, the lowest sequence number of an outbox holding it.
      private Map<String, Long> heldFromSequence = new Map<String, Long>();
  
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
  
      public Set<String> heldGroupIds() {
        return heldFromSequence.keySet().clone();
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
  
      private Long sequenceOf(TB_Subscription_Outbox__c item) {
        return Long.valueOf(item.Outbox_Message__r.Sequence_Number__c);
      }
    }
  
    /**
     * Bulk Resolve Messages.
     */
    private static Map<Id, Object> resolveMessages(
      Map<String, TB_Outbox_Message__c[]> msgsByType
    ) {
      Map<String, TB_Message_Definition__mdt> definitionsByLabel = TB_OutboxMetadataProvider.getMessageDefintionMap();
  
      //resolve Message DTO
      Map<Id, Object> allResolvedMessages = new Map<Id, Object>();
      for (String msgType : msgsByType.keySet()) {
        TB_Message_Definition__mdt def = definitionsByLabel.get(msgType);
        TB_Outbox_Message__c[] msgs = msgsByType.get(msgType);
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
  
      private Map<String, TB_IAfterRelayAction> afterRelayActions = new Map<String, TB_IAfterRelayAction>();
  
      private OutboxFinalizer(
        Map<String, TB_IAfterRelayAction> afterRelayActions,
        GroupHolds holds
      ) {
        this.holds = holds;
        this.afterRelayActions = afterRelayActions;
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
          Set<String> heldGroupIds = holds.heldGroupIds();
          TB_Subscription_Outbox__c[] activeOutboxItems = [
            SELECT Id
            FROM TB_Subscription_Outbox__c
            WHERE
              Completed_Timestamp__c = NULL
              AND Dead_Lettered__c = FALSE
              AND (Next_Attempt_Timestamp__c <= :System.now()
              OR Next_Attempt_Timestamp__c = NULL)
              AND Group_Id__c NOT IN :heldGroupIds
            LIMIT 1
          ];
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
  
      /** Run all After Relay Actions */
      private void executeAfterActions() {
        if (afterRelayActions.isEmpty()) {
          return;
        }
  
        //group results by subscription__c
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
  
        //run each after relay action
        for (String subscriptionKey : afterRelayActions.keySet()) {
          try {
            TB_IAfterRelayAction action = afterRelayActions.get(subscriptionKey);
            if (action != null) {
              action.execute(resultsBySubscription.get(subscriptionKey));
            }
          } catch (Exception e) {
            // eat the exception.  They should have handled it themselves :(
            System.debug(
              'Exception executing after relay action for subscription ' +
              subscriptionKey
            );
            System.debug(e);
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