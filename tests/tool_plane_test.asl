(module asl-agent-bus/tool-plane-test
  :d "Unit tests for Agent Bus Tool Control Plane Router and Multi-Repo Scoping."
  :x [test-router-creation
      test-router-repo-scoping
      test-router-agent-authorization
      test-router-safety-ceiling
      test-router-secret-masking
      test-router-runbook-and-guidance
      run-tests]
  :i [(../../asl-contracts/src/tool_plane :a tp)
      (asl-agent-bus/tool-plane :a tpr)])

(df test-router-creation [] -> Bool
  :d "Verifies router construction with tool list."
  (let [(t1 (tp/make-tool-descriptor "t1" "Tool 1" "doc" "g1" (list "*") (list "*") (tp/safety-safe) "cmd1" (list) (map-empty) (list)))
        (router (tpr/make-tool-router (list t1)))
        (empty-router (tpr/make-tool-router (list)))]
    (do
      (assert (= (list-len (.-tools router)) 1) "router has 1 tool")
      (assert (= (list-len (.-tools empty-router)) 0) "empty router has 0 tools")
      (assert (not (option-some? (tpr/get-tool-runbook router "nonexistent"))) "unregistered tool runbook is none")
      true)))

(df test-router-repo-scoping [] -> Bool
  :d "Verifies multi-repo scope isolation when routing tools."
  (let [(t-asl (tp/make-tool-descriptor "t-asl" "ASL Tool" "doc" "g" (list "asl") (list "*") (tp/safety-safe) "asl" (list) (map-empty) (list)))
        (t-crawl (tp/make-tool-descriptor "t-crawl" "Crawler Tool" "doc" "g" (list "crawler") (list "*") (tp/safety-safe) "crawl" (list) (map-empty) (list)))
        (t-all (tp/make-tool-descriptor "t-all" "Global Tool" "doc" "g" (list "*") (list "*") (tp/safety-safe) "all" (list) (map-empty) (list)))
        (router (tpr/make-tool-router (list t-asl t-crawl t-all)))
        (ctx-asl (tp/make-scope-context "asl" "implementer" (tp/safety-dangerous)))
        (ctx-crawl (tp/make-scope-context "crawler" "implementer" (tp/safety-dangerous)))
        (routed-asl (tpr/route-tools router ctx-asl false))
        (routed-crawl (tpr/route-tools router ctx-crawl false))]
    (do
      (assert (= (list-len routed-asl) 2) "routed asl count is 2")
      (assert (= (list-len routed-crawl) 2) "routed crawl count is 2")
      true)))

(df test-router-agent-authorization [] -> Bool
  :d "Verifies agent role permissions enforcement when routing tools."
  (let [(t-dev (tp/make-tool-descriptor "t-dev" "Dev Tool" "doc" "g" (list "*") (list "implementer") (tp/safety-safe) "dev" (list) (map-empty) (list)))
        (t-rev (tp/make-tool-descriptor "t-rev" "Review Tool" "doc" "g" (list "*") (list "reviewer") (tp/safety-safe) "rev" (list) (map-empty) (list)))
        (t-pub (tp/make-tool-descriptor "t-pub" "Public Tool" "doc" "g" (list "*") (list "*") (tp/safety-safe) "pub" (list) (map-empty) (list)))
        (router (tpr/make-tool-router (list t-dev t-rev t-pub)))
        (ctx-impl (tp/make-scope-context "asl" "implementer" (tp/safety-dangerous)))
        (ctx-rev (tp/make-scope-context "asl" "reviewer" (tp/safety-dangerous)))
        (routed-impl (tpr/route-tools router ctx-impl false))
        (routed-rev (tpr/route-tools router ctx-rev false))]
    (do
      (assert (= (list-len routed-impl) 2) "routed impl count is 2")
      (assert (= (list-len routed-rev) 2) "routed rev count is 2")
      true)))

(df test-router-safety-ceiling [] -> Bool
  :d "Verifies that dangerous tools are excluded when context safety ceiling is guarded or safe."
  (let [(t-safe (tp/make-tool-descriptor "ts" "Safe" "d" "g" (list "*") (list "*") (tp/safety-safe) "s" (list) (map-empty) (list)))
        (t-guard (tp/make-tool-descriptor "tg" "Guarded" "d" "g" (list "*") (list "*") (tp/safety-guarded) "g" (list) (map-empty) (list)))
        (t-dang (tp/make-tool-descriptor "td" "Dangerous" "d" "g" (list "*") (list "*") (tp/safety-dangerous) "d" (list) (map-empty) (list)))
        (router (tpr/make-tool-router (list t-safe t-guard t-dang)))
        (ctx-safe (tp/make-scope-context "asl" "implementer" (tp/safety-safe)))
        (ctx-guard (tp/make-scope-context "asl" "implementer" (tp/safety-guarded)))
        (ctx-dang (tp/make-scope-context "asl" "implementer" (tp/safety-dangerous)))]
    (do
      (assert (= (tpr/count-routed-tools router ctx-safe) 1) "safe count is 1")
      (assert (= (tpr/count-routed-tools router ctx-guard) 2) "guard count is 2")
      (assert (= (tpr/count-routed-tools router ctx-dang) 3) "dang count is 3")
      true)))

(df test-router-secret-masking [] -> Bool
  :d "Verifies that secret masking strips secrets on routed descriptors when requested."
  (let [(sec (tp/make-secret-ref "KEY" "env" "API_KEY" "def"))
        (env-map (map-set (map-empty) "API_KEY" "secret_value"))
        (t-sec (tp/make-tool-descriptor "t-sec" "Secured" "doc" "g" (list "*") (list "*") (tp/safety-safe) "cmd" (list) env-map (list sec)))
        (router (tpr/make-tool-router (list t-sec)))
        (ctx (tp/make-scope-context "asl" "implementer" (tp/safety-safe)))
        (masked-tools (tpr/route-tools router ctx true))
        (masked-t (list-head masked-tools))]
    (do
      (assert (= (list-len masked-tools) 1) "masked tools count is 1")
      (assert (.-redacted masked-t) "tool is redacted")
      (assert (= (list-len (.-secrets masked-t)) 0) "secrets list is empty")
      true)))

(df test-router-runbook-and-guidance [] -> Bool
  :d "Verifies guidance retrieval and runbook registration/lookup."
  (let [(t1 (tp/make-tool-descriptor "t-run" "Runner" "doc" "Run only after git status is clean" (list "*") (list "*") (tp/safety-safe) "run" (list) (map-empty) (list)))
        (rb (tp/make-runbook "rb-01" "Deployment Runbook" (list "step 1" "step 2")))
        (r0 (tpr/make-tool-router (list t1)))
        (r1 (tpr/register-tool-runbook r0 "t-run" rb))
        (guidance (tpr/get-tool-guidance r1 "t-run"))
        (found-rb (tpr/get-tool-runbook r1 "t-run"))]
    (do
      (assert (= guidance "Run only after git status is clean") "guidance matches")
      (assert (option-some? found-rb) "runbook is found")
      (assert (= (.-id (option-unwrap found-rb)) "rb-01") "runbook id matches")
      true)))

(df run-tests [] -> Bool
  :d "Executes agent bus tool plane unit test suite."
  (do
    (test-router-creation)
    (test-router-repo-scoping)
    (test-router-agent-authorization)
    (test-router-safety-ceiling)
    (test-router-secret-masking)
    (test-router-runbook-and-guidance)
    true))
