---
name: inspect-image-detail
description: Ground a claim about fine detail in an image instead of reading it off the full view. Use when reading small or blurry text, numbers, or labels in a screenshot, receipt, document photo, chart, or PDF page; when judging exact spacing, border width, alignment, or which of two close elements is larger or higher; when comparing a design reference against a build; when identifying an exact color from an image; when a Figma or browser screenshot came back too coarse to read; and whenever you are about to say "it looks like" about anything small in an image.
---

# Inspect image detail

You see an image in **patches** of 28×28 pixels — one visual token each — and images are downscaled to fit a budget before they reach you (long edge 2576 px / 4784 patches on the high-resolution tier, 1568/1568 on the standard tier). Anything thinner than a patch is not faint. It is **absent**.

The trap is what absence feels like from the inside. Missing detail does not arrive as uncertainty; it arrives as a confident, fluent, wrong answer with plausible supporting narration. On a chart-reading benchmark, models asked to compare two lines 8 px apart answered wrong in 36 of 40 runs — and narrated a nearby crossing as if they had watched it happen. There is no internal signal to wait for. The only defence is to check the pixels before the claim, which is what this skill is for.

So the trigger is not "I feel unsure." It is **the claim is about something roughly a patch wide or smaller** — a hairline border, a 2 px gap, 8 pt type, two lines nearly touching, a colour you would name from memory.

## The ladder

Three rungs, truest first. Take the highest one that applies and stop — each rung below it knows strictly less.

### 1. Source — read the thing that produced the pixels

Pixels are a rendering of something. Where that something is still queryable, query it and skip images entirely.

| Image of… | Ask instead |
|---|---|
| a web page | `getComputedStyle` / the DOM, via `/agent-browser` |
| a Figma node | `mcp__figma__get_design_context`, `get_variable_defs`, `get_metadata` |
| a chart you generated | the underlying data |
| a text PDF | extract the text layer |

Measuring a border off a screenshot when the CSS is one call away trades a fact for a guess.

### 2. Re-render — ask for more pixels

When there is no queryable source but the image can be produced again, produce it bigger. This is the rung most often skipped, and it is the one that hands you detail that genuinely was not there before.

- **Figma**: `get_screenshot` defaults to `maxDimension: 1024` — under half the budget. Pass `maxDimension: 2576`. Its response carries `original_width`/`original_height` so you can tell when a re-request will actually gain you something. To go tighter, request a **child `nodeId`**: a semantic crop that re-renders rather than interpolates.
- **Browser**: `agent-browser set viewport 1920 1080 2` — the third argument is `devicePixelRatio`, so layout is unchanged and the screenshot carries 2× the pixels. Use `3` when you need more.
- **Figma assets**: `export_node_as_image` takes `scale`; `download_assets` takes `defaultScale` up to 4.

Comparing two web pages? `agent-browser diff screenshot --baseline` and `diff url <a> <b> --selector "#main"` already do pixel diffing, scoped to an element.

### 3. Magnify — crop what you have and blow it up

For pixels with no source and no re-render path: a PNG pasted into Linear or Slack, a receipt photo, a phone capture, a PDF page render, a screenshot someone sent you.

```bash
magick identify -format '%wx%h\n' IN.png          # know the true size first

magick IN.png -crop WxH+X+Y +repage \
  -filter Lanczos -resize 2576x2576 \
  -background white -alpha remove -alpha off \
  -quality 92 -sampling-factor 1x1 \
  .context/zoom/OUT.jpg
```

Then `Read` the crop. Go again on the result, each crop tighter than the last, until the thing you are judging spans many patches instead of part of one.

Magnifying invents no detail — Lanczos interpolates. What it buys is patches: the detail already captured in the file gets enough of them to be *read*. That is why rung 2 beats rung 3 whenever it is available.

**Four ways to spend the tokens and learn nothing:**

- **Reading the crop at native size.** Same patches as before, so the same blindness. The resize is the entire mechanism.
- **Dropping `+repage`.** The crop keeps the original canvas offset, and every later geometry operation lands somewhere else.
- **Letting JPEG default to 4:2:0.** Chroma subsampling halves colour resolution and smears exactly the 1–2 px coloured lines you cropped in order to see. `-sampling-factor 1x1`.
- **Flattening alpha to black.** Transparent PNGs need `-background white -alpha remove`, or the subject vanishes into the background.

You never have to derive what you actually received. When an image arrives downscaled, `Read` says so:

> `[Image: original 2576x386, displayed at 2000x300. Multiply coordinates by 1.29 to map to original image.]`

Two things come out of that one line. Apply the multiplier to any coordinate you read off the picture before cropping — skipping it hides itself, because the crop lands somewhere else entirely *and still looks like a perfectly legitimate crop of something*, so you read a confident answer off the wrong region. And treat the delivered width as the real ceiling: a 2576 px crop has come back at 2000 px, so let the first note of a session calibrate your resize target instead of assuming 2576 survives. No note at all means the image arrived whole and coordinates map 1:1.

## Colour: sample it

No crop, at any magnification, yields a hex value — your read of a magnified swatch is still a guess.

```bash
magick IN.png -alpha off -depth 8 -format '%[hex:p{X,Y}]' info:    # -> 3B82F6
```

Both flags are load-bearing: without `-depth 8` a 16-bit PNG reports `3B3B8282F6F6FFFF`, and without `-alpha off` you get a trailing `FF` you might read as part of the value.

On a 1 px line or border, the true colour occupies exactly one row, and its neighbours are blends against the background — a real `#3B82F6` hairline reads as `#F3F7FE` one pixel off, which looks like a pale grey border that was never in the stylesheet. Sample a short perpendicular run and take the most saturated value rather than trusting a single guessed coordinate:

```bash
for y in $(seq 118 126); do echo "$y -> $(magick IN.png -alpha off -depth 8 -format "%[hex:p{600,$y}]" info:)"; done
```

## Done, and what it costs

The claim is grounded when you can name what it rests on: a computed value, a re-rendered view, a crop, a sampled pixel. Not when the image merely looks clearer.

Each magnified crop costs up to ~4784 tokens that stay in context for the rest of the session. That prices this as a deliberate move against one specific unresolved question — worth it every time, against a question you actually have. Sweeping every screenshot through rung 3 on principle just burns the window.
