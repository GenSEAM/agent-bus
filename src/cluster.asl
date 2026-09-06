(module asl-bus/cluster
  :d "Cluster-Native Multi-Node Agent Swarm Mesh, Remote Worker Pool & Single-Token DAG Dispatch."
  :x [NodeState
      WorkerNode
      ClusterPool
      OpKind
      ClusterFrame
      pack-tkn
      unpack-tkn
      pack-dag
      pool-create
      pool-add
      pool-select
      dispatch-task
      make-receipt
      worker-idle?]
  :i [])

(dfe NodeState
  (:c state-idle [] "Worker is idle and ready for tasks")
  (:c state-busy [] "Worker is executing assigned task")
  (:c state-down [] "Worker node offline or unreachable"))

(dfs WorkerNode
  (:f id Str "Unique worker node identifier e.g. worker-qwen-1")
  (:f host Str "Remote IP or hostname")
  (:f port I64 "Target cluster port")
  (:f role Str "Specialized role e.g. coder, vision, crawler")
  (:f arm Str "Model arm profile e.g. qwen-3b, gemma-31b, gemini-flash")
  (:f state NodeState "Active lifecycle state")
  (:f caps (List Str) "List of supported capability tokens")
  (:f ping I64 "Latency in milliseconds"))

(dfs ClusterPool
  (:f workers (List WorkerNode) "Registered worker nodes in cluster"))

(dfe OpKind
  (:c op-prop [] "Task proposal to remote node")
  (:c op-acc [] "Task acceptance confirmation")
  (:c op-exec [] "Task execution directive")
  (:c op-rc [] "Completion receipt")
  (:c op-fail [] "Task execution failure"))

(dfs ClusterFrame
  (:f id Str "Frame tracking message ID")
  (:f from Str "Source node identifier")
  (:f to Str "Target worker node identifier")
  (:f op OpKind "Cluster operation verb")
  (:f task-id Str "Unique DAG task identifier")
  (:f payload Str "Arbitrary payload string")
  (:f tkn-single Str "Dense single-token ASN payload"))

(df worker-idle? [(w WorkerNode)] -> Bool
  :d "Returns true if worker is currently in idle state."
  (mt (.-state w)
    ((state-idle) true)
    (_ false)))

(df pack-tkn [(raw Str)] -> Str
  :d "Applies rational unambiguous normalization: standardizes verbose keys into canonical single-token identifiers without collision."
  (let [(s1 (string-replace raw ":dependencies" ":deps"))
        (s2 (string-replace s1 ":sender" ":from"))
        (s3 (string-replace s2 ":target" ":to"))]
    s3))

(df unpack-tkn [(compacted Str)] -> Str
  :d "Expands normalized keys back into legacy verbose keys where required."
  (let [(s1 (string-replace compacted ":deps" ":dependencies"))
        (s2 (string-replace s1 ":from" ":sender"))
        (s3 (string-replace s2 ":to" ":target"))]
    s3))

(df pack-dag [(task-id Str) (title Str) (deps (List Str)) (premises (List Str))] -> Str
  :d "Formats a DAG task node into a canonical single-token ASN expression preserving explicit state."
  (let [(d-count (list-length deps))
        (p-count (list-length premises))]
    (pack-tkn (str "(:node :id \"" task-id "\" :title \"" title "\" :deps " (int-to-str d-count) " :premises " (int-to-str p-count) " :state :pending)"))))

(df pool-create [] -> ClusterPool
  :d "Creates an empty cluster worker pool."
  (ClusterPool :workers (list)))

(df pool-add [(pool ClusterPool) (w WorkerNode)] -> ClusterPool
  :d "Registers a remote worker node into the cluster pool."
  (ClusterPool :workers (list-append (.-workers pool) (list w))))

(df pool-select [(pool ClusterPool) (role Str) (required-cap Str)] -> (Option WorkerNode)
  :d "Selects the first idle worker in the pool matching the specified role and capability."
  (let [(matches (filter (fn [(w WorkerNode)] -> Bool
                           (and (worker-idle? w)
                                (= (.-role w) role)
                                (list-contains? (.-caps w) required-cap)))
                         (.-workers pool)))]
    (if (list-empty? matches)
      (none)
      (some (list-head matches)))))

(df dispatch-task [(frame-id Str) (from-node Str) (worker WorkerNode) (task-id Str) (dag-payload Str)] -> ClusterFrame
  :d "Dispatches a DAG task to a remote worker node with single-token compaction."
  (ClusterFrame
    :id frame-id
    :from from-node
    :to (.-id worker)
    :op (op-exec)
    :task-id task-id
    :payload dag-payload
    :tkn-single (pack-tkn dag-payload)))

(df make-receipt [(frame-id Str) (worker-id Str) (target-node Str) (task-id Str) (diff-lines I64) (gate-ms I64)] -> ClusterFrame
  :d "Mints a single-token completion receipt frame from a completed worker task."
  (let [(raw-receipt (str "(:receipt :node \"" worker-id "\" :task \"" task-id "\" :status :pass :action \"ast-patch\" :diff " (int-to-str diff-lines) " :gate-ms " (int-to-str gate-ms) ")"))
        (compact-rc (pack-tkn raw-receipt))]
    (ClusterFrame
      :id frame-id
      :from worker-id
      :to target-node
      :op (op-rc)
      :task-id task-id
      :payload raw-receipt
      :tkn-single compact-rc)))
