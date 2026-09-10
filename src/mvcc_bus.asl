(module asl-agent-bus/mvcc-bus
  :d "Branching Causal Message DAG and Semantic Intent Merging for Multi-Agent Swarms"
  :exports [
    CausalMessage
    IntentConflict
    MergedIntent
    MvccBus
    mvcc-bus-create
    mvcc-bus-publish
    mvcc-bus-get-message
    mvcc-bus-find-heads
    mvcc-bus-merge-intents
    format-merged-intent
    extract-payload-facts
    merge-fact-lists
  ])

(dfs CausalMessage
  (:f id Str "Unique message identifier")
  (:f parents (List Str) "List of causal parent message IDs")
  (:f sender Str "Originating agent role or ID")
  (:f topic Str "Channel or topic identifier")
  (:f payload-form Str "S-expression payload text")
  (:f clock I64 "Logical Lamport or vector clock")
  (:f epoch I64 "Workspace epoch"))

(dfs IntentConflict
  (:f topic Str "Conflicted topic")
  (:f parent-id Str "Common causal ancestor message ID")
  (:f msg-a-id Str "Branch A message ID")
  (:f msg-b-id Str "Branch B message ID")
  (:f reason Str "Explanation of semantic divergence"))

(dfs MergedIntent
  (:f topic Str "Target topic")
  (:f source-msg-ids (List Str) "Contributing branch message IDs")
  (:f merged-payload Str "Synthesized S-expression payload")
  (:f conflicts (List IntentConflict) "Detected intent conflicts")
  (:f clean Bool "True if zero conflicts occurred"))

(dfs MvccBus
  (:f messages (List CausalMessage) "All immutable causal messages in DAG")
  (:f head-ids (List Str) "Current frontier leaf message IDs")
  (:f conflicts (List IntentConflict) "Accumulated arbitration records"))

(df mvcc-bus-create [] -> MvccBus
  :d "Initializes an empty branching MVCC message bus."
  (MvccBus
    :messages (list)
    :head-ids (list)
    :conflicts (list)))

(df mvcc-bus-get-message [(bus MvccBus) (msg-id Str)] -> (Option CausalMessage)
  :d "Finds message by ID in causal graph."
  (fold (fn [(acc (Option CausalMessage)) (m CausalMessage)] -> (Option CausalMessage)
          (mt acc
            ((some found) (some found))
            ((none) (if (= (.-id m) msg-id) (some m) (none)))))
        (none)
        (.-messages bus)))

(df mvcc-bus-publish [(bus MvccBus)
                      (sender Str)
                      (topic Str)
                      (payload Str)
                      (parents (List Str))
                      (clock I64)
                      (epoch I64)] -> MvccBus
  :d "Publishes immutable message into branching causal DAG."
  (let [(next-id (str topic "-" sender "-" clock))
        (msg (CausalMessage
               :id next-id
               :parents parents
               :sender sender
               :topic topic
               :payload-form payload
               :clock clock
               :epoch epoch))
        (next-msgs (list-append (.-messages bus) (list msg)))
        (remaining-heads (fold (fn [(acc (List Str)) (h Str)] -> (List Str)
                                 (if (list-contains? parents h)
                                   acc
                                   (list-append acc (list h))))
                               (list)
                               (.-head-ids bus)))
        (next-heads (list-append remaining-heads (list next-id)))]
    (MvccBus
      :messages next-msgs
      :head-ids next-heads
      :conflicts (.-conflicts bus))))

(df mvcc-bus-find-heads [(bus MvccBus) (target-topic Str)] -> (List CausalMessage)
  :d "Returns all current frontier heads for specific topic."
  (let [(heads (.-head-ids bus))]
    (fold (fn [(acc (List CausalMessage)) (m CausalMessage)] -> (List CausalMessage)
            (if (and (= (.-topic m) target-topic) (list-contains? heads (.-id m)))
              (list-append acc (list m))
              acc))
          (list)
          (.-messages bus))))

(df extract-payload-facts [(payload Str)] -> (List Str)
  :d "Extracts individual fact lines from S-expression payload."
  (let [(lines (string-split payload "\n"))]
    (fold (fn [(acc (List Str)) (l Str)] -> (List Str)
            (let [(trimmed (string-trim l))]
              (if (or (string-empty? trimmed) (string-starts-with? trimmed ";"))
                acc
                (list-append acc (list trimmed)))))
          (list)
          lines)))

(df merge-fact-lists [(base-facts (List Str)) (a-facts (List Str)) (b-facts (List Str))] -> (List Str)
  :d "Merges fact assertions using monotonic set union."
  (let [(added-a (fold (fn [(acc (List Str)) (f Str)] -> (List Str)
                         (if (list-contains? base-facts f)
                           acc
                           (if (list-contains? acc f) acc (list-append acc (list f)))))
                       (list)
                       a-facts))
        (added-b (fold (fn [(acc (List Str)) (f Str)] -> (List Str)
                         (if (list-contains? base-facts f)
                           acc
                           (if (or (list-contains? added-a f) (list-contains? acc f))
                             acc
                             (list-append acc (list f)))))
                       (list)
                       b-facts))
        (retained-base (fold (fn [(acc (List Str)) (f Str)] -> (List Str)
                               (if (and (list-contains? a-facts f) (list-contains? b-facts f))
                                 (list-append acc (list f))
                                 acc))
                             (list)
                             base-facts))]
    (list-concat retained-base (list-concat added-a added-b))))

(df detect-intent-contradiction [(a-payload Str) (b-payload Str)] -> Bool
  :d "Detects mutual contradictions between agent proposals."
  (or (and (string-contains? a-payload ":status :ok") (string-contains? b-payload ":status :failed"))
      (or (and (string-contains? a-payload ":status :failed") (string-contains? b-payload ":status :ok"))
          (and (string-contains? a-payload ":verdict :approve") (string-contains? b-payload ":verdict :reject")))))

(df mvcc-bus-merge-intents [(bus MvccBus)
                            (topic Str)
                            (base-msg-id Str)
                            (branch-a-id Str)
                            (branch-b-id Str)] -> MergedIntent
  :d "Performs semantic 3-way intent merge between divergent message branches."
  (let [(base-opt (mvcc-bus-get-message bus base-msg-id))
        (a-opt (mvcc-bus-get-message bus branch-a-id))
        (b-opt (mvcc-bus-get-message bus branch-b-id))]
    (mt a-opt
      ((none)
       (MergedIntent
         :topic topic
         :source-msg-ids (list)
         :merged-payload ""
         :conflicts (list (IntentConflict :topic topic :parent-id base-msg-id :msg-a-id branch-a-id :msg-b-id branch-b-id :reason "Missing branch A message"))
         :clean false))
      ((some ma)
       (mt b-opt
         ((none)
          (MergedIntent
            :topic topic
            :source-msg-ids (list branch-a-id)
            :merged-payload (.-payload-form ma)
            :conflicts (list (IntentConflict :topic topic :parent-id base-msg-id :msg-a-id branch-a-id :msg-b-id branch-b-id :reason "Missing branch B message"))
            :clean false))
         ((some mb)
          (let [(a-raw (.-payload-form ma))
                (b-raw (.-payload-form mb))
                (base-raw (mt base-opt ((none) "") ((some mbase) (.-payload-form mbase))))
                (has-conflict (detect-intent-contradiction a-raw b-raw))]
            (if has-conflict
              (let [(c (IntentConflict
                         :topic topic
                         :parent-id base-msg-id
                         :msg-a-id branch-a-id
                         :msg-b-id branch-b-id
                         :reason "Contradictory status/verdict between agent proposals"))]
                (MergedIntent
                  :topic topic
                  :source-msg-ids (list branch-a-id branch-b-id)
                  :merged-payload (str "(:intentConflict\n  :branchA " a-raw "\n  :branchB " b-raw ")")
                  :conflicts (list c)
                  :clean false))
              (let [(base-facts (extract-payload-facts base-raw))
                    (a-facts (extract-payload-facts a-raw))
                    (b-facts (extract-payload-facts b-raw))
                    (merged-facts (merge-fact-lists base-facts a-facts b-facts))
                    (merged-text (string-join merged-facts "\n"))]
                (MergedIntent
                  :topic topic
                  :source-msg-ids (list branch-a-id branch-b-id)
                  :merged-payload merged-text
                  :conflicts (list)
                  :clean true))))))))))

(df format-merged-intent [(intent MergedIntent)] -> Str
  :d "Serializes merged intent into structured S-expression frame."
  (str "(:mergedIntent\n"
       "  :topic \"" (.-topic intent) "\"\n"
       "  :clean " (if (.-clean intent) "true" "false") "\n"
       "  :sources [" (string-join (.-source-msg-ids intent) " ") "]\n"
       "  :payload \n" (.-merged-payload intent) ")"))
