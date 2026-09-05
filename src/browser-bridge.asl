(module asl-bus/browser-bridge
  :d "Pure ASL Local Bridge Server: routes MCP commands from desktop agents to in-browser extensions with permissive CORS."
  :x [BridgeTab
      BridgeCommand
      BrowserBridgeState
      bridge-init
      bridge-register-tab
      bridge-enqueue-command
      bridge-poll-commands
      bridge-complete-command
      handle-mcp-request
      format-cors-http-response]
  :i [(core/strings :a s)])

(dfs BridgeTab
  (:f tab-id Str "Unique tab identifier")
  (:f url Str "Active tab URL")
  (:f title Str "Active tab title")
  (:f connected-at I64 "Registration timestamp"))

(dfs BridgeCommand
  (:f id Str "Command UUID")
  (:f tab-id Str "Target tab identifier")
  (:f action Str "Target action: browser_get_dom, browser_click, browser_type, browser_eval, browser_run_slm")
  (:f payload Str "Action parameters in JSON/ASN")
  (:f status Str "pending | dispatched | completed | failed")
  (:f result Str "Execution output or error diagnostic"))

(dfs BrowserBridgeState
  (:f port I64 "Listening port, default 8765")
  (:f tabs (List BridgeTab) "Registered browser tabs")
  (:f commands (List BridgeCommand) "In-memory FIFO command queue"))

(df bridge-init [(port I64)] -> BrowserBridgeState
  :d "Initializes an empty browser bridge state on target port"
  (BrowserBridgeState
    :port port
    :tabs (list)
    :commands (list)))

(df bridge-register-tab [(state BrowserBridgeState) (tab BridgeTab)] -> BrowserBridgeState
  :d "Registers a new tab or updates metadata for an existing tab-id"
  (let [(existing (filter (fn [(t BridgeTab)] -> Bool
                            (!= (.-tab-id t) (.-tab-id tab)))
                          (.-tabs state)))
        (updated-tabs (list-append existing (list tab)))]
    (BrowserBridgeState
      :port (.-port state)
      :tabs updated-tabs
      :commands (.-commands state))))

(df bridge-enqueue-command [(state BrowserBridgeState) (cmd BridgeCommand)] -> BrowserBridgeState
  :d "Appends a new command with status pending to the FIFO queue"
  (BrowserBridgeState
    :port (.-port state)
    :tabs (.-tabs state)
    :commands (list-append (.-commands state) (list cmd))))

(df bridge-poll-commands [(state BrowserBridgeState) (tab-id Str)] -> (Pair BrowserBridgeState (List BridgeCommand))
  :d "Retrieves pending commands for target tab and atomically marks them as dispatched"
  (let [(pending-cmds (filter (fn [(c BridgeCommand)] -> Bool
                                (and (== (.-tab-id c) tab-id)
                                     (== (.-status c) "pending")))
                              (.-commands state)))
        (updated-commands (map (fn [(c BridgeCommand)] -> BridgeCommand
                                 (if (and (== (.-tab-id c) tab-id)
                                          (== (.-status c) "pending"))
                                     (BridgeCommand
                                       :id (.-id c)
                                       :tab-id (.-tab-id c)
                                       :action (.-action c)
                                       :payload (.-payload c)
                                       :status "dispatched"
                                       :result (.-result c))
                                     c))
                               (.-commands state)))]
    (pair (BrowserBridgeState
            :port (.-port state)
            :tabs (.-tabs state)
            :commands updated-commands)
          pending-cmds)))

(df bridge-complete-command [(state BrowserBridgeState) (cmd-id Str) (status Str) (result Str)] -> BrowserBridgeState
  :d "Updates target command status to completed or failed and records result output"
  (let [(updated-commands (map (fn [(c BridgeCommand)] -> BridgeCommand
                                 (if (== (.-id c) cmd-id)
                                     (BridgeCommand
                                       :id (.-id c)
                                       :tab-id (.-tab-id c)
                                       :action (.-action c)
                                       :payload (.-payload c)
                                       :status status
                                       :result result)
                                     c))
                               (.-commands state)))]
    (BrowserBridgeState
      :port (.-port state)
      :tabs (.-tabs state)
      :commands updated-commands)))

(df format-cors-http-response [(status-code I64) (content-type Str) (body Str)] -> Str
  :d "Formats standard HTTP/1.1 response with full CORS headers (origin, methods, headers)"
  (let [(cors-headers "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE\r\nAccess-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With")]
    (if (== status-code 204)
        (s/concat "HTTP/1.1 204 No Content\r\n"
                  (s/concat cors-headers "\r\nContent-Length: 0\r\n\r\n"))
        (let [(status-line (cond
                             ((== status-code 200) "HTTP/1.1 200 OK")
                             ((== status-code 400) "HTTP/1.1 400 Bad Request")
                             ((== status-code 404) "HTTP/1.1 404 Not Found")
                             (true "HTTP/1.1 500 Internal Server Error")))
              (body-len (string-length body))]
          (s/concat status-line "\r\n"
            (s/concat cors-headers "\r\n"
              (s/concat "Content-Type: " (s/concat content-type "\r\n"
                (s/concat "Content-Length: " (s/concat (str body-len) "\r\n\r\n"
                  body))))))))))

(df handle-mcp-request [(state BrowserBridgeState) (request-json Str)] -> (Pair BrowserBridgeState Str)
  :d "Handles MCP JSON-RPC 2.0 requests (initialize, tools/list, tools/call) and returns updated state and JSON response"
  (cond
    ((string-contains? request-json "\"method\":\"initialize\"")
     (pair state "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"asl-browser-bridge\",\"version\":\"1.0.0\"}}}"))
    ((string-contains? request-json "\"method\":\"tools/list\"")
     (let [(tools-json "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"browser_get_dom\",\"description\":\"Extract DOM or accessibility tree\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tabId\":{\"type\":\"string\"}},\"required\":[\"tabId\"]}},{\"name\":\"browser_click\",\"description\":\"Click element by CSS selector\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tabId\":{\"type\":\"string\"},\"selector\":{\"type\":\"string\"}},\"required\":[\"tabId\",\"selector\"]}},{\"name\":\"browser_type\",\"description\":\"Type text into element\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tabId\":{\"type\":\"string\"},\"selector\":{\"type\":\"string\"},\"text\":{\"type\":\"string\"}},\"required\":[\"tabId\",\"selector\",\"text\"]}},{\"name\":\"browser_eval\",\"description\":\"Evaluate JS script in tab\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tabId\":{\"type\":\"string\"},\"expression\":{\"type\":\"string\"}},\"required\":[\"tabId\",\"expression\"]}},{\"name\":\"browser_run_slm\",\"description\":\"Run on-device SLM inference in tab\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tabId\":{\"type\":\"string\"},\"prompt\":{\"type\":\"string\"}},\"required\":[\"tabId\",\"prompt\"]}}]}}")]
       (pair state tools-json)))
    ((string-contains? request-json "\"method\":\"tools/call\"")
     (let [(cmd-id (s/concat "cmd-" (str (+ (list-length (.-commands state)) 1))))
           (action (cond
                     ((string-contains? request-json "\"name\":\"browser_get_dom\"") "browser_get_dom")
                     ((string-contains? request-json "\"name\":\"browser_click\"") "browser_click")
                     ((string-contains? request-json "\"name\":\"browser_type\"") "browser_type")
                     ((string-contains? request-json "\"name\":\"browser_eval\"") "browser_eval")
                     ((string-contains? request-json "\"name\":\"browser_run_slm\"") "browser_run_slm")
                     (true "unknown")))
           (new-cmd (BridgeCommand
                      :id cmd-id
                      :tab-id "tab-active"
                      :action action
                      :payload request-json
                      :status "pending"
                      :result ""))
           (updated-state (bridge-enqueue-command state new-cmd))
           (resp-json (s/concat "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Enqueued command " (s/concat cmd-id (s/concat " for action " (s/concat action "\"}]}}")))))]
       (pair updated-state resp-json)))
    (true
     (pair state "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}"))))
