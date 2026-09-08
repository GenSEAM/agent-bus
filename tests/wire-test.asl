(module asl-bus/wire-test
  :d "Unit verification test suite for ASB Wire Protocol and Compression Framing."
  :x [test-wire-small-payload-uncompressed
      test-wire-large-payload-compressed
      test-wire-payload-roundtrip
      test-wire-payload-keys-collision
      test-wire-encode-decode-envelope
      test-wire-unpack-direct-vs-decompressed
      test-wire-internal-delimiters
      run-wire-tests]
  :i [(wire :a w)])

(df test-wire-small-payload-uncompressed [] -> Bool
  :d "Tests that messages under 128 bytes bypass compression."
  (let [(msg "(:msg :sender \"agent-1\" :target \"agent-2\" :payload \"ping\")")
        (frame (w/create-wire-frame (w/codec-asn-text) msg true))]
    (assert (not (w/is-compressed? frame)) "Payload under 128 bytes must remain uncompressed")
    (assert (= (w/unpack-wire-frame frame) msg) "Unpacked payload must match original uncompressed message")
    (assert (= (.-uncompressed-bytes frame) (string-length msg)) "Recorded uncompressed-bytes must match original length")
    true))

(df test-wire-large-payload-compressed [] -> Bool
  :d "Tests that payloads >= 128 bytes are compressed automatically."
  (let [(msg (str "(:msg :sender \"claude-code-orchestrator\""
                  " :target \"subagent-reviewer-pool\""
                  " :room \"refactor-matrix\""
                  " :status \"active\""
                  " :capabilities [\"ast-patch\" \"css-cascade\" \"git-patch\"]"
                  " :timestamp 1757160000"
                  " :payload \"(batch-transform-classes :source-code 'sample' :target 'btn' :replace 'button'))\""))]
    (let [(frame (w/create-wire-frame (w/codec-asb-binary) msg true))]
      (assert (w/is-compressed? frame) "Payload >= 128 bytes must have compressed flag true")
      (assert (> (string-length msg) 128) "Input message must exceed 128 byte threshold")
      (assert (< (string-length (.-payload frame)) (string-length msg)) "Compacted payload size must be smaller than raw")
      (assert (= (.-uncompressed-bytes frame) (string-length msg)) "Pre-allocation uncompressed buffer size must match")
      true)))

(df test-wire-payload-roundtrip [] -> Bool
  :d "Tests that dictionary compaction and expansion round-trips with zero data loss."
  (let [(raw "(:msg :sender \"a1\" :target \"a2\" :room \"main\" :status \"busy\" :capabilities [\"x\"] :timestamp 100 :payload \"hello\")")
        (compacted (w/compact-wire-payload raw))
        (restored (w/expand-wire-payload compacted))]
    (assert (= raw restored) "Expanded payload must equal original raw payload")
    (assert (not (= raw compacted)) "Compacted payload must differ from raw verbose payload")
    true))

(df test-wire-payload-keys-collision [] -> Bool
  :d "Tests that collision-prone payload keys are preserved without naive substring mutation."
  (let [(raw "(:msg :sender \"agent\" :payload \"ping\" :port 8080 :priority 1 :protocol \"tcp\" :state \"idle\" :role \"worker\")")
        (compacted (w/compact-wire-payload raw))
        (restored (w/expand-wire-payload compacted))]
    (assert (string-contains? compacted ":port 8080") "Compacted payload must preserve :port key")
    (assert (string-contains? compacted ":priority 1") "Compacted payload must preserve :priority key")
    (assert (string-contains? compacted ":protocol \"tcp\"") "Compacted payload must preserve :protocol key")
    (assert (string-contains? compacted ":state \"idle\"") "Compacted payload must preserve :state key")
    (assert (string-contains? compacted ":role \"worker\"") "Compacted payload must preserve :role key")
    (assert (not (string-contains? restored ":payloadort")) "Restored payload must not corrupt :port into :payloadort")
    (assert (not (string-contains? restored ":payloadriority")) "Restored payload must not corrupt :priority into :payloadriority")
    (assert (not (string-contains? restored ":payloadrotocol")) "Restored payload must not corrupt :protocol into :payloadrotocol")
    (assert (not (string-contains? restored ":statusate")) "Restored payload must not corrupt :state into :statusate")
    (assert (not (string-contains? restored ":roomeole")) "Restored payload must not corrupt :role into :roomeole")
    (assert (= raw restored) "Round-tripped payload with collision keys must match original exactly")
    true))

(df test-wire-encode-decode-envelope [] -> Bool
  :d "Tests serializing a wire frame into an envelope and parsing it back."
  (let [(msg "(:msg :sender \"node-a\" :target \"node-b\" :payload \"test-payload\")")
        (frame0 (w/create-wire-frame (w/codec-asn-text) msg false))
        (encoded (w/encode-wire-frame frame0))
        (decoded (w/decode-wire-frame encoded))]
    (assert (string-contains? encoded ":wire :v 1") "Encoded envelope must contain :wire :v 1 header")
    (assert (string-contains? encoded ":codec \"asn-text\"") "Encoded envelope must contain codec spec")
    (assert (not (w/is-compressed? decoded)) "Decoded frame must be uncompressed")
    (assert (= (w/unpack-wire-frame decoded) msg) "Unpacked envelope must match original message")
    true))

(df test-wire-unpack-direct-vs-decompressed [] -> Bool
  :d "Tests unpacking both raw and compressed frames."
  (let [(msg (str "(:msg :sender \"long-sender-identifier\""
                  " :target \"long-target-identifier\""
                  " :room \"long-room-identifier\""
                  " :status \"active-processing-queue\""
                  " :capabilities [\"capability-1\" \"capability-2\"]"
                  " :timestamp 1757160999"
                  " :payload \"(deep-analysis :target-ast 'large-monorepo-node-graph-entry-points-collection'))\""))]
    (let [(frame-raw (w/create-wire-frame (w/codec-asn-text) msg false))
          (frame-comp (w/create-wire-frame (w/codec-asb-binary) msg true))]
      (assert (= (w/unpack-wire-frame frame-raw) msg) "Raw unpacked frame must match original message")
      (assert (= (w/unpack-wire-frame frame-comp) msg) "Compressed unpacked frame must match original message")
      true)))

(df test-wire-internal-delimiters [] -> Bool
  :d "Tests that payload with internal quotes and closing parens is parsed without truncation."
  (let [(msg "(call :tool \"edit\" :args (list \"val)\" \"foo\"))")
        (frame (w/create-wire-frame (w/codec-asn-text) msg false))
        (encoded (w/encode-wire-frame frame))
        (decoded (w/decode-wire-frame encoded))]
    (assert (= (w/unpack-wire-frame decoded) msg) "Internal delimiters in payload must parse without truncation")
    (assert (not (w/is-compressed? decoded)) "Uncompressed frame with internal delimiters must not be marked compressed")
    (assert (not (= (w/unpack-wire-frame decoded) "(call :tool \"edit\" :args (list \"val)")) "Truncated payload at paren must not match")
    true))

(df run-wire-tests [] -> Bool
  :d "Runs all wire protocol unit tests."
  (and (test-wire-small-payload-uncompressed)
       (and (test-wire-large-payload-compressed)
            (and (test-wire-payload-roundtrip)
                 (and (test-wire-payload-keys-collision)
                      (and (test-wire-encode-decode-envelope)
                           (and (test-wire-unpack-direct-vs-decompressed)
                                (test-wire-internal-delimiters))))))))

