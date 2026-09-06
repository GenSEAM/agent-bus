(module asl-bus/wire-test
  :d "Unit verification test suite for ASB Wire Protocol and Compression Framing."
  :x [test-wire-small-payload-uncompressed
      test-wire-large-payload-compressed
      test-wire-payload-roundtrip
      test-wire-encode-decode-envelope
      test-wire-unpack-direct-vs-decompressed
      run-wire-tests]
  :i [(wire :a w)])

(df test-wire-small-payload-uncompressed [] -> Bool
  :d "Tests that messages under 128 bytes bypass compression."
  (let [(msg "(:msg :sender \"agent-1\" :target \"agent-2\" :payload \"ping\")")
        (frame (w/create-wire-frame (w/codec-asn-text) msg true))]
    (and (not (w/is-compressed? frame))
         (= (w/unpack-wire-frame frame) msg)
         (= (.-uncompressed-bytes frame) (string-length msg)))))

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
      (and (w/is-compressed? frame)
           (> (string-length msg) 128)
           (< (string-length (.-payload frame)) (string-length msg))))))

(df test-wire-payload-roundtrip [] -> Bool
  :d "Tests that dictionary compaction and expansion round-trips with zero data loss."
  (let [(raw "(:msg :sender \"a1\" :target \"a2\" :room \"main\" :status \"busy\" :capabilities [\"x\"] :timestamp 100 :payload \"hello\")")
        (compacted (w/compact-wire-payload raw))
        (restored (w/expand-wire-payload compacted))]
    (and (= raw restored)
         (not (= raw compacted)))))

(df test-wire-encode-decode-envelope [] -> Bool
  :d "Tests serializing a wire frame into an envelope and parsing it back."
  (let [(msg "(:msg :sender \"node-a\" :target \"node-b\" :payload \"test-payload\")")
        (frame0 (w/create-wire-frame (w/codec-asn-text) msg false))
        (encoded (w/encode-wire-frame frame0))
        (decoded (w/decode-wire-frame encoded))]
    (and (string-contains? encoded ":wire :v 1")
         (string-contains? encoded ":codec \"asn-text\"")
         (not (w/is-compressed? decoded))
         (= (w/unpack-wire-frame decoded) msg))))

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
      (and (= (w/unpack-wire-frame frame-raw) msg)
           (= (w/unpack-wire-frame frame-comp) msg)))))

(df run-wire-tests [] -> Bool
  :d "Runs all wire protocol unit tests."
  (and (test-wire-small-payload-uncompressed)
       (test-wire-large-payload-compressed)
       (test-wire-payload-roundtrip)
       (test-wire-encode-decode-envelope)
       (test-wire-unpack-direct-vs-decompressed)))
