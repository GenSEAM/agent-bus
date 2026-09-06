(module asl-bus/presence
  :d "Swarm Room Presence, Discovery, and Task Negotiation Protocol for Autonomous Inter-Agent Collaboration."
  :x [AgentStatus
      SwarmPeer
      SwarmRoom
      NegotiationKind
      NegotiationOffer
      create-swarm-room
      join-swarm-room
      leave-swarm-room
      list-room-peers
      find-peer-in-room
      propose-task
      accept-task
      decline-task
      format-presence-roster]
  :i [])

(dfe AgentStatus
  (:c status-idle [] "Agent is online and ready for task assignment")
  (:c status-busy [] "Agent is actively processing a task queue")
  (:c status-listening [] "Agent is registered in passive listener/observer mode")
  (:c status-offline [] "Agent heartbeat has expired or node disconnected"))

(dfs SwarmPeer
  (:f agent-id Str "Unique peer identifier e.g. claude-code-worker-1")
  (:f role Str "Specialized role e.g. planner, coder, reviewer")
  (:f room Str "Target room name e.g. refactor-matrix")
  (:f status AgentStatus "Current execution status")
  (:f capabilities (List Str) "List of advertised capability tokens")
  (:f last-ping-epoch I64 "Last registered heartbeat epoch"))

(dfs SwarmRoom
  (:f room-name Str "Unique room name")
  (:f topic Str "Human-readable mission or channel topic")
  (:f peers (List SwarmPeer) "Active registered peers in the room"))

(dfe NegotiationKind
  (:c kind-propose [] "Task assignment proposal from coordinator")
  (:c kind-accept [] "Task acceptance confirmation with ETA")
  (:c kind-decline [] "Task rejection with diagnostic reason")
  (:c kind-complete [] "Task completion receipt with result"))

(dfs NegotiationOffer
  (:f bid-id Str "Unique negotiation offer identifier")
  (:f task-name Str "Target task or action identifier")
  (:f from-agent Str "Sender agent identifier")
  (:f to-agent Str "Target recipient agent identifier")
  (:f kind NegotiationKind "Negotiation state transition")
  (:f eta-seconds I64 "Estimated completion time in seconds")
  (:f reason Str "Rejection explanation or status description"))

(df create-swarm-room [(name Str) (topic Str)] -> SwarmRoom
  :d "Initializes an empty swarm coordination room."
  (SwarmRoom
    :room-name name
    :topic topic
    :peers (list)))

(df join-swarm-room [(room SwarmRoom) (peer SwarmPeer)] -> SwarmRoom
  :d "Registers or updates a peer in the room."
  (let [(filtered (filter (fn [(p SwarmPeer)] -> Bool
                            (not (= (.-agent-id p) (.-agent-id peer))))
                          (.-peers room)))]
    (SwarmRoom
      :room-name (.-room-name room)
      :topic (.-topic room)
      :peers (list-append filtered (list peer)))))

(df leave-swarm-room [(room SwarmRoom) (agent-id Str)] -> SwarmRoom
  :d "Removes an agent from the room."
  (let [(filtered (filter (fn [(p SwarmPeer)] -> Bool
                            (not (= (.-agent-id p) agent-id)))
                          (.-peers room)))]
    (SwarmRoom
      :room-name (.-room-name room)
      :topic (.-topic room)
      :peers filtered)))

(df list-room-peers [(room SwarmRoom)] -> (List SwarmPeer)
  :d "Returns list of all peers registered in the room."
  (.-peers room))

(df find-peer-in-room [(room SwarmRoom) (agent-id Str)] -> (Option SwarmPeer)
  :d "Finds peer by agent identifier."
  (let [(matches (filter (fn [(p SwarmPeer)] -> Bool
                           (= (.-agent-id p) agent-id))
                         (.-peers room)))]
    (if (list-empty? matches)
        (none)
        (some (first matches)))))

(df propose-task [(from-id Str) (to-id Str) (task-name Str) (bid-id Str)] -> NegotiationOffer
  :d "Creates a task assignment proposal."
  (NegotiationOffer
    :bid-id bid-id
    :task-name task-name
    :from-agent from-id
    :to-agent to-id
    :kind (kind-propose)
    :eta-seconds 0
    :reason "Task proposal pending review"))

(df accept-task [(bid-id Str) (from-id Str) (to-id Str) (eta I64)] -> NegotiationOffer
  :d "Accepts a task proposal with estimated completion seconds."
  (NegotiationOffer
    :bid-id bid-id
    :task-name ""
    :from-agent from-id
    :to-agent to-id
    :kind (kind-accept)
    :eta-seconds eta
    :reason "Task accepted into active execution queue"))

(df decline-task [(bid-id Str) (from-id Str) (to-id Str) (reason Str)] -> NegotiationOffer
  :d "Declines a task proposal with diagnostic reason."
  (NegotiationOffer
    :bid-id bid-id
    :task-name ""
    :from-agent from-id
    :to-agent to-id
    :kind (kind-decline)
    :eta-seconds 0
    :reason reason))

(df format-presence-roster [(room SwarmRoom)] -> Str
  :d "Renders human-readable presence roster of room peers."
  (let [(hdr (str "### Swarm Room: " (.-room-name room) " (" (.-topic room) ")\n"
                  "| Agent ID | Role | Status | Capabilities |\n"
                  "|---|---|---|---|\n"))]
    (foldl (fn [(acc Str) (p SwarmPeer)] -> Str
             (let [(st-str (mt (.-status p)
                             ((status-idle) "idle")
                             ((status-busy) "busy")
                             ((status-listening) "listening")
                             ((status-offline) "offline")))
                   (caps-str (string-join (.-capabilities p) ", "))]
               (str acc "| `" (.-agent-id p) "` | " (.-role p) " | *" st-str "* | " caps-str " |\n")))
           hdr
           (.-peers room))))
