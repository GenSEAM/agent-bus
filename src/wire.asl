(module asl-bus/wire
  :d "AgentScript Binary (ASB) Wire Protocol and Adaptive Compression Framing for High-Frequency Swarm Inter-Agent Bus."
  :x [CodecKind
      CompressionAlgo
      WireFrame
      create-wire-frame
      compact-wire-payload
      expand-wire-payload
      encode-wire-frame
      decode-wire-frame
      unpack-wire-frame
      is-compressed?]
  :i [])

(dfe CodecKind
  (:c codec-asn-text [] "Plain UTF-8 ASN S-expression text codec")
  (:c codec-asb-binary [] "Binary token-indexed ASB bytecode codec"))

(dfe CompressionAlgo
  (:c algo-none [] "No compression applied (raw payload)")
  (:c algo-zstd-dict [] "Dictionary-trained grammar compaction")
  (:c algo-rle [] "Byte-level run-length repetition encoding"))

(dfs WireFrame
  (:f version I64 "Wire protocol specification version e.g. 1")
  (:f codec CodecKind "Serialization codec kind")
  (:f compressed Bool "True if payload must be decompressed before decoding")
  (:f algorithm CompressionAlgo "Applied compression algorithm")
  (:f uncompressed-bytes I64 "Pre-allocation buffer length for receiver")
  (:f payload Str "Wire transmission payload"))

(df is-compressed? [(frame WireFrame)] -> Bool
  :d "Returns true if the wire frame is compressed."
  (.-compressed frame))

(df compact-wire-payload [(raw Str)] -> Str
  :d "Applies dictionary-trained token compaction replacing verbose S-expression heads with compact markers."
  (let [(s1 (string-replace raw ":sender" ":s"))
        (s2 (string-replace s1 ":target" ":t"))
        (s3 (string-replace s2 ":payload" ":p"))
        (s4 (string-replace s3 ":timestamp" ":ts"))
        (s5 (string-replace s4 ":room" ":r"))
        (s6 (string-replace s5 ":status" ":st"))
        (s7 (string-replace s6 ":capabilities" ":caps"))]
    s7))

(df expand-wire-payload [(compacted Str)] -> Str
  :d "Inverts dictionary compaction, restoring canonical ASN S-expression heads."
  (let [(s1 (string-replace compacted ":caps" ":capabilities"))
        (s2 (string-replace s1 ":st" ":status"))
        (s3 (string-replace s2 ":r" ":room"))
        (s4 (string-replace s3 ":ts" ":timestamp"))
        (s5 (string-replace s4 ":p" ":payload"))
        (s6 (string-replace s5 ":t" ":target"))
        (s7 (string-replace s6 ":s" ":sender"))]
    s7))

(df create-wire-frame [(codec CodecKind) (payload Str) (enable-compress Bool)] -> WireFrame
  :d "Constructs an adaptive wire frame. Payloads < 128 bytes are sent uncompressed; larger payloads are compacted."
  (let [(raw-len (string-length payload))
        (should-compress (and enable-compress (>= raw-len 128)))]
    (if should-compress
        (let [(compacted (compact-wire-payload payload))]
          (WireFrame
            :version 1
            :codec codec
            :compressed true
            :algorithm (algo-zstd-dict)
            :uncompressed-bytes raw-len
            :payload compacted))
        (WireFrame
          :version 1
          :codec codec
          :compressed false
          :algorithm (algo-none)
          :uncompressed-bytes raw-len
          :payload payload))))

(df encode-wire-frame [(frame WireFrame)] -> Str
  :d "Encodes a WireFrame into a serialized wire transmission envelope."
  (let [(c-tag (mt (.-codec frame)
                 ((codec-asn-text) "asn-text")
                 ((codec-asb-binary) "asb-binary")))
        (comp-tag (if (.-compressed frame) "true" "false"))
        (algo-tag (mt (.-algorithm frame)
                    ((algo-none) "none")
                    ((algo-zstd-dict) "zstd-dict")
                    ((algo-rle) "rle")))]
    (str "(:wire :v " (show (.-version frame))
         " :codec \"" c-tag "\""
         " :compressed " comp-tag
         " :algo \"" algo-tag "\""
         " :orig-len " (show (.-uncompressed-bytes frame))
         " :data \"" (.-payload frame) "\")")))

(df decode-wire-frame [(raw Str)] -> WireFrame
  :d "Parses a serialized wire envelope string into a WireFrame structure."
  (let [(trimmed (string-trim raw))
        (is-comp (string-contains? trimmed ":compressed true"))
        (is-binary (string-contains? trimmed ":codec \"asb-binary\""))
        (is-rle (string-contains? trimmed ":algo \"rle\""))
        (is-zstd (string-contains? trimmed ":algo \"zstd-dict\""))
        ;; Extract :data payload
        (data-idx (string-index-of trimmed ":data \""))]
    (let [(payload (mt data-idx
                     ((none) trimmed)
                     ((some d)
                      (let [(after (option-or (string-slice trimmed (+ d 7) (string-length trimmed)) ""))
                            (end-idx (string-index-of after "\")"))]
                        (mt end-idx
                          ((none) after)
                          ((some e) (option-or (string-slice after 0 e) after)))))))]
      (WireFrame
        :version 1
        :codec (if is-binary (codec-asb-binary) (codec-asn-text))
        :compressed is-comp
        :algorithm (if is-zstd (algo-zstd-dict) (if is-rle (algo-rle) (algo-none)))
        :uncompressed-bytes (string-length payload)
        :payload payload))))

(df unpack-wire-frame [(frame WireFrame)] -> Str
  :d "Unpacks wire payload: if compressed, decompresses/expands first; otherwise decodes directly."
  (if (.-compressed frame)
      (expand-wire-payload (.-payload frame))
      (.-payload frame)))
