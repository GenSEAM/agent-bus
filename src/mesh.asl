(module asl-agent-bus/mesh
  :d "A2A Mesh Topology, Peer Routing Table & Swarm Bus in ASL"
  :x [MeshNode RoutingTable TransportProtocol
      create-routing-table register-mesh-node
      route-packet is-node-alive
      TaskConstraint TaskContract
      make-task-constraint make-task-contract delegate-contract
      ControlSignalFrame make-control-signal format-control-signal
      ComputeTier get-compute-tier-name]
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
