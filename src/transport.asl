(module asl-bus/transport
  :d "Pure AgentScript Bus Transport Specification for socket wire framing, duplex sessions, and RPC message envelopes."
  :x [TransportFrameType TransportState TransportEnvelope TransportSession
      make-transport-envelope init-transport-session session-record-sent
      session-record-received session-set-state is-session-active?
      format-frame-header validate-transport-envelope]
  :i [])

(dfe TransportFrameType
  (:c frame-handshake [] "Connection handshake and protocol negotiation frame")
  (:c frame-heartbeat [] "Periodic liveness ping or pong frame")
  (:c frame-rpc-req [] "Synchronous or batch RPC request frame")
  (:c frame-rpc-res [] "RPC outcome or failure response frame")
  (:c frame-stream-chunk [] "Chunked streaming payload frame")
  (:c frame-close [] "Graceful transport termination frame"))

(dfe TransportState
  (:c transport-idle [] "Transport initialized but connection not established")
  (:c transport-connecting [] "Transport handshake in flight")
  (:c transport-connected [] "Transport active and streaming frames")
  (:c transport-closing [] "Transport draining pending frames prior to termination")
  (:c transport-closed [] "Transport fully terminated"))

(dfs TransportEnvelope
  (:f id Str "Unique frame identifier")
  (:f frame-type TransportFrameType "Wire protocol frame discriminator")
  (:f sender Str "Originating agent or node address")
  (:f target Str "Destination agent, node, or broadcast channel")
  (:f seq I64 "Monotonically increasing sequence number")
  (:f payload Str "Serialized message payload")
  (:f timestamp I64 "Epoch timestamp in milliseconds"))

(dfs TransportSession
  (:f session-id Str "Unique duplex transport session identifier")
  (:f state TransportState "Current connection lifecycle state")
  (:f remote-node Str "Remote peer node address")
  (:f last-seq I64 "Highest sequence number processed")
  (:f frames-sent I64 "Total frames transmitted across session")
  (:f frames-received I64 "Total frames received across session"))

(df make-transport-envelope [(id Str) (frame-type TransportFrameType) (sender Str) (target Str) (seq I64) (payload Str) (timestamp I64)] -> TransportEnvelope
  :d "Constructs a validated transport envelope for wire transmission."
  (TransportEnvelope
    :id id
    :frame-type frame-type
    :sender sender
    :target target
    :seq seq
    :payload payload
    :timestamp timestamp))

(df init-transport-session [(session-id Str) (remote-node Str)] -> TransportSession
  :d "Initializes an idle transport session bound to a remote peer."
  (TransportSession
    :session-id session-id
    :state (transport-idle)
    :remote-node remote-node
    :last-seq 0
    :frames-sent 0
    :frames-received 0))

(df session-record-sent [(session TransportSession) (seq I64)] -> TransportSession
  :d "Records transmission of a frame and updates sequence and counter metrics."
  (TransportSession
    :session-id (.-session-id session)
    :state (.-state session)
    :remote-node (.-remote-node session)
    :last-seq seq
    :frames-sent (+ (.-frames-sent session) 1)
    :frames-received (.-frames-received session)))

(df session-record-received [(session TransportSession) (seq I64)] -> TransportSession
  :d "Records receipt of an inbound frame and updates metrics."
  (TransportSession
    :session-id (.-session-id session)
    :state (.-state session)
    :remote-node (.-remote-node session)
    :last-seq seq
    :frames-sent (.-frames-sent session)
    :frames-received (+ (.-frames-received session) 1)))

(df session-set-state [(session TransportSession) (new-state TransportState)] -> TransportSession
  :d "Transitions the transport session into a new connection lifecycle state."
  (TransportSession
    :session-id (.-session-id session)
    :state new-state
    :remote-node (.-remote-node session)
    :last-seq (.-last-seq session)
    :frames-sent (.-frames-sent session)
    :frames-received (.-frames-received session)))

(df is-session-active? [(session TransportSession)] -> Bool
  :d "Returns true if the session state is currently connected."
  (mt (.-state session)
    ((transport-connected) true)
    ((transport-idle) false)
    ((transport-connecting) false)
    ((transport-closing) false)
    ((transport-closed) false)))

(df format-frame-header [(env TransportEnvelope)] -> Str
  :d "Formats transport envelope metadata into a compact wire transmission header line."
  (str "FRAME:" (.-id env) ":" (string-from-int64 (.-seq env)) ":" (.-sender env) "->" (.-target env)))

(df validate-transport-envelope [(env TransportEnvelope)] -> Bool
  :d "Validates transport envelope invariants: non-empty identifiers and non-negative sequence."
  (and (not (string-empty? (.-id env)))
       (and (not (string-empty? (.-sender env)))
            (and (not (string-empty? (.-target env)))
                 (>= (.-seq env) 0)))))
