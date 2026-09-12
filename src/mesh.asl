(module asl-agent-bus/mesh
  :d "A2A Mesh Topology, Peer Routing Table & Swarm Bus in ASL"
  :x [MeshNode RoutingTable TransportProtocol
      create-routing-table register-mesh-node
      route-packet is-node-alive
      TaskConstraint TaskContract
      make-task-constraint make-task-contract delegate-contract
      ControlSignalFrame make-control-signal format-control-signal
      ComputeTier get-compute-tier-name
      DaemonPeer PeerRegistry
      make-daemon-peer create-peer-registry
      register-daemon-peer find-daemon-peer
      detect-workspace-collisions
      BufferLease MutexRegistry
      make-buffer-lease create-mutex-registry
      lease-expired? acquire-buffer-lease
      release-buffer-lease evict-dead-peers
      get-buffer-lease is-buffer-locked?
      AgentMeshNode join-mesh-cluster]
  :i [])

(dfe TransportProtocol
  (:c ipc-uds [] "Unix domain socket IPC")
  (:c in-memory [] "In-memory fast ring transport")
  (:c sse-stream [] "Server-Sent Events streaming transport")
  (:c wasm-channel [] "Wasm linear memory direct channel")
  (:c cluster-net [] "Remote cluster TCP/WebSocket transport"))

(dfs MeshNode
  (:f id Str "unique agent node identifier")
  (:f role Str "orchestrator, planner, coder, reviewer, searcher")
  (:f tier Str "layer-1, layer-2, layer-3, worker")
  (:f inbox-size I64 "current pending queue depth")
  (:f is-alive Bool "heartbeat active flag"))

(dfs RoutingTable
  (:f nodes (Map Str MeshNode) "registered swarm agents")
  (:f default-transport TransportProtocol "primary cluster transport"))

(df create-routing-table [] -> RoutingTable
  :d "Creates an empty routing table for the swarm mesh"
  (RoutingTable
    :nodes (map-empty)
    :default-transport (in-memory)))

(df register-mesh-node [(rt RoutingTable) (node MeshNode)] -> RoutingTable
  :d "Registers an agent node into the mesh routing table"
  (RoutingTable
    :nodes (map-set (.-nodes rt) (.-id node) node)
    :default-transport (.-default-transport rt)))

(df is-node-alive [(node MeshNode)] -> Bool
  :d "Checks if node is currently healthy"
  (.-is-alive node))

(df route-packet [(rt RoutingTable) (from Str) (to Str) (payload Str)] -> Str
  :d "Generates dispatch frame for routed packet"
  (str "(packet :from \"" from "\" :to \"" to "\" :data " payload ")"))

(dfs TaskConstraint
  (:f id Str "Constraint identifier e.g. C01")
  (:f rule Str "Normative constraint requirement or invariant")
  (:f severity Str "Severity level: hard | soft | advisory"))

(dfs TaskContract
  (:f task-id Str "Unique task identifier")
  (:f origin-prompt Str "Original user or delegator instruction")
  (:f constraints (List TaskConstraint) "Active constraints and invariants")
  (:f acceptance-criteria (List Str) "List of verifiable acceptance criteria")
  (:f delegation-mode Str "Delegation mode: direct | mesh")
  (:f assigned-roles (List Str) "Assigned swarm agent roles e.g. scout, coder, reviewer"))

(df make-task-constraint [(id Str) (rule Str) (severity Str)] -> TaskConstraint
  :d "Constructs a validated task constraint descriptor."
  (TaskConstraint :id id :rule rule :severity severity))

(df make-task-contract [(task-id Str) (origin-prompt Str) (constraints (List TaskConstraint)) (acceptance-criteria (List Str)) (delegation-mode Str) (assigned-roles (List Str))] -> TaskContract
  :d "Constructs a formal task contract for cross-agent delegation."
  (TaskContract
    :task-id task-id
    :origin-prompt origin-prompt
    :constraints constraints
    :acceptance-criteria acceptance-criteria
    :delegation-mode delegation-mode
    :assigned-roles assigned-roles))

(df delegate-contract [(contract TaskContract) (target-role Str)] -> Str
  :d "Dispatches a task contract to an assigned role within the mesh."
  (str "(:contract-dispatch :task-id \"" (.-task-id contract) "\" :role \"" target-role "\" :mode \"" (.-delegation-mode contract) "\")"))

(dfs ControlSignalFrame
  (:f signal-type Str "ping | lease | ack | dispatch | receipt")
  (:f task-id Str "Unique contract ID")
  (:f target-cluster Str "local | browser-edge | remote-gpu")
  (:f vfs-descriptor-uri Str "mem://vfs/... resident RAM pointer")
  (:f payload Str "Compact S-expression metadata"))

(df make-control-signal [(signal-type Str) (task-id Str) (target-cluster Str) (vfs-descriptor-uri Str) (payload Str)] -> ControlSignalFrame
  :d "Constructs a validated control plane signal frame for cross-cluster delegation."
  (ControlSignalFrame
    :signal-type signal-type
    :task-id task-id
    :target-cluster target-cluster
    :vfs-descriptor-uri vfs-descriptor-uri
    :payload payload))

(df format-control-signal [(frame ControlSignalFrame)] -> Str
  :d "Serializes control signal frame into compact wire format under 80 tokens."
  (str "(:signal \"" (.-signal-type frame) "\" :task-id \"" (.-task-id frame) "\" :cluster \"" (.-target-cluster frame) "\" :vfs \"" (.-vfs-descriptor-uri frame) "\" :data " (.-payload frame) ")"))

(dfe ComputeTier
  (:c tier-0-deterministic [] "Deterministic ripgrep/AWK/syntax tools under 1ms")
  (:c tier-1-edge-mediator [] "Edge SLM on WebGPU DOM accessibility tree 15-50ms")
  (:c tier-2-workhorse [] "Gemma 31B/Haiku sub-second workhorse 400-900ms")
  (:c tier-3-frontier-reasoning [] "Frontier reasoning Claude 3.5 Sonnet/O1 2-8s"))

(df get-compute-tier-name [(tier ComputeTier)] -> Str
  :d "Returns canonical string descriptor of compute tier."
  (mt tier
    ((tier-0-deterministic) "tier-0-deterministic")
    ((tier-1-edge-mediator) "tier-1-edge-mediator")
    ((tier-2-workhorse) "tier-2-workhorse")
    ((tier-3-frontier-reasoning) "tier-3-frontier-reasoning")))

(dfs DaemonPeer
  (:f daemon-id Str "Unique daemon instance identifier")
  (:f workspace-hash Str "Workspace 8-character hash")
  (:f pid I64 "Process identifier")
  (:f socket-path Str "Unix domain socket path")
  (:f port I64 "TCP port")
  (:f role Str "master or secondary")
  (:f heartbeat-epoch I64 "Timestamp of last recorded heartbeat")
  (:f status Str "active or dead or collision"))

(dfs PeerRegistry
  (:f peers (Map Str DaemonPeer) "Active daemon peers mapped by daemon-id")
  (:f local-workspace-hash Str "Local workspace hash"))

(df make-daemon-peer [(daemon-id Str) (workspace-hash Str) (pid I64) (socket-path Str) (port I64) (role Str) (heartbeat-epoch I64)] -> DaemonPeer
  :d "Creates a validated DaemonPeer record"
  (DaemonPeer
    :daemon-id daemon-id
    :workspace-hash workspace-hash
    :pid pid
    :socket-path socket-path
    :port port
    :role role
    :heartbeat-epoch heartbeat-epoch
    :status "active"))

(df create-peer-registry [(workspace-hash Str)] -> PeerRegistry
  :d "Initializes an empty peer registry for a workspace hash"
  (PeerRegistry
    :peers (map-empty)
    :local-workspace-hash workspace-hash))

(df register-daemon-peer [(reg PeerRegistry) (peer DaemonPeer)] -> PeerRegistry
  :d "Registers or updates a daemon peer in the registry"
  (PeerRegistry
    :peers (map-set (.-peers reg) (.-daemon-id peer) peer)
    :local-workspace-hash (.-local-workspace-hash reg)))

(df find-daemon-peer [(reg PeerRegistry) (daemon-id Str)] -> (Option DaemonPeer)
  :d "Finds a registered daemon peer by ID"
  (map-get (.-peers reg) daemon-id))

(df detect-workspace-collisions [(peers (List DaemonPeer)) (target-ws Str)] -> (List DaemonPeer)
  :d "Filters peers matching workspace hash to detect multi-daemon collisions"
  (filter (fn [(p DaemonPeer)] -> Bool
            (and (= (.-workspace-hash p) target-ws)
                 (= (.-status p) "active")))
          peers))

(dfs BufferLease
  (:f buffer-id Str "Identifier of buffer or mutex-locked resource")
  (:f holder-id Str "Unique daemon peer ID holding the lease")
  (:f acquired-epoch I64 "Epoch timestamp when lease was acquired")
  (:f ttl-seconds I64 "Lease validity duration default 30 seconds"))

(dfs MutexRegistry
  (:f leases (Map Str BufferLease) "Active buffer leases indexed by buffer-id"))

(df make-buffer-lease [(buffer-id Str) (holder-id Str) (acquired-epoch I64) (ttl-seconds I64)] -> BufferLease
  :d "Constructs a validated BufferLease record"
  (BufferLease
    :buffer-id buffer-id
    :holder-id holder-id
    :acquired-epoch acquired-epoch
    :ttl-seconds ttl-seconds))

(df create-mutex-registry [] -> MutexRegistry
  :d "Initializes an empty distributed buffer mutex registry"
  (MutexRegistry :leases (map-empty)))

(df lease-expired? [(lease BufferLease) (current-epoch I64)] -> Bool
  :d "Checks whether a buffer lease has expired given current epoch"
  (>= (- current-epoch (.-acquired-epoch lease)) (.-ttl-seconds lease)))

(df acquire-buffer-lease [(reg MutexRegistry) (buffer-id Str) (peer-id Str) (current-epoch I64) (ttl-seconds I64)] -> (Option MutexRegistry)
  :d "Attempts to acquire distributed buffer mutex lease with finite TTL, succeeding if unheld or expired"
  (let [(existing (map-get (.-leases reg) buffer-id))]
    (mt existing
      ((some lease)
       (if (or (= (.-holder-id lease) peer-id)
               (lease-expired? lease current-epoch))
           (let [(new-lease (make-buffer-lease buffer-id peer-id current-epoch ttl-seconds))
                 (updated-leases (map-set (.-leases reg) buffer-id new-lease))]
             (some (MutexRegistry :leases updated-leases)))
           (none)))
      ((none)
       (let [(new-lease (make-buffer-lease buffer-id peer-id current-epoch ttl-seconds))
             (updated-leases (map-set (.-leases reg) buffer-id new-lease))]
         (some (MutexRegistry :leases updated-leases)))))))

(df release-buffer-lease [(reg MutexRegistry) (buffer-id Str) (peer-id Str)] -> MutexRegistry
  :d "Releases distributed buffer lease if held by requesting peer"
  (let [(existing (map-get (.-leases reg) buffer-id))]
    (mt existing
      ((some lease)
       (if (= (.-holder-id lease) peer-id)
           (MutexRegistry :leases (map-remove (.-leases reg) buffer-id))
           reg))
      ((none) reg))))

(df get-buffer-lease [(reg MutexRegistry) (buffer-id Str)] -> (Option BufferLease)
  :d "Retrieves active buffer lease for buffer identifier if present"
  (map-get (.-leases reg) buffer-id))

(df is-buffer-locked? [(reg MutexRegistry) (buffer-id Str) (current-epoch I64)] -> Bool
  :d "Returns true if buffer is held under an active unexpired lease"
  (let [(existing (map-get (.-leases reg) buffer-id))]
    (mt existing
      ((some lease) (not (lease-expired? lease current-epoch)))
      ((none) false))))

(df evict-dead-peers [(reg PeerRegistry) (current-epoch I64) (ttl-threshold I64)] -> PeerRegistry
  :d "Evicts peers whose heartbeat age exceeds ttl-threshold, removing dead peers from active routing"
  (let [(alive-peers (filter (fn [(p DaemonPeer)] -> Bool
                               (<= (- current-epoch (.-heartbeat-epoch p)) ttl-threshold))
                             (map-values (.-peers reg))))
        (new-map (fold (fn [(acc (Map Str DaemonPeer)) (p DaemonPeer)] -> (Map Str DaemonPeer)
                         (map-set acc (.-daemon-id p) p))
                       (map-empty)
                       alive-peers))]
    (PeerRegistry
      :peers new-map
      :local-workspace-hash (.-local-workspace-hash reg))))

(dfs AgentMeshNode
  (:f node-id Str "Unique sovereign agent mesh node identifier")
  (:f role Str "Assigned agent role e.g. planner, coder, verifier")
  (:f endpoint Str "Direct socket endpoint or in-process bus address")
  (:f status Str "Active node execution status online, busy, idle")
  (:f last-seen-epoch I64 "Epoch timestamp of last verified activity"))

(df join-mesh-cluster [(rt RoutingTable) (node AgentMeshNode)] -> RoutingTable
  :d "Registers or updates sovereign agent node into the mesh routing table without daemon overhead"
  (let [(mesh-node (MeshNode
                     :id (.-node-id node)
                     :role (.-role node)
                     :tier "tier-1-sovereign"
                     :inbox-size 0
                     :is-alive true))]
    (register-mesh-node rt mesh-node)))
