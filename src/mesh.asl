(module asl-agent-bus/mesh
  :d "A2A Mesh Topology, Peer Routing Table & Swarm Bus in ASL"
  :x [MeshNode RoutingTable TransportProtocol
      create-routing-table register-mesh-node
      route-packet is-node-alive
      TaskConstraint TaskContract
      make-task-constraint make-task-contract delegate-contract]
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
