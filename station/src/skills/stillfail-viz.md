---
name: stillfail-viz
description: Create inline HTML diagrams, charts, comparisons or interactive widgets in still.fail chats. Use when a small visual explains better than prose; Slack receives an attached file.
---

# Inline visualizations

In still.fail (EMBER/…), placed HTML attachments render in the message. An HTML code fence is only code;
an unplaced attachment opens as a file. For a simple flow, sequence, state machine or timeline, use a Mermaid
code fence instead: it renders in still.fail colours without a file.

## Post

Write an HTML fragment in the session workspace, e.g. `session-lifecycle.html`. Attach with
`chat_post(files=["/abs/path/session-lifecycle.html"])` and put `[Session lifecycle](session-lifecycle.html)` on
its own line in the text. Every still.fail app (web, desktop, phones) draws it there; still say its point around the
link: notifications and chat lists show only your words, and figures are not read aloud.
In Slack, attach but omit the Markdown link; files upload below the text, and still.fail's copy of the thread shows
the file as a card that opens it, not drawn in the message. Say what the figure shows for people staying in Slack.

## Write

- Fragments omit `<html>`, `<head>` and `<body>`; order `<style>`, markup, then `<script>`. Stay well under 1 MB.
- Use the loaded stylesheet's variables/classes below; add only layout your figure needs.
- The sandbox has no fetch, XHR, WebSocket or access to the page, station or files. Scripts/styles may load from
  cdnjs.cloudflare.com, esm.sh, cdn.jsdelivr.net or unpkg.com. Images must be data URIs, SVG or canvas; embed data.
- Design for 736 px down to 320 px. Avoid fixed widths/viewport heights; wrap with `.viz-grid` / `.viz-row` and
  `.table-responsive`. Use system `--font-sans`, weights 400–600.
- A full document (`<!doctype>` or `<html>`) renders as written in a 16:9 window, not content-sized, without the
  stylesheet: about 736×414 down to 320×180. All content and controls must scale together. Full-screen pages are
  better attached unplaced or served via stillfail-jobs.

## Talking back

`window.ember` (the name it had before still.fail; also named `window.openai`, as Codex's Visualize has it):

- `ember.widgetState` — what the widget kept last time it was shown (or null); `ember.setWidgetState(value)` keeps a
  JSON value of up to 16 KiB on the station, restored whenever and wherever the message is shown again. Put what you
  should know in `value.modelContent` (the person's choices, say) and the rest in `value.privateContent`:
  `modelContent` reaches you with the next message they send, as a note beside it; keeping state never starts a turn.
- `ember.sendFollowUpMessage({ prompt })` — puts `prompt` in the chat's composer for the person to send, as if they
  wrote it. Only from their click or key press (a button's handler); it never sends by itself. Use it for "ask about
  this", "go with option B", a filled-in form.

## Look

The classes already look like still.fail's own app; keep what you add in the same style:

- Grey by default. Colour only what must be noticed (a failure, a warning, a change) and tell chart series apart;
  normal values, labels and states stay grey. Show a status as a small dot or a badge plus words, not a block of
  colour.
- Mark the current or chosen thing in ink (`.is-active`, `.is-selected`), never in orange: `--brand` and `--accent` are
  for still.fail's own marks, not for emphasis.
- Set things apart with room and grounds (`.card`, a node's grey ground), not frames, rules or dividers. No banners or
  coloured callout boxes: an aside is a `.viz-note` line.
- Numbers are already all one width; use the text sizes below as they are.

Light and dark follow the viewer's theme. Never hard-code colours (no `#fff`, `black`, `slate-500`): use the variables.

- Surfaces and text: `--background`, `--foreground`, `--card`, `--muted`, `--muted-foreground`, `--border`,
  `--border-strong`, `--primary` / `--primary-foreground` (ink buttons), `--accent` / `--accent-foreground` (still.fail's
  orange, tinted ground and text), `--brand` (the orange itself), `--destructive`.
- Status and series: `--blue`, `--green`, `--orange`, `--red`, `--purple`, `--yellow`, each with a
  `-bg` ground (`--blue-bg`…); `--chart-1` … `--chart-6` in order for chart series. Tell series apart by label or
  shape too. In SVG use `currentColor` or `var(--…)`; for a canvas or a library that needs real colours, read them
  with `getComputedStyle(document.documentElement).getPropertyValue("--chart-1")` and redraw on the
  `ember-viz:theme` event.
- Type, the app's sizes (a size up on phones): `--font-size-base` (what is read), `--font-size-ui` (controls, tables),
  `--font-size-small` (labels, notes), `--font-size-display` (a big number); h1–h3 are set. `--font-sans`,
  `--font-mono`, `.text-muted`, `.text-small`. Weights 400, 500 to stand out, 600 for titles. Nothing smaller than
  11px.
- Corners: `--radius-card`, `--radius-field`, `--radius-small`.

## Classes

- Layout: `.card`, `.widget` (a column with gaps), `.viz-grid` (auto columns), `.viz-row`, `.viz-controls`.
- Figures: `.viz-stat` with `.viz-stat-label` and `.viz-stat-value`; `.viz-badge` (add `.is-blue`, `.is-green`,
  `.is-orange`, `.is-red`, `.is-yellow`, `.is-purple`).
- Diagrams: `.viz-flow` (add `.is-vertical`) of `.viz-node` boxes (`.viz-node-title`, `.viz-node-body`; `.is-active`
  for the current one, a colour as above only for one that is wrong or needs attention) with `.viz-arrow` between them
  (its text is the arrow's label); `.viz-note` for an aside.
  For anything a flow of boxes cannot draw (cycles, curves), use inline SVG with the variables.
- Controls: `.btn`, `.btn-primary`, `.btn-ghost`, `.btn-sm`, `.is-selected`; `.form-label`, `.form-control`,
  `.form-select`, `.form-check` + `.form-check-input` + `.form-check-label`, `.form-switch`, `.form-range`.
- Tabs: `.nav.nav-pills` of `.nav-link` (mark the current one `.is-selected`): a segmented choice.
- Tables: `.table` (cells `.num` for numbers) inside `.table-responsive`.
- Progress: `.progress` > `.progress-bar` with `style="width:40%"`.
- Tooltips: any element with `data-tooltip="text"` shows it on hover and focus.

Use the classes as they are; do not restyle their sizes, borders or colours.

## Example

`session-lifecycle.html`, placed with `[Session lifecycle](session-lifecycle.html)`:

```html
<div class="widget">
  <div class="viz-flow">
    <div class="viz-node is-active"><span class="viz-node-title">hot</span><span class="viz-node-body">turn running</span></div>
    <div class="viz-arrow">turn ends</div>
    <div class="viz-node"><span class="viz-node-title">warm</span><span class="viz-node-body">process kept</span></div>
    <div class="viz-arrow">idle 30 min</div>
    <div class="viz-node"><span class="viz-node-title">cold</span><span class="viz-node-body">on disk only</span></div>
  </div>
  <div class="viz-note">Any new message brings a session back to hot.</div>
</div>
```

Before posting a large or scripted one, check it renders: open the file in a browser (or a screenshot tool) and fix
what does not draw or throws.
