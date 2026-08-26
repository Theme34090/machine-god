---
name: figma-ui-implement
description: Implement a UI screen or component from a Figma design with high visual fidelity, using the TalkToFigma MCP (`mcp__TalkToFigma__*`). Use whenever the user provides a Figma URL/node link and asks to build, code, implement, or match the design — or resumes work on a page that has a Figma source of truth. Trigger even if the user doesn't say "Figma" explicitly, as long as the task is "match this design". Also use when the user says "build this page", "code this up", "implement this screen", "pixel match", or similar alongside any design reference.
---

# Figma UI implementation

**At a glance:**
1. Phase 1 — subagent walks the Figma node via MCP, writes the design spec to `/tmp/figma-<node-id>.md`, returns a digest.
2. Phase 2 — main agent re-renders the node, reads the spec, reconciles with codebase tokens/components, writes code.
3. Verify visually in a real browser before declaring done.

## STOP — before any node-reading MCP call

Before you call any of `get_document_info`, `get_node_info`, `get_nodes_info`, `scan_nodes_by_types`, `scan_text_nodes`, `get_styles`, `get_local_components`, or `export_node_as_image` — STOP.

- If you have NOT spawned a Phase 1 subagent and received its digest yet: spawn it now. Do not inline these calls in your own context.
- `join_channel` is the documented exception — it has no payload to spill.
- If you have already made any node-reading MCP call in this turn: tell the user 'I skipped Phase 1 — restarting via subagent' and spawn the subagent fresh. It will re-walk the node (idempotent reads, cheap re-exports) and produce the auditable spec file. Your context is already polluted; the spec file is the user-auditable artifact.

**Why this is a hard gate, not a suggestion:** an inline `get_node_info` on a multi-component frame routinely exceeds 30k tokens of nested JSON and has spilled to 2MB+ in observed sessions. Phase 2 reconciliation and code-writing budget is what gets squeezed. Without the `/tmp/figma-<node-id>.md` spec file, there is also no artifact for the user to audit the implementation against later — only your chat narration.

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

Spawn a **Opus** subagent (read-heavy, not reasoning-heavy) with figma mcp access. The prompt should instruct it to do all of the following.

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

### Step 1: Render, narrate, and emit the scope/surface block

Call `export_node_as_image` yourself on the target node — the inline PNG appears in your tool result. Read the spec file (`/tmp/figma-<node-id>.md`).

Before moving to Step 2, your narration MUST end with these explicit lines (each line present, even if empty):

```
ROOT SURFACE: <page bg color / image>
PARENT MOUNT: <standalone page | inside <ParentComponent> | bottom-sheet over <X> | dialog over <Y>>
CARD LAYER: <full-bleed | inset N% gutters | none>
Z-ORDER (top → bottom): <list>
WILL IMPLEMENT: <Figma elements I will build>
WILL OMIT (in Figma, not in code): <element + reason, or 'none'>
WILL ADD (in code, not in Figma): <element + reason, or 'none'>
KNOWN UNKNOWNS: <questions for user, or 'none'>
```

If `PARENT MOUNT` is anything other than 'standalone page', `WILL OMIT` is non-empty, `WILL ADD` is non-empty, or `KNOWN UNKNOWNS` is non-empty — STOP and use AskUserQuestion before any Write/Edit to a `.tsx` file.

**Why this is a literal output gate:** the most expensive failures observed (sections built outside the real sheet container, hallucinated back-buttons, silently-dropped mascot heroes, scope creep on copy) all stem from skipping this narration. `PARENT MOUNT` and `Z-ORDER` cannot be derived from `get_node_info` — it omits ancestor context. Compose them from the inline PNG + spec file + your codebase recon, and ask the user when the Figma node alone can't answer.

### Step 2: Reconcile with the existing codebase

STOP. Before any Write/Edit with a hex literal or arbitrary Tailwind class:

- [ ] For each `#xxxxxx` in the spec you intend to use, run `grep -rn '<hex>' apps/frontend/app/globals.css apps/frontend/tailwind.config.*`. If a hit, use the token. Paste the grep result inline before the Write.
- [ ] For each `rounded-[Npx]`, `bg-[#...]`, `border-[#...]`, `text-[#...]` you'd write, grep `apps/frontend/components/ui/` for the same pattern. If a hit, use the existing class.
- [ ] Multi-screen: scan all spec files for the same new color/component before duplicating.

No new token or arbitrary-value class without a one-line 'no existing match because X' justification in your narration. Inventing inline hex colors or redefining tokens is a code-review smell.

**Post-Write check (before commit):** run `git diff -U0 | grep -E '\[#|rounded-\[|bg-\[|border-\[|text-\['` on staged changes. For each remaining hit, either map to a token or justify in one line.

### Step 3: Wire graphic assets — STOP gate

Graphic assets live on disk in the project (e.g., `apps/frontend/public/images/...`). The MCP wrapper drops the bytes after returning `export_node_as_image` inline, so the MCP cannot put them there.

Before writing any SVG or CSS for a visual element, STOP and check your own output:

- inline `<svg>` with >2 `<path>`/`<polygon>` elements → STOP, export
- `clip-path: polygon(...)` or `mask-image:` with custom geometry → STOP, export
- `<canvas>` painted with hatch / sparkle / scratch / foil patterns → STOP, export
- `repeating-linear-gradient` + `::before`/`::after` to fake a torn / zigzag / sawtooth edge → STOP, export
- any element whose Figma source is a hand-drawn / Streamline / Freehand illustration set → STOP, export (regardless of how 'simple' it looks rendered)
- any decorative scatter (sparkles, confetti, particles, doodles) → STOP, export

On STOP, do exactly one of:

1. Reuse an existing asset already in the codebase if the spec description matches one.
2. AskUserQuestion: 'Please drag-export node `<id>` to `<path>`.'
3. Use the WS-bridge bulk export — but ONLY if the user's original prompt contained an explicit export verb ('export those', 'grab the PNGs', 'pull the assets'). See `references/bulk-export.md`.

**Allowed exceptions** (do NOT trigger STOP):
- A primitive shape (solid circle, stroked line, single rectangle, simple geometric accent).
- An icon that already exists in the project's icon library.
- An SVG `<circle>` + `<text dominant-baseline='central'>` for a circled-number badge.

**Anti-patterns observed — do NOT do these:**
- 'This is a primitive geometric pattern — buildable in CSS.' (Said about a multi-tooth torn-paper edge. It wasn't.)
- Painting foil hatch / sparkle scatter with `<canvas>` primitives. (Always looks worse than the export.)
- Substituting lucide icons for Streamline/Freehand illustrations and flagging as 'known nit'. (The user did not authorize the substitution.)

#### On-request bulk export (WS-bridge escape hatch)

When the user explicitly asks you to export assets yourself ("export those yourself", "grab the PNGs"), use the bundled `scripts/figma-export.mjs`. The TalkToFigma MCP wrapper of `export_node_as_image` discards the inline `imageData`, but a direct WS client on the same channel can read it and write the bytes.

See `references/bulk-export.md` for the full recipe — prerequisites, env vars, gotchas. Read it on demand; no need to load it ahead of time.

### Step 4: Write the code

- Match existing component conventions — file naming, styling approach, props shape.
- Copy text verbatim from Figma. If the project mandates a specific language (e.g., Thai for paypers), the copy is already in that language in Figma — do not translate.
- Sentence case for UI text unless the design clearly uses Title Case.
- **Bundle multi-screen changes into one push.** Local-e2e rebuilds cost ~3-4 min per cycle; batch related visual fixes before triggering verification.

### Step 5: Verify visually — production mount only, two-strike escalation

STOP. Before declaring done, render the screen **at the same route/mount the user will hit in production**.

DO:
- Navigate to the real route inside the real parent (`ReceiptCreateDialog`, claim flow, dashboard shell, etc.).
- Use `/test-prep` + seed data to bypass auth / feature-flag / state gates.
- Screenshot side-by-side against the Figma render.

DO NOT:
- Build a standalone HTML mock with the exported PNGs and screenshot that.
- Add a `/preview-*` route to render the component in isolation and call that 'verified'.
- Substitute 'code review is enough' or 'the screen is gated, can't reach it' for a real screenshot.

If the gated state is genuinely unreachable (destructive credit-claim, one-shot onboarding), surface the specific seeding gap to the user and ASK whether to proceed without live verify. Do not silently substitute a mock.

**Two-strike escalation on any single visual delta** (placement, alignment, crop, padding, surface color):

- Attempt 1 fails → one more tweak, with a written hypothesis.
- Attempt 2 fails → STOP. Do NOT try a 3rd value tweak on the same delta. Use AskUserQuestion with options classified by delta type:
  - **Graphic-asset delta** (illustration crop, boundary line, decorative image): the wrapper drops `export_node_as_image` bytes, so CSS-cropping a fake will keep diverging. Options: (a) drag-export the full asset, (b) WS-bridge bulk export, (c) ship as-is with TODO.
  - **Font-metric / centering delta** (circled-number badge, vertically-centered Thai glyph): HTML line-height never matches Figma's text-box metrics. Options: (a) rebuild as SVG `<circle>` + `<text dominant-baseline='central'>`, (b) accept ±1px, (c) change layout to remove the centering requirement.
  - **Spacing/padding delta**: re-read the spec file rather than tweaking a 3rd value; if the spec is silent, ask the user.

Tuning the same lever 3+ times means you're on the wrong primitive, not the wrong value.

**Iteration hygiene:** when overwriting an exported asset filename during iteration, append `-v2`, `-v3` to bust Next.js image cache. Rename to the canonical filename only after the user approves — otherwise you may be debugging a stale render.

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
