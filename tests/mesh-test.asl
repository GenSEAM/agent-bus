(module asl-agent-bus/mesh-test
  :d "Unit tests for agent mesh topology, peer routing table, and packet dispatch."
  :x [test-routing-table-creation
      test-node-registration
      test-node-liveness
      test-packet-routing
      test-task-contract-delegation
      run-tests]
  :i [(mesh :a m)])

"run: (run-tests)"

(df test-routing-table-creation [] -> Bool
  (let [(rt (m/create-routing-table))]
    (= (int32-to-int64 (map-size (.-nodes rt))) 0)))

(df test-node-registration [] -> Bool
  (let [(rt (m/create-routing-table))
        (node (m/MeshNode :id "node:scout" :role "scout" :tier "layer-1" :inbox-size 0 :is-alive true))
        (rt2 (m/register-mesh-node rt node))]
    (and (= (int32-to-int64 (map-size (.-nodes rt2))) 1)
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

(df test-task-contract-delegation [] -> Bool
  :d "Verifies TaskConstraint and TaskContract creation and delegation frame formatting."
  (let [(c1 (m/make-task-constraint "C01" "Zero foreign code" "hard"))
        (c2 (m/make-task-constraint "C02" "Under 50ms latency" "soft"))
        (contract (m/make-task-contract
                    "TASK-100"
                    "Implement mesh transport"
                    (list c1 c2)
                    (list "All tests pass" "Type check succeeds")
                    "mesh"
                    (list "scout" "coder" "reviewer")))
        (dispatch-str (m/delegate-contract contract "coder"))]
    (and (= (.-id c1) "C01")
         (and (= (.-rule c2) "Under 50ms latency")
              (and (= (list-length (.-constraints contract)) 2)
                   (and (= (list-length (.-acceptance-criteria contract)) 2)
                        (and (= (list-length (.-assigned-roles contract)) 3)
                             (and (string-contains? dispatch-str ":task-id \"TASK-100\"")
                                  (and (string-contains? dispatch-str ":role \"coder\"")
                                       (string-contains? dispatch-str ":mode \"mesh\""))))))))))

(df run-tests [] -> Bool
  :d "Runs all mesh unit test assertions."
  (do
    (assert (test-routing-table-creation))
    (assert (test-node-registration))
    (assert (test-node-liveness))
    (assert (test-packet-routing))
    (assert (test-task-contract-delegation))
    true))
