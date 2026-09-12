(module asl-agent-bus/test
  :d "Unit tests for agent bus protocol in ASL"
  :x [test-sse-formatting test-broadcast-event test-direct-event test-ping-event run-tests]
  :i [(bus :a bus)])

(df test-sse-formatting [] -> Bool
  :d "Verifies Server-Sent Events payload serialization."
  (let [(formatted (bus/format-sse-event "task-update" "status:ready"))]
    (assert (string-contains? formatted "event: task-update") "SSE format must contain event name")
    (assert (string-contains? formatted "data: status:ready") "SSE format must contain data payload")
    (assert (string-ends-with? formatted "\n\n") "SSE format must end with double newline")
    true))

(df test-broadcast-event [] -> Bool
  :d "Verifies broadcast event classification."
  (let [(msg (bus/AgentMessage :sender "agent-a" :target "all" :payload "ping" :timestamp 1700000000))
        (evt (bus/broadcast msg))]
    (assert (bus/is-broadcast evt) "Broadcast event must be detected as broadcast")
    (assert (= (.-sender msg) "agent-a") "Sender must match agent-a")
    (assert (= (.-target msg) "all") "Target must match all")
    true))

(df test-direct-event [] -> Bool
  :d "Verifies direct message event classification."
  (let [(msg (bus/AgentMessage :sender "agent-a" :target "agent-b" :payload "req" :timestamp 1700000001))
        (evt (bus/direct msg))]
    (assert (not (bus/is-broadcast evt)) "Direct event must not be detected as broadcast")
    (assert (= (.-target msg) "agent-b") "Target must match agent-b")
    true))

(df test-ping-event [] -> Bool
  :d "Verifies ping event behavior."
  (let [(evt (bus/ping))
        (msg (bus/AgentMessage :sender "kernel" :target "all" :payload "ping" :timestamp 1700000002))
        (b-evt (bus/broadcast msg))]
    (assert (not (bus/is-broadcast evt)) "Ping event must not be broadcast")
    (assert (bus/is-broadcast b-evt) "Broadcast event must be detected as broadcast")
    (assert (= (.-sender msg) "kernel") "Ping sender matches")
    true))

(df test-query-events-and-condition-wake [] -> Bool
  :d "Verifies pull-based event querying and condition-triggered wake evaluation"
  (let [(m1 (bus/AgentMessage :sender "a1" :target "bus" :payload "(:change :path \"asl/tools/asl.c\")" :timestamp 100))
        (m2 (bus/AgentMessage :sender "a2" :target "bus" :payload "(:change :path \"mem/src/vfs.asl\")" :timestamp 101))
        (events (list m1 m2))
        (q1 (bus/query-bus-events events "change" "asl/tools/asl.c"))
        (w0 (bus/make-condition-wake "watch-asl" "asl/tools/asl.c" "supervisor"))
        (w1 (bus/eval-condition-wake w0 m1))
        (w2 (bus/eval-condition-wake w0 m2))]
    (assert (= (list-length q1) 1) "Query must return exactly 1 matching event")
    (assert (not (.-triggered w0)) "Initial wake must not be triggered")
    (assert (.-triggered w1) "Wake against m1 must be triggered")
    (assert (not (.-triggered w2)) "Wake against m2 must not be triggered")
    true))

(df run-tests [] -> Bool
  :d "Runs agent bus unit tests"
  (and (test-sse-formatting)
       (test-broadcast-event)
       (test-direct-event)
       (test-ping-event)
       (test-query-events-and-condition-wake)))

(run-tests)
