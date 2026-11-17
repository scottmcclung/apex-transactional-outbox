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
  
      Integer batchSize = TB_OutboxMetadataProvider.getRelayBatchSize();
      Integer fallbackRetryWait = TB_OutboxMetadataProvider.getFallbackRetryWait();
      GroupHolds holds = new GroupHolds();
      List<TB_Subscription_Outbox__c> outboxRecords = loadForAttempt(
        chooseAttemptable(batchSize, scanPageSize(batchSize), holds, executeStart),
        holds,
        executeStart
      );
  
      Map<String, TB_Outbox_Message__c[]> msgsByType = groupMessagesByType(
        outboxRecords
      );
  
      Map<String, TB_Message_Definition__mdt> definitionsByName = TB_OutboxMetadataProvider.getMessageDefintionMap();

      // transform DTO's
      Map<Id, Object> allResolvedMessages = resolveMessages(
        msgsByType,
        definitionsByName
      );
  
      // An outbox finds its subscription by name, whichever message definition that subscription is on now.
      Map<String, TB_Message_Subscription__mdt> subscriptionsByName = TB_OutboxMetadataProvider.getSubscriptionsByName(
        subscriptionNamesOf(outboxRecords)
      );
  
      OutboxFinalizer finalizer = attachFinalizer(
        holds,
        scanPageSize(batchSize)
      );
  
      Boolean isFirst = true;
      // Once an isolated subscription has had an attempt, no outbox with configuration is attempted in this run.
      Boolean isolatedAttempted = false;
      // Process Each Outbox
      for (TB_Subscription_Outbox__c item : outboxRecords) {
        if (holds.isHeld(item)) {
          continue;
        }
  
        TB_Message_Subscription__mdt subDef = subscriptionsByName.get(
          item.Subscription__c
        );
        TB_Message_Definition__mdt msgDef = definitionsByName.get(
          item.Outbox_Message__r.Type__c
        );
  
        // Nothing is sent for an outbox without configuration, so isolation does not keep it from
        // being failed. Its attempt still counts as one of the run's attempts, so an isolated outbox
        // behind it is not first, and an isolated subscription it belongs to still ends normal attempts.
        if (subDef == null || msgDef == null) {
          failWithoutConfiguration(
            item,
            subDef,
            msgDef,
            fallbackRetryWait,
            finalizer
          );
          holds.hold(item);
          isFirst = false;
          if (subDef != null && subDef.Isolate_Relay__c) {
            isolatedAttempted = true;
          }
          continue;
        }
  
        // DO NOT process isolated outbox unless it's first
        if (isolatedAttempted || (!isFirst && subDef.Isolate_Relay__c)) {
          holds.hold(item);
          continue;
        }
  
        Object resolvedEvt = allResolvedMessages.get(item.Outbox_Message__c);
  
        isFirst = false;
        Boolean delivered = attemptRelay(item, resolvedEvt, subDef, finalizer);
        if (!delivered) {
          holds.hold(item);
        }
  
        if (subDef.Isolate_Relay__c) {
          isolatedAttempted = true;
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
  
    /**
     * Makes one relay attempt for an outbox and hands the outcome to the finalizer.
     * Returns whether the attempt finished without an exception.
     * A subscription config that cannot be read fails the counted attempt before anything is sent,
     * and the outbox waits on its subscription's backoff like any failed attempt.
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
        obCtx.requireReadableConfig();
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
  
      private Long sequenceOf(TB_Subscription_Outbox__c item) {
        return Long.valueOf(item.Outbox_Message__r.Sequence_Number__c);
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
        // A type with no definition has no resolver. Its outboxes fail without being sent.
        if (def != null && def.Message_Resolver__c != null) {
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