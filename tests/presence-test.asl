(module asl-bus/presence-test
  :d "Unit verification test suite for Swarm Room Presence, Task Negotiation, and External Bridge."
  :x [test-room-create-and-join
      test-room-peer-lookup
      test-room-leave
      test-negotiation-handshake-accept
      test-negotiation-handshake-decline
      test-format-presence-roster
      test-bridge-external-dispatch
      test-claim-path-and-roster
      run-presence-tests]
  :i [(presence :a p)
      (bridge :a b)])

(df test-room-create-and-join [] -> Bool
  :d "Tests creating a room and registering peers."
  (let [(r0 (p/create-swarm-room "refactor-matrix" "Polyglot Refactoring Swarm"))
        (p1 (p/SwarmPeer :agent-id "claude-code-1" :role "coder" :room "refactor-matrix" :status (p/status-idle) :capabilities (list "react-ast" "css-cascade") :last-ping-epoch 1757160000 :claims (list)))
        (p2 (p/SwarmPeer :agent-id "gemini-architect" :role "planner" :room "refactor-matrix" :status (p/status-busy) :capabilities (list "dag-planning") :last-ping-epoch 1757160000 :claims (list)))
        (r1 (p/join-swarm-room r0 p1))
        (r2 (p/join-swarm-room r1 p2))]
    (assert (= (list-length (p/list-room-peers r2)) 2) "Room peers length must be 2")
    (assert (= (.-room-name r2) "refactor-matrix") "Room name must be refactor-matrix")
    true))

(df test-room-peer-lookup [] -> Bool
  :d "Tests finding a peer by identifier."
  (let [(r0 (p/create-swarm-room "benchmarks" "Model Telemetry"))
        (p1 (p/SwarmPeer :agent-id "slm-m1-worker" :role "benchmarker" :room "benchmarks" :status (p/status-listening) :capabilities (list "m1-telemetry") :last-ping-epoch 1757160000 :claims (list)))
        (r1 (p/join-swarm-room r0 p1))
        (found (p/find-peer-in-room r1 "slm-m1-worker"))
        (missing (p/find-peer-in-room r1 "unknown-agent"))]
    (assert (is-some? found) "Found peer must be some")
    (assert (is-none? missing) "Missing peer must be none")
    (assert (mt found
              ((some (some p)) (= (.-role p) "benchmarker"))
              ((some p) (= (.-role p) "benchmarker"))
              (_ false)) "Peer role must be benchmarker")
    true))

(df test-room-leave [] -> Bool
  :d "Tests removing a peer on room leave."
  (let [(r0 (p/create-swarm-room "eval-room" "SWE-bench"))
        (p1 (p/SwarmPeer :agent-id "agent-a" :role "coder" :room "eval-room" :status (p/status-idle) :capabilities (list) :last-ping-epoch 0 :claims (list)))
        (r1 (p/join-swarm-room r0 p1))
        (r2 (p/leave-swarm-room r1 "agent-a"))]
    (assert (= (list-length (p/list-room-peers r1)) 1) "Room peers before leave must be 1")
    (assert (= (list-length (p/list-room-peers r2)) 0) "Room peers after leave must be 0")
    true))

(df test-negotiation-handshake-accept [] -> Bool
  :d "Tests task proposal and acceptance handshake."
  (let [(prop (p/propose-task "coordinator-1" "claude-code-1" "batch-refactor-navbar" "bid-001"))
        (acc (p/accept-task "bid-001" "claude-code-1" "coordinator-1" 15))]
    (assert (= (.-bid-id prop) "bid-001") "Bid ID must match bid-001")
    (assert (= (.-eta-seconds acc) 15) "ETA seconds must be 15")
    (assert (mt (.-kind acc) ((p/kind-accept) true) (_ false)) "Response kind must be kind-accept")
    true))

(df test-negotiation-handshake-decline [] -> Bool
  :d "Tests task rejection with diagnostic reason."
  (let [(dec (p/decline-task "bid-002" "busy-agent" "coordinator-1" "busy-running-integration-gates"))]
    (assert (= (.-bid-id dec) "bid-002") "Bid ID must match bid-002")
    (assert (= (.-reason dec) "busy-running-integration-gates") "Reason must match")
    (assert (mt (.-kind dec) ((p/kind-decline) true) (_ false)) "Response kind must be kind-decline")
    true))

(df test-format-presence-roster [] -> Bool
  :d "Tests formatting presence roster table."
  (let [(r0 (p/create-swarm-room "ops" "Cluster Operations"))
        (p1 (p/SwarmPeer :agent-id "gate-keeper" :role "auditor" :room "ops" :status (p/status-idle) :capabilities (list "gate.sh") :last-ping-epoch 0 :claims (list)))
        (r1 (p/join-swarm-room r0 p1))
        (roster (p/format-presence-roster r1))]
    (assert (string-contains? roster "Swarm Room: ops") "Roster must contain room name")
    (assert (string-contains? roster "gate-keeper") "Roster must contain peer agent-id")
    (assert (string-contains? roster "auditor") "Roster must contain peer role")
    (assert (string-contains? roster "*idle*") "Roster must contain status idle")
    true))

(df test-bridge-external-dispatch [] -> Bool
  :d "Tests external tool command dispatch and schema formatting."
  (let [(schema (b/format-external-tool-schema))
        (r0 (p/create-swarm-room "bridge-room" "External Bridge"))
        (cmd (b/ExternalToolCommand :action "join-room" :agent-id "claude-code" :room-name "bridge-room" :payload "()"))
        (res (b/dispatch-external-command r0 cmd))]
    (assert (string-contains? schema "asl_swarm_bus") "Schema must contain asl_swarm_bus")
    (assert (string-contains? res "Successfully joined room bridge-room") "Response must confirm joining room")
    true))

(df test-claim-path-and-roster [] -> Bool
  :d "Tests acquiring and releasing path claims and verifying roster formatting."
  (let [(p0 (p/SwarmPeer :agent-id "worker-1" :role "coder" :room "swarm" :status (p/status-idle) :capabilities (list) :last-ping-epoch 100 :claims (list)))
        (p1 (p/claim-path p0 "asl/tools/asl.c" (p/claim-write) 100 60))
        (p2 (p/claim-path p1 "mem/src/vfs.asl" (p/claim-read) 100 60))
        (p3 (p/release-claim p2 "asl/tools/asl.c"))
        (room (p/join-swarm-room (p/create-swarm-room "swarm" "testing") p2))
        (roster (p/format-presence-roster room))]
    (assert (= (list-length (.-claims p2)) 2) "p2 must have 2 claims")
    (assert (not (p/is-claim-expired? (first (.-claims p2)) 120)) "claim must not be expired at 120")
    (assert (p/is-claim-expired? (first (.-claims p2)) 170) "claim must be expired at 170")
    (assert (= (list-length (.-claims p3)) 1) "p3 must have 1 claim after release")
    (assert (string-contains? roster "asl/tools/asl.c") "roster must contain claimed path")
    true))

(df run-tests [] -> Bool
  :d "Runs all room presence and negotiation unit tests."
  (and (test-room-create-and-join)
       (test-room-peer-lookup)
       (test-room-leave)
       (test-negotiation-handshake-accept)
       (test-negotiation-handshake-decline)
       (test-format-presence-roster)
       (test-bridge-external-dispatch)
       (test-claim-path-and-roster)))

(df run-presence-tests [] -> Bool
  :d "Runs all room presence and negotiation unit tests."
  (run-tests))

(run-tests)
