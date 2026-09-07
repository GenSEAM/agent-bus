(module asl-agent-bus/mesh-test
  :d "Unit tests for agent mesh topology, peer routing table, and packet dispatch."
  :x [test-routing-table-creation
      test-node-registration
      test-node-liveness
      test-packet-routing
      run-tests]
  :i [(mesh :a m)])

"run: (run-tests)"

(df test-routing-table-creation [] -> Bool
  (let [(rt (m/create-routing-table))]
    (= (map-size (.-nodes rt)) 0)))

(df test-node-registration [] -> Bool
  (let [(rt (m/create-routing-table))
        (node (m/MeshNode :id "node:scout" :role "scout" :tier "layer-1" :inbox-size 0 :is-alive true))
        (rt2 (m/register-mesh-node rt node))]
    (and (= (map-size (.-nodes rt2)) 1)
         (m/is-node-alive node))))

(df test-node-liveness [] -> Bool
  (let [(alive-node (m/MeshNode :id "n1" :role "coder" :tier "layer-1" :inbox-size 0 :is-alive true))
        (dead-node (m/MeshNode :id "n2" :role "planner" :tier "layer-2" :inbox-size 0 :is-alive false))]
    (and (m/is-node-alive alive-node)
         (not (m/is-node-alive dead-node)))))

(df test-packet-routing [] -> Bool
  (let [(rt (m/create-routing-table))
        (frame (m/route-packet rt "node:planner" "node:coder" "(:directive \"run-tests\")"))]
    (and (string-contains? frame ":from \"node:planner\"")
         (string-contains? frame ":to \"node:coder\""))))

(df run-tests [] -> Bool
  (and (and (test-routing-table-creation)
            (test-node-registration))
       (and (test-node-liveness)
            (test-packet-routing))))
