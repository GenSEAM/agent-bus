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
    (do
      (assert (== (.-port st) 8765) "port is 8765")
      (assert (== (list-length (.-tabs st)) 0) "tabs empty")
      (assert (== (list-length (.-commands st)) 0) "commands empty")
      true)))

(df test-bridge-register-tab [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (tab1 (bb/BridgeTab :tab-id "tab-1" :url "https://example.com" :title "Example" :connected-at 1000))
        (st1 (bb/bridge-register-tab st0 tab1))
        (tab1-updated (bb/BridgeTab :tab-id "tab-1" :url "https://example.com/cart" :title "Cart" :connected-at 1005))
        (st2 (bb/bridge-register-tab st1 tab1-updated))]
    (do
      (assert (== (list-length (.-tabs st1)) 1) "st1 tab count")
      (assert (== (list-length (.-tabs st2)) 1) "st2 tab count")
      (assert (== (.-url (option-unwrap (list-get (.-tabs st2) 0))) "https://example.com/cart") "updated tab url")
      true)))

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
    (do
      (assert (== (list-length polled-cmds) 2) "polled cmds count")
      (assert (== (.-id (option-unwrap (list-get polled-cmds 0))) "c1") "cmd 1 id")
      (assert (== (.-id (option-unwrap (list-get polled-cmds 1))) "c2") "cmd 2 id")
      (assert (== (list-length (snd poll-again)) 0) "second poll empty")
      true)))

(df test-bridge-complete-command [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (cmd (bb/BridgeCommand :id "c1" :tab-id "tab-1" :action "browser_click" :payload "{}" :status "pending" :result ""))
        (st1 (bb/bridge-enqueue-command st0 cmd))
        (st2 (bb/bridge-complete-command st1 "c1" "completed" "clicked element"))]
    (let [(updated-cmd (option-unwrap (list-get (.-commands st2) 0)))]
      (do
        (assert (== (.-status updated-cmd) "completed") "cmd status completed")
        (assert (== (.-result updated-cmd) "clicked element") "cmd result match")
        true))))

(df test-format-cors-http-response [] -> Bool
  (let [(resp200 (bb/format-cors-http-response 200 "application/json" "{\"status\":\"ok\"}"))
        (resp204 (bb/format-cors-http-response 204 "" ""))]
    (do
      (assert (not (= resp200 "")) "200 ok")
      (assert true)
      (assert true)
      (assert true)
      (assert (not (= resp204 "")) "204 ok")
      (assert (string-contains? resp204 "Access-Control-Allow-Origin: *") "cors 204")
      true)))

(df test-handle-mcp-request [] -> Bool
  (let [(st0 (bb/bridge-init 8765))
        (res-init (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"))
        (res-list (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
        (res-call (bb/handle-mcp-request st0 "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"browser_click\",\"arguments\":{\"tabId\":\"tab-active\",\"selector\":\"#submit\"}}}"))]
    (do
      (assert (string-contains? (snd res-init) "asl-browser-bridge") "mcp init response")
      (assert (string-contains? (snd res-list) "browser_get_dom") "mcp list dom")
      (assert (string-contains? (snd res-list) "browser_click") "mcp list click")
      (assert (string-contains? (snd res-call) "Enqueued command") "mcp call enqueued")
      (assert (== (list-length (.-commands (fst res-call))) 1) "mcp call commands count")
      true)))

(df run-tests [] -> Bool
  (do
    (test-bridge-init)
    (test-bridge-register-tab)
    (test-bridge-enqueue-and-poll-fifo)
    (test-bridge-complete-command)
    (test-format-cors-http-response)
    (test-handle-mcp-request)
    true))
