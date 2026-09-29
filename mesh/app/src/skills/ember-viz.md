---
name: ember-viz
description: Inline visualizations in ember chats (EMBER/…) — an HTML file attached with chat_post and placed in the text is drawn in the message as a small sandboxed page in ember's own look. Use when a diagram, chart, table, comparison, state machine, flow, or small interactive widget explains something better than prose, instead of rendering a PNG or describing it in words. Not for Slack threads (they take no files).
---

# Inline visualizations

In an ember chat (EMBER/…) an HTML file you attach and place in your message is drawn there as a page of its own,
sized to its content, with a link to open the file itself. Nothing else is drawn as a page: an ```html code block
shows as code, and an HTML file you attach without placing it shows as a file to open.

For a plain diagram (a flow, a sequence, a state machine, a timeline) a ```mermaid block in the text is enough: it is
drawn as a chart in ember's colours, no file needed. Use a file when you need layout, data or interaction.

## Posting one

1. Write the fragment to a file in your session workspace, named for what it shows (`session-lifecycle.html`).
2. Attach it: `chat_post(to=…, text=…, files=["/abs/path/session-lifecycle.html"])`.
3. Place it: in the text, a line of its own that links to it by its file name: `[Session lifecycle](session-lifecycle.html)`.
   Put the words that explain it around that line; the figure is not read aloud, and a phone app may show only the file.

## Writing one

- Write a fragment, not a document: no `<html>`, `<head>` or `<body>`. `<style>` and `<script>` inside it are fine.
  Order it style, then markup, then script. Keep it well under 1 MB.
- ember's stylesheet is already loaded (below): use its variables and classes, and add only the layout your figure
  needs.
- It runs in a sandbox with no network: no fetch, XHR or WebSocket, and no access to the page, the station or files.
  Scripts and styles may come from cdnjs.cloudflare.com, esm.sh, cdn.jsdelivr.net and unpkg.com (a charting library,
  say); images only as data: URIs or drawn (SVG, canvas). Put the data in the fragment itself.
- Width is the message's: design for about 736 px and keep it working down to 320 px (a phone). No fixed widths or
  viewport heights; wrap with `.viz-grid` / `.viz-row`, and give wide content `.table-responsive`.
- Fonts are the system's (`--font-sans`); weights 400 to 600.

## Talking back

`window.ember` (also named `window.openai`, as Codex's Visualize has it):

- `ember.widgetState` — what the widget kept last time it was shown (or null); `ember.setWidgetState(value)` keeps a
  JSON value of up to 16 KiB on the station, restored whenever and wherever the message is shown again. Put what you
  should know in `value.modelContent` (the person's choices, say) and the rest in `value.privateContent`:
  `modelContent` reaches you with the next message they send, as a note beside it; keeping state never starts a turn.
- `ember.sendFollowUpMessage({ prompt })` — puts `prompt` in the chat's composer for the person to send, as if they
  wrote it. Only from their click or key press (a button's handler); it never sends by itself. Use it for "ask about
  this", "go with option B", a filled-in form.

## Look

Light and dark follow the viewer's theme. Never hard-code colours (no `#fff`, `black`, `slate-500`): use the variables.

- Surfaces and text: `--background`, `--foreground`, `--card`, `--muted`, `--muted-foreground`, `--border`,
  `--border-strong`, `--primary` / `--primary-foreground` (ink buttons), `--accent` / `--accent-foreground` (ember's
  orange, tinted ground and text), `--brand` (the orange itself), `--destructive`.
- Status and series: `--blue`, `--green`, `--orange`, `--red`, `--purple`, `--yellow`, each of the first five with a
  `-bg` ground (`--blue-bg`…); `--chart-1` … `--chart-6` in order for chart series. Tell series apart by label or
  shape too. In SVG use `currentColor` or `var(--…)`; for a canvas or a library that needs real colours, read them
  with `getComputedStyle(document.documentElement).getPropertyValue("--chart-1")` and redraw on the
  `ember-viz:theme` event.
- Type: `--font-sans`, `--font-mono`, `--font-size-base` (14px), `--font-size-small` (12px), `.text-muted`,
  `.text-small`, `.tabular-nums`. Nothing smaller than 11px.
- Corners: `--radius-card`, `--radius-field`, `--radius-small`.

## Classes

- Layout: `.card`, `.widget` (a column with gaps), `.viz-grid` (auto columns), `.viz-row`, `.viz-controls`.
- Figures: `.viz-stat` with `.viz-stat-label` and `.viz-stat-value`; `.viz-badge` (add `.is-blue`, `.is-green`,
  `.is-orange`, `.is-red`, `.is-yellow`).
- Diagrams: `.viz-flow` (add `.is-vertical`) of `.viz-node` boxes (`.viz-node-title`, `.viz-node-body`; `.is-active`
  or a colour as above) with `.viz-arrow` between them (its text is the arrow's label); `.viz-note` for an aside.
  For anything a flow of boxes cannot draw (cycles, curves), use inline SVG with the variables.
- Controls: `.btn`, `.btn-primary`, `.btn-ghost`, `.btn-sm`, `.is-selected`; `.form-label`, `.form-control`,
  `.form-select`, `.form-check` + `.form-check-input` + `.form-check-label`, `.form-switch`, `.form-range`.
- Tabs: `.nav.nav-pills` of `.nav-link` (mark the current one `.is-selected`).
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
