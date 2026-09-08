(module agent-bus/nd-asn-test
  :d "Unit verification test suite for M2M newline-delimited ASN serialization, framing, and live memory evaluation"
  :x [test-frame-construction
      test-serialization-and-deserialization
      test-stream-chunking-and-delimiters
      test-toolcall-and-eval-payload
      test-corrupted-line-recovery
      run-tests]
  :i [(nd_asn :a n)])

(df test-frame-construction [] -> Bool
  :d "Verifies construction and field accessors of NDASNFrame records"
  (let [(meta (map-set (map-empty) "client" "gemini-cli"))
        (frame (n/nd-asn-frame "swarm.events" 101 1757160000 "(ping)" meta))]
    (assert (= (.-topic frame) "swarm.events") "Topic field must match constructor input")
    (assert (= (.-seq frame) 101) "Sequence number must match constructor input")
    (assert (= (.-ts frame) 1757160000) "Timestamp must match constructor input")
    (assert (= (.-payload frame) "(ping)") "Payload string must match constructor input")
    (assert (= (map-size (.-meta frame)) 1) "Metadata map size must equal 1")
    true))

(df test-serialization-and-deserialization [] -> Bool
  :d "Verifies single-frame and multi-frame serialization, roundtrip fidelity, and newline delimiters"
  (let [(meta1 (map-set (map-empty) "src" "node-1"))
        (f1 (n/nd-asn-frame "ch-alpha" 1 1000 "(event :status active)" meta1))
        (f2 (n/nd-asn-frame "ch-beta" 2 2000 "(event :status idle)" (map-empty)))
        (frames (list f1 f2))
        (serialized (n/nd-asn-serialize frames))]
    (assert (string-contains? serialized "\n") "Multi-frame serialization must contain newline delimiter")
    (let [(parsed (n/nd-asn-deserialize serialized))]
      (assert (= (list-length parsed) 2) "Deserializer must produce 2 results")
      (assert (is-ok? (option-or (list-head parsed) (err "missing-head"))) "First frame result must be ok")
      (let [(res1 (option-or (list-head parsed) (err "missing")))
            (frame1 (result-or res1 f2))]
        (assert (= (.-topic frame1) "ch-alpha") "Roundtrip topic must match f1")
        (assert (= (.-seq frame1) 1) "Roundtrip sequence number must match f1")
        (assert (= (.-payload frame1) "(event :status active)") "Roundtrip payload must match f1")))
    true))

(df test-stream-chunking-and-delimiters [] -> Bool
  :d "Verifies newline splitting, CRLF stripping, empty line filtering, and balanced multi-line expressions"
  (let [(stream-crlf "(:frame :topic \"t1\" :seq 1 :ts 10 :payload \"p1\" :meta [])\r\n\r\n(:frame :topic \"t2\" :seq 2 :ts 20 :payload \"p2\" :meta [])\r\n")
        (lines-crlf (n/nd-asn-parse-lines stream-crlf))]
    (assert (= (list-length lines-crlf) 2) "CRLF stream with blank line must yield exactly 2 frame lines")
    (let [(multiline-raw "(:frame :topic \"multi\"\n:seq 3\n:ts 30\n:payload \"payload\"\n:meta [])\n")
          (multiline-res (n/nd-asn-parse-lines multiline-raw))]
      (assert (= (list-length multiline-res) 1) "Balanced multi-line frame must be parsed into single frame chunk")
      (let [(parsed-multi (n/nd-asn-deserialize multiline-raw))]
        (assert (= (list-length parsed-multi) 1) "Multi-line stream must deserialize into exactly 1 result")
        (assert (is-ok? (option-or (list-head parsed-multi) (err "fail"))) "Multi-line frame result must be ok")
        (let [(frame (result-or (option-or (list-head parsed-multi) (err "fail")) (n/nd-asn-frame "" 0 0 "" (map-empty))))]
          (assert (= (.-topic frame) "multi") "Parsed multi-line frame topic must match multi"))))
    true))

(df test-toolcall-and-eval-payload [] -> Bool
  :d "Verifies toolcall creation with unquoted atom formatting, hydration load frames, and live payload evaluation"
  (let [(tc (n/nd-asn-make-toolcall "grep" "codebase" "tokenizer" 5))]
    (assert (= (.-payload tc) "(call! grep :col codebase :q tokenizer :limit 5)") "Toolcall payload must format unquoted atoms")
    (assert (= (.-topic tc) "toolcall") "Toolcall default topic must be toolcall")
    (let [(eval-tc (n/nd-asn-eval-payload tc))]
      (assert (is-ok? eval-tc) "Toolcall payload evaluation must succeed")
      (assert (= (result-or eval-tc "") "dispatched:grep") "Toolcall evaluation must dispatch tool name"))
    (let [(load-frame (n/nd-asn-frame "hydrate" 1 0 "(load! chunk-9988)" (map-empty)))
          (eval-load (n/nd-asn-eval-payload load-frame))]
      (assert (= (result-or eval-load "") "loaded:chunk-9988") "Hydration load frame evaluation must extract chunk id"))
    true))

(df test-corrupted-line-recovery [] -> Bool
  :d "Verifies stream parser resilience and error isolation when encountering corrupted or malformed lines"
  (let [(f-good-1 (n/nd-asn-frame "good1" 1 100 "data1" (map-empty)))
        (f-good-2 (n/nd-asn-frame "good2" 2 200 "data2" (map-empty)))
        (s1 (n/nd-asn-serialize (list f-good-1)))
        (s2 (n/nd-asn-serialize (list f-good-2)))
        (corrupted-stream (str s1 "\ncorrupted-garbage-line-without-frame-structure\n" s2))
        (results (n/nd-asn-deserialize corrupted-stream))]
    (assert (= (list-length results) 3) "Deserializer must produce 3 results for 3 non-empty lines")
    (let [(r1 (option-or (list-head results) (err "missing-1")))
          (rest1 (option-or (list-tail results) (list)))
          (r2 (option-or (list-head rest1) (ok (n/nd-asn-frame "" 0 0 "" (map-empty)))))
          (rest2 (option-or (list-tail rest1) (list)))
          (r3 (option-or (list-head rest2) (err "missing-3")))]
      (assert (is-ok? r1) "First valid line in mixed stream must succeed with ok")
      (assert (is-err? r2) "Corrupted line in mixed stream must be isolated as err")
      (assert (is-ok? r3) "Second valid line after corrupted line must recover and succeed with ok")
      (let [(bad-eval (n/nd-asn-eval-payload (n/nd-asn-frame "err" 3 300 "not-an-sexpr" (map-empty))))]
        (assert (is-err? bad-eval) "Evaluating malformed non-S-expression payload must return err")))
    true))

(df run-tests [] -> Bool
  :d "Executes full ND-ASN test suite verifying framing, chunking, toolcalls, and error recovery"
  (do
    (assert (test-frame-construction))
    (assert (test-serialization-and-deserialization))
    (assert (test-stream-chunking-and-delimiters))
    (assert (test-toolcall-and-eval-payload))
    (assert (test-corrupted-line-recovery))
    true))
