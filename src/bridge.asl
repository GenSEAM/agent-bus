(module asl-bus/bridge
  :d "Minimal Single-Tool Swarm Bridge for External Agents (Claude Code, Cursor, Windsurf) Connecting to ASL Bus."
  :x [ExternalToolCommand
      bridge-connect-external
      format-external-tool-schema
      dispatch-external-command]
  :i [(presence :a p)])

(dfs ExternalToolCommand
  (:f action Str "join-room, list-peers, propose-task, accept-task, decline-task")
  (:f agent-id Str "Caller external agent identifier")
  (:f room-name Str "Target swarm room")
  (:f payload Str "Action-specific parameters in ASN format"))

(df bridge-connect-external [(agent-id Str) (role Str) (room Str) (caps (List Str))] -> p/SwarmPeer
  :d "Registers an external AI agent into the ASL swarm presence bus."
  (p/SwarmPeer
    :agent-id agent-id
    :role role
    :room room
    :status (p/status-idle)
    :capabilities caps
    :last-ping-epoch 1757160000))

(df format-external-tool-schema [] -> Str
  :d "Renders the single canonical tool schema for external agents to interface with the ASL Swarm Bus."
  (str "{\n"
       "  \"name\": \"asl_swarm_bus\",\n"
       "  \"description\": \"Single entry point to connect, discover peers, and negotiate tasks on the ASL Swarm Bus\",\n"
       "  \"parameters\": {\n"
       "    \"type\": \"object\",\n"
       "    \"properties\": {\n"
       "      \"action\": { \"type\": \"string\", \"enum\": [\"join-room\", \"list-peers\", \"propose-task\", \"accept-task\", \"decline-task\"] },\n"
       "      \"room_name\": { \"type\": \"string\" },\n"
       "      \"payload\": { \"type\": \"string\" }\n"
       "    },\n"
       "    \"required\": [\"action\", \"room_name\"]\n"
       "  }\n"
       "}"))

(df dispatch-external-command [(room p/SwarmRoom) (cmd ExternalToolCommand)] -> Str
  :d "Dispatches an external tool command against the active swarm room."
  (let [(action (.-action cmd))]
    (cond
      ((= action "list-peers")
       (p/format-presence-roster room))
      ((= action "join-room")
       (let [(peer (bridge-connect-external (.-agent-id cmd) "external-worker" (.-room-name cmd) (list "general-tasks")))]
         (str "Successfully joined room " (.-room-name cmd) " as " (.-agent-id cmd))))
      (:else
       (str "Acknowledged " action " for " (.-agent-id cmd))))))
