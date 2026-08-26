# Figma spec — <node-id> <node-name>

Source: Figma node `<node-id>`

## Layout

Page-level structure (header / main / card / footer) and **surfaces and z-layers** (e.g., "card floats on #FAFAFA gray page surface with subtle shadow"). Don't skip surfaces — Phase 2 step 1 needs them.

-

## Components

Top-to-bottom list. For each: dimensions, fill, corner radius, padding, gap, alignment.

-

## Typography

Per text style: font-family, weight, size, line-height, color.

-

## Colors

Hex values grouped by role.

- Surface:
- Text:
- Accent:
- Border:

## Effects

Shadows, blurs, opacity. Source from the rendered image, not JSON — `get_node_info` often omits these.

-

## Copy

All visible text, verbatim, in the original language. Don't translate — Figma is the source of truth for both wording and language.

-

## Interaction hints

Buttons, links, hover states visible in the design.

-

## Graphics

Per-node entries (node ID, semantic name, short description) for any picture/illustration/logo. If none, write "none" so the main agent doesn't go looking.

-
