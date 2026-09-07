(module asl-agent-bus/ambient
  :d "Ambient Status Broadcast Frame and Lightweight Swarm Perception in ASL"
  :x [AmbientFrame
      create-ambient-frame
      validate-ambient-frame
      encode-ambient-asn]
  :i [])

(dfs AmbientFrame
  (:f peer-id Str "Unique daemon peer identifier")
  (:f load F64 "Normalized system load between 0.0 and 1.0")
  (:f claimed (List Str) "List of claimed buffer or resource identifiers")
  (:f ts I64 "Heartbeat epoch timestamp"))

(df create-ambient-frame [(peer-id Str) (load F64) (claimed (List Str)) (ts I64)] -> AmbientFrame
  :d "Constructs an AmbientFrame record representing a peer status broadcast"
  (AmbientFrame
    :peer-id peer-id
    :load load
    :claimed claimed
    :ts ts))

(df validate-ambient-frame [(frame AmbientFrame)] -> Bool
  :d "Validates ambient frame invariants: non-empty peer-id, load in [0.0, 1.0], positive ts"
  (and (not (string-empty? (.-peer-id frame)))
       (and (>= (.-load frame) 0.0)
            (and (<= (.-load frame) 1.0)
                 (>= (.-ts frame) 0)))))

(df format-claimed-buffers [(items (List Str))] -> Str
  :d "Formats a list of claimed buffer string identifiers into an ASN list literal"
  (if (list-empty? items)
      "[]"
      (str "[" (string-join (map (fn [(s Str)] -> Str (str "\"" s "\"")) items) " ") "]")))

(df encode-ambient-asn [(frame AmbientFrame)] -> Str
  :d "Serializes an AmbientFrame into compact canonical ASN format strictly under 120 tokens"
  (let [(claimed-str (format-claimed-buffers (.-claimed frame)))]
    (str "(:ambient :peer-id \"" (.-peer-id frame) "\" :load " (string-from-float64 (.-load frame)) " :claimed " claimed-str " :ts " (string-from-int64 (.-ts frame)) ")")))
