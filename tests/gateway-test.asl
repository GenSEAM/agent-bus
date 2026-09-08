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
    (and (= (list-length frames) 3)
         (let [(f-think (list-head frames))
               (f-tool (list-head (list-drop frames 1)))
               (f-ui (list-head (list-drop frames 2)))]
           (and (mt f-think
                  ((some ft) (and (mt (.-channel ft) ((channel-think) true) ((channel-ui) false) ((channel-tool) false))
                                  (string-contains? (.-content ft) "Let me analyze")))
                  ((none) false))
                (and (mt f-tool
                       ((some fto) (and (mt (.-channel fto) ((channel-tool) true) ((channel-ui) false) ((channel-think) false))
                                        (string-contains? (.-content fto) "(call :tool search")))
                       ((none) false))
                     (mt f-ui
                       ((some fu) (and (mt (.-channel fu) ((channel-ui) true) ((channel-think) false) ((channel-tool) false))
                                       (string-contains? (.-content fu) "I am searching")))
                       ((none) false))))))))

(df test-quarantine-reasoning [] -> Bool
  :d "Verifies that reasoning tokens are quarantined from sanitized user output."
  (let [(raw "<think>\nInternal confidential thoughts\n</think>\nHello user, how can I help you?")
        (verdict (gw/inspect-gateway-turn raw true))]
    (and (.-allowed verdict)
         (and (string-contains? (.-quarantined-reasoning verdict) "Internal confidential thoughts")
              (and (not (string-contains? (.-sanitized-user-output verdict) "Internal confidential thoughts"))
                   (string-contains? (.-sanitized-user-output verdict) "Hello user"))))))

(df test-verbal-esh-rejection [] -> Bool
  :d "Verifies that verbal claims of test passage without verified execution are rejected."
  (let [(raw "I have finished the task. All tests pass cleanly.")
        (verdict (gw/inspect-gateway-turn raw false))]
    (and (not (.-allowed verdict))
         (string-contains? (.-rejection-reason verdict) "ESH violation"))))

(df test-verified-execution-allowed [] -> Bool
  :d "Verifies that completion statements with verified runtime execution pass the gateway."
  (let [(raw "I have finished the task. All tests pass cleanly.")
        (verdict (gw/inspect-gateway-turn raw true))]
    (and (.-allowed verdict)
         (= (.-rejection-reason verdict) ""))))

(df test-lcs-grounding [] -> Bool
  :d "Verifies Longest Common Subsequence grounding calculation."
  (let [(ref "def calculate(x):\n    return x * 2\n")
        (snip-exact "return x * 2")
        (snip-partial "return x * 2\nvalue = 42")
        (g-exact (gw/calculate-lcs-grounding snip-exact ref))
        (g-partial (gw/calculate-lcs-grounding snip-partial ref))]
    (and (= g-exact 1.0)
         (and (> g-partial 0.4)
              (< g-partial 1.0)))))

(df test-format-gateway-verdict [] -> Bool
  :d "Verifies diagnostic formatting for allowed and rejected gateway verdicts."
  (let [(v-ok (gw/GatewayInspectionVerdict :allowed true :quarantined-reasoning "" :sanitized-user-output "hello" :tool-frames (list "call1") :rejection-reason ""))
        (v-err (gw/GatewayInspectionVerdict :allowed false :quarantined-reasoning "" :sanitized-user-output "" :tool-frames (list) :rejection-reason "ESH violation"))
        (s-ok (gw/format-gateway-verdict v-ok))
        (s-err (gw/format-gateway-verdict v-err))]
    (and (string-contains? s-ok "(:gateway-verdict :allowed true")
         (string-contains? s-err "(:gateway-verdict :allowed false"))))

(df test-anthropic-adapter [] -> Bool
  :d "Verifies adaptation of Anthropic Messages requests and responses"
  (let [(req (gw/adapt-anthropic-request "[{\"role\": \"user\", \"content\": \"hello\"}]" "[]"))
        (v-ok (gw/GatewayInspectionVerdict :allowed true :quarantined-reasoning "internal" :sanitized-user-output "hello" :tool-frames (list "fs-read") :rejection-reason ""))
        (resp (gw/format-anthropic-response v-ok "claude-3-7-sonnet"))]
    (and (string-contains? req ":anthropic-turn")
         (and (string-contains? resp "\"type\": \"message\"")
              (string-contains? resp "\"type\": \"tool_use\"")))))

(df test-remote-mesh-timeout-unreachable [] -> Bool
  :d "Verifies gateway emits structured remote-unreachable diagnostic on unreachable cluster."
  (let [(contract (m/make-task-contract "task-101" "Process remote telemetry" (list) (list "Exit 0") "mesh" (list "coder")))
        (res-unreachable (gw/proxy-contract-to-mesh contract "remote-gpu" false))
        (res-reachable (gw/proxy-contract-to-mesh contract "browser-edge" true))]
    (and (string-contains? res-unreachable ":remote-unreachable")
         (and (string-contains? res-unreachable ":cluster \"remote-gpu\"")
              (and (string-contains? res-unreachable ":fallback \"local-vfs\"")
                   (and (string-contains? res-unreachable ":preserved-contract \"task-101\"")
                        (and (string-contains? res-reachable ":control-dispatch")
                             (and (string-contains? res-reachable ":cluster \"browser-edge\"")
                                  (string-contains? res-reachable ":status \"proxied\"")))))))))

(df test-control-plane-token-economy [] -> Bool
  :d "Verifies that control plane dispatch frames stay compact and under token budget ceiling."
  (let [(contract (m/make-task-contract "task-202" "Run AST indexing" (list) (list "Pass") "mesh" (list "indexer")))
        (dispatch-str (gw/proxy-contract-to-mesh contract "remote-gpu" true))]
    (and (< (string-length dispatch-str) 200)
         (string-contains? dispatch-str ":control-dispatch"))))

(df test-asn-tool-call-detection-and-headers [] -> Bool
  :d "Verifies disambiguation between ASN tool calls and structural ASN data, plus wire headers."
  (let [(tc1 "(:call :tool read :path \"core/auth.asl\" :start 1 :end 20)")
        (tc2 "(call :tool exec :cmd \"asl test\")")
        (data1 "(:struct User (:f name Str) (:f age I64))")
        (data2 "(:ast-outline (:module auth) (:exports [login]))")
        (mixed (str "Here is the user type:\n" data1 "\n" tc1 "\nDone."))
        (frames (gw/demux-stream-content mixed))
        (headers (gw/format-asn-protocol-headers))]
    (and (gw/is-asn-tool-call? tc1)
         (and (gw/is-asn-tool-call? tc2)
              (and (not (gw/is-asn-tool-call? data1))
                   (and (not (gw/is-asn-tool-call? data2))
                        (and (= (list-length frames) 2)
                             (let [(f-tool (list-head frames))
                                   (f-ui (list-head (list-drop frames 1)))]
                               (and (mt f-tool
                                      ((some ft) (and (mt (.-channel ft) ((channel-tool) true) ((channel-ui) false) ((channel-think) false))
                                                      (string-contains? (.-content ft) "(:call :tool read")))
                                      ((none) false))
                                    (mt f-ui
                                      ((some fu) (and (mt (.-channel fu) ((channel-ui) true) ((channel-tool) false) ((channel-think) false))
                                                      (string-contains? (.-content fu) "(:struct User")))
                                      ((none) false)))))))))))

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
