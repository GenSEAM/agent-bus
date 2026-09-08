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
  (let [(evt (bus/ping))]
    (assert (not (bus/is-broadcast evt)) "Ping event must not be broadcast")
    true))

(df run-tests [] -> Bool
  :d "Runs agent bus unit tests"
  (and (test-sse-formatting)
       (test-broadcast-event)
       (test-direct-event)
       (test-ping-event)))

(run-tests)
