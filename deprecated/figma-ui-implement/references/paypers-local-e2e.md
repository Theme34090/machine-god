# Local-e2e gotchas (paypers-specific)

Project-specific notes for the paypers local-e2e + `agent-browser` workflow. Skip this file entirely if working outside paypers.

- `NEXT_PUBLIC_*` env vars are baked at build time. A flag-gated page will silently redirect in the e2e stack unless the frontend Dockerfile has an `ARG` for that flag. Worth a one-time PR to bake in common dev flags.
- `agent-browser cookies set <name> <value> --url <origin> --path / --httpOnly` — **positional** args, not `--name`/`--value`.
- `agent-browser set viewport W H` is a subcommand of `set`, not a top-level command. `location.reload()` doesn't reliably preserve viewport; set it before each `navigate`.
- **`agent-browser screenshot --full` on fixed-position overlays/modals is a footgun.** Fixed elements only cover the viewport. `--full` captures the full scrollable document, so anything past the viewport bottom shows the underlying page content with no overlay/sheet on top — looks like the modal is "clipping" but it's not. Use viewport-only (no `--full`) for any modal/sheet/dialog/popover screenshot. Reserve `--full` for long scrolling content (forms, lists).
- Local-e2e rebuild is ~3-4 min. Bundle multi-screen visual fixes into one push to avoid back-to-back rebuild cycles.
- Clean up test users via the `internal/e2e/cleanup/{userId}` endpoint after iterating, or the DB fills with orphaned `e2e_user_*` rows across runs.
