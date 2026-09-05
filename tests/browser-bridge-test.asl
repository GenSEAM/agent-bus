(module asl-bus-tests/browser-bridge-test
  :d "Unit tests for pure ASL local browser bridge server: tabs, FIFO queue, CORS, and MCP protocol"
  :x [test-bridge-init
      test-bridge-register-tab
      test-bridge-enqueue-and-poll-fifo
      test-bridge-complete-command
      test-format-cors-http-response
      test-handle-mcp-request
      run-tests]
  :i [(asl-bus/browser-bridge :a bb)
      (core/strings :a s)])

(df test-bridge-init [] -> Bool
  (let [(st (bb/bridge-init 8765))]
    (and (== (.-port st) 8765)
         (== (list-length (.-tabs st)) 0)
         (== (list-length (.-commands st)) 0))))

(df test-bridge-register-tab [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (tab1 (bb/BridgeTab :tab-id "tab-1" :url "https://example.com" :title "Example" :connected-at 1000))
        (st1 (bb/bridge-register-tab st0 tab1))
        (tab1-updated (bb/BridgeTab :tab-id "tab-1" :url "https://example.com/cart" :title "Cart" :connected-at 1005))
        (st2 (bb/bridge-register-tab st1 tab1-updated))]
    (and (== (list-length (.-tabs st1)) 1)
         (== (list-length (.-tabs st2)) 1)
         (== (.-url (option-unwrap (list-get (.-tabs st2) 0))) "https://example.com/cart"))))

(df test-bridge-enqueue-and-poll-fifo [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (cmd1 (bb/BridgeCommand :id "c1" :tab-id "tab-1" :action "browser_get_dom" :payload "{}" :status "pending" :result ""))
        (cmd2 (bb/BridgeCommand :id "c2" :tab-id "tab-1" :action "browser_click" :payload "{\"selector\":\"#btn\"}" :status "pending" :result ""))
        (cmd3 (bb/BridgeCommand :id "c3" :tab-id "tab-2" :action "browser_eval" :payload "{\"expression\":\"1+1\"}" :status "pending" :result ""))
        (st1 (bb/bridge-enqueue-command st0 cmd1))
        (st2 (bb/bridge-enqueue-command st1 cmd2))
        (st3 (bb/bridge-enqueue-command st2 cmd3))
        (poll-res (bb/bridge-poll-commands st3 "tab-1"))
        (st-polled (fst poll-res))
        (polled-cmds (snd poll-res))
        (poll-again (bb/bridge-poll-commands st-polled "tab-1"))]
    (and (== (list-length polled-cmds) 2)
         (== (.-id (option-unwrap (list-get polled-cmds 0))) "c1")
         (== (.-id (option-unwrap (list-get polled-cmds 1))) "c2")
         ;; second poll yields 0 pending since they are dispatched
         (== (list-length (snd poll-again)) 0))))

(df test-bridge-complete-command [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (cmd (bb/BridgeCommand :id "c1" :tab-id "tab-1" :action "browser_click" :payload "{}" :status "pending" :result ""))
        (st1 (bb/bridge-enqueue-command st0 cmd))
        (st2 (bb/bridge-complete-command st1 "c1" "completed" "clicked element"))]
    (let [(updated-cmd (option-unwrap (list-get (.-commands st2) 0)))]
      (and (== (.-status updated-cmd) "completed")
           (== (.-result updated-cmd) "clicked element")))))

(df test-format-cors-http-response [] -> Bool
  (let [(resp200 (bb/format-cors-http-response 200 "application/json" "{\"status\":\"ok\"}"))
        (resp204 (bb/format-cors-http-response 204 "" ""))]
    (and (string-contains? resp200 "HTTP/1.1 200 OK")
         (string-contains? resp200 "Access-Control-Allow-Origin: *")
         (string-contains? resp200 "Access-Control-Allow-Methods:")
         (string-contains? resp200 "Content-Type: application/json")
         (string-contains? resp204 "HTTP/1.1 204 No Content")
         (string-contains? resp204 "Access-Control-Allow-Origin: *"))))

(df test-handle-mcp-request [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (res-init (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
        (res-list (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
        (res-call (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"browser_click\",\"arguments\":{\"tabId\":\"tab-active\",\"selector\":\"#submit\"}}}"))]
    (and (string-contains? (snd res-init) "asl-browser-bridge")
         (string-contains? (snd res-list) "browser_get_dom")
         (string-contains? (snd res-list) "browser_click")
         (string-contains? (snd res-call) "Enqueued command")
         (== (list-length (.-commands (fst res-call))) 1))))

(df run-tests [] -> Bool
  (and (test-bridge-init)
       (test-bridge-register-tab)
       (test-bridge-enqueue-and-poll-fifo)
       (test-bridge-complete-command)
       (test-format-cors-http-response)
       (test-handle-mcp-request)))
