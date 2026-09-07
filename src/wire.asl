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

(dfs WireScanState
  (:f out Str "Accumulated output buffer")
  (:f cur Str "Current token buffer")
  (:f in-str Bool "True if currently inside double quotes")
  (:f esc Bool "True if escape backslash active"))

(df compact-token [(token Str)] -> Str
  :d "Maps verbose ASN keyword token to compact shorthand marker."
  (cond
    ((= token ":sender") ":s")
    ((= token ":target") ":t")
    ((= token ":payload") ":p")
    ((= token ":timestamp") ":ts")
    ((= token ":room") ":r")
    ((= token ":status") ":st")
    ((= token ":capabilities") ":caps")
    (:else token)))

(df expand-token [(token Str)] -> Str
  :d "Maps compact shorthand marker to canonical verbose ASN keyword token."
  (cond
    ((= token ":s") ":sender")
    ((= token ":t") ":target")
    ((= token ":p") ":payload")
    ((= token ":ts") ":timestamp")
    ((= token ":r") ":room")
    ((= token ":st") ":status")
    ((= token ":caps") ":capabilities")
    (:else token)))

(df is-delim-char? [(c Str)] -> Bool
  :d "Returns true if character is a delimiter or whitespace separating ASN tokens."
  (or (= c " ")
      (or (= c "\t")
          (or (= c "\n")
              (or (= c "\r")
                  (or (= c "(")
                      (or (= c ")")
                          (or (= c "[")
                              (= c "]")))))))))

(df transform-wire-payload [(raw Str) (mode-compact Bool)] -> Str
  :d "Walks payload characters applying lexical token replacement outside string literals."
  (let [(init (WireScanState :out "" :cur "" :in-str false :esc false))
        (chars (string-chars raw))]
    (let [(final-state
           (fold (fn [(st WireScanState) (c Str)] -> WireScanState
                   (if (.-in-str st)
                       (if (.-esc st)
                           (WireScanState :out (str (.-out st) c) :cur "" :in-str true :esc false)
                           (if (= c "\\")
                               (WireScanState :out (str (.-out st) c) :cur "" :in-str true :esc true)
                               (if (= c "\"")
                                   (WireScanState :out (str (.-out st) c) :cur "" :in-str false :esc false)
                                   (WireScanState :out (str (.-out st) c) :cur "" :in-str true :esc false))))
                       (if (= c "\"")
                           (let [(tok (if mode-compact (compact-token (.-cur st)) (expand-token (.-cur st))))]
                             (WireScanState :out (str (.-out st) tok c) :cur "" :in-str true :esc false))
                           (if (is-delim-char? c)
                               (let [(tok (if mode-compact (compact-token (.-cur st)) (expand-token (.-cur st))))]
                                 (WireScanState :out (str (.-out st) tok c) :cur "" :in-str false :esc false))
                               (WireScanState :out (.-out st) :cur (str (.-cur st) c) :in-str false :esc false)))))
                 init
                 chars))]
      (let [(final-tok (if mode-compact (compact-token (.-cur final-state)) (expand-token (.-cur final-state))))]
        (str (.-out final-state) final-tok)))))

(df compact-wire-payload [(raw Str)] -> Str
  :d "Applies dictionary-trained token compaction replacing verbose S-expression heads with compact markers."
  (transform-wire-payload raw true))

(df expand-wire-payload [(compacted Str)] -> Str
  :d "Inverts dictionary compaction, restoring canonical ASN S-expression heads."
  (transform-wire-payload compacted false))

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

(df extract-envelope-orig-len [(header Str)] -> (Option I64)
  :d "Extracts the :orig-len integer from the wire envelope header."
  (let [(idx (string-index-of header ":orig-len "))]
    (mt idx
      ((none) (none))
      ((some i)
       (let [(sub (option-or (string-slice header (+ i 10) (string-length header)) ""))
             (sp-idx (string-index-of sub " "))]
         (let [(num-str (mt sp-idx
                          ((none) (string-trim sub))
                          ((some sp) (option-or (string-slice sub 0 sp) sub))))]
           (string-to-int64 (string-trim num-str))))))))

(df decode-wire-frame [(raw Str)] -> WireFrame
  :d "Parses a serialized wire envelope string into a WireFrame structure."
  (let [(trimmed (string-trim raw))
        (data-idx (string-index-of trimmed ":data \""))]
    (mt data-idx
      ((none)
       (WireFrame
         :version 1
         :codec (codec-asn-text)
         :compressed false
         :algorithm (algo-none)
         :uncompressed-bytes (string-length trimmed)
         :payload trimmed))
      ((some d)
       (let [(header (option-or (string-slice trimmed 0 d) ""))
             (after (option-or (string-slice trimmed (+ d 7) (string-length trimmed)) ""))]
         (let [(payload (if (string-ends-with? after "\")")
                            (option-or (string-slice after 0 (- (string-length after) 2)) after)
                            after))
               (is-comp (string-contains? header ":compressed true"))
               (is-binary (string-contains? header ":codec \"asb-binary\""))
               (is-rle (string-contains? header ":algo \"rle\""))
               (is-zstd (string-contains? header ":algo \"zstd-dict\""))
               (orig-len-opt (extract-envelope-orig-len header))]
           (let [(orig-len (option-or orig-len-opt (string-length payload)))]
             (WireFrame
               :version 1
               :codec (if is-binary (codec-asb-binary) (codec-asn-text))
               :compressed is-comp
               :algorithm (if is-zstd (algo-zstd-dict) (if is-rle (algo-rle) (algo-none)))
               :uncompressed-bytes orig-len
               :payload payload))))))))

(df unpack-wire-frame [(frame WireFrame)] -> Str
  :d "Unpacks wire payload: if compressed, decompresses/expands first; otherwise decodes directly."
  (if (.-compressed frame)
      (expand-wire-payload (.-payload frame))
      (.-payload frame)))
