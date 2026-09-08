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
  :d "Verifies initial empty routing table invariants."
  (let [(rt (m/create-routing-table))]
    (do
      (assert (= (int32-to-int64 (map-size (.-nodes rt))) 0) "Initial routing table must be empty")
      (assert (not (map-has? (.-nodes rt) "node:nonexistent")) "Empty routing table must not contain unregistered nodes")
      true)))

(df test-node-registration [] -> Bool
  :d "Verifies registering a mesh node into routing table."
  (let [(rt (m/create-routing-table))
        (node (m/MeshNode :id "node:scout" :role "scout" :tier "layer-1" :inbox-size 0 :is-alive true))
        (rt2 (m/register-mesh-node rt node))]
    (do
      (assert (= (int32-to-int64 (map-size (.-nodes rt2))) 1) "Routing table must contain 1 node after registration")
      (assert (m/is-node-alive node) "Registered scout node must be alive")
      (assert (not (map-has? (.-nodes rt2) "node:unknown")) "Unregistered node must not be present in table")
      true)))

(df test-node-liveness [] -> Bool
  :d "Verifies node liveness predicate distinguishes active vs inactive nodes."
  (let [(alive-node (m/MeshNode :id "n1" :role "coder" :tier "layer-1" :inbox-size 0 :is-alive true))
        (dead-node (m/MeshNode :id "n2" :role "planner" :tier "layer-2" :inbox-size 0 :is-alive false))]
    (do
      (assert (m/is-node-alive alive-node) "Alive node must return true")
      (assert (not (m/is-node-alive dead-node)) "Dead node must return false")
      true)))

(df test-packet-routing [] -> Bool
  :d "Verifies packet routing frame formatting and address integrity."
  (let [(rt (m/create-routing-table))
        (frame (m/route-packet rt "node:planner" "node:coder" "(:directive \"run-tests\")"))]
    (do
      (assert (string-contains? frame ":from \"node:planner\"") "Frame must contain originating node")
      (assert (string-contains? frame ":to \"node:coder\"") "Frame must contain destination node")
      (assert (not (string-contains? frame ":from \"node:coder\"")) "Origin node must not be inverted")
      (assert (not (string-contains? frame ":to \"node:planner\"")) "Destination node must not be inverted")
      true)))

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
    (do
      (assert (= (.-id c1) "C01") "Constraint id must match")
      (assert (= (.-rule c2) "Under 50ms latency") "Constraint rule must match")
      (assert (= (list-length (.-constraints contract)) 2) "Constraints count must be 2")
      (assert (= (list-length (.-acceptance-criteria contract)) 2) "Acceptance criteria count must be 2")
      (assert (= (list-length (.-assigned-roles contract)) 3) "Assigned roles count must be 3")
      (assert (string-contains? dispatch-str ":task-id \"TASK-100\"") "Dispatch frame must include task id")
      (assert (string-contains? dispatch-str ":role \"coder\"") "Dispatch frame must include assigned role")
      (assert (string-contains? dispatch-str ":mode \"mesh\"") "Dispatch frame must include delegation mode")
      (assert (not (string-contains? dispatch-str ":role \"architect\"")) "Unassigned role must not appear in dispatch frame")
      (assert (not (string-contains? dispatch-str ":task-id \"TASK-999\"")) "Mismatched task id must not appear")
      true)))

(df run-tests [] -> Bool
  :d "Runs all mesh unit test assertions."
  (do
    (assert (test-routing-table-creation))
    (assert (test-node-registration))
    (assert (test-node-liveness))
    (assert (test-packet-routing))
    (assert (test-task-contract-delegation))
    true))
