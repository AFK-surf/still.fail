---
name: ember-viz
description: Inline visualizations in ember chats (EMBER/…) — an ```html block in chat_post is drawn in place as a small sandboxed page in ember's own look. Use when a diagram, chart, table, comparison, state machine, flow, or small interactive widget explains something better than prose, instead of rendering a PNG or describing it in words. Not for Slack threads (they show the block as code).
---

# Inline visualizations

In an ember chat (EMBER/…) a fenced code block whose language is `html` is not shown as code: ember draws it in the
message as a page of its own, sized to its content, with a switch to see the source. Slack threads show it as plain
code, so do not use it there.

## Writing one

- Write a fragment, not a document: no `<html>`, `<head>` or `<body>`. `<style>` and `<script>` inside it are fine.
- ember's stylesheet is already loaded (below): use its variables and classes, and add only the layout your figure
  needs. Keep it one block, well under 100 KB.
- It runs in a sandbox with no network: no fetch, XHR or WebSocket, and no access to the page, the station or files.
  Scripts and styles may come from cdnjs.cloudflare.com, esm.sh, cdn.jsdelivr.net and unpkg.com (a charting library,
  say); images only as data: URIs or drawn (SVG, canvas). Put the data in the block itself.
- Width is the message's (about 600–800 px, narrower on a phone): let it flow, wrap with `.viz-grid` / `.viz-row`,
  and give wide content `.table-responsive`.
- Say what the figure shows in a sentence of text around it too; the block is not read aloud and not shown in Slack.

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

Before posting a large or scripted one, check it renders: write it to a file, wrap it the way ember does, open it in a
browser (or a screenshot tool), and fix what does not draw or throws.
