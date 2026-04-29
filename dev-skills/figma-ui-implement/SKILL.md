---
name: figma-ui-implement
description: Implement a UI screen or component from a Figma design with high visual fidelity, using the TalkToFigma MCP (`mcp__TalkToFigma__*`). Use whenever the user provides a Figma URL/node link and asks to build, code, implement, or match the design — or resumes work on a page that has a Figma source of truth. Trigger even if the user doesn't say "Figma" explicitly, as long as the task is "match this design". Also use when the user says "build this page", "code this up", "implement this screen", "pixel match", or similar alongside any design reference.
---

# Figma UI implementation

**At a glance:**
1. Phase 1 — subagent walks the Figma node via MCP, writes the design spec to `/tmp/figma-<node-id>.md`, returns a digest.
2. Phase 2 — main agent re-renders the node, reads the spec, reconciles with codebase tokens/components, writes code.
3. Verify visually in a real browser before declaring done.

We split Phase 1 out because Figma MCP exploration generates a lot of JSON noise and the screenshot-based visual read is lossy on its own. Running the noisy part in a subagent and passing back a distilled summary keeps the main agent's context clean for the part that actually matters — codebase reconciliation and writing code.

Throughout this skill, "figma mcp" means the **TalkToFigma** MCP (tools named `mcp__TalkToFigma__*`).

## Prerequisites

- figma mcp is connected. If not, stop and ask the user to connect it.
- A Figma channel has been joined via `join_channel`. If you hit "no active channel" errors, ask the user for the channel name.
- The user has given you one or more Figma URLs or node references (node IDs often look like `123:456`).

## Step 0 — Greenfield or defect-fix?

Before extracting the spec, decide which case you're in:

- **Greenfield**: the screen doesn't exist yet. Skip ahead to Phase 1.
- **Defect-fix**: the user is asking to "fix", "polish", or "match Figma" on an existing screen. Locate the existing implementation first — spawn an `Explore` subagent grepping for the screen's title/copy or the route path. The Phase 2 reconcile step is much sharper when you're matching against a known starting point instead of guessing.

Defect-fix is the more common case in practice. A two-line `Explore` query saves a round of "wait, where does this live?"

## Step 0.5 — Multi-screen jobs (N > 1 Figma URLs)

If the user provides multiple Figma URLs/nodes in a single prompt, treat the multi-screen case as the default. Detection of "related" vs "unrelated" is the main agent's job, with the user as tiebreaker — don't force them to declare it upfront.

- **Always parallel exploration.** Spawn one Phase 1 subagent per node in a single message. They're independent reads and you save wall-clock.
- **Always file-output.** Tell each subagent to write its full spec to `/tmp/figma-<node-id>.md` and return only the path + a 5-line digest. Subagent stdout clips on long outputs (observed at N=2 in real sessions); file paths don't.
- **Track per-screen progress** with `TaskCreate` when N > 2 — extract X / implement X / verify X. Easy to lose track in the middle otherwise.
- **Before writing code, scan all spec files for shared concerns.** Do multiple specs introduce the same new color, badge variant, or component pattern? Unify before duplicating. This is the cross-pollination move that only matters when N > 1 and the screens are related.
- **Single verification pass.** Local-e2e rebuild dominates iteration cost when N > 1. One bring-up, sequential per-screen screenshots in one browser session — never N separate cycles.
- **Commit/PR granularity.** If the specs look unrelated by surface (different folders, different features), flag this once and let the user decide one PR vs. multiple. Default to one PR if the user already said "fix in one go" or similar.

## Phase 1 — Subagent extracts the design spec

Spawn a **Sonnet** subagent (read-heavy, not reasoning-heavy) with figma mcp access. The prompt should instruct it to do all of the following.

### What the subagent does

1. **Walk the structure with MCP methods.** `get_document_info` → `get_node_info` / `get_nodes_info` → `scan_nodes_by_types` / `scan_text_nodes` → `get_styles` / `get_local_components`. This gives fills, typography, spacing, auto-layout, and named tokens.
2. **Render the node as an image.** Call `export_node_as_image` on the target frame. The MCP returns the PNG inline in the tool response, which the subagent sees visually. Use this to cross-check the JSON — it catches things JSON misses.
3. **Flatten JSON for speed.** Piping `get_node_info` through `jq` into a small Python walker that prints `TYPE:name [WxH] fill=#... fontSize=...` produces a ~150-line summary that's faster to reason about than raw nested JSON. Prefer this over scrolling the raw dump.
4. **Capture what JSON misses.** Effects — drop shadows, blurs, glass/blur backgrounds — are often absent from `get_node_info` or stripped behind style tokens. If the rendered image shows depth, floating, or shadows, capture it explicitly in the spec. The main agent only sees the digest plus its own inline render and will miss anything you don't name.
5. **Identify graphic assets.** Anything that is a picture rather than a layout — illustrations, logos, decorative images, complex/custom icons, charts, photographs, multi-path vector art — needs to come in as a real asset file. Describing it in words loses fidelity; rebuilding it in CSS always looks worse and burns time. The subagent can render each via `export_node_as_image` for its own visual check, but **cannot save to disk** (the MCP returns inline bytes only). For each such node, the subagent flags it in the spec with node ID + semantic name + short description; the main agent asks the user to drag-export it from Figma in Phase 2 if no matching asset is already in the codebase.

### Output: write to file, return only a digest

The subagent writes the full spec to `/tmp/figma-<node-id>.md` using the scaffold in `assets/figma-spec-template.md` (copy and fill in). Spec shape:

- **Layout**: page-level structure (header / main / card / footer), plus **surfaces and z-layers** (e.g., "card floats on #FAFAFA gray page surface with subtle shadow"). Do not skip — Phase 2 step 1 needs this.
- **Components**: top-to-bottom list; for each: dimensions, fill, corner radius, padding, gap, alignment.
- **Typography**: font-family, weight, size, line-height, color, per text style.
- **Colors**: hex values grouped by role (surface / text / accent / border).
- **Effects**: shadows, blurs, opacity — sourced from the rendered image, not JSON.
- **Copy**: all visible text, verbatim and in the original language. Do not translate.
- **Interaction hints**: buttons, links, hover states visible in the design.
- **Graphics**: per-node entries (node ID, semantic name, short description) for any picture/illustration/logo. If none, say so explicitly so the main agent doesn't go looking.

The subagent's stdout is just:

```
spec: /tmp/figma-<node-id>.md
graphics: <count> — <none | list of node-ids>
digest: <5-line layout summary>
```

This protects against stdout truncation. The main agent reads the spec file in Phase 2 when it needs it.

### Visual cross-check is the main agent's job

The MCP cannot save the design screenshot to disk. The subagent uses its own inline render to cross-check JSON. In Phase 2, the **main agent re-calls** `export_node_as_image` itself and reads the result inline — no round-trip via disk, no asking the user, no truncation worries.

## Phase 2 — Main agent implements

### Step 1: Render and narrate the screenshot

Call `export_node_as_image` yourself on the target node — the inline PNG appears in your tool result. Read the spec file (`/tmp/figma-<node-id>.md`).

Write a short top-to-bottom description in your own words.

**Call out surfaces and z-layers first.** Is this a flat page, or does a card float on a distinct background? Are there visual groupings created purely by surface color or shadow depth? Getting surfaces right on the first pass is the single biggest factor in matching the design, and it's the easiest thing to miss when you jump straight to component structure. If you're unsure, ask the user: "is this one flat page, or does the card float on a different bg?"

Then enumerate components top to bottom, matching the spec.

### Step 2: Reconcile with the existing codebase

Before writing any new CSS, variables, or component variants:

- **Grep the project's token file** (`globals.css` or equivalent) for existing CSS variables. Most of the palette is likely already defined — `--gray-25`, `--blue-main`, `--blue-lighter`, etc. The Figma palette usually maps 1:1.
- **Check existing component variants.** A matching `brand` badge, `brand-outline` button, etc. often already exists. Search for similar components (cards, step lists, CTA rows) and reuse their patterns.
- **Multi-screen: scan all spec files for repeated new tokens/components.** If two specs both introduce the same new color or badge style, unify before duplicating. Skipping this is how you end up with two near-identical CSS additions or two parallel components that should have been one.

Inventing inline hex colors or redefining tokens is a code-review smell. Match an existing variant first; introduce a new token only if nothing fits.

### Step 3: Wire graphic assets — do not rebuild them in HTML

If the spec lists graphics, the asset files have to live on disk somewhere in the project (e.g., `apps/frontend/public/images/...`). The MCP wrapper drops the bytes after returning them inline, so it cannot put them there for you. Either:

- Ask the user to drag-export the node from Figma and drop it into the assets directory, or
- Reuse an existing asset already in the codebase if the spec description matches one, or
- **On request only — bulk export via the WS bridge** (see `references/bulk-export.md` and `scripts/figma-export.mjs`). Do not reach for this unprompted; default to the drag-export ask.

Do **not** attempt to reproduce illustrations, logos, charts, or multi-path icons in HTML/CSS — it always looks worse than the exported asset, burns time, and hides the fact that a real asset was available. The only exceptions are:

- A primitive shape (solid circle, stroked line, simple geometric accent) clearly built from CSS.
- An icon that already exists in the project's icon library — reuse that instead of a Figma export.

If you find yourself reaching for nested divs with `border-radius` and gradients to approximate a shape you saw in the screenshot, stop. Either ask the user to export the asset, or check the icon library for a match.

#### On-request bulk export (WS-bridge escape hatch)

When the user explicitly asks you to export assets yourself ("export those yourself", "grab the PNGs"), use the bundled `scripts/figma-export.mjs`. The TalkToFigma MCP wrapper of `export_node_as_image` discards the inline `imageData`, but a direct WS client on the same channel can read it and write the bytes.

See `references/bulk-export.md` for the full recipe — prerequisites, env vars, gotchas. Read it on demand; no need to load it ahead of time.

### Step 4: Write the code

- Match existing component conventions — file naming, styling approach, props shape.
- Copy text verbatim from Figma. If the project mandates a specific language (e.g., Thai for paypers), the copy is already in that language in Figma — do not translate.
- Sentence case for UI text unless the design clearly uses Title Case.
- **Bundle multi-screen changes into one push.** Local-e2e rebuilds cost ~3-4 min per cycle; batch related visual fixes before triggering verification.

### Step 5: Verify visually

If a local dev or e2e environment is available, render the page in a real browser and compare side-by-side against the screenshot. Note any delta — surfaces, spacing, font weight, shadows — before declaring done. Type-check/tests verify correctness, not fidelity; only a visual pass catches surface-level misses.

For multi-screen jobs, do this once at the end across all screens — single browser session, sequential navigation, one screenshot per screen.

## Gotchas

### Figma MCP

- `export_node_as_image` (the MCP tool) returns inline PNG only, never on disk. The main agent re-calls it directly in Phase 2 to visually cross-check; the subagent's render is for the subagent's own use.
- For graphic assets (illustrations/logos), the MCP wrapper drops the bytes after returning them. Default: ask the user to drag-export, or reuse existing project assets. **On user request only**, bypass the wrapper via the WS bridge — see `references/bulk-export.md`.
- `get_node_info` JSON omits effects (shadows, blurs). Trust the rendered image for depth.
- Structure walks (`jq` + flatten to `TYPE:name [WxH] …`) beat reading raw nested JSON.
- Subagent stdout truncates on long outputs (observed in real sessions, not theoretical). Always have the subagent write the full spec to `/tmp/figma-<node-id>.md` and return only path + digest.

### UI correctness

- Surfaces and z-layers matter most. Call them out before components.
- Grep `globals.css` (or the project's token file) before inventing colors.
- Existing variants (`brand-outline`, badges, etc.) usually already exist — search first.
- Don't trust your own visual read on the first pass. Name surfaces explicitly so a second read can catch misses.
- **Graphics are assets, not HTML.** If you catch yourself CSS-approximating an illustration, logo, chart, or multi-path icon, stop and ask the user to export it from Figma.
- Multi-screen: scan specs for shared new tokens/components and unify before writing.

### Project-specific gotchas

If working in the paypers project, see `references/paypers-local-e2e.md` for local-e2e build flags, `agent-browser` quirks, and screenshot footguns. Skip the file otherwise.
