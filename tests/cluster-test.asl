(module asl-bus/cluster-test
  :d "Unit verification test suite for Cluster-Native Mesh, Worker Pools, and Single-Token DAG Dispatch."
  :x [test-worker-idle-state
      test-pool-registration-and-selection
      test-single-tkn-compaction
      test-pack-dag-single-tkn
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

(df test-single-tkn-compaction [] -> Bool
  :d "Verifies that verbose S-expression heads are packed into single-token keywords."
  (let [(raw "(:node :sender \"orchestrator\" :target \"worker-1\" :payload \"test\" :status :pass :dependencies [\"t0\"] :premises [\"p1\"])")
        (packed (c/pack-tkn raw))]
    (and (string-contains? packed ":n")
         (string-contains? packed ":s")
         (string-contains? packed ":t")
         (string-contains? packed ":p")
         (string-contains? packed ":st")
         (string-contains? packed ":d")
         (string-contains? packed ":pr")
         (< (string-length packed) (string-length raw)))))

(df test-pack-dag-single-tkn [] -> Bool
  :d "Tests compacting a DAG task node definition into a single-token expression."
  (let [(deps (list "task-setup" "task-schema"))
        (premises (list "premise-airgap-active"))
        (dag-str (c/pack-dag "task-cluster-01" "Deploy remote worker" deps premises))]
    (and (string-contains? dag-str ":n :id \"task-cluster-01\"")
         (string-contains? dag-str ":d 2")
         (string-contains? dag-str ":pr 1")
         (string-contains? dag-str ":st :pending"))))

(df test-dispatch-and-receipt-lifecycle [] -> Bool
  :d "Tests dispatching a task frame to a worker and receiving a single-token receipt."
  (let [(w (c/WorkerNode
             :id "worker-qwen-1"
             :host "10.0.0.1"
             :port 8765
             :role "coder"
             :arm "qwen-3b"
             :state (c/state-idle)
             :caps (list "ast-patch")
             :ping 10))
        (dag-payload "(:task :title \"Patch AST\" :dependencies 0 :status :active)")
        (dispatch-frame (c/dispatch-task "frame-9001" "leader-node" w "task-42" dag-payload))
        (rc-frame (c/make-receipt "frame-9002" "worker-qwen-1" "leader-node" "task-42" 18 55))]
    (and (= (.-from dispatch-frame) "leader-node")
         (= (.-to dispatch-frame) "worker-qwen-1")
         (string-contains? (.-tkn-single dispatch-frame) ":t")
         (= (.-from rc-frame) "worker-qwen-1")
         (= (.-to rc-frame) "leader-node")
         (string-contains? (.-tkn-single rc-frame) ":rc :n \"worker-qwen-1\"")
         (string-contains? (.-tkn-single rc-frame) ":st :pass"))))

(df run-cluster-tests [] -> Bool
  :d "Executes all cluster mesh and single-token DAG dispatch tests."
  (and (test-worker-idle-state)
       (test-pool-registration-and-selection)
       (test-single-tkn-compaction)
       (test-pack-dag-single-tkn)
       (test-dispatch-and-receipt-lifecycle)))
