(module asl-bus/cluster-test
  :d "Unit verification test suite for Cluster-Native Mesh, Worker Pools, and Unambiguous DAG Dispatch."
  :x [test-worker-idle-state
      test-pool-registration-and-selection
      test-normalize-keys
      test-pack-dag-keys
      test-dispatch-and-receipt-lifecycle
      run-cluster-tests
      run-tests]
  :i [(cluster :a c)])

(df test-worker-idle-state [] -> Bool
  :d "Verifies worker liveness and idle state predicates."
  (let [(w1 (c/WorkerNode
              :id "worker-qwen-1"
              :host "10.0.0.1"
              :port 8765
              :role "coder"
              :arm "qwen-3b"
              :state (c/state-idle)
              :caps (list "ast-patch" "test-runner")
              :ping 12))
        (w2 (c/WorkerNode
              :id "worker-gemma-1"
              :host "10.0.0.2"
              :port 8765
              :role "architect"
              :arm "gemma-31b"
              :state (c/state-busy)
              :caps (list "dag-plan" "adr-review")
              :ping 24))]
    (do
      (assert (c/worker-idle? w1) "worker 1 is idle")
      (assert (not (c/worker-idle? w2)) "worker 2 is not idle")
      true)))

(df test-pool-registration-and-selection [] -> Bool
  :d "Tests adding remote workers to the pool and querying by capability."
  (let [(p0 (c/pool-create))
        (w1 (c/WorkerNode
              :id "worker-qwen-1"
              :host "10.0.0.1"
              :port 8765
              :role "coder"
              :arm "qwen-3b"
              :state (c/state-idle)
              :caps (list "ast-patch")
              :ping 10))
        (w2 (c/WorkerNode
              :id "worker-vision-1"
              :host "10.0.0.3"
              :port 8765
              :role "vision"
              :arm "gemini-flash"
              :state (c/state-idle)
              :caps (list "vdom-render" "svg-diff")
              :ping 45))
        (p1 (c/pool-add (c/pool-add p0 w1) w2))
        (coder-opt (c/pool-select p1 "coder" "ast-patch"))
        (vision-opt (c/pool-select p1 "vision" "svg-diff"))
        (miss-opt (c/pool-select p1 "crawler" "deep-search"))]
    (do
      (assert (option-some? coder-opt) "coder worker found")
      (assert (option-some? vision-opt) "vision worker found")
      (assert (not (option-some? miss-opt)) "missing worker not found")
      (assert (= (.-id (option-unwrap coder-opt)) "worker-qwen-1") "coder worker id match")
      (assert (= (.-id (option-unwrap vision-opt)) "worker-vision-1") "vision worker id match")
      true)))

(df test-normalize-keys [] -> Bool
  :d "Verifies rational unambiguous normalization without state and status collision."
  (let [(raw "(:node :sender \"orchestrator\" :target \"worker-1\" :payload \"test\" :status :pass :state :active :dependencies [\"t0\"])")
        (normalized (c/pack-keys raw))
        (restored (c/unpack-keys normalized))]
    (do
      (assert (string-contains? normalized ":from \"orchestrator\"") "has from")
      (assert (string-contains? normalized ":to \"worker-1\"") "has to")
      (assert (string-contains? normalized ":deps [\"t0\"]") "has deps")
      (assert (string-contains? normalized ":status :pass") "has status pass")
      (assert (string-contains? normalized ":state :active") "has state active")
      (assert (= restored raw) "restored matches raw")
      true)))

(df test-pack-dag-keys [] -> Bool
  :d "Tests compacting a DAG task node definition into a canonical expression."
  (let [(deps (list "task-setup" "task-schema"))
        (premises (list "premise-airgap-active"))
        (dag-str (c/pack-dag "task-cluster-01" "Deploy remote worker" deps premises))]
    (do
      (assert (string-contains? dag-str ":node :id \"task-cluster-01\"") "has node id")
      (assert (string-contains? dag-str ":deps 2") "has deps 2")
      (assert (string-contains? dag-str ":premises 1") "has premises 1")
      (assert (string-contains? dag-str ":state :pending") "has state pending")
      true)))

(df test-dispatch-and-receipt-lifecycle [] -> Bool
  :d "Tests dispatching a task frame to a worker and receiving a canonical receipt."
  (let [(w (c/WorkerNode
             :id "worker-qwen-1"
             :host "10.0.0.1"
             :port 8765
             :role "coder"
             :arm "qwen-3b"
             :state (c/state-idle)
             :caps (list "ast-patch")
             :ping 10))
        (dag-payload "(:task :title \"Patch AST\" :deps 0 :status :active)")
        (dispatch-frame (c/dispatch-task "frame-9001" "leader-node" w "task-42" dag-payload))
        (rc-frame (c/make-receipt "frame-9002" "worker-qwen-1" "leader-node" "task-42" 18 55))]
    (do
      (assert (= (.-from dispatch-frame) "leader-node") "dispatch frame leader")
      (assert (= (.-to dispatch-frame) "worker-qwen-1") "dispatch frame to worker")
      (assert (string-contains? (.-wire-payload dispatch-frame) ":task :title \"Patch AST\"") "dispatch payload content")
      (assert (= (.-from rc-frame) "worker-qwen-1") "rc frame from worker")
      (assert (= (.-to rc-frame) "leader-node") "rc frame to leader")
      (assert (string-contains? (.-wire-payload rc-frame) ":receipt :node \"worker-qwen-1\"") "rc payload worker")
      (assert (string-contains? (.-wire-payload rc-frame) ":status :pass") "rc payload pass")
      true)))

(df run-cluster-tests [] -> Bool
  :d "Executes all cluster mesh and single-token DAG dispatch tests."
  (do
    (test-worker-idle-state)
    (test-pool-registration-and-selection)
    (test-normalize-keys)
    (test-pack-dag-keys)
    (test-dispatch-and-receipt-lifecycle)
    true))

(df run-tests [] -> Bool
  :d "Standard test runner."
  (run-cluster-tests))
