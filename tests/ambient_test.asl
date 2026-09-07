(module asl-agent-bus/ambient-test
  :d "Unit verification test suite for ambient perception, peer discovery, buffer mutex, and eviction."
  :x [test-ambient-frame-creation
      test-ambient-frame-validation
      test-ambient-frame-token-economy
      test-daemon-peer-registration
      test-workspace-collision-detection
      test-buffer-lease-lifecycle
      test-dead-peers-eviction
      run-tests]
  :i [(ambient :a amb)
      (mesh :a m)])

(df test-ambient-frame-creation [] -> Bool
  :d "Verifies AmbientFrame construction and field assignments."
  (let [(frame (amb/create-ambient-frame "d-751f1272" 0.05 (list "buf-01" "buf-02") 1757160000))]
    (assert (= (.-peer-id frame) "d-751f1272"))
    (assert (= (.-load frame) 0.05))
    (assert (= (list-length (.-claimed frame)) 2))
    (assert (= (.-ts frame) 1757160000))
    (assert (amb/validate-ambient-frame frame))
    true))

(df test-ambient-frame-validation [] -> Bool
  :d "Verifies validation of valid and invalid ambient frames."
  (let [(valid-frame (amb/create-ambient-frame "d-active" 0.5 (list) 100))
        (bad-empty-id (amb/create-ambient-frame "" 0.1 (list) 100))
        (bad-neg-load (amb/create-ambient-frame "d-1" -0.1 (list) 100))
        (bad-high-load (amb/create-ambient-frame "d-1" 1.5 (list) 100))
        (bad-neg-ts (amb/create-ambient-frame "d-1" 0.5 (list) -10))]
    (assert (amb/validate-ambient-frame valid-frame))
    (assert (not (amb/validate-ambient-frame bad-empty-id)))
    (assert (not (amb/validate-ambient-frame bad-neg-load)))
    (assert (not (amb/validate-ambient-frame bad-high-load)))
    (assert (not (amb/validate-ambient-frame bad-neg-ts)))
    true))

(df test-ambient-frame-token-economy [] -> Bool
  :d "Verifies ambient frame serializes to compact ASN strictly under 120 tokens."
  (let [(frame (amb/create-ambient-frame "d-751f1272" 0.05 (list "buf-01" "buf-02") 1757160000))
        (encoded (amb/encode-ambient-asn frame))
        (empty-frame (amb/create-ambient-frame "d-idle" 0.0 (list) 1000))
        (empty-encoded (amb/encode-ambient-asn empty-frame))]
    (assert (string-contains? encoded "(:ambient :peer-id \"d-751f1272\""))
    (assert (string-contains? encoded ":load 0.05"))
    (assert (string-contains? encoded ":claimed [\"buf-01\" \"buf-02\"]"))
    (assert (string-contains? encoded ":ts 1757160000"))
    (assert (string-contains? empty-encoded ":claimed []"))
    (assert (< (string-length encoded) 200))
    (assert (< (string-length empty-encoded) 200))
    true))

(df test-daemon-peer-registration [] -> Bool
  :d "Verifies peer registration and retrieval in peer registry."
  (let [(reg0 (m/create-peer-registry "751f1272"))
        (peer-a (m/make-daemon-peer "d-a" "751f1272" 1001 "/tmp/sock_a" 0 ":master" 1000))
        (peer-b (m/make-daemon-peer "d-b" "751f1272" 1002 "/tmp/sock_b" 0 ":secondary" 1000))
        (reg1 (m/register-daemon-peer reg0 peer-a))
        (reg2 (m/register-daemon-peer reg1 peer-b))
        (found-a (m/find-daemon-peer reg2 "d-a"))
        (missing (m/find-daemon-peer reg2 "unknown"))]
    (assert (= (.-local-workspace-hash reg0) "751f1272"))
    (assert (= (map-size (.-peers reg1)) 1))
    (assert (= (map-size (.-peers reg2)) 2))
    (assert (is-some? found-a))
    (assert (is-none? missing))
    (assert (mt found-a
              ((some p) (and (= (.-role p) ":master") (= (.-pid p) 1001)))
              (_ false)))
    true))

(df test-workspace-collision-detection [] -> Bool
  :d "Verifies detection of multiple active daemons in the same workspace."
  (let [(peer-a (m/make-daemon-peer "d-a" "ws-alpha" 1001 "/tmp/sock_a" 0 ":master" 1000))
        (peer-b (m/make-daemon-peer "d-b" "ws-alpha" 1002 "/tmp/sock_b" 0 ":secondary" 1000))
        (peer-c (m/make-daemon-peer "d-c" "ws-beta" 1003 "/tmp/sock_c" 0 ":master" 1000))
        (peers (list peer-a peer-b peer-c))
        (collisions (m/detect-workspace-collisions peers "ws-alpha"))
        (disjoint (m/detect-workspace-collisions peers "ws-gamma"))]
    (assert (= (list-length collisions) 2))
    (assert (= (list-length disjoint) 0))
    true))

(df test-buffer-lease-lifecycle [] -> Bool
  :d "Verifies buffer lease acquisition conflict expiry and release."
  (let [(reg0 (m/create-mutex-registry))
        (opt-reg1 (m/acquire-buffer-lease reg0 "buf-alpha" "peer-a" 1000 30))]
    (assert (is-some? opt-reg1))
    (let [(reg1 (mt opt-reg1 ((some r) r) (_ reg0)))]
      (assert (m/is-buffer-locked? reg1 "buf-alpha" 1010))
      (let [(lease-opt (m/get-buffer-lease reg1 "buf-alpha"))]
        (assert (is-some? lease-opt))
        (assert (mt lease-opt ((some l) (= (.-holder-id l) "peer-a")) (_ false))))
      (let [(opt-conflict (m/acquire-buffer-lease reg1 "buf-alpha" "peer-b" 1010 30))]
        (assert (is-none? opt-conflict)))
      (let [(opt-renew (m/acquire-buffer-lease reg1 "buf-alpha" "peer-a" 1020 30))]
        (assert (is-some? opt-renew)))
      (let [(reg-bad-rel (m/release-buffer-lease reg1 "buf-alpha" "peer-b"))]
        (assert (m/is-buffer-locked? reg-bad-rel "buf-alpha" 1015)))
      (let [(reg-rel (m/release-buffer-lease reg1 "buf-alpha" "peer-a"))]
        (assert (not (m/is-buffer-locked? reg-rel "buf-alpha" 1015))))
      (let [(lease (m/make-buffer-lease "buf-exp" "peer-a" 1000 30))]
        (assert (not (m/lease-expired? lease 1020)))
        (assert (m/lease-expired? lease 1030)))
      (let [(opt-exp (m/acquire-buffer-lease reg1 "buf-alpha" "peer-b" 1035 30))]
        (assert (is-some? opt-exp))))
    true))

(df test-dead-peers-eviction [] -> Bool
  :d "Verifies eviction of dead peers exceeding heartbeat TTL."
  (let [(reg0 (m/create-peer-registry "ws-main"))
        (p-live (m/make-daemon-peer "p-live" "ws-main" 2001 "/tmp/live" 0 ":master" 1000))
        (p-dead (m/make-daemon-peer "p-dead" "ws-main" 2002 "/tmp/dead" 0 ":secondary" 950))
        (reg1 (m/register-daemon-peer reg0 p-live))
        (reg2 (m/register-daemon-peer reg1 p-dead))]
    (assert (= (map-size (.-peers reg2)) 2))
    (let [(reg-evicted (m/evict-dead-peers reg2 1000 30))]
      (assert (= (map-size (.-peers reg-evicted)) 1))
      (assert (is-some? (m/find-daemon-peer reg-evicted "p-live")))
      (assert (is-none? (m/find-daemon-peer reg-evicted "p-dead"))))
    true))

(df run-tests [] -> Bool
  :d "Runs all ambient perception and mesh commutation tests."
  (do
    (assert (test-ambient-frame-creation))
    (assert (test-ambient-frame-validation))
    (assert (test-ambient-frame-token-economy))
    (assert (test-daemon-peer-registration))
    (assert (test-workspace-collision-detection))
    (assert (test-buffer-lease-lifecycle))
    (assert (test-dead-peers-eviction))
    true))
