(module asl-bus/gateway-test
  :d "Unit tests for Universal Deterministic L7 Cognitive Gateway Proxy."
  :x [test-demux-channels
      test-quarantine-reasoning
      test-verbal-esh-rejection
      test-verified-execution-allowed
      test-lcs-grounding
      test-format-gateway-verdict
      test-anthropic-adapter
      test-remote-mesh-timeout-unreachable
      test-control-plane-token-economy
      test-asn-tool-call-detection-and-headers
      run-tests]
  :i [(gateway :a gw) (mesh :a m)])

"run: (run-tests)"

(df test-demux-channels [] -> Bool
  :d "Verifies tri-channel de-multiplexing separates think, tool calls, and UI text."
  (let [(raw "<think>\nLet me analyze the problem...\nWe should use tool search.\n</think>\nI am searching the repository.\n(call :tool search :q \"gateway\")\nPlease wait for the result.")
        (frames (gw/demux-stream-content raw))]
    (do
      (assert (= (list-length frames) 3) "Must demux stream into 3 frames")
      (let [(f-think (list-head frames))
            (f-tool (list-head (list-drop frames 1)))
            (f-ui (list-head (list-drop frames 2)))]
        (do
          (assert (mt f-think
                    ((some ft) (and (mt (.-channel ft) ((channel-think) true) ((channel-ui) false) ((channel-tool) false))
                                    (string-contains? (.-content ft) "Let me analyze")))
                    ((none) false)) "Think channel frame must match")
          (assert (mt f-tool
                    ((some fto) (and (mt (.-channel fto) ((channel-tool) true) ((channel-ui) false) ((channel-think) false))
                                     (string-contains? (.-content fto) "(call :tool search")))
                    ((none) false)) "Tool channel frame must match")
          (assert (mt f-ui
                    ((some fu) (and (mt (.-channel fu) ((channel-ui) true) ((channel-think) false) ((channel-tool) false))
                                    (string-contains? (.-content fu) "I am searching")))
                    ((none) false)) "UI channel frame must match")
          (assert (not (= (list-length frames) 0)) "Frames list must not be empty")
          (assert (not (list-empty? frames)) "Frames list must not be empty predicate")
          true)))))

(df test-quarantine-reasoning [] -> Bool
  :d "Verifies that reasoning tokens are quarantined from sanitized user output."
  (let [(raw "<think>\nInternal confidential thoughts\n</think>\nHello user, how can I help you?")
        (verdict (gw/inspect-gateway-turn raw true))]
    (do
      (assert (.-allowed verdict) "Gateway turn must be allowed")
      (assert (string-contains? (.-quarantined-reasoning verdict) "Internal confidential thoughts") "Quarantined reasoning must contain think tokens")
      (assert (not (string-contains? (.-sanitized-user-output verdict) "Internal confidential thoughts")) "Sanitized user output must not leak reasoning tokens")
      (assert (string-contains? (.-sanitized-user-output verdict) "Hello user") "Sanitized output must retain user response")
      true)))

(df test-verbal-esh-rejection [] -> Bool
  :d "Verifies that verbal claims of test passage without verified execution are rejected."
  (let [(raw "I have finished the task. All tests pass cleanly.")
        (verdict (gw/inspect-gateway-turn raw false))]
    (do
      (assert (not (.-allowed verdict)) "Verbal claim without verified execution must be rejected")
      (assert (string-contains? (.-rejection-reason verdict) "ESH violation") "Rejection reason must cite ESH violation")
      (assert (not (= (.-rejection-reason verdict) "")) "Rejection reason must not be empty")
      true)))

(df test-verified-execution-allowed [] -> Bool
  :d "Verifies that completion statements with verified runtime execution pass the gateway."
  (let [(raw "I have finished the task. All tests pass cleanly.")
        (verdict (gw/inspect-gateway-turn raw true))]
    (do
      (assert (.-allowed verdict) "Completion with verified execution must pass")
      (assert (= (.-rejection-reason verdict) "") "Rejection reason must be empty")
      (assert (not (string-contains? (.-rejection-reason verdict) "ESH violation")) "Must not trigger ESH violation when verified")
      true)))

(df test-lcs-grounding [] -> Bool
  :d "Verifies Longest Common Subsequence grounding calculation."
  (let [(ref "def calculate(x):\n    return x * 2\n")
        (snip-exact "return x * 2")
        (snip-partial "return x * 2\nvalue = 42")
        (snip-none "unrelated random string 999")
        (g-exact (gw/calculate-lcs-grounding snip-exact ref))
        (g-partial (gw/calculate-lcs-grounding snip-partial ref))
        (g-none (gw/calculate-lcs-grounding snip-none ref))]
    (do
      (assert (= g-exact 1.0) "Exact snippet must have grounding score 1.0")
      (assert (> g-partial 0.4) "Partial match grounding score must be > 0.4")
      (assert (< g-partial 1.0) "Partial match grounding score must be < 1.0")
      (assert (not (= g-none 1.0)) "Unrelated text grounding must not be 1.0")
      true)))

(df test-format-gateway-verdict [] -> Bool
  :d "Verifies diagnostic formatting for allowed and rejected gateway verdicts."
  (let [(v-ok (gw/GatewayInspectionVerdict :allowed true :quarantined-reasoning "" :sanitized-user-output "hello" :tool-frames (list "call1") :rejection-reason ""))
        (v-err (gw/GatewayInspectionVerdict :allowed false :quarantined-reasoning "" :sanitized-user-output "" :tool-frames (list) :rejection-reason "ESH violation"))
        (s-ok (gw/format-gateway-verdict v-ok))
        (s-err (gw/format-gateway-verdict v-err))]
    (do
      (assert (string-contains? s-ok "(:gateway-verdict :allowed true") "Formatted verdict must indicate allowed true")
      (assert (string-contains? s-err "(:gateway-verdict :allowed false") "Formatted verdict must indicate allowed false")
      (assert (not (string-contains? s-ok ":rejection-reason \"ESH violation\"")) "Allowed verdict must not contain rejection reason")
      (assert (not (string-contains? s-err "(:gateway-verdict :allowed true")) "Error verdict must not indicate allowed true")
      true)))

(df test-anthropic-adapter [] -> Bool
  :d "Verifies adaptation of Anthropic Messages requests and responses"
  (let [(req (gw/adapt-anthropic-request "[{\"role\": \"user\", \"content\": \"hello\"}]" "[]"))
        (v-ok (gw/GatewayInspectionVerdict :allowed true :quarantined-reasoning "internal" :sanitized-user-output "hello" :tool-frames (list "fs-read") :rejection-reason ""))
        (resp (gw/format-anthropic-response v-ok "claude-3-7-sonnet"))]
    (do
      (assert (string-contains? req ":anthropic-turn") "Adapted request must contain :anthropic-turn")
      (assert (string-contains? resp "\"type\": \"message\"") "Response must contain message type")
      (assert (string-contains? resp "\"type\": \"tool_use\"") "Response must contain tool_use type")
      (assert (not (string-contains? resp "internal")) "Confidential reasoning must not leak in adapter response")
      true)))

(df test-remote-mesh-timeout-unreachable [] -> Bool
  :d "Verifies gateway emits structured remote-unreachable diagnostic on unreachable cluster."
  (let [(contract (m/make-task-contract "task-101" "Process remote telemetry" (list) (list "Exit 0") "mesh" (list "coder")))
        (res-unreachable (gw/proxy-contract-to-mesh contract "remote-gpu" false))
        (res-reachable (gw/proxy-contract-to-mesh contract "browser-edge" true))]
    (do
      (assert (string-contains? res-unreachable ":remote-unreachable") "Unreachable cluster must trigger :remote-unreachable")
      (assert (string-contains? res-unreachable ":cluster \"remote-gpu\"") "Diagnostic must name cluster")
      (assert (string-contains? res-unreachable ":fallback \"local-vfs\"") "Diagnostic must state fallback")
      (assert (string-contains? res-unreachable ":preserved-contract \"task-101\"") "Diagnostic must preserve contract")
      (assert (string-contains? res-reachable ":control-dispatch") "Reachable proxy must dispatch")
      (assert (string-contains? res-reachable ":cluster \"browser-edge\"") "Reachable proxy must name cluster")
      (assert (string-contains? res-reachable ":status \"proxied\"") "Reachable proxy status must be proxied")
      (assert (not (string-contains? res-reachable ":remote-unreachable")) "Reachable cluster must not be marked unreachable")
      (assert (not (string-contains? res-unreachable ":status \"proxied\"")) "Unreachable cluster must not be marked proxied")
      true)))

(df test-control-plane-token-economy [] -> Bool
  :d "Verifies that control plane dispatch frames stay compact and under token budget ceiling."
  (let [(contract (m/make-task-contract "task-202" "Run AST indexing" (list) (list "Pass") "mesh" (list "indexer")))
        (dispatch-str (gw/proxy-contract-to-mesh contract "remote-gpu" true))]
    (do
      (assert (< (string-length dispatch-str) 200) "Dispatch string must be compact under 200 bytes")
      (assert (string-contains? dispatch-str ":control-dispatch") "Dispatch string must contain :control-dispatch")
      (assert (not (> (string-length dispatch-str) 200)) "Dispatch string must not exceed token budget ceiling")
      (assert (not (string-empty? dispatch-str)) "Dispatch string must not be empty")
      true)))

(df test-asn-tool-call-detection-and-headers [] -> Bool
  :d "Verifies disambiguation between ASN tool calls and structural ASN data, plus wire headers."
  (let [(tc1 "(:call :tool read :path \"core/auth.asl\" :start 1 :end 20)")
        (tc2 "(call :tool exec :cmd \"asl test\")")
        (data1 "(:struct User (:f name Str) (:f age I64))")
        (data2 "(:ast-outline (:module auth) (:exports [login]))")
        (mixed (str "Here is the user type:\n" data1 "\n" tc1 "\nDone."))
        (frames (gw/demux-stream-content mixed))
        (headers (gw/format-asn-protocol-headers))]
    (do
      (assert (gw/is-asn-tool-call? tc1) "tc1 must be detected as ASN tool call")
      (assert (gw/is-asn-tool-call? tc2) "tc2 must be detected as ASN tool call")
      (assert (not (gw/is-asn-tool-call? data1)) "data1 must not be detected as ASN tool call")
      (assert (not (gw/is-asn-tool-call? data2)) "data2 must not be detected as ASN tool call")
      (assert (= (list-length frames) 2) "Mixed stream must demux into 2 frames")
      (assert (string-contains? headers "ASL-Protocol-Version") "Headers must contain protocol version")
      (let [(f-tool (list-head frames))
            (f-ui (list-head (list-drop frames 1)))]
        (do
          (assert (mt f-tool
                    ((some ft) (and (mt (.-channel ft) ((channel-tool) true) ((channel-ui) false) ((channel-think) false))
                                    (string-contains? (.-content ft) "(:call :tool read")))
                    ((none) false)) "Tool frame content must match")
          (assert (mt f-ui
                    ((some fu) (and (mt (.-channel fu) ((channel-ui) true) ((channel-tool) false) ((channel-think) false))
                                    (string-contains? (.-content fu) "(:struct User")))
                    ((none) false)) "UI frame content must match")
          (assert (not (string-contains? headers "UNKNOWN-PROTOCOL")) "Headers must not contain unknown protocol")
          true)))))

(df run-tests [] -> Bool
  :d "Executes full L7 cognitive gateway test suite with strict falsification assertions."
  (do
    (assert (test-demux-channels))
    (assert (test-quarantine-reasoning))
    (assert (test-verbal-esh-rejection))
    (assert (test-verified-execution-allowed))
    (assert (test-lcs-grounding))
    (assert (test-format-gateway-verdict))
    (assert (test-anthropic-adapter))
    (assert (test-remote-mesh-timeout-unreachable))
    (assert (test-control-plane-token-economy))
    (assert (test-asn-tool-call-detection-and-headers))
    true))
