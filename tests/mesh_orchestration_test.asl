(module agent-bus/mesh-orchestration-test
  :d "Unit verification test suite for Multi-Project Daemon Launch, VFS Partitioning, and Peer Mesh Orchestration."
  :x [test-daemon-peer-registration
      test-workspace-partitioning
      test-buffer-mutex-acquisition
      test-mesh-routing-packet
      test-peer-heartbeat-timeout
      run-tests]
  :i [(mesh :a m)])

(df test-daemon-peer-registration [] -> Bool
  :d "Verifies daemon peer registration and lookup in peer registry"
  (let [(reg (m/create-peer-registry "genseam-hash"))
        (peer (m/make-daemon-peer "node-1" "genseam-hash" 1234 "/tmp/asl_hub.sock" 8443 "orchestrator" 1773490000000))
        (reg2 (m/register-daemon-peer reg peer))
        (found (m/find-daemon-peer reg2 "node-1"))
        (peer-list (map-values (.-peers reg2)))]
    (assert (= (list-length peer-list) 1) "Registry must have 1 peer")
    (assert (not (nil? found)) "Peer must be found in registry")
    (mt found
      ((some p) (assert (= (.-daemon-id p) "node-1") "Found peer ID must match node-1"))
      ((none) (assert false "Peer must exist")))
    true))

(df test-workspace-partitioning [] -> Bool
  :d "Verifies detection of workspace collisions across distinct monorepo projects with dual polarity"
  (let [(p1 (m/make-daemon-peer "n1" "project-alpha" 100 "/tmp/s1.sock" 8441 "worker" 1773490000000))
        (p2 (m/make-daemon-peer "n2" "project-alpha" 200 "/tmp/s2.sock" 8442 "worker" 1773490000000))
        (p3 (m/make-daemon-peer "n3" "project-beta" 300 "/tmp/s3.sock" 8443 "worker" 1773490000000))
        (peers (list p1 p2 p3))
        (collisions (m/detect-workspace-collisions peers "project-alpha"))
        (empty-collisions (m/detect-workspace-collisions peers "project-gamma"))]
    (assert (= (list-length collisions) 2) "Must detect 2 peers sharing project-alpha workspace")
    (refute (> (list-length empty-collisions) 0) "Must not detect collisions for unused project-gamma")
    true))

(df test-buffer-mutex-acquisition [] -> Bool
  :d "Verifies acquiring and releasing in-memory buffer leases"
  (let [(reg (m/create-mutex-registry))
        (opt-reg (m/acquire-buffer-lease reg "src/main.asl" "agent-1" 1773490000000 3600))]
    (mt opt-reg
      ((some reg-locked)
       (let [(is-locked (m/is-buffer-locked? reg-locked "src/main.asl" 1773490001000))
             (reg-released (m/release-buffer-lease reg-locked "src/main.asl" "agent-1"))
             (is-unlocked (not (m/is-buffer-locked? reg-released "src/main.asl" 1773490001000)))]
         (assert is-locked "Buffer must be locked after lease acquisition")
         (assert is-unlocked "Buffer must be unlocked after lease release")))
      ((none)
       (assert false "Acquiring unheld buffer lease must succeed")))
    true))

(df test-mesh-routing-packet [] -> Bool
  :d "Verifies control signal routing to target mesh node"
  (let [(table (m/create-routing-table))
        (node (m/MeshNode :id "remote-slm" :role "infer" :tier "tier-1" :inbox-size 0 :is-alive true))
        (table2 (m/register-mesh-node table node))
        (routed (m/route-packet table2 "local" "remote-slm" "payload"))]
    (assert (m/is-node-alive node) "Node must be alive within threshold")
    (assert (string-contains? routed "remote-slm") "Packet must be successfully routed to alive node")
    true))

(df test-peer-heartbeat-timeout [] -> Bool
  :d "Verifies eviction of dead peers exceeding heartbeat threshold with dual polarity"
  (let [(reg (m/create-peer-registry "ws-hash"))
        (dead-peer (m/make-daemon-peer "dead-node" "ws-hash" 500 "/tmp/dead.sock" 8440 "worker" 1773490000000))
        (reg2 (m/register-daemon-peer reg dead-peer))
        (reg-clean (m/evict-dead-peers reg2 1773490020000 15000))
        (peer-list (map-values (.-peers reg-clean)))]
    (assert (= (list-length peer-list) 0) "Dead peer must be evicted after 15s timeout")
    (refute (map-contains-key? (.-peers reg-clean) "dead-node") "Dead peer must not remain in registry")
    true))

(df run-tests [] -> Bool
  :d "Executes all mesh orchestration unit verification tests"
  (and (test-daemon-peer-registration)
       (and (test-workspace-partitioning)
            (and (test-buffer-mutex-acquisition)
                 (and (test-mesh-routing-packet)
                      (test-peer-heartbeat-timeout))))))
