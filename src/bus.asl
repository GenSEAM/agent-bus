(module asl-agent-bus/bus
  :d "Inter-Agent Swarm Bus Protocol in ASL"
  :x [AgentMessage
      BusEvent
      format-sse-event
      is-broadcast
      BusChannel
      TaskLifecycleState
      BusReceipt
      ConditionWake
      dispatch-bus-event
      query-bus-events
      pull-bus-events
      make-condition-wake
      eval-condition-wake
      make-lifecycle-event
      format-lifecycle-sse
      channel-to-str
      lifecycle-to-str]
  :i [(asl-text/string :a s)])

(dfs AgentMessage
  (:f sender Str "sender id")
  (:f target Str "target id")
  (:f payload Str "ast payload")
  (:f timestamp I64 "unix epoch"))

(dfe BusEvent
  (:c direct [(msg AgentMessage)] "direct message")
  (:c broadcast [(msg AgentMessage)] "broadcast message")
  (:c ping [] "ping event"))

(dfe BusChannel
  (:c lifecycle [] "Task lifecycle state transition events")
  (:c telemetry [] "High-signal auditory and visual telemetry metrics")
  (:c control [] "Supervisory control and handoff commands")
  (:c audit [] "Clean-context verification gate receipts"))

(dfe TaskLifecycleState
  (:c queued [] "Task queued in pending buffer")
  (:c routing [] "Task routing to worker lanes")
  (:c executing [] "Task executing in worker lanes")
  (:c verifying [] "Task undergoing gate verification")
  (:c done [] "Task completed successfully")
  (:c failed [] "Task execution or verification failed"))

(dfs BusReceipt
  (:f channel Str "Target bus channel identifier")
  (:f sender Str "Sender identifier")
  (:f target Str "Target recipient identifier")
  (:f delivered Bool "True if event was delivered to channel")
  (:f timestamp I64 "Dispatch timestamp"))

(dfs ConditionWake
  (:f condition-name Str "Identifier of condition being observed")
  (:f predicate-expr Str "Predicate expression to evaluate against event")
  (:f target-agent Str "Target agent to be notified upon trigger")
  (:f triggered Bool "True if condition predicate evaluated to true"))

(df format-sse-event [(event-name Str) (data Str)] -> Str
  :d "Formats SSE event payload"
  (s/concat (s/concat (s/concat "event: " event-name) "\ndata: ") (s/concat data "\n\n")))

(df is-broadcast [(event BusEvent)] -> Bool
  :d "Checks if event is broadcast"
  (mt event
    ((broadcast msg) true)
    (_ false)))

(df channel-to-str [(ch BusChannel)] -> Str
  :d "Converts bus channel enum to string identifier"
  (mt ch
    ((lifecycle) "lifecycle")
    ((telemetry) "telemetry")
    ((control) "control")
    ((audit) "audit")))

(df lifecycle-to-str [(state TaskLifecycleState)] -> Str
  :d "Converts lifecycle state enum to canonical string"
  (mt state
    ((queued) "QUEUED")
    ((routing) "ROUTING")
    ((executing) "EXECUTING")
    ((verifying) "VERIFYING")
    ((done) "DONE")
    ((failed) "FAILED")))

(df make-lifecycle-event [(task-id Str) (state TaskLifecycleState) (detail Str)] -> AgentMessage
  :d "Creates an AgentMessage representing a lifecycle state transition"
  (AgentMessage
    :sender "kernel"
    :target "bus"
    :payload (str "(:lifecycle :task \"" task-id "\" :state \"" (lifecycle-to-str state) "\" :detail \"" detail "\")")
    :timestamp 1725800000))

(df dispatch-bus-event [(ch BusChannel) (msg AgentMessage)] -> BusReceipt
  :d "Dispatches an event message to the designated channel"
  (BusReceipt
    :channel (channel-to-str ch)
    :sender (.-sender msg)
    :target (.-target msg)
    :delivered true
    :timestamp (.-timestamp msg)))

(df query-bus-events [(events (List AgentMessage)) (channel-filter Str) (target-path Str)] -> (List AgentMessage)
  :d "Pulls filtered event records on demand matching channel and target path outside context"
  (filter (fn [(msg AgentMessage)] -> Bool
            (and (or (= channel-filter "") (string-contains? (.-payload msg) channel-filter))
                 (or (= target-path "") (string-contains? (.-payload msg) target-path))))
          events))

(df pull-bus-events [(events (List AgentMessage)) (topic Str)] -> (List AgentMessage)
  :d "Pulls messages matching a specific topic or query"
  (query-bus-events events topic ""))

(df make-condition-wake [(name Str) (pred Str) (agent Str)] -> ConditionWake
  :d "Initializes an un-triggered condition wake descriptor"
  (ConditionWake
    :condition-name name
    :predicate-expr pred
    :target-agent agent
    :triggered false))

(df eval-condition-wake [(wake ConditionWake) (msg AgentMessage)] -> ConditionWake
  :d "Evaluates incoming event against condition wake predicate delivering condition rather than raw log"
  (if (string-contains? (.-payload msg) (.-predicate-expr wake))
      (ConditionWake
        :condition-name (.-condition-name wake)
        :predicate-expr (.-predicate-expr wake)
        :target-agent (.-target-agent wake)
        :triggered true)
      wake))

(df format-lifecycle-sse [(task-id Str) (state TaskLifecycleState) (detail Str)] -> Str
  :d "Formats task lifecycle event into SSE wire format"
  (let [(data (str "(:lifecycle :task \"" task-id "\" :state \"" (lifecycle-to-str state) "\" :detail \"" detail "\")"))]
    (format-sse-event "lifecycle" data)))
