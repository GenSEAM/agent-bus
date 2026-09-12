(module asl-agent-bus/tool-plane
  :d "Agent Bus Tool Control Plane Router: multi-repo routing, agent role access control, safety enforcement, and runbook orchestration."
  :x [ToolRouter
      make-tool-router
      register-tool-runbook
      get-tool-runbook
      get-tool-guidance
      is-tool-eligible?
      route-tools
      count-routed-tools]
  :i [(../../asl-contracts/src/tool_plane :a tp)])

(dfs ToolRouter
  (:f tools (List ToolDescriptor) "Registered tool descriptors")
  (:f runbooks (Map Str ToolRunbook) "Catalog of tool operational runbooks"))

(df make-tool-router [(tools (List ToolDescriptor))] -> ToolRouter
  :d "Instantiates a tool router managing the provided list of tool descriptors."
  (ToolRouter
    :tools tools
    :runbooks (map-empty)))

(df register-tool-runbook [(router ToolRouter) (tool-id Str) (runbook ToolRunbook)] -> ToolRouter
  :d "Associates an operational runbook with a specific tool identifier."
  (ToolRouter
    :tools (.-tools router)
    :runbooks (map-set (.-runbooks router) tool-id runbook)))

(df get-tool-runbook [(router ToolRouter) (tool-id Str)] -> Option
  :d "Retrieves operational runbook for a tool if registered."
  (if (map-has? (.-runbooks router) tool-id)
    (some (map-get (.-runbooks router) tool-id))
    (none)))

(df get-tool-guidance [(router ToolRouter) (tool-id Str)] -> Str
  :d "Retrieves guidance instructions for the specified tool."
  (let [(matches (list-filter (fn [t] (= (.-id t) tool-id)) (.-tools router)))]
    (if (list-empty? matches)
      ""
      (.-guidance (list-head matches)))))

(df is-tool-eligible? [(tool ToolDescriptor) (ctx ToolScopeContext)] -> Bool
  :d "Evaluates whether tool matches active repository, agent role, and safety ceiling."
  (and (tp/is-tool-in-scope? tool (.-active-repo ctx))
       (and (tp/is-agent-authorized? tool (.-agent-role ctx))
            (tp/is-safety-permitted? tool (.-safety-ceiling ctx)))))

(df route-tools [(router ToolRouter) (ctx ToolScopeContext) (redact? Bool)] -> (List ToolDescriptor)
  :d "Filters tools according to context invariants and applies secret masking if requested."
  (let [(filtered (list-filter (fn [t] (is-tool-eligible? t ctx)) (.-tools router)))]
    (if redact?
      (list-map (fn [t] (tp/mask-tool-secrets t)) filtered)
      filtered)))

(df count-routed-tools [(router ToolRouter) (ctx ToolScopeContext)] -> I64
  :d "Returns number of accessible tools for the given execution context."
  (list-len (route-tools router ctx false)))
