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
//   OUT_DIR        — output directory (REQUIRED, must be absolute path)
//   SCALE          — @Nx export scale (default: 2)
//
// Bridge protocol reference: ~/work/cursor-talk-to-figma-mcp/dist/server.js

import { writeFileSync, mkdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';

const CHANNEL = process.env.FIGMA_CHANNEL;
const NODES = JSON.parse(process.env.FIGMA_NODES);
const OUT_DIR = process.env.OUT_DIR;
if (!OUT_DIR || !path.isAbsolute(OUT_DIR)) {
  console.error('FATAL: OUT_DIR must be set to an absolute path. A relative path resolves against cwd and silently creates nested junk dirs if a prior `cd` ran in this shell. Got: ' + JSON.stringify(OUT_DIR));
  process.exit(2);
}
console.log('OUT_DIR resolved to:', OUT_DIR);
mkdirSync(OUT_DIR, { recursive: true });

const SCALE = Number(process.env.SCALE) || 2;
// Plugin (cursor_mcp_plugin/code.js) hardcodes format='PNG' and discards SVG/JPG/PDF.
// Caller's format param never reaches Figma — do not pretend otherwise.

const ws = new WebSocket('ws://localhost:3055');
const pending = new Map();
const failed = [];

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
  for (const { id: nodeId, filename } of NODES) {
    const res = await send('export_node_as_image', { nodeId, format: 'PNG', scale: SCALE });
    const buf = Buffer.from(res.imageData, 'base64');
    const filePath = `${OUT_DIR}/${filename}`;
    writeFileSync(filePath, buf);
    // PNG IHDR at byte offset 16: 4 bytes width + 4 bytes height, big-endian.
    const width  = buf.length >= 24 ? buf.readUInt32BE(16) : 0;
    const height = buf.length >= 24 ? buf.readUInt32BE(20) : 0;
    if (buf.length < 1024 || width < 8 || height < 8) {
      failed.push({ nodeId, filename, bytes: buf.length, width, height });
      console.error(`ASSET_INVALID ${nodeId} ${filename} ${buf.length}B ${width}x${height}`);
      continue;
    }
    console.log(`wrote ${filePath} (${buf.length} bytes, ${width}x${height})`);
  }
  ws.close();
  if (failed.length) {
    console.error('Bulk export had ' + failed.length + ' invalid asset(s):');
    for (const f of failed) console.error('  ' + JSON.stringify(f));
    console.error('Do NOT silently substitute or drop these. Surface to the user and request drag-export.');
    process.exit(2);
  }
  process.exit(0);
});

ws.addEventListener('error', (e) => { console.error('ws error', e?.message ?? e); process.exit(1); });
