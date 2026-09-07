(module asl-bus/transport-test
  :d "Unit tests for AgentScript Bus Transport Specification."
  :x [test-envelope-creation
      test-session-lifecycle
      test-session-counters
      test-frame-header-formatting
      test-envelope-validation
      run-tests]
  :i [(transport :a tr)])

(df test-envelope-creation [] -> Bool
  :d "Verifies transport envelope field assignment and integrity."
  (let [(env (tr/make-transport-envelope "env-101" (tr/frame-rpc-req) "agent:planner" "agent:worker" 1 "(:batch (:out \"main.asl\"))" 1725700000))]
    (and (= (.-id env) "env-101")
         (and (= (.-sender env) "agent:planner")
              (and (= (.-target env) "agent:worker")
                   (and (= (.-seq env) 1)
                        (= (.-payload env) "(:batch (:out \"main.asl\"))")))))))

(df test-session-lifecycle [] -> Bool
  :d "Verifies transport session state transitions and active predicate."
  (let [(s0 (tr/init-transport-session "sess-001" "node-peer-42"))
        (s1 (tr/session-set-state s0 (tr/transport-connecting)))
        (s2 (tr/session-set-state s1 (tr/transport-connected)))
        (s3 (tr/session-set-state s2 (tr/transport-closed)))]
    (and (not (tr/is-session-active? s0))
         (and (not (tr/is-session-active? s1))
              (and (tr/is-session-active? s2)
                   (not (tr/is-session-active? s3)))))))

(df test-session-counters [] -> Bool
  :d "Verifies sent and received frame counters and sequence tracking."
  (let [(s0 (tr/init-transport-session "sess-002" "node-peer-43"))
        (s1 (tr/session-record-sent s0 10))
        (s2 (tr/session-record-sent s1 11))
        (s3 (tr/session-record-received s2 12))]
    (and (= (.-frames-sent s3) 2)
         (and (= (.-frames-received s3) 1)
              (= (.-last-seq s3) 12)))))

(df test-frame-header-formatting [] -> Bool
  :d "Verifies compact wire transmission header line formatting."
  (let [(env (tr/make-transport-envelope "f-99" (tr/frame-heartbeat) "nodeA" "nodeB" 42 "ping" 1000))
        (hdr (tr/format-frame-header env))]
    (= hdr "FRAME:f-99:42:nodeA->nodeB")))

(df test-envelope-validation [] -> Bool
  :d "Verifies envelope invariant checking across valid and invalid envelopes."
  (let [(valid (tr/make-transport-envelope "f-01" (tr/frame-rpc-res) "src" "dst" 1 "ok" 500))
        (invalid-id (tr/make-transport-envelope "" (tr/frame-rpc-res) "src" "dst" 1 "ok" 500))
        (invalid-seq (tr/make-transport-envelope "f-02" (tr/frame-rpc-res) "src" "dst" -1 "ok" 500))]
    (and (tr/validate-transport-envelope valid)
         (and (not (tr/validate-transport-envelope invalid-id))
              (not (tr/validate-transport-envelope invalid-seq))))))

(df run-tests [] -> Bool
  :d "Executes all transport specification unit tests."
  (and (test-envelope-creation)
       (and (test-session-lifecycle)
            (and (test-session-counters)
                 (and (test-frame-header-formatting)
                      (test-envelope-validation))))))
