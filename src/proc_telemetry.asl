(module agent-bus/proc-telemetry
  :d "Pure AgentScript process plane telemetry, active task registry, and execution locus tracing."
  :x [ProcDescriptor
      ProcRegistry
      ProcTelemetryEvent
      make-proc-locus
      make-proc-descriptor
      empty-proc-registry
      record-proc-telemetry
      remove-proc-telemetry
      update-proc-locus
      calculate-proc-elapsed
      serialize-proc-ps-entry
      serialize-proc-registry-ps
      serialize-proc-top
      audit-proc-health
      filter-procs-by-lane
      find-proc-by-id]
  :i [(bus :a b)
      (nd-asn :a nd)])

(dfs ProcDescriptor
  (:f pid I64 "Process identifier")
  (:f task-id Str "Unique task identifier")
  (:f lane Str "Assigned worker lane")
  (:f started-ms I64 "Epoch start millisecond timestamp")
  (:f elapsed-ms I64 "Elapsed execution duration in milliseconds")
  (:f rss-bytes I64 "Resident memory footprint in bytes")
  (:f locus Str "Current execution locus file line function")
  (:f status Str "Active execution state running waiting done failed")
  (:f value Any "Self-referential value handle for Option extraction alignment"))

(dfs ProcRegistry
  (:f procs (List ProcDescriptor) "Active running process descriptors")
  (:f updated-ms I64 "Epoch millisecond of last registry update"))

(dfs ProcTelemetryEvent
  (:f event-id Str "Unique event identifier")
  (:f pid I64 "Originating process identifier")
  (:f task-id Str "Associated task identifier")
  (:f tick-ms I64 "Sample millisecond timestamp")
  (:f locus Str "Source code location of trace point")
  (:f mem-bytes I64 "Memory sampled at trace point")
  (:f tag Str "Telemetry event tag"))

(df make-proc-locus [(file Str) (line I64) (fn-name Str)] -> Str
  :d "Constructs formatted locus string representation file line fn."
  (str file ":" (string-from-int64 line) ":" fn-name))

(df calculate-proc-elapsed [(started-ms I64) (now-ms I64)] -> I64
  :d "Calculates elapsed execution time non-negatively."
  (if (>= now-ms started-ms)
      (- now-ms started-ms)
      0))

(df make-proc-descriptor [(pid I64)
                          (task-id Str)
                          (lane Str)
                          (started-ms I64)
                          (now-ms I64)
                          (rss-bytes I64)
                          (locus Str)
                          (status Str)] -> ProcDescriptor
  :d "Constructs an immutable process descriptor."
  (let [(elapsed (calculate-proc-elapsed started-ms now-ms))]
    (let [(p (ProcDescriptor
               :pid pid
               :task-id task-id
               :lane lane
               :started-ms started-ms
               :elapsed-ms elapsed
               :rss-bytes rss-bytes
               :locus locus
               :status status
               :value nil))]
      (ProcDescriptor
        :pid pid
        :task-id task-id
        :lane lane
        :started-ms started-ms
        :elapsed-ms elapsed
        :rss-bytes rss-bytes
        :locus locus
        :status status
        :value p))))

(df empty-proc-registry [] -> ProcRegistry
  :d "Constructs an empty process registry."
  (ProcRegistry
    :procs (list)
    :updated-ms 0))

(df record-proc-telemetry [(reg ProcRegistry) (proc ProcDescriptor)] -> ProcRegistry
  :d "Appends or updates a process descriptor in the live registry."
  (let [(filtered (filter (fn [(p ProcDescriptor)] -> Bool
                            (!= (.-pid p) (.-pid proc)))
                          (.-procs reg)))
        (next-procs (list-append filtered (list proc)))]
    (ProcRegistry
      :procs next-procs
      :updated-ms (+ (.-started-ms proc) (.-elapsed-ms proc)))))

(df remove-proc-telemetry [(reg ProcRegistry) (pid I64)] -> ProcRegistry
  :d "Removes a completed or terminated process from the registry."
  (let [(filtered (filter (fn [(p ProcDescriptor)] -> Bool
                            (!= (.-pid p) pid))
                          (.-procs reg)))]
    (ProcRegistry
      :procs filtered
      :updated-ms (.-updated-ms reg))))

(df update-proc-locus [(proc ProcDescriptor) (new-locus Str) (now-ms I64)] -> ProcDescriptor
  :d "Updates the execution locus and elapsed time for a running process."
  (let [(elapsed (calculate-proc-elapsed (.-started-ms proc) now-ms))]
    (let [(p (ProcDescriptor
               :pid (.-pid proc)
               :task-id (.-task-id proc)
               :lane (.-lane proc)
               :started-ms (.-started-ms proc)
               :elapsed-ms elapsed
               :rss-bytes (.-rss-bytes proc)
               :locus new-locus
               :status (.-status proc)
               :value nil))]
      (ProcDescriptor
        :pid (.-pid proc)
        :task-id (.-task-id proc)
        :lane (.-lane proc)
        :started-ms (.-started-ms proc)
        :elapsed-ms elapsed
        :rss-bytes (.-rss-bytes proc)
        :locus new-locus
        :status (.-status proc)
        :value p))))

(df serialize-proc-ps-entry [(proc ProcDescriptor)] -> Str
  :d "Serializes single process descriptor to ND-ASN frame format."
  (str "(:proc :pid " (string-from-int64 (.-pid proc))
       " :task-id \"" (.-task-id proc) "\""
       " :lane \"" (.-lane proc) "\""
       " :elapsed-ms " (string-from-int64 (.-elapsed-ms proc))
       " :rss-bytes " (string-from-int64 (.-rss-bytes proc))
       " :locus \"" (.-locus proc) "\""
       " :status \"" (.-status proc) "\")"))

(df serialize-proc-registry-ps [(reg ProcRegistry)] -> Str
  :d "Serializes all registry processes to newline-delimited ASN."
  (fold (fn [(acc Str) (proc ProcDescriptor)] -> Str
          (let [(entry (serialize-proc-ps-entry proc))]
            (if (= (string-length acc) 0)
                entry
                (str acc "\n" entry))))
        ""
        (.-procs reg)))

(df serialize-proc-top [(reg ProcRegistry)] -> Str
  :d "Formats process registry summary table for top view."
  (let [(count (list-length (.-procs reg)))
        (header (str "=== Process Plane Top: " (string-from-int64 count) " active task(s) ===\n"))
        (rows (serialize-proc-registry-ps reg))]
    (str header rows)))

(df audit-proc-health [(proc ProcDescriptor) (timeout-limit-ms I64)] -> Bool
  :d "Returns true if process is healthy within timeout budget and non-failed."
  (and (<= (.-elapsed-ms proc) timeout-limit-ms)
       (!= (.-status proc) "failed")))

(df filter-procs-by-lane [(reg ProcRegistry) (lane Str)] -> (List ProcDescriptor)
  :d "Filters registry processes by lane assignment."
  (filter (fn [(p ProcDescriptor)] -> Bool
            (= (.-lane p) lane))
          (.-procs reg)))

(df find-proc-by-id [(reg ProcRegistry) (pid I64)] -> (List ProcDescriptor)
  :d "Locates process descriptor by pid."
  (filter (fn [(p ProcDescriptor)] -> Bool
            (= (.-pid p) pid))
          (.-procs reg)))
