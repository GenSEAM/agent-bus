(module agent-bus/nd-asn
  :d "Newline-delimited ASN streaming serialization, framing, and M2M toolcall evaluation"
  :x [NDASNFrame
      nd-asn-frame
      nd-asn-serialize
      nd-asn-deserialize
      nd-asn-parse-lines
      nd-asn-make-toolcall
      nd-asn-eval-payload]
  :i [])

(dfs NDASNFrame
  (:f topic Str "Topic name or routing channel")
  (:f seq I64 "Monotonic sequence number")
  (:f ts I64 "Millisecond epoch timestamp")
  (:f payload Str "Serialized payload S-expression or text")
  (:f meta (Map Str Str) "Metadata key-value pairs"))

(dfs DelimDepth
  (:f depth I64 "Current unclosed delimiter count")
  (:f in-str Bool "Flag indicating if inside string literal")
  (:f esc Bool "Flag indicating escape backslash"))

(dfs LineAcc
  (:f items (List Str) "Completed parsed line items")
  (:f cur Str "Current multi-line buffer")
  (:f depth I64 "Active delimiter depth"))

(df nd-asn-frame [(topic Str) (seq I64) (ts I64) (payload Str) (meta (Map Str Str))] -> NDASNFrame
  :d "Constructs an NDASNFrame record packaging topic seq payload and timestamp"
  (NDASNFrame
    :topic topic
    :seq seq
    :ts ts
    :payload payload
    :meta meta))

(df escape-nd-asn-str [(s Str)] -> Str
  :d "Escapes backslashes, double quotes, and newlines for wire transmission"
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))
        (s3 (string-replace s2 "\n" "\\n"))
        (s4 (string-replace s3 "\r" "\\r"))]
    (string-replace s4 "\t" "\\t")))

(df unescape-nd-asn-str [(s Str)] -> Str
  :d "Inverts string escaping for wire frame payloads"
  (let [(s1 (string-replace s "\\n" "\n"))
        (s2 (string-replace s1 "\\r" "\r"))
        (s3 (string-replace s2 "\\t" "\t"))
        (s4 (string-replace s3 "\\\"" "\""))]
    (string-replace s4 "\\\\" "\\")))

(df format-meta [(m (Map Str Str))] -> Str
  :d "Formats a metadata map into ASN key-value pairs"
  (let [(keys (map-keys m))]
    (if (list-empty? keys)
        "[]"
        (let [(entries (map (fn [(k Str)] -> Str
                              (let [(v-opt (map-get m k))]
                                (let [(v (mt v-opt ((some val) val) (_ "")))]
                                  (str "(\"" (escape-nd-asn-str k) "\" \"" (escape-nd-asn-str v) "\")"))))
                            keys))]
          (str "[" (string-join entries " ") "]")))))

(df parse-meta-loop [(s Str) (acc (Map Str Str))] -> (Map Str Str)
  :d "Recursively extracts key-value string pairs from metadata representation"
  (let [(pair-idx (string-index-of s "(\""))]
    (mt pair-idx
      ((none) acc)
      ((some p-start)
       (let [(after-p (option-or (string-slice s (+ p-start 2) (string-length s)) ""))
             (k-end (string-index-of after-p "\""))]
         (mt k-end
           ((none) acc)
           ((some ke)
            (let [(key (option-or (string-slice after-p 0 ke) ""))
                  (after-k (option-or (string-slice after-p (+ ke 1) (string-length after-p)) ""))
                  (v-start (string-index-of after-k "\""))]
              (mt v-start
                ((none) acc)
                ((some vs)
                 (let [(after-v (option-or (string-slice after-k (+ vs 1) (string-length after-k)) ""))
                       (v-end (string-index-of after-v "\""))]
                   (mt v-end
                     ((none) acc)
                     ((some ve)
                      (let [(val (option-or (string-slice after-v 0 ve) ""))
                            (rest (option-or (string-slice after-v (+ ve 1) (string-length after-v)) ""))
                            (next-acc (map-set acc key val))]
                        (parse-meta-loop rest next-acc)))))))))))))))

(df parse-meta-pairs [(raw Str)] -> (Map Str Str)
  :d "Parses serialized metadata key-value pairs into a Map"
  (let [(trimmed (string-trim raw))]
    (if (or (string-empty? trimmed) (= trimmed "[]"))
        (map-empty)
        (parse-meta-loop trimmed (map-empty)))))

(df compute-delim-depth [(s Str) (initial-depth I64)] -> I64
  :d "Computes updated delimiter depth tracking string escapes"
  (let [(chars (string-chars s))
        (init (DelimDepth :depth initial-depth :in-str false :esc false))]
    (let [(final-st
           (fold (fn [(st DelimDepth) (c Str)] -> DelimDepth
                   (if (.-in-str st)
                       (if (.-esc st)
                           (DelimDepth :depth (.-depth st) :in-str true :esc false)
                           (if (= c "\\")
                               (DelimDepth :depth (.-depth st) :in-str true :esc true)
                               (if (= c "\"")
                                   (DelimDepth :depth (.-depth st) :in-str false :esc false)
                                   (DelimDepth :depth (.-depth st) :in-str true :esc false))))
                       (if (= c "\"")
                           (DelimDepth :depth (.-depth st) :in-str true :esc false)
                           (if (= c "(")
                               (DelimDepth :depth (+ (.-depth st) 1) :in-str false :esc false)
                               (if (= c ")")
                                   (DelimDepth :depth (- (.-depth st) 1) :in-str false :esc false)
                                   (DelimDepth :depth (.-depth st) :in-str false :esc false))))))
                 init
                 chars))]
      (.-depth final-st))))

(df nd-asn-parse-lines [(raw Str)] -> (List Str)
  :d "Splits raw string buffer on newline boundaries while preserving balanced expressions"
  (let [(normalized (string-replace raw "\r" ""))
        (raw-lines (string-split normalized "\n"))
        (init (LineAcc :items (list) :cur "" :depth 0))]
    (let [(final-acc
           (fold (fn [(acc LineAcc) (raw-ln Str)] -> LineAcc
                   (let [(trimmed (string-trim raw-ln))]
                     (if (string-empty? trimmed)
                         acc
                         (if (string-empty? (.-cur acc))
                             (let [(d (compute-delim-depth trimmed 0))]
                               (if (<= d 0)
                                   (LineAcc :items (list-append (.-items acc) (list trimmed)) :cur "" :depth 0)
                                   (LineAcc :items (.-items acc) :cur trimmed :depth d)))
                             (let [(merged (str (.-cur acc) " " trimmed))
                                   (d (compute-delim-depth trimmed (.-depth acc)))]
                               (if (<= d 0)
                                   (LineAcc :items (list-append (.-items acc) (list merged)) :cur "" :depth 0)
                                   (LineAcc :items (.-items acc) :cur merged :depth d)))))))
                 init
                 raw-lines))]
      (if (string-empty? (.-cur final-acc))
          (.-items final-acc)
          (list-append (.-items final-acc) (list (.-cur final-acc)))))))

(df nd-asn-serialize-single [(frame NDASNFrame)] -> Str
  :d "Serializes a single NDASNFrame into a one-line S-expression"
  (let [(top (.-topic frame))
        (seq-str (string-from-int64 (.-seq frame)))
        (ts-str (string-from-int64 (.-ts frame)))
        (esc-payload (escape-nd-asn-str (.-payload frame)))
        (meta-str (format-meta (.-meta frame)))]
    (str "(:frame :topic \"" top "\" :seq " seq-str " :ts " ts-str " :payload \"" esc-payload "\" :meta " meta-str ")")))

(df nd-asn-serialize [(frames (List NDASNFrame))] -> Str
  :d "Serializes ASL records or S-expressions into newline-delimited ASN frames"
  (if (list-empty? frames)
      ""
      (string-join (map (fn [(f NDASNFrame)] -> Str (nd-asn-serialize-single f)) frames) "\n")))

(df nd-asn-deserialize-single [(line Str)] -> (Result NDASNFrame Str)
  :d "Deserializes a single frame line into a Result containing NDASNFrame or error message"
  (let [(t (string-trim line))]
    (if (not (and (or (string-starts-with? t "(:frame ") (string-starts-with? t "(:nd-asn "))
                  (string-ends-with? t ")")))
        (err (str "malformed-frame: invalid framing delimiters: " t))
        (let [(top-idx (string-index-of t ":topic \""))
              (seq-idx (string-index-of t ":seq "))
              (ts-idx (string-index-of t ":ts "))
              (pay-idx (string-index-of t ":payload \""))
              (meta-idx (string-index-of t ":meta "))]
          (if (or (is-none? top-idx)
                  (or (is-none? seq-idx)
                      (or (is-none? ts-idx)
                          (or (is-none? pay-idx) (is-none? meta-idx)))))
              (err (str "malformed-frame: missing required field markers: " t))
              (let [(ti (option-or top-idx 0))
                    (si (option-or seq-idx 0))
                    (tsi (option-or ts-idx 0))
                    (pi (option-or pay-idx 0))
                    (mi (option-or meta-idx 0))]
                (let [(top-sub (option-or (string-slice t (+ ti 8) (string-length t)) ""))
                      (top-end (string-index-of top-sub "\""))]
                  (mt top-end
                    ((none) (err "malformed-frame: unclosed topic quote"))
                    ((some te)
                     (let [(topic (option-or (string-slice top-sub 0 te) ""))
                           (seq-sub (option-or (string-slice t (+ si 5) (string-length t)) ""))
                           (seq-end (string-index-of seq-sub " "))]
                       (mt seq-end
                         ((none) (err "malformed-frame: missing space after seq"))
                         ((some se)
                          (let [(seq-opt (string-to-int64 (option-or (string-slice seq-sub 0 se) "")))]
                            (mt seq-opt
                              ((none) (err "malformed-frame: invalid seq integer"))
                              ((some seq)
                               (let [(ts-sub (option-or (string-slice t (+ tsi 4) (string-length t)) ""))
                                     (ts-end (string-index-of ts-sub " "))]
                                 (mt ts-end
                                   ((none) (err "malformed-frame: missing space after ts"))
                                   ((some tse)
                                    (let [(ts-opt (string-to-int64 (option-or (string-slice ts-sub 0 tse) "")))]
                                      (mt ts-opt
                                        ((none) (err "malformed-frame: invalid ts integer"))
                                        ((some ts)
                                         (let [(pay-start (+ pi 10))
                                               (pay-end-idx (string-index-of t "\" :meta "))]
                                           (mt pay-end-idx
                                             ((none) (err "malformed-frame: payload delimiter mismatch"))
                                             ((some pei)
                                              (let [(esc-payload (option-or (string-slice t pay-start pei) ""))
                                                    (payload (unescape-nd-asn-str esc-payload))
                                                    (meta-start (+ mi 6))
                                                    (meta-end (- (string-length t) 1))
                                                    (meta-raw (option-or (string-slice t meta-start meta-end) "[]"))
                                                    (meta (parse-meta-pairs meta-raw))]
                                                (ok (NDASNFrame
                                                      :topic topic
                                                      :seq seq
                                                      :ts ts
                                                      :payload payload
                                                      :meta meta)))))))))))))))))))))))))))

(df nd-asn-deserialize [(raw Str)] -> (List (Result NDASNFrame Str))
  :d "Parses newline-delimited ASN stream into individual parsed ASL expressions or frames"
  (let [(lines (nd-asn-parse-lines raw))]
    (map (fn [(line Str)] -> (Result NDASNFrame Str) (nd-asn-deserialize-single line)) lines)))

(df nd-asn-make-toolcall [(tool Str) (col Str) (q Str) (limit I64)] -> NDASNFrame
  :d "Constructs an M2M tool call evaluation frame without JSON encoding overhead"
  (let [(payload (str "(call! " tool " :col " col " :q " q " :limit " (string-from-int64 limit) ")"))]
    (NDASNFrame
      :topic "toolcall"
      :seq 1
      :ts 0
      :payload payload
      :meta (map-empty))))

(df nd-asn-eval-payload [(frame NDASNFrame)] -> (Result Str Str)
  :d "Extracts and evaluates inline code or tool payload passed across the memory bus"
  (let [(p (string-trim (.-payload frame)))]
    (cond
      ((string-empty? p)
       (err "empty-payload"))
      ((not (and (string-starts-with? p "(") (string-ends-with? p ")")))
       (err (str "invalid-syntax: " p)))
      ((string-starts-with? p "(call! ")
       (let [(inner (option-or (string-slice p 7 (- (string-length p) 1)) ""))
             (sp (string-index-of inner " "))
             (tool (mt sp ((some idx) (option-or (string-slice inner 0 idx) inner)) ((none) inner)))]
         (if (string-empty? tool)
             (err "missing-tool-identifier")
             (ok (str "dispatched:" tool)))))
      ((string-starts-with? p "(load! ")
       (let [(inner (option-or (string-slice p 7 (- (string-length p) 1)) ""))
             (chunk (string-trim inner))]
         (if (string-empty? chunk)
             (err "missing-chunk-identifier")
             (ok (str "loaded:" chunk)))))
      ((string-starts-with? p "(echo ")
       (let [(inner (option-or (string-slice p 6 (- (string-length p) 1)) ""))]
         (ok (string-trim inner))))
      (:else
       (ok (str "eval:" p))))))
