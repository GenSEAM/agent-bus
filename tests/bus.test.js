import test from "node:test";
import assert from "node:assert/strict";
import { AgentBusServer } from "../bridges/ts/index.ts";
import { IpcTransport } from "../bridges/ipc_transport.js";

test("AgentBusServer - Peer Lifecycle & SSE Framing", () => {
  const server = new AgentBusServer();

  let registeredPeer = null;
  server.on("peer:registered", (p) => {
    registeredPeer = p;
  });

  server.registerPeer({
    id: "agent-eddie-1",
    name: "EDDIE Swarm Layer 1",
    role: "orchestrator",
    status: "idle",
    lastPing: Date.now()
  });

  assert.ok(registeredPeer !== null);
  assert.equal(registeredPeer.id, "agent-eddie-1");

  const peers = server.getPeers();
  assert.equal(peers.length, 1);
  assert.equal(peers[0].name, "EDDIE Swarm Layer 1");

  // SSE Framing
  const sse = server.formatSSE("delta", { change: "tree_mutated", count: 42 });
  assert.match(sse, /^event: delta\ndata: \{"change":"tree_mutated","count":42\}\n\n$/);
});

test("IpcTransport - Direct Point-to-Point Messaging & Latency", () => {
  const transport = new IpcTransport();

  transport.registerNode({ id: "planner", role: "planner", tier: "layer-2" });
  transport.registerNode({ id: "coder", role: "coder", tier: "worker" });

  let receivedPacket = null;
  transport.on("packet:coder", (pkt) => {
    receivedPacket = pkt;
  });

  const t0 = performance.now();
  const sent = transport.sendDirect("planner", "coder", { task: "implement-vad", files: ["src/vad.asl"] });
  const latency = performance.now() - t0;

  assert.equal(sent, true);
  assert.ok(receivedPacket !== null);
  assert.equal(receivedPacket.from, "planner");
  assert.equal(receivedPacket.to, "coder");
  assert.deepEqual(receivedPacket.payload, { task: "implement-vad", files: ["src/vad.asl"] });
  assert.ok(latency < 1.0, `Packet delivery latency ${latency}ms must be < 1ms`);

  const drained = transport.receive("coder");
  assert.equal(drained.length, 1);
  assert.equal(transport.receive("coder").length, 0); // Inbox emptied

  transport.close();
});

test("IpcTransport - Pub/Sub Channel Broadcast & Clean Teardown", () => {
  const transport = new IpcTransport();

  transport.registerNode({ id: "eddie", role: "orchestrator" });
  transport.registerNode({ id: "worker-1", role: "worker" });
  transport.registerNode({ id: "worker-2", role: "worker" });

  transport.subscribe("planning-channel", "worker-1");
  transport.subscribe("planning-channel", "worker-2");

  const deliveredCount = transport.broadcast("eddie", "planning-channel", { event: "new_phase_ready" });
  assert.equal(deliveredCount, 2);

  const w1Packets = transport.receive("worker-1");
  const w2Packets = transport.receive("worker-2");
  assert.equal(w1Packets.length, 1);
  assert.equal(w2Packets.length, 1);
  assert.equal(w1Packets[0].payload.event, "new_phase_ready");

  // Clean teardown
  transport.close();
  assert.equal(transport.closed, true);
  assert.equal(transport.nodes.size, 0);
  assert.equal(transport.channels.size, 0);
});
