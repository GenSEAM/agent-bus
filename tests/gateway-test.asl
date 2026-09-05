(module asl-bus/gateway-test
  :d "Unit tests for Universal Deterministic L7 Cognitive Gateway Proxy."
  :x [test-demux-channels
      test-quarantine-reasoning
      test-verbal-esh-rejection
      test-verified-execution-allowed
      test-lcs-grounding
      test-format-gateway-verdict
      run-tests]
  :i [(gateway :a gw)])

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

(df run-tests [] -> Bool
  :d "Executes full L7 cognitive gateway test suite."
  (and (test-demux-channels)
       (and (test-quarantine-reasoning)
            (and (test-verbal-esh-rejection)
                 (and (test-verified-execution-allowed)
                      (and (test-lcs-grounding)
                           (test-format-gateway-verdict)))))))
