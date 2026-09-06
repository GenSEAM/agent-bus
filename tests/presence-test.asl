(module asl-bus/presence-test
  :d "Unit verification test suite for Swarm Room Presence, Task Negotiation, and External Bridge."
  :x [test-room-create-and-join
      test-room-peer-lookup
      test-room-leave
      test-negotiation-handshake-accept
      test-negotiation-handshake-decline
      test-format-presence-roster
      test-bridge-external-dispatch
      run-presence-tests]
  :i [(presence :a p)
      (bridge :a b)])

(df test-room-create-and-join [] -> Bool
  :d "Tests creating a room and registering peers."
  (let [(r0 (p/create-swarm-room "refactor-matrix" "Polyglot Refactoring Swarm"))
        (p1 (p/SwarmPeer :agent-id "claude-code-1" :role "coder" :room "refactor-matrix" :status (p/status-idle) :capabilities (list "react-ast" "css-cascade") :last-ping-epoch 1757160000))
        (p2 (p/SwarmPeer :agent-id "gemini-architect" :role "planner" :room "refactor-matrix" :status (p/status-busy) :capabilities (list "dag-planning") :last-ping-epoch 1757160000))
        (r1 (p/join-swarm-room r0 p1))
        (r2 (p/join-swarm-room r1 p2))]
    (and (= (length (p/list-room-peers r2)) 2)
         (= (.-room-name r2) "refactor-matrix"))))

(df test-room-peer-lookup [] -> Bool
  :d "Tests finding a peer by identifier."
  (let [(r0 (p/create-swarm-room "benchmarks" "Model Telemetry"))
        (p1 (p/SwarmPeer :agent-id "slm-m1-worker" :role "benchmarker" :room "benchmarks" :status (p/status-listening) :capabilities (list "m1-telemetry") :last-ping-epoch 1757160000))
        (r1 (p/join-swarm-room r0 p1))
        (found (p/find-peer-in-room r1 "slm-m1-worker"))
        (missing (p/find-peer-in-room r1 "unknown-agent"))]
    (and (option-is-some? found)
         (option-is-none? missing)
         (= (.-role (option-unwrap found)) "benchmarker"))))

(df test-room-leave [] -> Bool
  :d "Tests removing a peer on room leave."
  (let [(r0 (p/create-swarm-room "eval-room" "SWE-bench"))
        (p1 (p/SwarmPeer :agent-id "agent-a" :role "coder" :room "eval-room" :status (p/status-idle) :capabilities (list) :last-ping-epoch 0))
        (r1 (p/join-swarm-room r0 p1))
        (r2 (p/leave-swarm-room r1 "agent-a"))]
    (and (= (length (p/list-room-peers r1)) 1)
         (= (length (p/list-room-peers r2)) 0))))

(df test-negotiation-handshake-accept [] -> Bool
  :d "Tests task proposal and acceptance handshake."
  (let [(prop (p/propose-task "coordinator-1" "claude-code-1" "batch-refactor-navbar" "bid-001"))
        (acc (p/accept-task "bid-001" "claude-code-1" "coordinator-1" 15))]
    (and (= (.-bid-id prop) "bid-001")
         (= (.-eta-seconds acc) 15)
         (mt (.-kind acc)
           ((kind-accept) true)
           (_ false)))))

(df test-negotiation-handshake-decline [] -> Bool
  :d "Tests task rejection with diagnostic reason."
  (let [(dec (p/decline-task "bid-002" "busy-agent" "coordinator-1" "busy-running-integration-gates"))]
    (and (= (.-bid-id dec) "bid-002")
         (= (.-reason dec) "busy-running-integration-gates")
         (mt (.-kind dec)
           ((kind-decline) true)
           (_ false)))))

(df test-format-presence-roster [] -> Bool
  :d "Tests formatting presence roster table."
  (let [(r0 (p/create-swarm-room "ops" "Cluster Operations"))
        (p1 (p/SwarmPeer :agent-id "gate-keeper" :role "auditor" :room "ops" :status (p/status-idle) :capabilities (list "gate.sh") :last-ping-epoch 0))
        (r1 (p/join-swarm-room r0 p1))
        (roster (p/format-presence-roster r1))]
    (and (string-contains? roster "Swarm Room: ops")
         (string-contains? roster "gate-keeper")
         (string-contains? roster "auditor")
         (string-contains? roster "*idle*"))))

(df test-bridge-external-dispatch [] -> Bool
  :d "Tests external tool command dispatch and schema formatting."
  (let [(schema (b/format-external-tool-schema))
        (r0 (p/create-swarm-room "bridge-room" "External Bridge"))
        (cmd (b/ExternalToolCommand :action "join-room" :agent-id "claude-code" :room-name "bridge-room" :payload "()"))
        (res (b/dispatch-external-command r0 cmd))]
    (and (string-contains? schema "asl_swarm_bus")
         (string-contains? res "Successfully joined room bridge-room"))))

(df run-presence-tests [] -> Bool
  :d "Runs all room presence and negotiation unit tests."
  (and (test-room-create-and-join)
       (test-room-peer-lookup)
       (test-room-leave)
       (test-negotiation-handshake-accept)
       (test-negotiation-handshake-decline)
       (test-format-presence-roster)
       (test-bridge-external-dispatch)))
