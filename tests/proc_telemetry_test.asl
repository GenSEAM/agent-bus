(module asl-agent-bus/tests/proc-telemetry-test
  :d "Falsifiable test suite for process telemetry registry, locus tracing, and ND-ASN serialization."
  :x [test-descriptor-creation
      test-registry-lifecycle
      test-lane-filtering
      test-serialization-nd-asn
      test-health-audit
      run-tests]
  :i [(proc-telemetry :a pt)
      (bus :a b)])

(df test-descriptor-creation [] -> Bool
  :d "Asserts process descriptor initialization and field invariants."
  (let [(locus (pt/make-proc-locus "gates/runner.asl" 42 "run-all-gates"))
        (p (pt/make-proc-descriptor 1001 "task-328-1" "main" 10000 10250 33554432 locus "running"))]
    (assert (= (.-pid p) 1001) "pid must equal 1001")
    (assert (= (.-task-id p) "task-328-1") "task-id must match")
    (assert (= (.-lane p) "main") "lane must be main")
    (assert (= (.-started-ms p) 10000) "started-ms must match")
    (assert (= (.-elapsed-ms p) 250) "elapsed-ms must be 250")
    (assert (= (.-rss-bytes p) 33554432) "rss-bytes must match")
    (assert (string-contains? (.-locus p) "gates/runner.asl") "locus must contain file path")
    (assert (= (.-status p) "running") "status must be running")
    true))

(df test-registry-lifecycle [] -> Bool
  :d "Asserts registry registration, updating, and removal mechanics."
  (let [(reg0 (pt/empty-proc-registry))
        (p1 (pt/make-proc-descriptor 101 "task-1" "main" 1000 1100 1024 "file.asl:10:fn1" "running"))
        (p2 (pt/make-proc-descriptor 102 "task-2" "fast" 1000 1050 2048 "file.asl:20:fn2" "running"))
        (reg1 (pt/record-proc-telemetry reg0 p1))
        (reg2 (pt/record-proc-telemetry reg1 p2))]
    (assert (= (list-length (.-procs reg0)) 0) "Empty registry has 0 procs")
    (assert (= (list-length (.-procs reg1)) 1) "reg1 has 1 proc")
    (assert (= (list-length (.-procs reg2)) 2) "reg2 has 2 procs")
    (let [(found (pt/find-proc-by-id reg2 101))]
      (assert (= (list-length found) 1) "find-proc-by-id must return exactly 1 proc")
      (assert (= (.-task-id (.-value (list-head found))) "task-1") "found proc task-id must match"))
    (let [(p1-up (pt/update-proc-locus p1 "file.asl:99:fn1" 1500))
          (reg3 (pt/record-proc-telemetry reg2 p1-up))]
      (assert (= (list-length (.-procs reg3)) 2) "Updating proc must preserve registry size")
      (assert (= (.-elapsed-ms p1-up) 500) "Updated proc must recalculate elapsed time"))
    (let [(reg4 (pt/remove-proc-telemetry reg2 101))]
      (assert (= (list-length (.-procs reg4)) 1) "Removed proc must leave 1 item in registry")
      (assert (= (list-length (pt/find-proc-by-id reg4 101)) 0) "Removed proc must not be found"))
    true))

(df test-lane-filtering [] -> Bool
  :d "Asserts lane-specific process filtering."
  (let [(p1 (pt/make-proc-descriptor 1 "t1" "main" 100 110 500 "l1" "running"))
        (p2 (pt/make-proc-descriptor 2 "t2" "fast" 100 120 500 "l2" "running"))
        (p3 (pt/make-proc-descriptor 3 "t3" "main" 100 130 500 "l3" "running"))
        (reg (pt/record-proc-telemetry (pt/record-proc-telemetry (pt/record-proc-telemetry (pt/empty-proc-registry) p1) p2) p3))
        (main-procs (pt/filter-procs-by-lane reg "main"))
        (fast-procs (pt/filter-procs-by-lane reg "fast"))
        (batch-procs (pt/filter-procs-by-lane reg "batch"))]
    (assert (= (list-length main-procs) 2) "main lane must have 2 procs")
    (assert (= (list-length fast-procs) 1) "fast lane must have 1 proc")
    (assert (= (list-length batch-procs) 0) "batch lane must have 0 procs")
    (assert (= (.-pid (.-value (list-head fast-procs))) 2) "fast lane proc pid must be 2")
    true))

(df test-serialization-nd-asn [] -> Bool
  :d "Asserts ND-ASN wire serialization of process telemetry."
  (let [(p1 (pt/make-proc-descriptor 201 "task-gate" "main" 500 550 16777216 "gate.asl:15:audit" "running"))
        (p2 (pt/make-proc-descriptor 202 "task-test" "fast" 500 580 8388608 "test.asl:30:eval" "done"))
        (s1 (pt/serialize-proc-ps-entry p1))
        (reg (pt/record-proc-telemetry (pt/record-proc-telemetry (pt/empty-proc-registry) p1) p2))
        (nd (pt/serialize-proc-registry-ps reg))
        (top (pt/serialize-proc-top reg))]
    (assert (string-contains? s1 ":proc") "Serialized entry must start with :proc")
    (assert (string-contains? s1 ":pid 201") "Serialized entry must contain pid")
    (assert (string-contains? s1 ":task-id \"task-gate\"") "Serialized entry must contain task-id")
    (assert (string-contains? s1 ":lane \"main\"") "Serialized entry must contain lane")
    (assert (string-contains? s1 ":status \"running\"") "Serialized entry must contain status")
    (assert (string-contains? nd "task-gate") "ND-ASN must contain first proc")
    (assert (string-contains? nd "task-test") "ND-ASN must contain second proc")
    (assert (string-contains? top "Process Plane Top: 2 active task(s)") "Top view must format active task count")
    true))

(df test-health-audit [] -> Bool
  :d "Asserts execution timeout and failure state detection."
  (let [(healthy (pt/make-proc-descriptor 1 "t1" "main" 0 50 100 "loc" "running"))
        (timed-out (pt/make-proc-descriptor 2 "t2" "main" 0 2500 100 "loc" "running"))
        (failed (pt/make-proc-descriptor 3 "t3" "main" 0 50 100 "loc" "failed"))]
    (assert (pt/audit-proc-health healthy 1000) "Healthy proc within limit must pass")
    (assert (not (pt/audit-proc-health timed-out 1000)) "Timed out proc must fail health audit")
    (assert (not (pt/audit-proc-health failed 1000)) "Failed status proc must fail health audit")
    true))

(df run-tests [] -> Bool
  :d "Master test runner for process telemetry test suite."
  (and (test-descriptor-creation)
       (and (test-registry-lifecycle)
            (and (test-lane-filtering)
                 (and (test-serialization-nd-asn)
                      (test-health-audit))))))
