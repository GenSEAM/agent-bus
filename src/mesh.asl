(module asl-agent-bus/mesh
  :d "A2A Mesh Topology, Peer Routing Table & Swarm Bus in ASL"
  :x [MeshNode RoutingTable TransportProtocol
      create-routing-table register-mesh-node
      route-packet is-node-alive]
  :i [(core/strings :a s)])

(dfe TransportProtocol
  (:c ipc-uds [] "Unix domain socket IPC")
  (:c in-memory [] "In-memory fast ring transport")
  (:c sse-stream [] "Server-Sent Events streaming transport")
  (:c wasm-channel [] "Wasm linear memory direct channel"))

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
  (s/concat (s/concat (s/concat "(packet :from \"" from) (s/concat "\" :to \"" to)) (s/concat "\" :data " (s/concat payload ")"))))
