#!/usr/bin/env node
// Bulk-export Figma nodes as PNG via the TalkToFigma WS bridge.
//
// Why this exists: the TalkToFigma MCP wrapper of `export_node_as_image` returns
// `imageData` (base64 PNG) inline and discards it. A direct WS client on the
// same channel can read that field and write the bytes to disk.
//
// Requires Node 22+ (built-in WebSocket). The MCP must already be joined to
// the same channel for the bridge to route messages.
//
// Env:
//   FIGMA_CHANNEL  — channel name (required)
//   FIGMA_NODES    — JSON: [{ "id": "123:456", "filename": "out.png" }, ...]
//   OUT_DIR        — output directory (default: /tmp)
//
// Bridge protocol reference: ~/work/cursor-talk-to-figma-mcp/dist/server.js

import { writeFileSync, mkdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const CHANNEL = process.env.FIGMA_CHANNEL;
const NODES = JSON.parse(process.env.FIGMA_NODES);
const OUT_DIR = process.env.OUT_DIR || '/tmp';
mkdirSync(OUT_DIR, { recursive: true });

const ws = new WebSocket('ws://localhost:3055');
const pending = new Map();

const send = (command, params) => new Promise((resolve, reject) => {
  const id = randomUUID();
  // `commandId` inside `params` is required by the bridge protocol even though
  // it duplicates the outer `id`.
  const payload = command === 'join'
    ? { id, type: 'join', channel: params.channel, message: { id, command, params: { ...params, commandId: id } } }
    : { id, type: 'message', channel: CHANNEL, message: { id, command, params: { ...params, commandId: id } } };
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify(payload));
  setTimeout(() => { if (pending.delete(id)) reject(new Error(`timeout: ${command}`)); }, 60_000);
});

ws.addEventListener('message', (ev) => {
  const j = JSON.parse(ev.data); if (j.type === 'progress_update') return;
  const r = j.message; const p = pending.get(r?.id); if (!p) return;
  pending.delete(r.id); r.error ? p.reject(new Error(r.error)) : p.resolve(r.result);
});

ws.addEventListener('open', async () => {
  await send('join', { channel: CHANNEL });
  for (const { id, filename } of NODES) {
    const res = await send('export_node_as_image', { nodeId: id, format: 'PNG', scale: 2 });
    const buf = Buffer.from(res.imageData, 'base64');
    writeFileSync(`${OUT_DIR}/${filename}`, buf);
    console.log(`wrote ${OUT_DIR}/${filename} (${buf.length} bytes)`);
  }
  ws.close(); process.exit(0);
});

ws.addEventListener('error', (e) => { console.error('ws error', e?.message ?? e); process.exit(1); });
