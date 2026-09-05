(module asl-bus/gateway
  :d "Universal Deterministic L7 Cognitive Gateway Proxy: tri-channel demuxing, quarantined reasoning, verbal ESH ban, and LCS grounding."
  :x [GatewayChannel
      MultiplexedFrame
      GatewayInspectionVerdict
      demux-stream-content
      detect-esh-violation
      calculate-lcs-grounding
      inspect-gateway-turn
      format-gateway-verdict
      adapt-anthropic-request
      format-anthropic-response]
  :i [])

(dfe GatewayChannel
  (:c channel-ui [] "Channel A: direct conversational output")
  (:c channel-think [] "Channel B: quarantined CoT reasoning")
  (:c channel-tool [] "Channel C: structured tool execution frames"))

(dfs MultiplexedFrame
  (:f channel GatewayChannel "Target channel")
  (:f content Str "Demuxed content payload")
  (:f metadata Str "Diagnostic or routing metadata"))

(dfs GatewayInspectionVerdict
  (:f allowed Bool "True if completion satisfies all cognitive gateway invariants")
  (:f quarantined-reasoning Str "Quarantined chain-of-thought scratchpad")
  (:f sanitized-user-output Str "Clean conversational output for user")
  (:f tool-frames (List Str) "Extracted executable tool call frames")
  (:f rejection-reason Str "Diagnostic reason if inspection failed"))

(df extract-think-blocks [(text Str)] -> (Pair Str Str)
  :d "Separates <think>...</think> block from remaining conversational stream, returning (pair think remaining)."
  (let [(open-tag "<think>")
        (close-tag "</think>")
        (idx-open (string-index-of text open-tag))]
    (mt idx-open
      ((none) (pair "" text))
      ((some o)
       (let [(after-open (option-or (string-slice text (+ o 7) (string-length text)) ""))
             (idx-close (string-index-of after-open close-tag))]
         (mt idx-close
           ((none) (pair (string-trim after-open) (option-or (string-slice text 0 o) "")))
           ((some c)
            (let [(think-content (option-or (string-slice after-open 0 c) ""))
                  (prefix (option-or (string-slice text 0 o) ""))
                  (suffix (option-or (string-slice after-open (+ c 8) (string-length after-open)) ""))
                  (remaining (string-trim (str prefix " " suffix)))]
              (pair (string-trim think-content) remaining)))))))))

(df extract-tool-calls [(text Str)] -> (Pair (List Str) Str)
  :d "Extracts top-level (call :tool ...) expressions from text, returning (pair tool-calls remaining)."
  (let [(lines (string-split text "\n"))
        (res (fold (fn [(acc (Pair (List Str) (List Str))) (ln Str)] -> (Pair (List Str) (List Str))
                     (let [(trimmed (string-trim ln))]
                       (if (string-starts-with? trimmed "(call :tool")
                           (pair (list-append (fst acc) (list trimmed)) (snd acc))
                           (pair (fst acc) (list-append (snd acc) (list ln))))))
                   (pair (list) (list))
                   lines))]
    (pair (fst res) (string-trim (string-join (snd res) "\n")))))

(df demux-stream-content [(raw-stream Str)] -> (List MultiplexedFrame)
  :d "De-multiplexes raw LLM stream into Channel A (UI), Channel B (Think), and Channel C (Tool)."
  (let [(think-split (extract-think-blocks raw-stream))
        (think-content (fst think-split))
        (non-think (snd think-split))
        (tool-split (extract-tool-calls non-think))
        (tool-calls (fst tool-split))
        (ui-content (snd tool-split))
        (frames0 (list))]
    (let [(frames1 (if (string-empty? think-content)
                       frames0
                       (list-append frames0 (list (MultiplexedFrame :channel (channel-think) :content think-content :metadata "quarantined-cot")))))
          (frames2 (fold (fn [(acc (List MultiplexedFrame)) (tc Str)] -> (List MultiplexedFrame)
                           (list-append acc (list (MultiplexedFrame :channel (channel-tool) :content tc :metadata "structured-call"))))
                         frames1
                         tool-calls))
          (frames3 (if (string-empty? ui-content)
                       frames2
                       (list-append frames2 (list (MultiplexedFrame :channel (channel-ui) :content ui-content :metadata "user-facing")))))]
      frames3)))

(df detect-esh-violation [(text Str)] -> Bool
  :d "Detects verbal self-declared execution completion (Execution Simulation Hallucination)."
  (let [(lower (string-lower text))]
    (or (string-contains? lower "i have run the tests and they pass")
        (or (string-contains? lower "all tests pass")
            (or (string-contains? lower "all tests passed")
                (or (string-contains? lower "tests are passing")
                    (or (string-contains? lower "i ran the tests and verified")
                        (or (string-contains? lower "everything is verified and passing")
                            (or (string-contains? lower "build succeeded cleanly")
                                (string-contains? lower "test suite passing cleanly"))))))))))

(df calculate-lcs-grounding [(model-snippet Str) (reference-source Str)] -> F64
  :d "Calculates token and character overlap grounding ratio between model code and reference source."
  (let [(trimmed-snippet (string-trim model-snippet))]
    (cond
      ((string-empty? trimmed-snippet) 1.0)
      ((string-empty? reference-source) 0.0)
      ((string-contains? reference-source trimmed-snippet) 1.0)
      (:else
       (let [(lines (filter (fn [(l Str)] -> Bool (not (string-empty? (string-trim l)))) (string-split trimmed-snippet "\n")))
             (total (list-length lines))]
         (if (<= total 0)
             1.0
             (let [(matched (fold (fn [(count I64) (ln Str)] -> I64
                                    (if (string-contains? reference-source (string-trim ln))
                                        (+ count 1)
                                        count))
                                  0
                                  lines))]
               (/ (float-from-int64 matched) (float-from-int64 total)))))))))

(df inspect-gateway-turn [(raw-completion Str) (has-verified-execution Bool)] -> GatewayInspectionVerdict
  :d "Universal L7 Gateway audit: quarantines reasoning, demuxes channels, and rejects verbal ESH."
  (let [(frames (demux-stream-content raw-completion))
        (thinks (filter (fn [(f MultiplexedFrame)] -> Bool
                          (mt (.-channel f)
                            ((channel-think) true)
                            ((channel-ui) false)
                            ((channel-tool) false)))
                        frames))
        (tools (filter (fn [(f MultiplexedFrame)] -> Bool
                         (mt (.-channel f)
                           ((channel-tool) true)
                           ((channel-ui) false)
                           ((channel-think) false)))
                       frames))
        (uis (filter (fn [(f MultiplexedFrame)] -> Bool
                       (mt (.-channel f)
                         ((channel-ui) true)
                         ((channel-think) false)
                         ((channel-tool) false)))
                     frames))
        (quarantined (string-join (map (fn [(f MultiplexedFrame)] -> Str (.-content f)) thinks) "\n"))
        (user-output (string-join (map (fn [(f MultiplexedFrame)] -> Str (.-content f)) uis) "\n"))
        (tool-calls (map (fn [(f MultiplexedFrame)] -> Str (.-content f)) tools))]
    (if (and (detect-esh-violation user-output) (not has-verified-execution))
        (GatewayInspectionVerdict
          :allowed false
          :quarantined-reasoning quarantined
          :sanitized-user-output user-output
          :tool-frames tool-calls
          :rejection-reason "Verbal self-declared execution without verified runtime proof (ESH violation)")
        (GatewayInspectionVerdict
          :allowed true
          :quarantined-reasoning quarantined
          :sanitized-user-output user-output
          :tool-frames tool-calls
          :rejection-reason ""))))

(df format-gateway-verdict [(verdict GatewayInspectionVerdict)] -> Str
  :d "Renders structured S-expression diagnostic block for gateway verdict."
  (if (.-allowed verdict)
      (str "(:gateway-verdict :allowed true :tool-count " (string-from-int64 (list-length (.-tool-frames verdict))) ")")
      (str "(:gateway-verdict :allowed false :reason \"" (.-rejection-reason verdict) "\")")))

(df adapt-anthropic-request [(messages-json Str) (tools-json Str)] -> Str
  :d "Adapts Anthropic Messages API payload into canonical ASL cognitive gateway frame."
  (str "(:anthropic-turn :messages " messages-json " :tools " tools-json ")"))

(df format-anthropic-response [(verdict GatewayInspectionVerdict) (model Str)] -> Str
  :d "Formats Gateway verdict into valid Anthropic Messages API response JSON."
  (if (.-allowed verdict)
      (let [(content (.-sanitized-user-output verdict))
            (tools (.-tool-frames verdict))]
        (if (list-empty? tools)
            (str "{\"id\": \"msg_asl\", \"type\": \"message\", \"role\": \"assistant\", \"model\": \"" model "\", \"content\": [{\"type\": \"text\", \"text\": \"" (string-replace content "\"" "\\\"") "\"}]}")
            (let [(tc (first tools))]
              (str "{\"id\": \"msg_asl\", \"type\": \"message\", \"role\": \"assistant\", \"model\": \"" model "\", \"content\": [{\"type\": \"text\", \"text\": \"" (string-replace content "\"" "\\\"") "\"}, {\"type\": \"tool_use\", \"id\": \"call_asl\", \"name\": \"tool\", \"input\": {\"call\": \"" (string-replace tc "\"" "\\\"") "\"}}]}"))))
      (str "{\"id\": \"msg_err\", \"type\": \"error\", \"error\": {\"type\": \"gateway_rejection\", \"message\": \"" (.-rejection-reason verdict) "\"}}")))
