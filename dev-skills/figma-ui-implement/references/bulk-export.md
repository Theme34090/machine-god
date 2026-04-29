# Bulk export via WS bridge

When the user explicitly asks Claude to export Figma assets directly ("export those yourself", "grab the PNGs", "you have export_node_as_image"), use the bundled `scripts/figma-export.mjs`. Default behavior elsewhere is to ask the user to drag-export from Figma — only reach for this on explicit request.

Reproduced working as of 2026-04-26.

## Why this exists

The TalkToFigma MCP and the Figma plugin both speak to a Bun WebSocket bridge on `ws://localhost:3055` and forward messages by `channel`. The MCP wrapper of `export_node_as_image` returns `imageData` (base64 PNG) inline and discards it; a direct WS client on the same channel can read that field and `writeFileSync` the bytes.

Bridge source for protocol reference: `~/work/cursor-talk-to-figma-mcp/dist/server.js`.

## Recipe

1. Confirm a channel is joined (`get_document_info` errors with "Must join a channel" otherwise) and ask the user for the channel name + the node IDs + filenames.

2. Run the bundled script:

   ```bash
   FIGMA_CHANNEL=<channel> \
   FIGMA_NODES='[{"id":"3758:78252","filename":"slide-1-hero.png"}]' \
   OUT_DIR=apps/frontend/public/assets/<feature> \
   node ~/.claude/skills/figma-ui-implement/scripts/figma-export.mjs
   ```

   `FIGMA_NODES` is a JSON array of `{id, filename}` pairs. Files are written to `OUT_DIR` (defaults to `/tmp`).

## Gotchas

- The MCP must already be joined to the same channel for the bridge to route messages. If you skipped `join_channel` earlier in the session, do it before running.
- The `commandId` field inside `params` is required by the bridge protocol even though it duplicates the outer `id`. The bundled script already does this; only relevant if you're rewriting it.
- Don't `import 'ws'` — Node 22+ has built-in `WebSocket`, so no `npm install` is needed and the script runs from anywhere.
- 60-second per-call timeout. For large batches, split into chunks.
