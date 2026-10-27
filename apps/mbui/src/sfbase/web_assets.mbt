// Made by scripts/webassets.py from the web's own files (do not edit: run it again when they change).

///|
/// web/src/viz/ember-viz.css, as it is.
// kept across runs: a file's words, never written
pub let viz_css : String =
  #|/*
  #| * The stylesheet of an inline visualization (Viz.tsx, the app's viz_file.mbt): an HTML file placed in a message, drawn
  #| * in a sandboxed frame. As Codex's visualize plugin does it: one token contract under the names agents know
  #| * (--background, --foreground, --muted-foreground, --viz-series-1…) and utility classes under Bootstrap's names (.card,
  #| * .btn, .table, .nav-pills…), the only design system a figure is written with. Their values are still.fail's: the page
  #| * hands in its own tokens for the theme it shows as --e-* (colours, type, corners), and the utilities look like the
  #| * app's parts (docs/ui-panels.md): grey unless something is wrong, what is chosen in ink and never the accent, things
  #| * set apart by grounds and room rather than frames, the app's sizes of type, numbers one width. Keep it in step with
  #| * station/src/skills/stillfail-viz.md.
  #| */
  #|@font-face {
  #|  font-family: "Inter Variable";
  #|  font-style: normal;
  #|  font-display: swap;
  #|  font-weight: 100 900;
  #|  src: url(https://cdn.jsdelivr.net/npm/@fontsource-variable/inter@5/files/inter-latin-wght-normal.woff2) format("woff2-variations");
  #|  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
  #|}
  #|
  #|:root {
  #|  /* ── The agents' contract: keep in step with the skill ─────────────────────────── */
  #|  /* Each pair is a ground and what is on it. */
  #|  --background: var(--e-canvas, #fff);
  #|  --foreground: var(--e-text, #3a3d42);
  #|  --card: var(--e-paper, #f6f4ef);
  #|  --card-foreground: var(--foreground);
  #|  --popover: var(--e-primary, #24272b);
  #|  --popover-foreground: var(--e-on-primary, #fff);
  #|  /* The solid control: ink. */
  #|  --primary: var(--e-primary, #24272b);
  #|  --primary-foreground: var(--e-on-primary, #fff);
  #|  /* A quiet ground (a pill, a box in a card, a secondary button) and the one grey for words. */
  #|  --secondary: var(--e-neutral-bg, rgb(36 39 43 / .075));
  #|  --secondary-foreground: var(--foreground);
  #|  --muted: var(--e-neutral-bg, rgb(36 39 43 / .075));
  #|  --muted-foreground: var(--e-muted, #565b62);
  #|  /* A soft highlight (a selected row): grey, never the brand's orange. */
  #|  --accent: var(--e-selected, #ebe8e2);
  #|  --accent-foreground: var(--foreground);
  #|  --destructive: var(--e-red, #9a2830);
  #|  /* Lines only for what has nothing in it (a chart's grid, an empty track), a field's edge, focus. */
  #|  --border: var(--e-line, rgb(50 45 36 / .141));
  #|  --input: var(--e-line-strong, #cdd0d5);
  #|  --ring: var(--e-field-focus, #646970);
  #|  /* Tones, each an ink for words and marks, and its ground. */
  #|  --blue: var(--e-blue, #0047ae);
  #|  --green: var(--e-green, #026039);
  #|  --yellow: var(--e-amber, #6e4802);
  #|  --red: var(--e-red, #9a2830);
  #|  --purple: var(--e-purple, var(--e-code-inline, #6830bf));
  #|  --orange: var(--e-accent-text, #982e01);
  #|  --blue-bg: var(--e-blue-bg, color-mix(in srgb, var(--blue) 18%, transparent));
  #|  --green-bg: var(--e-green-bg, color-mix(in srgb, var(--green) 18%, transparent));
  #|  --yellow-bg: var(--e-amber-bg, color-mix(in srgb, var(--yellow) 18%, transparent));
  #|  --red-bg: var(--e-red-bg, color-mix(in srgb, var(--red) 18%, transparent));
  #|  --purple-bg: var(--e-purple-bg, color-mix(in srgb, var(--purple) 18%, transparent));
  #|  --orange-bg: var(--e-accent-bg, color-mix(in srgb, var(--orange) 18%, transparent));
  #|  /* The brand's orange: a fill (a progress bar, a checked box), never words or emphasis. */
  #|  --brand: var(--e-accent, #dc5929);
  #|  /* Chart series: one measure in ink, then the tones. */
  #|  --viz-series-1: var(--foreground);
  #|  --viz-series-2: var(--blue);
  #|  --viz-series-3: var(--green);
  #|  --viz-series-4: var(--purple);
  #|  --viz-series-5: var(--yellow);
  #|  --viz-series-6: var(--red);
  #|  /* Type: the body's size; the rest follow it (a phone's a size up). */
  #|  --font-size-base: var(--e-text-body, 14px);
  #|
  #|  /* ── What the utilities are made of; not for agents ────────────────────────────── */
  #|  --font-sans: var(--e-font-body, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif);
  #|  --font-mono: ui-monospace, SFMono-Regular, Menlo, monospace;
  #|  --font-size-small: var(--e-text-meta, 12px);
  #|  --font-size-ui: var(--e-text-ui, 13px);
  #|  --font-size-caption: var(--e-text-caption, 11px);
  #|  --font-size-h1: var(--e-text-title, 16px);
  #|  --font-size-h2: var(--font-size-base);
  #|  --font-size-h3: var(--font-size-base);
  #|  --font-size-display: var(--e-text-display, 28px);
  #|  --line-height-normal: var(--e-leading-body, 22px);
  #|  --line-height-small: var(--e-leading-meta, 18px);
  #|  --line-height-ui: var(--e-leading-ui, 20px);
  #|  --line-height-h1: var(--e-leading-title, 24px);
  #|  /* Corners, stepping down as things nest: a card's, a box in it, a field's, a small mark's. */
  #|  --radius-xl: var(--e-r-card, 20px);
  #|  --radius-lg: var(--e-r-field, 12px);
  #|  --radius-md: calc(var(--radius-lg) * .75);
  #|  --radius-sm: calc(var(--radius-lg) / 2);
  #|  --corner-shape: var(--e-corner-shape, round);
  #|  --hover: var(--e-hover, rgb(36 39 43 / .065));
  #|  --selected: var(--e-selected, #ebe8e2);
  #|  --lifted: var(--e-lifted, var(--background));
  #|  --shadow: var(--e-shadow, rgb(0 0 0 / 10%));
  #|  --dur: 140ms;
  #|  --ease-out: cubic-bezier(.2, .7, .2, 1);
  #|
  #|  /* Names this sheet answered to before (Codex's older ones and ember's), kept so old figures draw. */
  #|  --chart-1: var(--viz-series-1);
  #|  --chart-2: var(--viz-series-2);
  #|  --chart-3: var(--viz-series-3);
  #|  --chart-4: var(--viz-series-4);
  #|  --chart-5: var(--viz-series-5);
  #|  --chart-6: var(--viz-series-6);
  #|  --border-strong: var(--input);
  #|  --radius-card: var(--radius-xl);
  #|  --radius-field: var(--radius-lg);
  #|  --radius-small: var(--radius-sm);
  #|
  #|  background: transparent;
  #|  color: var(--foreground);
  #|  font: var(--font-size-base) / var(--line-height-normal) var(--font-sans);
  #|  /* Numbers one width throughout, as the app's own words (docs/ui-panels.md 数字). */
  #|  font-variant-numeric: tabular-nums;
  #|  -webkit-font-smoothing: antialiased;
  #|}
  #|
  #|*, *::before, *::after { box-sizing: border-box; }
  #|html, body { margin: 0; padding: 0; }
  #|/* The frame is as tall as the content (Viz.tsx), so it never scrolls: a fractional scale on Windows can leave the
  #|   content a pixel over, enough for a scrollbar the width of the frame (2026-10-14). */
  #|html { overflow: hidden; }
  #|[hidden] { display: none !important; }
  #|body { padding: 2px; overflow-wrap: anywhere; }
  #|h1, h2, h3, h4, h5, h6, p { margin: 0; }
  #|h1 { font-size: var(--font-size-h1); line-height: var(--line-height-h1); font-weight: 600; }
  #|h2, h3, h4, h5, h6 { font-size: var(--font-size-base); line-height: var(--line-height-normal); font-weight: 600; }
  #|b, strong { font-weight: 600; }
  #|a { color: var(--blue); text-decoration: none; cursor: pointer; }
  #|a:is(:hover, :focus-visible) { text-decoration: underline; text-underline-offset: 2px; }
  #|code, kbd, pre { font-family: var(--font-mono); }
  #|code:not(pre code) { padding: 1px 6px; border-radius: var(--radius-sm); background: var(--muted); font-size: .92em; }
  #|pre { margin: 0; padding: 10px 12px; border-radius: var(--radius-lg); corner-shape: var(--corner-shape); background: var(--muted); font-size: var(--font-size-small); line-height: 20px; overflow-x: auto; }
  #|/* No rules between things: a separator is room. */
  #|hr { height: 0; margin: 8px 0; border: 0; }
  #|button { font: inherit; color: inherit; }
  #|[data-lucide], .lucide { width: 16px; height: 16px; flex: none; vertical-align: -3px; stroke-width: 1.75; }
  #|
  #|/* ── Text ─────────────────────────────────────────────────────────────────────────── */
  #|.text-small { font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|.text-muted { color: var(--muted-foreground); }
  #|.text-destructive { color: var(--destructive); }
  #|.text-success { color: var(--green); }
  #|.text-warning { color: var(--yellow); }
  #|.tabular-nums { font-variant-numeric: tabular-nums; }
  #|.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  #|.cursor-interaction { cursor: pointer; }
  #|
  #|/* ── Surfaces and layout ──────────────────────────────────────────────────────────── */
  #|/* A card is its ground, no frame; one nested in another steps its corner down. */
  #|.card {
  #|  display: flex; flex-direction: column; gap: 12px; min-width: 0; padding: 16px 20px;
  #|  border-radius: var(--radius-xl); corner-shape: var(--corner-shape); background: var(--card); color: var(--card-foreground);
  #|}
  #|.card .card { border-radius: var(--radius-lg); padding: 12px 14px; background: var(--muted); }
  #|.widget { display: flex; flex-direction: column; gap: 16px; min-width: 0; }
  #|.viz-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(160px, 100%), 1fr)); gap: 12px; }
  #|.viz-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; min-width: 0; }
  #|.viz-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px; min-width: 0; }
  #|.viz-dotted-background {
  #|  background-image: radial-gradient(color-mix(in srgb, var(--foreground) 14%, transparent) 1px, transparent 1px);
  #|  background-size: 14px 14px;
  #|}
  #|
  #|/* A number with its label. */
  #|.viz-stat { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  #|.viz-stat-label { color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|.viz-stat-value { font-size: var(--font-size-display); line-height: 1.25; font-weight: 600; letter-spacing: -.01em; }
  #|.viz-stat-value small { margin-left: 2px; color: var(--muted-foreground); font-size: var(--font-size-h1); font-weight: 500; letter-spacing: 0; }
  #|:where(.viz-stat > :not(.viz-stat-label, .viz-stat-value)) { color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|
  #|/* Badges, the app's pills: grey, a tone only for what must be noticed. */
  #|.viz-badge {
  #|  display: inline-flex; align-items: center; gap: 4px; height: 22px; padding: 0 9px; border-radius: 999px;
  #|  background: var(--muted); color: var(--muted-foreground); font-size: var(--font-size-small); font-weight: 500;
  #|  white-space: nowrap; vertical-align: middle;
  #|}
  #|.viz-badge.is-blue { background: var(--blue-bg); color: var(--blue); }
  #|.viz-badge.is-green { background: var(--green-bg); color: var(--green); }
  #|.viz-badge:is(.is-yellow, .is-amber) { background: var(--yellow-bg); color: var(--yellow); }
  #|.viz-badge.is-red { background: var(--red-bg); color: var(--red); }
  #|.viz-badge.is-purple { background: var(--purple-bg); color: var(--purple); }
  #|.viz-badge.is-orange { background: var(--orange-bg); color: var(--orange); }
  #|/* A status: a small dot before words. */
  #|.viz-dot { display: inline-block; flex: none; width: 7px; height: 7px; margin-right: 6px; border-radius: 50%; background: var(--muted-foreground); vertical-align: 1px; }
  #|.viz-dot.is-green { background: var(--green); }
  #|.viz-dot:is(.is-yellow, .is-amber) { background: var(--yellow); }
  #|.viz-dot.is-red { background: var(--red); }
  #|.viz-dot.is-blue { background: var(--blue); }
  #|.viz-dot.is-off { background: transparent; box-shadow: inset 0 0 0 1.5px var(--muted-foreground); }
  #|
  #|/* A tile in a dense grid (on a .btn): fills its cell, chosen ringed in ink. */
  #|.btn.viz-tile { width: 100%; height: auto; min-height: 36px; padding: 6px 8px; border-color: transparent; border-radius: var(--radius-md); background: var(--muted); color: var(--foreground); }
  #|.btn.viz-tile:is([aria-pressed="true"], [aria-selected="true"], .is-selected) { border-color: transparent; background: var(--muted); color: var(--foreground); box-shadow: inset 0 0 0 1.5px var(--foreground); }
  #|
  #|/* Progress: a track and a fill, no edges. */
  #|.progress { height: 6px; overflow: hidden; border-radius: 999px; background: var(--border); }
  #|.progress-bar { height: 100%; border-radius: inherit; background: var(--brand); transition: width var(--dur) var(--ease-out); }
  #|
  #|/* ── Buttons: the app's pills ─────────────────────────────────────────────────────── */
  #|.btn {
  #|  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 32px; padding: 0 14px;
  #|  border: 1px solid var(--input); border-radius: 999px; background: var(--background); color: var(--foreground);
  #|  font: inherit; font-size: var(--font-size-ui); font-weight: 500; white-space: nowrap; text-decoration: none; cursor: pointer;
  #|  transition: background var(--dur) var(--ease-out), border-color var(--dur) var(--ease-out);
  #|}
  #|.btn:hover:not(:disabled) { background: color-mix(in srgb, var(--foreground) 6%, var(--background)); text-decoration: none; }
  #|.btn:disabled, .btn[aria-disabled="true"] { opacity: .45; cursor: default; }
  #|.btn-primary, .btn:is([aria-pressed="true"], [aria-selected="true"], .is-selected) { border-color: var(--primary); background: var(--primary); color: var(--primary-foreground); }
  #|:is(.btn-primary, .btn:is([aria-pressed="true"], [aria-selected="true"], .is-selected)):hover:not(:disabled) { border-color: var(--e-primary-hover, var(--primary)); background: var(--e-primary-hover, var(--primary)); }
  #|.btn-secondary { border-color: transparent; background: var(--muted); }
  #|.btn-secondary:hover:not(:disabled) { background: color-mix(in srgb, var(--foreground) 12%, transparent); }
  #|.btn-ghost { border-color: transparent; background: transparent; }
  #|.btn-ghost:hover:not(:disabled) { background: var(--hover); }
  #|.btn-lg { height: 36px; padding: 0 16px; }
  #|.btn-sm { height: 26px; padding: 0 10px; font-size: var(--font-size-small); }
  #|.btn-xs { height: 22px; padding: 0 8px; font-size: var(--font-size-small); }
  #|.btn-block { display: flex; width: 100%; }
  #|
  #|/* ── Fields ───────────────────────────────────────────────────────────────────────── */
  #|.form-label { display: block; margin-bottom: 4px; color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|.form-control, .form-select {
  #|  width: 100%; height: 36px; padding: 0 16px; border: 1px solid var(--input); border-radius: 999px;
  #|  background: var(--background); color: var(--foreground); font: inherit; font-size: var(--font-size-base);
  #|  transition: border-color var(--dur) var(--ease-out);
  #|}
  #|textarea.form-control { height: auto; min-height: 72px; padding: 8px 12px; border-radius: var(--radius-lg); corner-shape: var(--corner-shape); resize: vertical; }
  #|:is(.form-control, .form-select):is(:hover, :focus) { border-color: var(--e-field-hover, var(--muted-foreground)); outline: none; }
  #|:is(.form-control, .form-select)::placeholder { color: var(--muted-foreground); }
  #|:is(.form-control-sm, .form-select-sm) { height: 28px; padding: 0 12px; font-size: var(--font-size-ui); }
  #|:is(.form-control-xs, .form-select-xs) { height: 24px; padding: 0 10px; font-size: var(--font-size-small); }
  #|.form-control-color { width: 36px; padding: 2px; border-radius: var(--radius-sm); }
  #|.form-check { display: inline-flex; align-items: center; gap: 6px; font-size: var(--font-size-ui); cursor: pointer; }
  #|.form-check-input { width: 16px; height: 16px; margin: 0; accent-color: var(--brand); cursor: pointer; }
  #|.form-switch .form-check-input { width: 28px; }
  #|.form-check-label { cursor: pointer; }
  #|.form-range { width: 100%; accent-color: var(--brand); }
  #|
  #|/* ── Tabs: the app's segmented choice (the runtime switches them) ─────────────────── */
  #|.nav { display: flex; flex-wrap: wrap; gap: 4px; margin: 0; padding: 0; list-style: none; }
  #|.nav-pills {
  #|  display: inline-flex; flex-wrap: nowrap; align-self: flex-start; width: fit-content; max-width: 100%; gap: 2px; padding: 3px;
  #|  border-radius: 999px; background: color-mix(in srgb, var(--foreground) 6%, transparent); overflow-x: auto;
  #|}
  #|.nav-justified { display: flex; width: auto; }
  #|.nav-justified > * { flex: 1; }
  #|.nav-link {
  #|  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 30px; padding: 0 12px; border: 0;
  #|  border-radius: 999px; background: none; color: var(--muted-foreground); font: inherit; font-size: var(--font-size-ui);
  #|  white-space: nowrap; cursor: pointer; transition: color var(--dur) var(--ease-out);
  #|}
  #|.nav-link:hover { color: var(--foreground); text-decoration: none; }
  #|.nav-link:is(.active, .is-selected, [aria-selected="true"]) { color: var(--foreground); font-weight: 500; }
  #|.nav-pills .nav-link:is(.active, .is-selected, [aria-selected="true"]) { background: var(--lifted); box-shadow: 0 0 2px var(--shadow), 0 0 0 .5px var(--border); }
  #|.nav-link:disabled { opacity: .4; cursor: default; }
  #|
  #|/* ── Tables: as a message's Markdown tables ───────────────────────────────────────── */
  #|.table-responsive { width: 100%; overflow-x: auto; }
  #|.table { width: 100%; border-collapse: collapse; font-size: var(--font-size-ui); line-height: var(--line-height-ui); }
  #|.table :is(th, td) { padding: 7px 12px; border-bottom: 1px solid var(--border); text-align: left; vertical-align: top; }
  #|.table thead th {
  #|  color: var(--muted-foreground); font-size: var(--font-size-small); font-weight: 500;
  #|  background: color-mix(in srgb, var(--foreground) 4%, transparent);
  #|}
  #|.table tbody tr:last-child :is(th, td) { border-bottom: 0; }
  #|.table.table-sm :is(th, td) { padding: 4px 8px; }
  #|.table :is(.text-end, .num, [align="right"]) { text-align: right; }
  #|.table :is(.text-center, [align="center"]) { text-align: center; }
  #|.table .text-nowrap { white-space: nowrap; }
  #|
  #|/* ── Boxes in a flow (ember's own) ────────────────────────────────────────────────── */
  #|.viz-flow { display: flex; flex-wrap: wrap; align-items: stretch; gap: 8px; }
  #|.viz-flow.is-vertical { flex-direction: column; align-items: flex-start; }
  #|.viz-node {
  #|  display: flex; flex-direction: column; gap: 2px; min-width: 96px; padding: 10px 12px;
  #|  border-radius: var(--radius-lg); corner-shape: var(--corner-shape); background: var(--muted);
  #|}
  #|.viz-node-title { font-weight: 500; }
  #|.viz-node-body { color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|.viz-node.is-active { background: var(--primary); color: var(--primary-foreground); }
  #|.viz-node.is-active .viz-node-body { color: color-mix(in srgb, var(--primary-foreground) 75%, transparent); }
  #|.viz-node.is-blue { background: var(--blue-bg); }
  #|.viz-node.is-green { background: var(--green-bg); }
  #|.viz-node.is-red { background: var(--red-bg); }
  #|.viz-node:is(.is-yellow, .is-amber) { background: var(--yellow-bg); }
  #|.viz-node.is-purple { background: var(--purple-bg); }
  #|.viz-arrow {
  #|  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; min-width: 40px;
  #|  color: var(--muted-foreground); font-size: var(--font-size-small); text-align: center;
  #|}
  #|.viz-arrow::after { content: "→"; font-size: 16px; line-height: 1; }
  #|.viz-flow.is-vertical .viz-arrow::after { content: "↓"; }
  #|.viz-note { color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|
  #|/* ── Charts (<viz-chart>, <viz-spark>): grid lines only, labels quiet, one measure in ink ─ */
  #|.widget > :is(h1, h2, h3) + :is(viz-chart, svg, .table-responsive, .viz-flow) { margin-top: -8px; }
  #|viz-chart { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
  #|viz-chart svg { display: block; width: 100%; overflow: visible; }
  #|viz-spark { display: inline-flex; vertical-align: middle; }
  #|.viz-chart-title { font-weight: 600; }
  #|.viz-chart-grid { stroke: var(--border); stroke-width: 1; }
  #|.viz-chart-axis { fill: var(--muted-foreground); font-size: var(--font-size-caption); }
  #|.viz-chart-legend { display: flex; flex-wrap: wrap; gap: 4px 14px; color: var(--muted-foreground); font-size: var(--font-size-small); line-height: var(--line-height-small); }
  #|.viz-chart-legend > span { display: inline-flex; align-items: center; gap: 6px; }
  #|.viz-chart-legend i { width: 8px; height: 8px; border-radius: 2px; }
  #|.viz-chart-donut { display: flex; flex-wrap: wrap; align-items: center; gap: 16px 24px; }
  #|.viz-chart-donut svg { width: 140px; height: 140px; flex: none; }
  #|.viz-chart-donut .viz-chart-legend { flex-direction: column; flex: 1; min-width: 140px; color: var(--foreground); font-size: var(--font-size-ui); line-height: var(--line-height-ui); }
  #|.viz-chart-donut .viz-chart-legend > span { justify-content: space-between; gap: 12px; }
  #|.viz-chart-donut .viz-chart-legend b { color: var(--muted-foreground); font-weight: 400; }
  #|.viz-chart-center { fill: var(--foreground); font-size: var(--font-size-h1); font-weight: 600; }
  #|.viz-hbars { display: grid; grid-template-columns: minmax(0, max-content) minmax(60px, 1fr) max-content; gap: 8px 12px; align-items: center; font-size: var(--font-size-ui); line-height: var(--line-height-ui); }
  #|.viz-bar-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #|.viz-bar-track { height: 8px; border-radius: 999px; background: var(--muted); overflow: hidden; }
  #|.viz-bar-fill { display: block; height: 100%; border-radius: inherit; background: var(--viz-series-1); }
  #|.viz-bar-value { color: var(--muted-foreground); text-align: right; }
  #|.viz-hit:hover { opacity: .8; }
  #|
  #|/* The tooltip the frame draws for any element with data-tooltip (see bridge.js). */
  #|.viz-tooltip, .tooltip {
  #|  position: fixed; z-index: 10; max-width: 240px; padding: 5px 8px; border-radius: var(--radius-sm);
  #|  background: var(--popover); color: var(--popover-foreground); font-size: var(--font-size-small); line-height: 1.4;
  #|  white-space: pre-line; pointer-events: none;
  #|}

///|
/// web/src/viz/bridge.js, as it is.
// kept across runs: a file's words, never written
pub let viz_bridge : String =
  #|// Runs first inside an inline visualization's frame (Viz.tsx). The frame is sandboxed without its page's origin, so
  #|// the two only talk by messages: the frame says how tall its content is, the page says when its theme changes (the
  #|// --e-* tokens ember-viz.css maps), and the frame draws the tooltip of any element with data-tooltip.
  #|//
  #|// The widget's API is window.ember, named as Codex's Visualize names window.openai (which it also answers to, for a
  #|// widget written for that): widgetState and setWidgetState keep what the widget wants back when it is shown again,
  #|// sendFollowUpMessage puts words in the chat's composer for the person to send — only on their click or key.
  #|(() => {
  #|  const root = document.documentElement;
  #|  // The page is the parent in a message; opened beside the chat it is the top, over the preview's own frame
  #|  // (Preview.tsx), which takes no notice.
  #|  const pages = parent === top ? [parent] : [parent, top];
  #|  const post = (message) => { for (const page of pages) page.postMessage({ emberViz: true, ...message }, "*"); };
  #|
  #|  const given = document.getElementById("ember-viz-state");
  #|  let state = JSON.parse(given?.textContent || "{}").widgetState ?? null;
  #|  given?.remove();
  #|  const api = {
  #|    get widgetState() { return state; },
  #|    setWidgetState(next) {
  #|      const json = JSON.stringify(next ?? null);
  #|      if (json.length > 16 * 1024) return Promise.reject(new Error("widgetState is over 16 KiB"));
  #|      state = JSON.parse(json);
  #|      post({ type: "state", state });
  #|      return Promise.resolve();
  #|    },
  #|    sendFollowUpMessage({ prompt } = {}) {
  #|      if (typeof prompt !== "string" || !prompt.trim()) return Promise.reject(new Error("sendFollowUpMessage needs a prompt"));
  #|      // Only as the person acts: a widget cannot write to the chat by itself.
  #|      if (navigator.userActivation && !navigator.userActivation.isActive) return Promise.reject(new Error("sendFollowUpMessage needs a click or key press"));
  #|      post({ type: "followup", prompt });
  #|      return Promise.resolve();
  #|    },
  #|  };
  #|  Object.defineProperty(window, "ember", { value: api });
  #|  Object.defineProperty(window, "openai", { value: api });
  #|
  #|  let last = 0;
  #|  const sendHeight = () => {
  #|    const height = Math.ceil(Math.max(document.body?.scrollHeight ?? 0, document.body?.getBoundingClientRect().height ?? 0));
  #|    if (height !== last) {
  #|      last = height;
  #|      post({ type: "height", height });
  #|    }
  #|  };
  #|  addEventListener("message", (event) => {
  #|    if (!pages.includes(event.source) || !event.data?.emberViz) return;
  #|    if (event.data.type === "theme") {
  #|      for (const [name, value] of Object.entries(event.data.tokens ?? {})) root.style.setProperty(name, value);
  #|      root.dataset.theme = event.data.scheme;
  #|      root.style.colorScheme = event.data.scheme;
  #|      // For charts drawn with resolved colours (a canvas, a chart library): redraw on this.
  #|      dispatchEvent(new CustomEvent("ember-viz:theme", { detail: { scheme: event.data.scheme } }));
  #|    }
  #|  });
  #|
  #|  let tip = null;
  #|  const place = (target) => {
  #|    const r = target.getBoundingClientRect();
  #|    const t = tip.getBoundingClientRect();
  #|    const left = Math.min(Math.max(4, r.left + r.width / 2 - t.width / 2), innerWidth - t.width - 4);
  #|    const top = r.top - t.height - 6 >= 0 ? r.top - t.height - 6 : r.bottom + 6;
  #|    tip.style.left = `${left}px`;
  #|    tip.style.top = `${top}px`;
  #|  };
  #|  const show = (target) => {
  #|    const text = target.getAttribute("data-tooltip");
  #|    if (!text) return hide();
  #|    tip ??= Object.assign(document.createElement("div"), { className: "viz-tooltip", role: "tooltip" });
  #|    tip.textContent = text;
  #|    document.body.append(tip);
  #|    place(target);
  #|  };
  #|  const hide = () => tip?.remove();
  #|  addEventListener("pointerover", (e) => { const t = e.target.closest?.("[data-tooltip]"); t ? show(t) : hide(); });
  #|  addEventListener("focusin", (e) => { const t = e.target.closest?.("[data-tooltip]"); t ? show(t) : hide(); });
  #|  addEventListener("pointerleave", hide);
  #|  addEventListener("scroll", hide, true);
  #|
  #|  addEventListener("DOMContentLoaded", () => {
  #|    sendHeight();
  #|    new ResizeObserver(sendHeight).observe(document.body);
  #|  });
  #|  addEventListener("load", sendHeight);
  #|  addEventListener("error", (e) => post({ type: "error", message: String(e.message ?? e) }));
  #|})();

///|
/// web/src/viz/components.js, as it is.
// kept across runs: a file's words, never written
pub let viz_components : String =
  #|// What inline visualizations get beside the stylesheet (Viz.tsx, the app's viz_file.mbt), as Codex's visualize plugin
  #|// gives its own: tabs (.nav[role="tablist"]) switched by themselves, Lucide icons (data-lucide), and still.fail's
  #|// charts, <viz-chart> and <viz-spark>, drawn from the data an agent gives them in the theme's colours (var(--…), so they
  #|// follow it without being drawn again). How agents use them: station/src/skills/stillfail-viz.md.
  #|(() => {
  #|  const NS = "http://www.w3.org/2000/svg";
  #|  const TONE_INK = {
  #|    green: "--green", ok: "--green", yellow: "--yellow", amber: "--yellow", warn: "--yellow", red: "--red", error: "--red",
  #|    blue: "--blue", info: "--blue", purple: "--purple", orange: "--orange", ink: "--foreground", muted: "--muted-foreground",
  #|  };
  #|
  #|  /** An element: tag (with .classes), attributes (on* are listeners), children (strings are text). */
  #|  const h = (tag, attrs = {}, ...kids) => {
  #|    const [name, ...classes] = tag.split(".");
  #|    const el = document.createElement(name);
  #|    if (classes.length) el.className = classes.join(" ");
  #|    for (const [k, v] of Object.entries(attrs)) {
  #|      if (v === undefined || v === null || v === false) continue;
  #|      if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
  #|      else if (k === "style") el.style.cssText = v;
  #|      else el.setAttribute(k, v === true ? "" : String(v));
  #|    }
  #|    for (const kid of kids.flat(Infinity)) if (kid !== undefined && kid !== null && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
  #|    return el;
  #|  };
  #|  const s = (tag, attrs = {}, ...kids) => {
  #|    const el = document.createElementNS(NS, tag);
  #|    for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) el.setAttribute(k, String(v));
  #|    for (const kid of kids.flat(Infinity)) if (kid) el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  #|    return el;
  #|  };
  #|  /** Puts what is given in place of an element's children, leaving out what is not there. */
  #|  const put = (el, ...kids) => el.replaceChildren(...kids.flat(Infinity).filter((k) => k !== undefined && k !== null && k !== false && k !== ""));
  #|  const ink = (tone, i = 0) => `var(${TONE_INK[tone] ?? `--viz-series-${(i % 6) + 1}`})`;
  #|
  #|  /** The element's data: its `data` attribute, else a <script type="application/json"> inside it. */
  #|  const dataOf = (el) => {
  #|    const raw = el.getAttribute("data") ?? el.querySelector(":scope > script[type='application/json']")?.textContent;
  #|    if (!raw) return null;
  #|    try {
  #|      return JSON.parse(raw);
  #|    } catch (e) {
  #|      put(el, h("p.text-small.text-muted", {}, `${el.localName}: its data is not JSON (${e.message})`));
  #|      return undefined;
  #|    }
  #|  };
  #|  const num = (v) => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v.replace(/[,_]/g, ""))) ? Number(v.replace(/[,_]/g, "")) : NaN);
  #|  const fmt = (n, digits = 2) => (Number.isFinite(n) ? n.toLocaleString(undefined, { maximumFractionDigits: digits }) : String(n));
  #|
  #|  /** Draws once its children are there (an element is upgraded as its tag is read, before what is inside it). */
  #|  class Base extends HTMLElement {
  #|    connectedCallback() {
  #|      if (this._drawn) return;
  #|      const go = () => {
  #|        if (this._drawn || !this.isConnected) return;
  #|        this._drawn = true;
  #|        try {
  #|          this.draw();
  #|        } catch (e) {
  #|          put(this, h("p.text-small.text-muted", {}, `${this.localName}: ${e.message}`));
  #|          postMessage({ emberViz: true, type: "error", message: `${this.localName}: ${e.message}` }, "*");
  #|        }
  #|      };
  #|      if (document.readyState === "loading") addEventListener("DOMContentLoaded", go, { once: true });
  #|      else queueMicrotask(go);
  #|    }
  #|    draw() {}
  #|  }
  #|  const define = (name, cls) => { if (!customElements.get(name)) customElements.define(name, cls); };
  #|
  #|  /** A small line of values (a trend), as wide as it is given, in ink. */
  #|  const spark = (values, { w = 80, hgt = 22, tone } = {}) => {
  #|    const vs = values.map(num).filter(Number.isFinite);
  #|    const svg = s("svg", { class: "viz-spark", viewBox: `0 0 ${w} ${hgt}`, preserveAspectRatio: "none", width: w, height: hgt });
  #|    if (vs.length < 2) return svg;
  #|    const lo = Math.min(...vs), hi = Math.max(...vs) === lo ? lo + 1 : Math.max(...vs);
  #|    const pts = vs.map((v, i) => `${(i / (vs.length - 1)) * w},${2 + (1 - (v - lo) / (hi - lo)) * (hgt - 4)}`);
  #|    svg.append(s("polyline", { points: pts.join(" "), fill: "none", stroke: tone ? ink(tone) : "var(--viz-series-1)", "stroke-width": 1.5, "stroke-linejoin": "round", "stroke-linecap": "round", "vector-effect": "non-scaling-stroke" }));
  #|    return svg;
  #|  };
  #|  const listOf = (raw) => { try { return JSON.parse(raw); } catch { return String(raw).split(/[\s,]+/).filter(Boolean); } };
  #|
  #|  define("viz-spark", class extends Base {
  #|    draw() {
  #|      put(this, spark(listOf(this.getAttribute("data") ?? this.textContent), { w: num(this.getAttribute("width")) || 80, hgt: num(this.getAttribute("height")) || 20, tone: this.getAttribute("tone") ?? undefined }));
  #|    }
  #|  });
  #|
  #|
  #|  // ── Charts ──────────────────────────────────────────────────────────────────────────
  #|  /** Round steps for an axis from 0 (or the least, when below it) to the most. */
  #|  const ticks = (lo, hi, n = 4) => {
  #|    if (hi === lo) hi = lo + 1;
  #|    const raw = (hi - lo) / n;
  #|    const mag = 10 ** Math.floor(Math.log10(raw));
  #|    const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((x) => x >= raw) ?? raw;
  #|    const start = Math.floor(lo / step) * step;
  #|    const out = [];
  #|    for (let v = start; v <= hi + step * 1e-9; v += step) out.push(Number(v.toPrecision(12)));
  #|    if (out[out.length - 1] < hi) out.push(Number((out[out.length - 1] + step).toPrecision(12)));
  #|    return out;
  #|  };
  #|  const short = (n) => {
  #|    const a = Math.abs(n);
  #|    return a >= 1e9 ? `${fmt(n / 1e9, 1)}B` : a >= 1e6 ? `${fmt(n / 1e6, 1)}M` : a >= 1e4 ? `${fmt(n / 1e3, 1)}k` : fmt(n);
  #|  };
  #|
  #|  define("viz-chart", class extends Base {
  #|    draw() {
  #|      const d = dataOf(this);
  #|      if (!d) return;
  #|      this._data = d;
  #|      this._width = 0;
  #|      this.render();
  #|      new ResizeObserver(() => { if (Math.round(this.clientWidth) !== this._width) this.render(); }).observe(this);
  #|    }
  #|    render() {
  #|      const d = this._data;
  #|      const type = this.getAttribute("type") ?? "bar";
  #|      const unit = this.getAttribute("unit") ?? "";
  #|      const width = Math.round(this.clientWidth) || 600;
  #|      this._width = width;
  #|      if (type === "donut" || type === "pie") return this.donut(d, unit);
  #|      if (type === "scatter") return this.scatter(d, unit, width);
  #|      if (type === "hbar") return this.hbar(d, unit);
  #|      const labels = d.labels ?? [];
  #|      const series = (d.series ?? [{ name: d.name ?? "", values: d.values ?? [], tone: d.tone }]).map((sr, i) => ({ ...sr, color: sr.tone ? ink(sr.tone) : ink(null, i) }));
  #|      const stacked = this.hasAttribute("stacked") && type === "bar";
  #|      const height = num(this.getAttribute("height")) || 200;
  #|      const all = stacked ? labels.map((_, i) => series.reduce((a, sr) => a + (num(sr.values[i]) || 0), 0)) : series.flatMap((sr) => sr.values.map(num).filter(Number.isFinite));
  #|      const lo = Math.min(0, ...all);
  #|      const hi = Math.max(0, ...all);
  #|      const ys = ticks(lo, hi);
  #|      const y0 = ys[0], y1 = ys[ys.length - 1];
  #|      const labelW = Math.max(...ys.map((v) => (short(v) + unit).length)) * 6.5 + 8;
  #|      const left = labelW, right = 4, top = 8, bottom = 22;
  #|      const plotW = Math.max(40, width - left - right), plotH = height - top - bottom;
  #|      const Y = (v) => top + plotH - ((v - y0) / (y1 - y0)) * plotH;
  #|      const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, height, role: "img" });
  #|      for (const v of ys) {
  #|        svg.append(s("line", { class: "viz-chart-grid", x1: left, x2: width - right, y1: Y(v), y2: Y(v) }));
  #|        svg.append(s("text", { class: "viz-chart-axis", x: left - 8, y: Y(v), "text-anchor": "end", "dominant-baseline": "middle" }, short(v) + unit));
  #|      }
  #|      const n = Math.max(1, labels.length);
  #|      const band = plotW / n;
  #|      const every = Math.max(1, Math.ceil((labels.reduce((m, l) => Math.max(m, String(l).length), 0) * 6.5 + 12) / band));
  #|      labels.forEach((l, i) => {
  #|        if (i % every) return;
  #|        const x = type === "bar" ? left + band * (i + .5) : left + (n === 1 ? plotW / 2 : (plotW * i) / (n - 1));
  #|        svg.append(s("text", { class: "viz-chart-axis", x, y: height - 6, "text-anchor": n > 1 && type !== "bar" && i === 0 ? "start" : n > 1 && type !== "bar" && i === n - 1 ? "end" : "middle" }, l));
  #|      });
  #|      const tip = (i, sr, v) => `${labels[i] ?? ""}${sr.name ? ` · ${sr.name}` : ""}: ${fmt(v)}${unit}`;
  #|      if (type === "bar") {
  #|        const inner = band * .72;
  #|        const each = stacked ? inner : inner / series.length;
  #|        const r = Math.min(4, each / 4);
  #|        labels.forEach((_, i) => {
  #|          let acc = 0;
  #|          series.forEach((sr, k) => {
  #|            const v = num(sr.values[i]) || 0;
  #|            const x = left + band * i + (band - inner) / 2 + (stacked ? 0 : each * k);
  #|            const from = stacked ? acc : 0;
  #|            acc += v;
  #|            const ya = Y(Math.max(from, from + v)), yb = Y(Math.min(from, from + v));
  #|            const w = Math.max(1, each - (stacked || series.length === 1 ? 0 : 2));
  #|            const hgt = Math.max(v === 0 ? 0 : 1, yb - ya);
  #|            const top_ = !stacked || k === series.length - 1;
  #|            const path = top_ && hgt > r
  #|              ? `M${x},${ya + hgt}V${ya + r}Q${x},${ya} ${x + r},${ya}H${x + w - r}Q${x + w},${ya} ${x + w},${ya + r}V${ya + hgt}Z`
  #|              : `M${x},${ya}h${w}v${hgt}h${-w}Z`;
  #|            svg.append(s("path", { d: path, fill: sr.color, class: "viz-hit", "data-tooltip": tip(i, sr, v) }));
  #|          });
  #|        });
  #|      } else {
  #|        const X = (i) => left + (n === 1 ? plotW / 2 : (plotW * i) / (n - 1));
  #|        series.forEach((sr) => {
  #|          const pts = sr.values.map((v, i) => [X(i), Y(num(v))]).filter(([, y]) => Number.isFinite(y));
  #|          if (!pts.length) return;
  #|          const line = pts.map(([x, y], i) => `${i ? "L" : "M"}${x},${y}`).join("");
  #|          if (type === "area") svg.append(s("path", { d: `${line}L${pts[pts.length - 1][0]},${Y(Math.max(0, y0))}L${pts[0][0]},${Y(Math.max(0, y0))}Z`, fill: sr.color, "fill-opacity": series.length > 1 ? .12 : .16 }));
  #|          svg.append(s("path", { d: line, fill: "none", stroke: sr.color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
  #|          sr.values.forEach((v, i) => {
  #|            if (!Number.isFinite(num(v))) return;
  #|            svg.append(s("circle", { cx: X(i), cy: Y(num(v)), r: pts.length > 24 ? 0 : 3, fill: sr.color }));
  #|            svg.append(s("rect", { x: X(i) - Math.max(6, plotW / n / 2), y: top, width: Math.max(12, plotW / n), height: plotH, fill: "transparent", "data-tooltip": tip(i, sr, num(v)) }));
  #|          });
  #|        });
  #|      }
  #|      const legend = series.length > 1 && h("div.viz-chart-legend", {}, series.map((sr) => h("span", {}, h("i", { style: `background:${sr.color}` }), sr.name)));
  #|      put(this, this.title_(), svg, legend);
  #|    }
  #|    title_() {
  #|      const t = this.getAttribute("title");
  #|      if (t) this.setAttribute("data-title", t), this.removeAttribute("title");
  #|      const said = this.getAttribute("data-title");
  #|      return said && h("div.viz-chart-title", {}, said);
  #|    }
  #|    hbar(d, unit) {
  #|      const items = d.items ?? (d.labels ?? []).map((l, i) => ({ label: l, value: (d.values ?? [])[i] }));
  #|      const max = num(this.getAttribute("max")) || Math.max(0, ...items.map((it) => num(it.value) || 0)) || 1;
  #|      put(this, this.title_(), h("div.viz-hbars", {}, items.map((it, i) => [
  #|        h("span.viz-bar-label", {}, it.label),
  #|        h("span.viz-bar-track", {}, h("span.viz-bar-fill", { style: `width:${Math.max(0, Math.min(100, ((num(it.value) || 0) / max) * 100))}%;background:${it.tone ? ink(it.tone) : "var(--viz-series-1)"}`, "data-tooltip": `${it.label}: ${fmt(num(it.value))}${unit}` })),
  #|        h("span.viz-bar-value", {}, it.note ?? `${fmt(num(it.value))}${unit}`),
  #|      ])));
  #|    }
  #|    scatter(d, unit, width) {
  #|      const series = (d.series ?? [{ name: d.name ?? "", points: d.points ?? [] }]).map((sr, i) => ({ ...sr, color: sr.tone ? ink(sr.tone) : ink(null, i) }));
  #|      const pts = series.flatMap((sr) => sr.points.map((p) => [num(p[0] ?? p.x), num(p[1] ?? p.y)]));
  #|      const height = num(this.getAttribute("height")) || 220;
  #|      const xs = ticks(Math.min(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[0])));
  #|      const ys = ticks(Math.min(0, ...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[1])));
  #|      const xunit = this.getAttribute("x-unit") ?? "";
  #|      const left = Math.max(...ys.map((v) => (short(v) + unit).length)) * 6.5 + 8, right = 8, top = 8, bottom = 22;
  #|      const pw = width - left - right, ph = height - top - bottom;
  #|      const X = (v) => left + ((v - xs[0]) / (xs[xs.length - 1] - xs[0])) * pw;
  #|      const Y = (v) => top + ph - ((v - ys[0]) / (ys[ys.length - 1] - ys[0])) * ph;
  #|      const svg = s("svg", { viewBox: `0 0 ${width} ${height}`, height, role: "img" });
  #|      for (const v of ys) svg.append(s("line", { class: "viz-chart-grid", x1: left, x2: width - right, y1: Y(v), y2: Y(v) }), s("text", { class: "viz-chart-axis", x: left - 8, y: Y(v), "text-anchor": "end", "dominant-baseline": "middle" }, short(v) + unit));
  #|      xs.forEach((v, i) => svg.append(s("text", { class: "viz-chart-axis", x: X(v), y: height - 6, "text-anchor": i === 0 ? "start" : i === xs.length - 1 ? "end" : "middle" }, short(v) + xunit)));
  #|      series.forEach((sr) => sr.points.forEach((p) => {
  #|        const x = num(p[0] ?? p.x), y = num(p[1] ?? p.y);
  #|        if (!Number.isFinite(x) || !Number.isFinite(y)) return;
  #|        svg.append(s("circle", { cx: X(x), cy: Y(y), r: 4, fill: sr.color, "fill-opacity": .85, class: "viz-hit", "data-tooltip": `${p.label ?? p[2] ?? (sr.name || "")}${p.label || p[2] || sr.name ? ": " : ""}${fmt(x)}${xunit}, ${fmt(y)}${unit}` }));
  #|      }));
  #|      const legend = series.length > 1 && h("div.viz-chart-legend", {}, series.map((sr) => h("span", {}, h("i", { style: `background:${sr.color};border-radius:50%` }), sr.name)));
  #|      put(this, this.title_(), svg, legend);
  #|    }
  #|    donut(d, unit) {
  #|      const items = d.items ?? (d.labels ?? []).map((l, i) => ({ label: l, value: (d.values ?? [])[i] }));
  #|      const total = items.reduce((a, it) => a + (num(it.value) || 0), 0) || 1;
  #|      const R = 60, r = this.getAttribute("type") === "pie" ? 0 : 42, c = 70;
  #|      const svg = s("svg", { viewBox: "0 0 140 140", role: "img" });
  #|      let a = -Math.PI / 2;
  #|      items.forEach((it, i) => {
  #|        const v = num(it.value) || 0;
  #|        const span = (v / total) * Math.PI * 2;
  #|        const color = it.tone ? ink(it.tone) : ink(null, i);
  #|        const b = a + span;
  #|        const big = span > Math.PI ? 1 : 0;
  #|        const p = (rad, ang) => `${c + rad * Math.cos(ang)},${c + rad * Math.sin(ang)}`;
  #|        const gap = items.length > 1 ? .012 : 0;
  #|        const d_ = span >= Math.PI * 2 - 1e-6
  #|          ? `M${c - R},${c}a${R},${R} 0 1,0 ${R * 2},0a${R},${R} 0 1,0 ${-R * 2},0${r ? `M${c - r},${c}a${r},${r} 0 1,1 ${r * 2},0a${r},${r} 0 1,1 ${-r * 2},0` : ""}Z`
  #|          : `M${p(R, a + gap)}A${R},${R} 0 ${big},1 ${p(R, b - gap)}${r ? `L${p(r, b - gap)}A${r},${r} 0 ${big},0 ${p(r, a + gap)}` : `L${c},${c}`}Z`;
  #|        svg.append(s("path", { d: d_, fill: color, "fill-rule": "evenodd", class: "viz-hit", "data-tooltip": `${it.label}: ${fmt(v)}${unit} (${fmt((v / total) * 100, 1)}%)` }));
  #|        it.color = color;
  #|        a = b;
  #|      });
  #|      const center = this.getAttribute("center");
  #|      if (r && center !== "") svg.append(s("text", { class: "viz-chart-center", x: c, y: c, "text-anchor": "middle", "dominant-baseline": "central" }, center ?? `${short(total)}${unit}`));
  #|      const legend = h("div.viz-chart-legend", {}, items.map((it) => h("span", {}, h("span", { style: "display:inline-flex;align-items:center;gap:6px" }, h("i", { style: `background:${it.color}` }), it.label), h("b", {}, `${fmt(num(it.value))}${unit}`))));
  #|      put(this, this.title_(), h("div.viz-chart-donut", {}, svg, legend));
  #|    }
  #|  });
  #|
  #|  // ── Tabs: a .nav[role="tablist"] of [role="tab"] buttons shows the panel its chosen one names ──────────────────
  #|  const TAB = '.nav[role="tablist"] [role="tab"]';
  #|  const pick = (tab) => {
  #|    for (const t of tab.closest('[role="tablist"]').querySelectorAll('[role="tab"]')) {
  #|      const on = t === tab;
  #|      t.classList.toggle("active", on);
  #|      t.setAttribute("aria-selected", String(on));
  #|      const panel = t.getAttribute("aria-controls") && document.getElementById(t.getAttribute("aria-controls"));
  #|      if (panel) panel.hidden = !on && t.getAttribute("aria-controls") !== tab.getAttribute("aria-controls");
  #|    }
  #|  };
  #|  addEventListener("click", (e) => {
  #|    const tab = e.target?.closest?.(TAB);
  #|    if (tab && !e.defaultPrevented && !tab.matches(':disabled,[aria-disabled="true"]')) pick(tab);
  #|  });
  #|  addEventListener("keydown", (e) => {
  #|    const tab = e.target?.closest?.(TAB);
  #|    if (!tab) return;
  #|    const tabs = [...tab.closest('[role="tablist"]').querySelectorAll('[role="tab"]')].filter((t) => !t.matches(':disabled,[aria-disabled="true"]'));
  #|    const at = tabs.indexOf(tab);
  #|    const to = { ArrowRight: at + 1, ArrowDown: at + 1, ArrowLeft: at - 1, ArrowUp: at - 1, Home: 0, End: tabs.length - 1 }[e.key];
  #|    if (to === undefined) return;
  #|    e.preventDefault();
  #|    const next = tabs[(to + tabs.length) % tabs.length];
  #|    next.focus();
  #|    pick(next);
  #|  });
  #|
  #|  // ── Icons: <i data-lucide="name">, drawn once Lucide has come (from a CDN the frame may load) ──────────────────
  #|  const icons = () => globalThis.lucide?.createIcons({ attrs: { width: 16, height: 16 } });
  #|  addEventListener("DOMContentLoaded", () => {
  #|    for (const list of document.querySelectorAll('.nav[role="tablist"]')) {
  #|      const tab = list.querySelector('[role="tab"][aria-selected="true"]') ?? list.querySelector('[role="tab"].active') ?? list.querySelector('[role="tab"]');
  #|      if (tab) pick(tab);
  #|    }
  #|    if (!document.querySelector("[data-lucide]")) return;
  #|    if (globalThis.lucide) return icons();
  #|    document.head.append(Object.assign(document.createElement("script"), { src: "https://unpkg.com/lucide@1.17.0/dist/umd/lucide.js", onload: icons }));
  #|  });
  #|})();

///|
/// apps/android/app/src/main/assets/preview/page.js, as it is.
// kept across runs: a file's words, never written
pub let page_js : String =
  #|// First in each of a web service's pages in the app's preview (screens/Preview.kt puts it there, after <head>): what a
  #|// preview's frame and its service worker do on the web (cloud/src/preview.ts, web/src/annotate/frame.ts), for a
  #|// WebView that is the page itself. Three parts: the page's WebSockets through the app (socketScript() of
  #|// cloud/src/previewSocket.ts, as written out with the link below: regenerate it from there when that changes), its
  #|// requests' bodies, and marking the page.
  #|(() => {
  #|  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  #|  const en = self.__stillfailLang === "en";
  #|  const link = (() => {
  #|  // The page's own WebSockets go through the app (the preview's JavascriptInterface, StillFailPreviewNative, on to
  #|  // the core's preview.socket): kept in the top page, which the app speaks to, for the page and its frames alike.
  #|  let top;
  #|  try { top = window.top; void top.location.href; } catch { return null; }
  #|  const native = top.StillFailPreviewNative;
  #|  if (!native) return null;
  #|  if (!top.__stillfailSockets) {
  #|    const open = new Map();
  #|    top.__stillfailSockets = open;
  #|    top.__stillfailSocketEvent = (sid, kind, a, b, c) => {
  #|      const on = open.get(sid);
  #|      if (!on) return;
  #|      if (kind === "open") on.open(a);
  #|      else if (kind === "text") on.message(a);
  #|      else if (kind === "binary") on.message(Uint8Array.from(atob(a), (ch) => ch.charCodeAt(0)));
  #|      else if (kind === "bytes") on.message(a);
  #|      else if (kind === "close") { open.delete(sid); on.close(a, b, c); }
  #|    };
  #|  }
  #|  const base64 = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
  #|  // Where the top page's port carries bytes as they are (__stillfailSocketPort, set by its script below), a socket says
  #|  // and hears everything on it, in order, its frames never base64; else through StillFailPreviewNative. It opens once
  #|  // it is known which (a few seconds at most): nothing is sent on a socket before it is open.
  #|  return (path, protocols, on) => {
  #|    const sid = top.crypto.randomUUID();
  #|    top.__stillfailSockets.set(sid, on);
  #|    let port = null;
  #|    const opened = Promise.resolve(top.__stillfailSocketPort).then((got) => {
  #|      port = got || null;
  #|      native.open(sid, path, protocols.join(","), port !== null);
  #|    });
  #|    return {
  #|      send: (data) => (port ? port.send(sid, data) : typeof data === "string" ? native.send(sid, data) : native.sendBinary(sid, base64(data))),
  #|      close: (code, reason) => opened.then(() => (port ? port.close(sid, code, reason) : native.close(sid, code, reason))),
  #|    };
  #|  };
  #|})();
  #|  if (!link) return;
  #|  const Native = window.WebSocket;
  #|  // The sockets still open: a page that goes (reloaded, left) closes them, as the browser's own would be.
  #|  const live = new Set();
  #|  class PreviewSocket extends EventTarget {
  #|    static CONNECTING = 0;
  #|    static OPEN = 1;
  #|    static CLOSING = 2;
  #|    static CLOSED = 3;
  #|    constructor(url, protocols) {
  #|      super();
  #|      const to = new URL(url, location.href);
  #|      if (to.protocol === "http:" || to.protocol === "https:") to.protocol = to.protocol === "http:" ? "ws:" : "wss:";
  #|      if (to.protocol !== "ws:" && to.protocol !== "wss:") throw new DOMException((en ? "Not a WebSocket address: " : "不是 WebSocket 地址：") + url, "SyntaxError");
  #|      if (to.host !== location.host) return new Native(url, protocols);
  #|      this.url = to.href;
  #|      this.readyState = 0;
  #|      this.protocol = "";
  #|      this.extensions = "";
  #|      this.bufferedAmount = 0;
  #|      this.binaryType = "blob";
  #|      this.onopen = this.onmessage = this.onerror = this.onclose = null;
  #|      this._sending = Promise.resolve();
  #|      const asked = protocols === undefined ? [] : [].concat(protocols).map(String);
  #|      this._link = link(to.pathname + to.search, asked, {
  #|        open: (protocol) => {
  #|          if (this.readyState !== 0) return;
  #|          this.readyState = 1;
  #|          this.protocol = protocol;
  #|          this._fire(new Event("open"));
  #|        },
  #|        message: (data) => {
  #|          if (this.readyState !== 1) return;
  #|          let got = data;
  #|          if (typeof got !== "string") {
  #|            const bytes = new Uint8Array(got.length);
  #|            bytes.set(got);
  #|            got = this.binaryType === "arraybuffer" ? bytes.buffer : new Blob([bytes]);
  #|          }
  #|          this._fire(new MessageEvent("message", { data: got, origin: location.origin }));
  #|        },
  #|        close: (code, reason, failed) => {
  #|          if (this.readyState === 3) return;
  #|          this.readyState = 3;
  #|          live.delete(this);
  #|          if (failed) this._fire(new Event("error"));
  #|          this._fire(new CloseEvent("close", { code, reason, wasClean: !failed }));
  #|        },
  #|      });
  #|      live.add(this);
  #|    }
  #|    _fire(event) {
  #|      const handler = this["on" + event.type];
  #|      if (typeof handler === "function") handler.call(this, event);
  #|      this.dispatchEvent(event);
  #|    }
  #|    send(data) {
  #|      if (this.readyState === 0) throw new DOMException(en ? "WebSocket is not connected yet" : "WebSocket 还没连上", "InvalidStateError");
  #|      if (this.readyState !== 1) return;
  #|      // In the order sent, a Blob read first.
  #|      this._sending = this._sending.then(async () => {
  #|        if (this.readyState !== 1) return;
  #|        if (typeof data === "string") return this._link.send(data);
  #|        const buffer = data instanceof Blob ? await data.arrayBuffer() : ArrayBuffer.isView(data) ? data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) : data.slice(0);
  #|        this._link.send(new Uint8Array(buffer));
  #|      });
  #|    }
  #|    close(code, reason) {
  #|      if (this.readyState >= 2) return;
  #|      this.readyState = 2;
  #|      this._link.close(code ?? 1000, reason ?? "");
  #|    }
  #|  }
  #|  Object.assign(PreviewSocket.prototype, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
  #|  addEventListener("pagehide", () => { for (const socket of [...live]) socket.close(1001, ""); });
  #|  window.WebSocket = PreviewSocket;
  #|
  #|  // Workers the page makes from its own code (a blob: URL: a dev server's check that it is back up, in a shared
  #|  // worker) get the same WebSocket: WORKER_SOCKET goes first in their code, and each is given a port to open its
  #|  // sockets here through. A worker from a script of the service's (not blob:) keeps the browser's own.
  #|  const shim = "(() => {\n  const Native = self.WebSocket;\n  let relay = null;\n  const queued = [];\n  const sockets = new Map();\n  let next = 0;\n  const post = (message) => (relay ? relay.postMessage(message) : queued.push(message));\n  const take = (event) => {\n    if (!(event.data && event.data.stillfailSockets instanceof MessagePort)) return;\n    event.stopImmediatePropagation();\n    relay = event.data.stillfailSockets;\n    relay.onmessage = ({ data }) => sockets.get(data.id)?._on(data);\n    for (const message of queued.splice(0)) relay.postMessage(message);\n  };\n  if (typeof SharedWorkerGlobalScope !== \"undefined\" && self instanceof SharedWorkerGlobalScope) {\n    self.addEventListener(\"connect\", (event) => {\n      const port = event.ports[0];\n      port.addEventListener(\"message\", take);\n      port.start();\n    });\n  } else {\n    self.addEventListener(\"message\", take);\n  }\n  class WorkerSocket extends EventTarget {\n    static CONNECTING = 0;\n    static OPEN = 1;\n    static CLOSING = 2;\n    static CLOSED = 3;\n    constructor(url, protocols) {\n      super();\n      // A blob: worker's own location has no host: the page's origin is its.\n      const here = new URL(location.origin);\n      const to = new URL(url, location.protocol === \"blob:\" ? here : location.href);\n      if (to.host !== here.host) return new Native(url, protocols);\n      this.url = to.href;\n      this.readyState = 0;\n      this.protocol = \"\";\n      this.extensions = \"\";\n      this.bufferedAmount = 0;\n      this.binaryType = \"blob\";\n      this.onopen = this.onmessage = this.onerror = this.onclose = null;\n      this._id = ++next;\n      sockets.set(this._id, this);\n      post({ open: this._id, url: to.href, protocols: protocols === undefined ? [] : [].concat(protocols).map(String) });\n    }\n    _on(data) {\n      if (data.opened && this.readyState === 0) {\n        this.readyState = 1;\n        this.protocol = data.protocol || \"\";\n        this._fire(new Event(\"open\"));\n      } else if (data.message !== undefined && this.readyState === 1) {\n        const got = typeof data.message === \"string\" || this.binaryType === \"arraybuffer\" ? data.message : new Blob([data.message]);\n        this._fire(new MessageEvent(\"message\", { data: got }));\n      } else if (data.close && this.readyState !== 3) {\n        this.readyState = 3;\n        sockets.delete(this._id);\n        if (data.failed) this._fire(new Event(\"error\"));\n        this._fire(new CloseEvent(\"close\", { code: data.code, reason: data.reason, wasClean: !data.failed }));\n      }\n    }\n    _fire(event) {\n      const handler = this[\"on\" + event.type];\n      if (typeof handler === \"function\") handler.call(this, event);\n      this.dispatchEvent(event);\n    }\n    send(data) {\n      if (this.readyState === 0) throw new DOMException(" + JSON.stringify(en ? "WebSocket is not connected yet" : "WebSocket 还没连上") + ", \"InvalidStateError\");\n      if (this.readyState === 1) post({ id: this._id, send: data });\n    }\n    close(code, reason) {\n      if (this.readyState >= 2) return;\n      this.readyState = 2;\n      post({ id: this._id, close: [code ?? 1000, reason ?? \"\"] });\n    }\n  }\n  Object.assign(WorkerSocket.prototype, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });\n  self.WebSocket = WorkerSocket;\n})();\n";
  #|  const relay = (port) => {
  #|    const open = new Map();
  #|    port.onmessage = ({ data }) => {
  #|      if (data.open !== undefined) {
  #|        let socket;
  #|        try { socket = new PreviewSocket(data.url, data.protocols); } catch { return port.postMessage({ id: data.open, close: true, code: 1006, reason: "", failed: true }); }
  #|        socket.binaryType = "arraybuffer";
  #|        open.set(data.open, socket);
  #|        socket.onopen = () => port.postMessage({ id: data.open, opened: true, protocol: socket.protocol });
  #|        socket.onmessage = (event) => port.postMessage({ id: data.open, message: event.data });
  #|        socket.onclose = (event) => {
  #|          open.delete(data.open);
  #|          port.postMessage({ id: data.open, close: true, code: event.code, reason: event.reason, failed: !event.wasClean });
  #|        };
  #|      } else if (data.send !== undefined) {
  #|        open.get(data.id)?.send(data.send);
  #|      } else if (data.close) {
  #|        open.get(data.id)?.close(data.close[0], data.close[1]);
  #|      }
  #|    };
  #|  };
  #|  const withShim = (code) => {
  #|    // A "use strict" directive only counts first: it stays first.
  #|    const strict = /^\s*(["'])use strict\1;?/.exec(code);
  #|    return strict ? strict[0] + "\n" + shim + code.slice(strict[0].length) : shim + code;
  #|  };
  #|  const wrap = (Native, shared) => {
  #|    const Wrapped = function (url, options) {
  #|      const href = String(url);
  #|      if (!new.target || !href.startsWith("blob:")) return new Native(url, options);
  #|      let code;
  #|      try {
  #|        const read = new XMLHttpRequest();
  #|        read.open("GET", href, false);
  #|        read.send();
  #|        code = read.responseText;
  #|      } catch {
  #|        return new Native(url, options);
  #|      }
  #|      const worker = new Native(URL.createObjectURL(new Blob([withShim(code)], { type: "text/javascript" })), options);
  #|      const { port1, port2 } = new MessageChannel();
  #|      relay(port1);
  #|      (shared ? worker.port : worker).postMessage({ stillfailSockets: port2 }, [port2]);
  #|      return worker;
  #|    };
  #|    Wrapped.prototype = Native.prototype;
  #|    return Wrapped;
  #|  };
  #|  if (window.Worker) window.Worker = wrap(window.Worker, false);
  #|  if (window.SharedWorker) window.SharedWorker = wrap(window.SharedWorker, true);
  #|})();
  #|
  #|// What a request of the service's carries (a POST's body): the WebView does not hand request bodies to the app, so a
  #|// body of the page's own fetch or XMLHttpRequest to its own host is left with the app first (stash), under an id the
  #|// request then carries in a header, x-stillfail-body, which the app takes off again. The top page's fetch() goes to
  #|// the app whole instead, and its answer comes as it is sent (below).
  #|(() => {
  #|  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  #|  const en = self.__stillfailLang === "en";
  #|  const native = window.StillFailPreviewNative;
  #|  if (!native || window.__stillfailBodies) return;
  #|  window.__stillfailBodies = true;
  #|  const base64 = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
  #|  const own = (url) => { try { return new URL(url, location.href).origin === location.origin; } catch { return false; } };
  #|  const stash = (bytes, type) => {
  #|    const id = crypto.randomUUID();
  #|    native.stash(id, base64(bytes), type || "");
  #|    return id;
  #|  };
  #|  // The top page's fetch() of its own host goes through the app instead (PreviewWeb.kt fetchSaid), over a message port
  #|  // the app gives it: a WebView hands the page what the app answers only 2 KB at a time, and this way each piece of a
  #|  // body comes as the service sends it (a log, a streamed answer). Bytes go on it as they are where the app says it can
  #|  // (fetchBytes: an ArrayBuffer, the length of the fetch's id, the id, then the bytes), else as base64 in JSON. Without
  #|  // the port (a file's page, an app from before), as below.
  #|  const bridge = (() => {
  #|    if (window !== window.top || typeof native.fetchPort !== "function") return null;
  #|    const token = "stillfail-fetch-" + crypto.randomUUID();
  #|    const waiting = new Map();
  #|    const port = new Promise((resolve) => {
  #|      const take = (event) => {
  #|        // Only the app's own message (no window sent it) carrying the token asked for.
  #|        if (event.data !== token || event.source !== null || !event.ports || !event.ports[0]) return;
  #|        event.stopImmediatePropagation();
  #|        removeEventListener("message", take, true);
  #|        const got = event.ports[0];
  #|        got.onmessage = ({ data }) => {
  #|          if (data instanceof ArrayBuffer) {
  #|            const all = new Uint8Array(data);
  #|            const n = all[0];
  #|            if (!n || all.length < 1 + n) return;
  #|            const id = String.fromCharCode(...all.subarray(1, 1 + n));
  #|            const bytes = all.subarray(1 + n);
  #|            const fetching = waiting.get(id);
  #|            // Else a binary frame of a socket's.
  #|            if (fetching) fetching({ t: "chunk", bytes });
  #|            else window.__stillfailSocketEvent?.(id, "bytes", bytes);
  #|            return;
  #|          }
  #|          let said;
  #|          try { said = JSON.parse(data); } catch { return; }
  #|          if (said && said.t === "socket") return void window.__stillfailSocketEvent?.(said.id, said.kind, said.a, said.b, said.c);
  #|          waiting.get(said && said.id)?.(said);
  #|        };
  #|        resolve(got);
  #|      };
  #|      addEventListener("message", take, true);
  #|      setTimeout(() => resolve(null), 5000);
  #|    });
  #|    let asking = false;
  #|    try { asking = native.fetchPort(token) === true; } catch {}
  #|    if (!asking) return null;
  #|    let binary = false;
  #|    try { binary = native.fetchBytes() === true; } catch {}
  #|    const frame = (id, bytes) => {
  #|      const out = new Uint8Array(1 + id.length + bytes.length);
  #|      out[0] = id.length;
  #|      for (let i = 0; i < id.length; i++) out[1 + i] = id.charCodeAt(i);
  #|      out.set(bytes, 1 + id.length);
  #|      return out.buffer;
  #|    };
  #|    // The page's WebSockets (above) on the port too, where it carries bytes: a text frame and a close as JSON, a
  #|    // binary frame as it is, framed with its socket's id.
  #|    if (binary) {
  #|      window.__stillfailSocketPort = port.then((to) => to && {
  #|        send: (sid, data) => to.postMessage(typeof data === "string" ? JSON.stringify({ t: "socket", id: sid, text: data }) : frame(sid, data)),
  #|        close: (sid, code, reason) => to.postMessage(JSON.stringify({ t: "socket", id: sid, close: [code, reason] })),
  #|      });
  #|    }
  #|    const bytesOf = (text) => { const s = atob(text); const out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i); return out; };
  #|    const define = (answer, props) => { for (const [k, v] of Object.entries(props)) Object.defineProperty(answer, k, { value: v }); return answer; };
  #|    const go = (to, asked, bytes) => new Promise((resolve, reject) => {
  #|      const id = crypto.randomUUID();
  #|      const signal = asked.signal;
  #|      const aborted = () => signal.reason ?? new DOMException("signal is aborted without reason", "AbortError");
  #|      if (signal.aborted) return reject(aborted());
  #|      let stream = null;
  #|      let done = false;
  #|      const finish = () => { done = true; waiting.delete(id); signal.removeEventListener("abort", onAbort); };
  #|      const stop = () => { if (done) return; finish(); to.postMessage(JSON.stringify({ t: "stop", id })); };
  #|      const onAbort = () => {
  #|        const why = aborted();
  #|        if (stream) { try { stream.error(why); } catch {} } else reject(why);
  #|        stop();
  #|      };
  #|      signal.addEventListener("abort", onAbort);
  #|      waiting.set(id, (said) => {
  #|        if (done) return;
  #|        if (said.t === "head") {
  #|          const moved = said.status >= 300 && said.status < 400 && said.headers.some(([k]) => k.toLowerCase() === "location");
  #|          const url = location.origin + said.path;
  #|          if (moved && asked.redirect === "error") { stop(); return reject(new TypeError("Failed to fetch")); }
  #|          if (moved && asked.redirect === "manual") { stop(); return resolve(define(Response.error(), { type: "opaqueredirect", url, redirected: false })); }
  #|          const headers = new Headers();
  #|          for (const [k, v] of said.headers) if (!/^set-cookie2?$/i.test(k)) { try { headers.append(k, v); } catch {} }
  #|          const empty = asked.method === "HEAD" || [101, 204, 205, 304].includes(said.status);
  #|          const body = empty ? null : new ReadableStream({ start: (c) => { stream = c; }, cancel: () => stop() }, new ByteLengthQueuingStrategy({ highWaterMark: 1 << 16 }));
  #|          let answer;
  #|          try { answer = new Response(body, { status: said.status, statusText: said.statusText || "", headers }); } catch (e) { stop(); return reject(new TypeError("Failed to fetch: " + e.message)); }
  #|          resolve(define(answer, { url, redirected: said.redirected === true, type: "basic" }));
  #|        } else if (said.t === "chunk") {
  #|          if (!stream) return;
  #|          stream.enqueue(said.bytes || bytesOf(said.b));
  #|          // Read too slowly (as in PreviewWeb.kt's Chunks): given up rather than kept here without end.
  #|          if (stream.desiredSize < -(32 << 20)) { stream.error(new TypeError(en ? "The page read too slowly and was stopped" : "网页读得太慢，已停止")); stop(); }
  #|        } else if (said.t === "end") {
  #|          finish();
  #|          try { stream?.close(); } catch {}
  #|        } else if (said.t === "error") {
  #|          finish();
  #|          const why = new TypeError("Failed to fetch: " + said.message);
  #|          if (stream) { try { stream.error(why); } catch {} } else reject(why);
  #|        }
  #|      });
  #|      const to_ = new URL(asked.url);
  #|      const headers = new Headers(asked.headers);
  #|      // What the browser would add to a request of its own.
  #|      if (!headers.has("accept")) headers.set("accept", "*/*");
  #|      if (!headers.has("accept-language") && navigator.languages?.length) headers.set("accept-language", navigator.languages.join(","));
  #|      headers.set("user-agent", navigator.userAgent);
  #|      if (asked.referrer && asked.referrer !== "no-referrer") headers.set("referer", asked.referrer === "about:client" ? location.href : asked.referrer);
  #|      if (asked.method !== "GET" && asked.method !== "HEAD") headers.set("origin", location.origin);
  #|      const sent = bytes && bytes.length ? bytes : null;
  #|      // Its body first, as it is, where the port carries bytes.
  #|      if (sent && binary) to.postMessage(frame(id, sent));
  #|      to.postMessage(JSON.stringify({
  #|        t: "go", id, method: asked.method, path: to_.pathname + to_.search, headers: [...headers], redirect: asked.redirect,
  #|        cookies: asked.credentials !== "omit", body: sent && !binary ? base64(sent) : "",
  #|      }));
  #|    });
  #|    const through = async (asked, bytes) => {
  #|      const to = await port;
  #|      return to ? go(to, asked, bytes) : null;
  #|    };
  #|    through.ready = port;
  #|    return through;
  #|  })();
  #|  const fetched = window.fetch;
  #|  window.fetch = async function (input, init) {
  #|    let asked;
  #|    try { asked = new Request(input, init); } catch { return fetched.call(this, input, init); }
  #|    if (bridge && own(asked.url) && /^https?:$/.test(new URL(asked.url).protocol) && !new URL(asked.url).pathname.startsWith("/_stillfail/")) {
  #|      const bytes = asked.method === "GET" || asked.method === "HEAD" ? null : new Uint8Array(await asked.clone().arrayBuffer());
  #|      const answer = await bridge(asked, bytes);
  #|      if (answer) return answer;
  #|    }
  #|    if (!own(asked.url) || asked.method === "GET" || asked.method === "HEAD") return fetched.call(this, input, init);
  #|    const bytes = new Uint8Array(await asked.clone().arrayBuffer());
  #|    if (!bytes.length) return fetched.call(this, input, init);
  #|    const headers = new Headers(asked.headers);
  #|    headers.set("x-stillfail-body", stash(bytes, headers.get("content-type")));
  #|    return fetched.call(this, new Request(asked, { headers }));
  #|  };
  #|  const X = XMLHttpRequest.prototype;
  #|  const opened = X.open, sent = X.send, typed = X.setRequestHeader;
  #|  X.open = function (method, url, async) {
  #|    this.__stillfail = { method: String(method).toUpperCase(), url: String(url), async: async !== false, type: null };
  #|    return opened.apply(this, arguments);
  #|  };
  #|  X.setRequestHeader = function (name, value) {
  #|    if (this.__stillfail && String(name).toLowerCase() === "content-type") this.__stillfail.type = String(value);
  #|    return typed.apply(this, arguments);
  #|  };
  #|  X.send = function (body) {
  #|    const asked = this.__stillfail;
  #|    if (!asked || body == null || asked.method === "GET" || asked.method === "HEAD" || !own(asked.url)) return sent.apply(this, arguments);
  #|    if (typeof body === "string") {
  #|      typed.call(this, "x-stillfail-body", stash(new TextEncoder().encode(body), asked.type || "text/plain;charset=UTF-8"));
  #|      return sent.call(this, body);
  #|    }
  #|    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
  #|      const bytes = body instanceof ArrayBuffer ? new Uint8Array(body) : new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  #|      typed.call(this, "x-stillfail-body", stash(bytes, asked.type));
  #|      return sent.call(this, body);
  #|    }
  #|    // A Blob, a form: read first (only when the request waits for nothing: a synchronous one goes without).
  #|    if (!asked.async) return sent.apply(this, arguments);
  #|    const answer = new Response(body);
  #|    const type = asked.type || answer.headers.get("content-type");
  #|    answer.arrayBuffer().then((buffer) => {
  #|      typed.call(this, "x-stillfail-body", stash(new Uint8Array(buffer), type));
  #|      if (!asked.type && type) typed.call(this, "content-type", type);
  #|      sent.call(this, buffer);
  #|    }, () => sent.call(this, body));
  #|  };
  #|
  #|  // The top page's asynchronous XMLHttpRequest of its own host goes the same way (its progress as the body comes): the
  #|  // request itself stays the page's, with what it says (its state, its answer, its events) given here.
  #|  if (!bridge) return;
  #|  const opened2 = X.open, sent2 = X.send, typed2 = X.setRequestHeader, aborted2 = X.abort, header2 = X.getResponseHeader, headers2 = X.getAllResponseHeaders;
  #|  const SHOWN = ["readyState", "status", "statusText", "responseURL", "responseText", "response", "responseXML"];
  #|  const unshow = (xhr) => { for (const k of SHOWN) delete xhr[k]; };
  #|  X.open = function (method, url, async) {
  #|    const had = this.__stillfailX;
  #|    if (had && had.state && !had.state.over) { had.state.over = true; had.controller.abort(); }
  #|    unshow(this);
  #|    this.__stillfailX = { method: String(method).toUpperCase(), url: String(url), async: async !== false, headers: [] };
  #|    return opened2.apply(this, arguments);
  #|  };
  #|  X.setRequestHeader = function (name, value) {
  #|    this.__stillfailX?.headers.push([String(name), String(value)]);
  #|    return typed2.apply(this, arguments);
  #|  };
  #|  X.getResponseHeader = function (name) {
  #|    const state = this.__stillfailX?.state;
  #|    if (!state) return header2.apply(this, arguments);
  #|    return state.readyState >= 2 && state.headers ? state.headers.get(name) : null;
  #|  };
  #|  X.getAllResponseHeaders = function () {
  #|    const state = this.__stillfailX?.state;
  #|    if (!state) return headers2.apply(this, arguments);
  #|    return state.readyState >= 2 && state.headers ? [...state.headers].map(([k, v]) => k + ": " + v + "\r\n").join("") : "";
  #|  };
  #|  X.abort = function () {
  #|    const asked = this.__stillfailX;
  #|    if (!asked || !asked.state) return aborted2.apply(this, arguments);
  #|    const state = asked.state;
  #|    if (state.over) { state.readyState = 0; return; }
  #|    state.over = true;
  #|    asked.controller.abort();
  #|    state.fail("abort");
  #|    state.readyState = 0;
  #|  };
  #|  X.send = function (body) {
  #|    const asked = this.__stillfailX;
  #|    const xhr = this;
  #|    let to;
  #|    try { to = new URL(asked.url, location.href); } catch { return sent2.apply(this, arguments); }
  #|    if (!asked || !asked.async || asked.state || to.origin !== location.origin || to.pathname.startsWith("/_stillfail/") || xhr.responseType === "document" || (typeof Document !== "undefined" && body instanceof Document)) return sent2.apply(this, arguments);
  #|    const args = arguments;
  #|    const controller = new AbortController();
  #|    const state = { readyState: 1, status: 0, statusText: "", url: "", headers: null, text: "", pieces: [], loaded: 0, over: false };
  #|    asked.controller = controller;
  #|    const fire = (type) => xhr.dispatchEvent(type === "readystatechange" ? new Event(type) : new ProgressEvent(type, { lengthComputable: state.total > 0, loaded: state.loaded, total: state.total || 0 }));
  #|    const move = (n) => { state.readyState = n; fire("readystatechange"); };
  #|    state.fail = (type) => {
  #|      state.status = 0; state.statusText = ""; state.headers = null; state.text = ""; state.pieces = [];
  #|      move(4); fire(type); fire("loadend");
  #|    };
  #|    const whole = () => {
  #|      if (state.readyState !== 4) return null;
  #|      const type = xhr.responseType;
  #|      if (type === "json") { try { return JSON.parse(state.text); } catch { return null; } }
  #|      if (type === "arraybuffer") return joined();
  #|      if (type === "blob") return new Blob(state.pieces, { type: state.headers?.get("content-type") || "" });
  #|      return state.text;
  #|    };
  #|    const joined = () => { const out = new Uint8Array(state.loaded); let at = 0; for (const p of state.pieces) { out.set(p, at); at += p.length; } return out.buffer; };
  #|    (async () => {
  #|      const port = await bridge.ready;
  #|      if (!port) return sent2.apply(xhr, args);
  #|      let request;
  #|      try {
  #|        const headers = new Headers(asked.headers);
  #|        request = new Request(to.href, { method: asked.method, headers, body: asked.method === "GET" || asked.method === "HEAD" ? undefined : body ?? undefined, signal: controller.signal, credentials: "include" });
  #|      } catch {
  #|        return sent2.apply(xhr, args);
  #|      }
  #|      asked.state = state;
  #|      Object.defineProperties(xhr, {
  #|        readyState: { get: () => state.readyState, configurable: true },
  #|        status: { get: () => state.status, configurable: true },
  #|        statusText: { get: () => state.statusText, configurable: true },
  #|        responseURL: { get: () => state.url, configurable: true },
  #|        responseXML: { get: () => null, configurable: true },
  #|        responseText: { get: () => { if (xhr.responseType && xhr.responseType !== "text") throw new DOMException(en ? "responseType is not text" : "responseType 不是文字", "InvalidStateError"); return state.text; }, configurable: true },
  #|        response: { get: () => (!xhr.responseType || xhr.responseType === "text" ? state.text : whole()), configurable: true },
  #|      });
  #|      fire("loadstart");
  #|      let timer = 0;
  #|      if (xhr.timeout > 0) timer = setTimeout(() => { if (state.over) return; state.over = true; controller.abort(); state.fail("timeout"); }, xhr.timeout);
  #|      try {
  #|        const bytes = asked.method === "GET" || asked.method === "HEAD" ? null : new Uint8Array(await request.clone().arrayBuffer());
  #|        const answer = await bridge(request, bytes);
  #|        if (state.over) return;
  #|        state.status = answer.status; state.statusText = answer.statusText; state.url = answer.url; state.headers = answer.headers;
  #|        state.total = Number(answer.headers.get("content-length")) || 0;
  #|        move(2);
  #|        const charset = /charset=([^;]+)/i.exec(answer.headers.get("content-type") || "")?.[1]?.trim().replace(/"/g, "") || "utf-8";
  #|        let decode;
  #|        try { decode = new TextDecoder(charset); } catch { decode = new TextDecoder(); }
  #|        const text = !xhr.responseType || xhr.responseType === "text" || xhr.responseType === "json";
  #|        if (answer.body) {
  #|          const reader = answer.body.getReader();
  #|          for (;;) {
  #|            const { value, done } = await reader.read();
  #|            if (state.over) return;
  #|            if (done) break;
  #|            state.loaded += value.length;
  #|            if (text) state.text += decode.decode(value, { stream: true }); else state.pieces.push(value);
  #|            move(3);
  #|            fire("progress");
  #|          }
  #|        }
  #|        if (text) state.text += decode.decode();
  #|        state.over = true;
  #|        clearTimeout(timer);
  #|        if (state.readyState < 3) move(3);
  #|        move(4);
  #|        fire("load");
  #|        fire("loadend");
  #|      } catch {
  #|        clearTimeout(timer);
  #|        if (state.over) return;
  #|        state.over = true;
  #|        state.fail("error");
  #|      }
  #|    })();
  #|  };
  #|})();
  #|
  #|// Marking the page for a chat's agent (as web/src/annotate/frame.ts does in a preview's frame): told by the app
  #|// (__stillfailMarks.on / remove / clear / scroll), it holds the page's taps while picking, says what was picked
  #|// (StillFailPreviewNative.marked, `picked`) and where the marks are as the page scrolls or moves (`at`, in the
  #|// page's viewport, with its width so the app knows its scale). The app draws the marks, and takes the pictures.
  #|(() => {
  #|  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  #|  const en = self.__stillfailLang === "en";
  #|  const native = window.StillFailPreviewNative;
  #|  if (!native || window !== window.top || window.__stillfailMarks) return;
  #|  let on = false;
  #|  let marks = [];
  #|  let next = 1;
  #|  const say = (data) => native.marked(JSON.stringify(data));
  #|  const box = (r) => ({ x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) });
  #|  let told = "";
  #|  const draw = () => {
  #|    const at = marks.map((m) => ({ n: m.n, ...box(m.el.isConnected ? m.el.getBoundingClientRect() : m.rect) }));
  #|    const now = JSON.stringify([innerWidth, at]);
  #|    if (now !== told) { told = now; say({ event: "at", at, width: innerWidth, height: innerHeight }); }
  #|  };
  #|  let frame = 0;
  #|  const loop = () => { draw(); frame = on || marks.length ? requestAnimationFrame(loop) : 0; };
  #|  const wake = () => { if (!frame) frame = requestAnimationFrame(loop); };
  #|  const target = (el) => {
  #|    if (!el || !(el instanceof Element)) return null;
  #|    const svg = el.closest("svg");
  #|    return svg && svg !== el ? svg : el;
  #|  };
  #|  const pick = (el) => {
  #|    const had = marks.find((m) => m.el === el);
  #|    if (had) { say({ event: "focus", n: had.n }); return; }
  #|    const r = el.getBoundingClientRect();
  #|    const n = next++;
  #|    marks.push({ n, el, rect: r });
  #|    say({ event: "picked", mark: {
  #|      n, path: location.pathname + location.search + location.hash, viewport: { width: innerWidth, height: innerHeight },
  #|      label: label(el), kind: kindOf(el), selector: selector(el), text: words(el), rect: box(r),
  #|      page: box(new DOMRect(r.left + scrollX, r.top + scrollY, r.width, r.height)), component: component(el),
  #|    } });
  #|    wake();
  #|  };
  #|  const hold = (event) => {
  #|    if (!on) return;
  #|    event.preventDefault();
  #|    event.stopImmediatePropagation();
  #|    if (event.type === "click") { const el = target(event.target); if (el) pick(el); }
  #|  };
  #|  for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "click", "dblclick", "auxclick", "contextmenu", "submit"]) document.addEventListener(type, hold, true);
  #|  window.__stillfailMarks = {
  #|    on(value) { on = value; wake(); },
  #|    remove(n) { marks = marks.filter((m) => m.n !== n); told = ""; wake(); },
  #|    clear() { marks = []; next = 1; told = ""; wake(); },
  #|    /** Where a mark is now, in the viewport; `center`: the page scrolled first so that it is in the middle. */
  #|    place(n, center) {
  #|      const m = marks.find((x) => x.n === n);
  #|      if (!m) return null;
  #|      if (center) {
  #|        const r = m.el.isConnected ? m.el.getBoundingClientRect() : m.rect;
  #|        scrollTo({ left: scrollX, top: Math.max(0, r.top + scrollY + r.height / 2 - innerHeight / 2), behavior: "instant" });
  #|      }
  #|      return JSON.stringify({ ...box(m.el.isConnected ? m.el.getBoundingClientRect() : m.rect), width: innerWidth, scrollY });
  #|    },
  #|    back(y) { scrollTo({ left: scrollX, top: y, behavior: "instant" }); },
  #|  };
  #|
  #|  /** Names that look made by a build (css-in-js, css modules) say nothing to a person. */
  #|  const made = (name) => /\d{3,}|^css-|^sc-|^_|__[A-Za-z0-9]{5,}$|^[a-z]{1,3}-[A-Za-z0-9]{5,}$/.test(name);
  #|  function label(el) {
  #|    let text = el.localName;
  #|    if (el.id && !made(el.id)) text += "#" + el.id;
  #|    const classes = [...el.classList].filter((c) => !made(c)).slice(0, 3);
  #|    if (classes.length) text += "." + classes.join(".");
  #|    return text;
  #|  }
  #|  const KINDS = en ? {
  #|    button: "button", a: "link", img: "image", svg: "icon", picture: "image", video: "video", input: "input", textarea: "input",
  #|    select: "dropdown", label: "label", h1: "heading", h2: "heading", h3: "heading", h4: "heading", h5: "heading", h6: "heading", p: "paragraph",
  #|    li: "list item", ul: "list", ol: "list", nav: "navigation", header: "header", footer: "footer", table: "table", tr: "table row", td: "cell",
  #|    th: "table header", form: "form", aside: "sidebar", dialog: "dialog", code: "code", pre: "code",
  #|  } : {
  #|    button: "按钮", a: "链接", img: "图片", svg: "图标", picture: "图片", video: "视频", input: "输入框", textarea: "输入框",
  #|    select: "下拉框", label: "标签", h1: "标题", h2: "标题", h3: "标题", h4: "标题", h5: "标题", h6: "标题", p: "段落",
  #|    li: "列表项", ul: "列表", ol: "列表", nav: "导航", header: "页头", footer: "页脚", table: "表格", tr: "表格行", td: "单元格",
  #|    th: "表头", form: "表单", aside: "侧栏", dialog: "对话框", code: "代码", pre: "代码",
  #|  };
  #|  function kindOf(el) {
  #|    const role = el.getAttribute("role");
  #|    if (role === "button") return KINDS.button;
  #|    if (role === "link") return KINDS.a;
  #|    if (el instanceof HTMLInputElement && ["button", "submit", "reset"].includes(el.type)) return KINDS.button;
  #|    if (el instanceof HTMLInputElement && ["checkbox", "radio"].includes(el.type)) return en ? "checkbox" : "选框";
  #|    if (KINDS[el.localName]) return KINDS[el.localName];
  #|    const own = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
  #|    return own ? (en ? "text" : "文字") : (en ? "block" : "区块");
  #|  }
  #|  function selector(el) {
  #|    const one = (css) => { try { return document.querySelectorAll(css).length === 1; } catch { return false; } };
  #|    const parts = [];
  #|    for (let node = el; node && node !== document.documentElement; node = node.parentElement) {
  #|      if (node.id && !made(node.id) && one("#" + CSS.escape(node.id))) { parts.unshift("#" + CSS.escape(node.id)); break; }
  #|      const tag = ["data-testid", "data-test", "data-cy", "data-qa"].find((a) => node.hasAttribute(a));
  #|      if (tag) {
  #|        const css = "[" + tag + '="' + CSS.escape(node.getAttribute(tag)) + '"]';
  #|        if (one(css)) { parts.unshift(css); break; }
  #|      }
  #|      let part = node.localName;
  #|      const kin = node.parentElement ? [...node.parentElement.children].filter((c) => c.localName === node.localName) : [];
  #|      if (kin.length > 1) part += ":nth-of-type(" + (kin.indexOf(node) + 1) + ")";
  #|      parts.unshift(part);
  #|      if (node.localName === "body") break;
  #|    }
  #|    return parts.join(" > ");
  #|  }
  #|  function words(el) {
  #|    const cut = (s) => { const t = s.replace(/\s+/g, " ").trim(); return t.length > 80 ? t.slice(0, 80) + "…" : t; };
  #|    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) return cut(el.value || el.placeholder || "");
  #|    if (el instanceof HTMLImageElement) return cut(el.alt);
  #|    const aria = el.getAttribute("aria-label");
  #|    if (aria) return cut(aria);
  #|    return cut(el.innerText ?? el.textContent ?? "");
  #|  }
  #|  function component(el) {
  #|    const names = [];
  #|    let source = null;
  #|    const fiberKey = Object.keys(el).find((k) => k.startsWith("__reactFiber$"));
  #|    if (fiberKey) {
  #|      for (let fiber = el[fiberKey]; fiber && names.length < 4; fiber = fiber.return) {
  #|        if (!source && fiber._debugSource) source = fiber._debugSource.fileName + ":" + fiber._debugSource.lineNumber;
  #|        const type = fiber.type;
  #|        if (!type || typeof type === "string") continue;
  #|        const name = type.displayName || type.name || (type.render && type.render.name);
  #|        if (name && !names.includes(name) && /^[A-Z]/.test(name)) names.unshift(name);
  #|      }
  #|    } else {
  #|      let node = el;
  #|      while (node && !node.__vueParentComponent) node = node.parentElement;
  #|      for (let c = node ? node.__vueParentComponent : null; c && names.length < 4; c = c.parent) {
  #|        const name = c.type.__name || c.type.name || (c.type.__file && c.type.__file.split("/").pop().replace(/\.vue$/, ""));
  #|        if (!source && c.type.__file) source = c.type.__file;
  #|        if (name && !names.includes(name)) names.unshift(name);
  #|      }
  #|    }
  #|    if (!names.length) return null;
  #|    return names.join(" › ") + (source ? "（" + source + "）" : "");
  #|  }
  #|})();
