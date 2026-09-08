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
    (assert (= (.-id env) "env-101") "Envelope id must match")
    (assert (= (.-sender env) "agent:planner") "Sender must match")
    (assert (= (.-target env) "agent:worker") "Target must match")
    (assert (= (.-seq env) 1) "Sequence number must match 1")
    (assert (= (.-payload env) "(:batch (:out \"main.asl\"))") "Payload must match")
    true))

(df test-session-lifecycle [] -> Bool
  :d "Verifies transport session state transitions and active predicate."
  (let [(s0 (tr/init-transport-session "sess-001" "node-peer-42"))
        (s1 (tr/session-set-state s0 (tr/transport-connecting)))
        (s2 (tr/session-set-state s1 (tr/transport-connected)))
        (s3 (tr/session-set-state s2 (tr/transport-closed)))]
    (assert (not (tr/is-session-active? s0)) "Initial session must not be active")
    (assert (not (tr/is-session-active? s1)) "Connecting session must not be active")
    (assert (tr/is-session-active? s2) "Connected session must be active")
    (assert (not (tr/is-session-active? s3)) "Closed session must not be active")
    true))

(df test-session-counters [] -> Bool
  :d "Verifies sent and received frame counters and sequence tracking."
  (let [(s0 (tr/init-transport-session "sess-002" "node-peer-43"))
        (s1 (tr/session-record-sent s0 10))
        (s2 (tr/session-record-sent s1 11))
        (s3 (tr/session-record-received s2 12))]
    (assert (= (.-frames-sent s3) 2) "Frames sent must be 2")
    (assert (= (.-frames-received s3) 1) "Frames received must be 1")
    (assert (= (.-last-seq s3) 12) "Last sequence number must be 12")
    true))

(df test-frame-header-formatting [] -> Bool
  :d "Verifies compact wire transmission header line formatting."
  (let [(env (tr/make-transport-envelope "f-99" (tr/frame-heartbeat) "nodeA" "nodeB" 42 "ping" 1000))
        (hdr (tr/format-frame-header env))]
    (assert (= hdr "FRAME:f-99:42:nodeA->nodeB") "Frame header must match FRAME:id:seq:sender->target format")
    (assert (not (string-contains? hdr "nodeB->nodeA")) "Frame header direction must not be reversed")
    (assert (not (string-contains? hdr "FRAME:f-99:0:")) "Frame header sequence must not be 0")
    true))

(df test-envelope-validation [] -> Bool
  :d "Verifies envelope invariant checking across valid and invalid envelopes."
  (let [(valid (tr/make-transport-envelope "f-01" (tr/frame-rpc-res) "src" "dst" 1 "ok" 500))
        (invalid-id (tr/make-transport-envelope "" (tr/frame-rpc-res) "src" "dst" 1 "ok" 500))
        (invalid-seq (tr/make-transport-envelope "f-02" (tr/frame-rpc-res) "src" "dst" -1 "ok" 500))]
    (assert (tr/validate-transport-envelope valid) "Valid envelope must pass validation")
    (assert (not (tr/validate-transport-envelope invalid-id)) "Empty id envelope must fail validation")
    (assert (not (tr/validate-transport-envelope invalid-seq)) "Negative sequence envelope must fail validation")
    true))

(df run-tests [] -> Bool
  :d "Executes all transport specification unit tests."
  (and (test-envelope-creation)
       (test-session-lifecycle)
       (test-session-counters)
       (test-frame-header-formatting)
       (test-envelope-validation)))

(run-tests)
