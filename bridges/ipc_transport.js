/**
 * High-Throughput In-Memory & IPC Mesh Transport Bridge
 * Provides sub-millisecond A2A message routing, pub/sub channels, and descriptor leak prevention.
 */
import { EventEmitter } from "events";

export class IpcTransport extends EventEmitter {
  constructor(options = {}) {
    super();
    this.options = {
      maxQueuePerAgent: options.maxQueuePerAgent || 1000,
      ...options
    };
    this.nodes = new Map(); // id -> MeshNode
    this.channels = new Map(); // channelName -> Set<nodeId>
    this.inboxes = new Map(); // nodeId -> Array<Packet>
    this.metrics = {
      messagesSent: 0,
      broadcastsSent: 0,
      totalLatencyMs: 0
    };
    this.closed = false;
  }

  registerNode(node) {
    if (this.closed) throw new Error("Transport is closed");
    this.nodes.set(node.id, {
      ...node,
      isAlive: true,
      lastSeen: Date.now()
    });
    if (!this.inboxes.has(node.id)) {
      this.inboxes.set(node.id, []);
    }
    this.emit("node:joined", node);
  }

  unregisterNode(nodeId) {
    this.nodes.delete(nodeId);
    this.inboxes.delete(nodeId);
    for (const subscribers of this.channels.values()) {
      subscribers.delete(nodeId);
    }
    this.emit("node:left", nodeId);
  }

  subscribe(channel, nodeId) {
    if (!this.channels.has(channel)) {
      this.channels.set(channel, new Set());
    }
    this.channels.get(channel).add(nodeId);
  }

  unsubscribe(channel, nodeId) {
    if (this.channels.has(channel)) {
      this.channels.get(channel).delete(nodeId);
    }
  }

  /**
   * Send direct point-to-point packet
   */
  sendDirect(from, to, payload) {
    if (this.closed) return false;
    const t0 = performance.now();
    const packet = {
      id: `pkt-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      from,
      to,
      payload,
      timestamp: Date.now()
    };

    const inbox = this.inboxes.get(to);
    if (inbox) {
      if (inbox.length >= this.options.maxQueuePerAgent) {
        inbox.shift(); // Evict oldest on overflow
      }
      inbox.push(packet);
    }

    const dt = performance.now() - t0;
    this.metrics.messagesSent++;
    this.metrics.totalLatencyMs += dt;

    this.emit(`packet:${to}`, packet);
    this.emit("packet", packet);
    return true;
  }

  /**
   * Broadcast message to channel or all nodes
   */
  broadcast(from, channel, payload) {
    if (this.closed) return 0;
    const packet = {
      id: `bcast-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      from,
      channel,
      payload,
      timestamp: Date.now()
    };

    let delivered = 0;
    const targets = channel && this.channels.has(channel)
      ? this.channels.get(channel)
      : this.nodes.keys();

    for (const targetId of targets) {
      if (targetId === from) continue;
      const inbox = this.inboxes.get(targetId);
      if (inbox) {
        inbox.push(packet);
        delivered++;
      }
    }

    this.metrics.broadcastsSent++;
    this.emit(`broadcast:${channel}`, packet);
    this.emit("broadcast", packet);
    return delivered;
  }

  receive(nodeId) {
    const inbox = this.inboxes.get(nodeId);
    if (!inbox || inbox.length === 0) return [];
    return inbox.splice(0, inbox.length);
  }

  close() {
    this.closed = true;
    this.nodes.clear();
    this.channels.clear();
    this.inboxes.clear();
    this.removeAllListeners();
  }
}
