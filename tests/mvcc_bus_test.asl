(module asl-agent-bus/tests/mvcc-bus-test
  :d "Falsifiable verification test suite for MVCC Branching Agent Bus and Intent Merge"
  :x [run-tests
      TestBusPublishAndCausalChain
      TestParallelBranchingHeads
      TestDisjointIntentMerge
      TestContradictoryIntentConflict
      TestMergedIntentFormatting]
  :i [(mvcc_bus :a mb)])

(df TestBusPublishAndCausalChain [] -> Bool
  :d "Verifies initial message publication establishes root head and clock."
  (let [(bus0 (mb/mvcc-bus-create))
        (bus1 (mb/mvcc-bus-publish bus0 "architect" "task-triage" "(:plan :id \"p1\")" (list) 1 100))
        (msg-opt (mb/mvcc-bus-get-message bus1 "task-triage-architect-1"))
        (heads (mb/mvcc-bus-find-heads bus1 "task-triage"))]
    (assert (= (list-length (.-messages bus1)) 1) "Bus must contain exactly 1 message")
    (assert (= (list-length heads) 1) "Must have 1 frontier head")
    (mt msg-opt
      ((none) (assert false "Published message must be retrievable"))
      ((some m)
       (assert (= (.-sender m) "architect") "Sender must match")
       (assert (= (.-clock m) 1) "Clock must be 1")
       (assert (= (list-length (.-parents m)) 0) "Root message must have 0 parents")))
    true))

(df TestParallelBranchingHeads [] -> Bool
  :d "Verifies concurrent messages from same parent branch into 2 active heads."
  (let [(bus0 (mb/mvcc-bus-create))
        (bus1 (mb/mvcc-bus-publish bus0 "architect" "triage" "(:base)" (list) 1 100))
        (parent-id "triage-architect-1")
        (bus2 (mb/mvcc-bus-publish bus1 "scout-1" "triage" "(:findings-1)" (list parent-id) 2 100))
        (bus3 (mb/mvcc-bus-publish bus2 "scout-2" "triage" "(:findings-2)" (list parent-id) 2 100))
        (heads (mb/mvcc-bus-find-heads bus3 "triage"))]
    (assert (= (list-length (.-messages bus3)) 3) "Bus must contain 3 total messages")
    (assert (= (list-length heads) 2) "Parallel branch must produce exactly 2 frontier heads")
    (let [(head-senders (fold (fn [(acc (List Str)) (h mb/CausalMessage)] -> (List Str)
                                (list-append acc (list (.-sender h))))
                              (list)
                              heads))]
      (assert (list-contains? head-senders "scout-1") "Heads must include scout-1")
      (assert (list-contains? head-senders "scout-2") "Heads must include scout-2"))
    true))

(df TestDisjointIntentMerge [] -> Bool
  :d "Verifies non-overlapping findings from two scouts merge cleanly."
  (let [(bus0 (mb/mvcc-bus-create))
        (bus1 (mb/mvcc-bus-publish bus0 "lead" "audit" "(:fact :baseline true)" (list) 1 100))
        (base-id "audit-lead-1")
        (bus2 (mb/mvcc-bus-publish bus1 "scout-a" "audit" "(:fact :symbol \"f1\")\n(:fact :file \"a.asl\")" (list base-id) 2 100))
        (bus3 (mb/mvcc-bus-publish bus2 "scout-b" "audit" "(:fact :symbol \"f2\")\n(:fact :file \"b.asl\")" (list base-id) 2 100))
        (a-id "audit-scout-a-2")
        (b-id "audit-scout-b-2")
        (intent (mb/mvcc-bus-merge-intents bus3 "audit" base-id a-id b-id))
        (payload (.-merged-payload intent))]
    (assert (.-clean intent) "Disjoint scout findings must merge cleanly")
    (assert (= (list-length (.-conflicts intent)) 0) "Clean intent merge must have 0 conflicts")
    (assert (string-contains? payload "f1") "Merged payload must include f1 from scout A")
    (assert (string-contains? payload "f2") "Merged payload must include f2 from scout B")
    (assert (string-contains? payload "a.asl") "Merged payload must include a.asl")
    (assert (string-contains? payload "b.asl") "Merged payload must include b.asl")
    true))

(df TestContradictoryIntentConflict [] -> Bool
  :d "Verifies contradictory status assertions trigger explicit IntentConflict."
  (let [(bus0 (mb/mvcc-bus-create))
        (bus1 (mb/mvcc-bus-publish bus0 "lead" "review" "(:review :target \"item-1\")" (list) 1 100))
        (base-id "review-lead-1")
        (bus2 (mb/mvcc-bus-publish bus1 "implementer" "review" "(:review :target \"item-1\" :status :ok)" (list base-id) 2 100))
        (bus3 (mb/mvcc-bus-publish bus2 "auditor" "review" "(:review :target \"item-1\" :status :failed)" (list base-id) 2 100))
        (a-id "review-implementer-2")
        (b-id "review-auditor-2")
        (intent (mb/mvcc-bus-merge-intents bus3 "review" base-id a-id b-id))]
    (assert (not (.-clean intent)) "Contradictory status must trigger conflict")
    (assert (= (list-length (.-conflicts intent)) 1) "Must record exactly 1 intent conflict")
    (let [(c (option-or (list-get (.-conflicts intent) 0) (mb/IntentConflict :topic "" :parent-id "" :msg-a-id "" :msg-b-id "" :reason "")))]
      (assert (= (.-topic c) "review") "Conflict topic must be review")
      (assert (string-contains? (.-reason c) "Contradictory") "Conflict reason must mention contradictory"))
    true))

(df TestMergedIntentFormatting [] -> Bool
  :d "Verifies serialization of MergedIntent to S-expression frame."
  (let [(intent (mb/MergedIntent
                  :topic "telemetry"
                  :source-msg-ids (list "m1" "m2")
                  :merged-payload "(:fact :latency 10)"
                  :conflicts (list)
                  :clean true))
        (fmt (mb/format-merged-intent intent))]
    (assert (string-contains? fmt "(:mergedIntent") "Frame must open with :mergedIntent")
    (assert (string-contains? fmt ":clean true") "Frame must report :clean true")
    (assert (string-contains? fmt ":topic \"telemetry\"") "Frame must report topic")
    (assert (string-contains? fmt "(:fact :latency 10)") "Frame must contain payload")
    true))

(df run-tests [] -> Bool
  :d "Executes all MVCC Branching Agent Bus test suites."
  (and (TestBusPublishAndCausalChain)
       (and (TestParallelBranchingHeads)
            (and (TestDisjointIntentMerge)
                 (and (TestContradictoryIntentConflict)
                      (TestMergedIntentFormatting))))))
