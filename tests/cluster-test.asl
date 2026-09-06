(module asl-bus/cluster-test
  :d "Unit verification test suite for Cluster-Native Mesh, Worker Pools, and Unambiguous DAG Dispatch."
  :x [test-worker-idle-state
      test-pool-registration-and-selection
      test-normalize-keys
      test-pack-dag-keys
      test-dispatch-and-receipt-lifecycle
      run-cluster-tests]
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
    (and (c/worker-idle? w1)
         (not (c/worker-idle? w2)))))

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
    (and (option-some? coder-opt)
         (option-some? vision-opt)
         (not (option-some? miss-opt))
         (= (.-id (option-unwrap coder-opt)) "worker-qwen-1")
         (= (.-id (option-unwrap vision-opt)) "worker-vision-1"))))

(df test-normalize-keys [] -> Bool
  :d "Verifies rational unambiguous normalization without state and status collision."
  (let [(raw "(:node :sender \"orchestrator\" :target \"worker-1\" :payload \"test\" :status :pass :state :active :dependencies [\"t0\"])")
        (normalized (c/pack-keys raw))
        (restored (c/unpack-keys normalized))]
    (and (string-contains? normalized ":from \"orchestrator\"")
         (string-contains? normalized ":to \"worker-1\"")
         (string-contains? normalized ":deps [\"t0\"]")
         (string-contains? normalized ":status :pass")
         (string-contains? normalized ":state :active")
         (= restored raw))))

(df test-pack-dag-keys [] -> Bool
  :d "Tests compacting a DAG task node definition into a canonical expression."
  (let [(deps (list "task-setup" "task-schema"))
        (premises (list "premise-airgap-active"))
        (dag-str (c/pack-dag "task-cluster-01" "Deploy remote worker" deps premises))]
    (and (string-contains? dag-str ":node :id \"task-cluster-01\"")
         (string-contains? dag-str ":deps 2")
         (string-contains? dag-str ":premises 1")
         (string-contains? dag-str ":state :pending"))))

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
    (and (= (.-from dispatch-frame) "leader-node")
         (= (.-to dispatch-frame) "worker-qwen-1")
         (string-contains? (.-wire-payload dispatch-frame) ":task :title \"Patch AST\"")
         (= (.-from rc-frame) "worker-qwen-1")
         (= (.-to rc-frame) "leader-node")
         (string-contains? (.-wire-payload rc-frame) ":receipt :node \"worker-qwen-1\"")
         (string-contains? (.-wire-payload rc-frame) ":status :pass"))))

(df run-cluster-tests [] -> Bool
  :d "Executes all cluster mesh and single-token DAG dispatch tests."
  (and (test-worker-idle-state)
       (test-pool-registration-and-selection)
       (test-normalize-keys)
       (test-pack-dag-keys)
       (test-dispatch-and-receipt-lifecycle)))
