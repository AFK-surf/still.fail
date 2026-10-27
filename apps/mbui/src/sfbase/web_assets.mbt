// Made by scripts/webassets.py from the web's own files (do not edit: run it again when they change).

///|
/// web/src/viz/ember-viz.css, as it is.
// kept across runs: a file's words, never written
pub let viz_css : String =
  #|/*
  #| * The stylesheet of an inline visualization (Viz.tsx, the app's viz_file.mbt): an HTML file placed in a message, drawn
  #| * in a sandboxed frame. The page hands in still.fail's own tokens for the theme it shows as --e-* (its colours, type,
  #| * corners); this sheet says them again as the design tokens agents write against (--sf-*), styles still.fail's
  #| * components (components.js: <sf-…> elements) and keeps Codex's visualize.css names (--background, .btn, .card…) as
  #| * aliases, so a figure written for that still draws. Keep it in step with station/src/skills/stillfail-viz.md.
  #| *
  #| * What everything looks like is still.fail's own (docs/ui-panels.md): grey unless something is wrong, what is chosen
  #| * in ink and never the accent, things set apart by grounds and room rather than frames and lines, the app's six sizes
  #| * of type, numbers one width.
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
  #|  /* ── Design tokens ─────────────────────────────────────────────────────────────── */
  #|
  #|  /* Grounds: the page the figure lies on, a card on it, a quiet ground under what is in it (a pill, a node), what is
  #|     lifted out of a tinted track, a field's. */
  #|  --sf-page: var(--e-canvas, #fff);
  #|  --sf-card: var(--e-paper, #f6f4ef);
  #|  --sf-quiet: var(--e-neutral-bg, rgb(36 39 43 / .075));
  #|  --sf-lifted: var(--e-lifted, var(--sf-page));
  #|  --sf-field: var(--e-canvas, #fff);
  #|  --sf-hover: var(--e-hover, rgb(36 39 43 / .065));
  #|  --sf-selected: var(--e-selected, #ebe8e2);
  #|  /* Words: ink, and the one grey (labels, notes, what is said under a title). */
  #|  --sf-ink: var(--e-text, #3a3d42);
  #|  --sf-muted: var(--e-muted, #565b62);
  #|  /* Lines: only what has nothing in it (a chart's grid, a gauge's empty track, a step's rail). */
  #|  --sf-line: var(--e-line, rgb(50 45 36 / .141));
  #|  --sf-line-strong: var(--e-line-strong, #cdd0d5);
  #|  /* The solid button's ground and words. */
  #|  --sf-primary: var(--e-primary, #24272b);
  #|  --sf-on-primary: var(--e-on-primary, #fff);
  #|  /* The accent: a fill or a small mark (a progress bar, a checked box), never words or emphasis. */
  #|  --sf-accent: var(--e-accent, #dc5929);
  #|  /* Tones, each an ink for words and marks and a ground (that ink at an opacity) under them. Only for what must be
  #|     noticed: a failure (red), a warning (amber), done (green), information (blue), merged (purple). */
  #|  --sf-blue: var(--e-blue, #0047ae);
  #|  --sf-blue-ground: var(--e-blue-bg, color-mix(in srgb, var(--sf-blue) 18%, transparent));
  #|  --sf-green: var(--e-green, #026039);
  #|  --sf-green-ground: var(--e-green-bg, color-mix(in srgb, var(--sf-green) 18%, transparent));
  #|  --sf-amber: var(--e-amber, #6e4802);
  #|  --sf-amber-ground: var(--e-amber-bg, color-mix(in srgb, var(--sf-amber) 18%, transparent));
  #|  --sf-red: var(--e-red, #9a2830);
  #|  --sf-red-ground: var(--e-red-bg, color-mix(in srgb, var(--sf-red) 18%, transparent));
  #|  --sf-purple: var(--e-purple, var(--e-code-inline, #6830bf));
  #|  --sf-purple-ground: var(--e-purple-bg, color-mix(in srgb, var(--sf-purple) 18%, transparent));
  #|  /* Chart series in order: ink first (one series needs no colour), then the tones. */
  #|  --sf-series-1: var(--sf-ink);
  #|  --sf-series-2: var(--sf-blue);
  #|  --sf-series-3: var(--sf-green);
  #|  --sf-series-4: var(--sf-purple);
  #|  --sf-series-5: var(--sf-amber);
  #|  --sf-series-6: var(--sf-red);
  #|  --sf-shadow: var(--e-shadow, rgb(0 0 0 / 10%));
  #|
  #|  /* Type: six roles, each a size and its line (a phone's a size up); weights 400, 500 to stand out, 600 for titles. */
  #|  --sf-font: var(--e-font-body, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif);
  #|  --sf-font-mono: ui-monospace, SFMono-Regular, Menlo, monospace;
  #|  --sf-text-caption: var(--e-text-caption, 11px);
  #|  --sf-leading-caption: var(--e-leading-caption, 16px);
  #|  --sf-text-meta: var(--e-text-meta, 12px);
  #|  --sf-leading-meta: var(--e-leading-meta, 18px);
  #|  --sf-text-ui: var(--e-text-ui, 13px);
  #|  --sf-leading-ui: var(--e-leading-ui, 20px);
  #|  --sf-text-body: var(--e-text-body, 14px);
  #|  --sf-leading-body: var(--e-leading-body, 22px);
  #|  --sf-text-title: var(--e-text-title, 16px);
  #|  --sf-leading-title: var(--e-leading-title, 24px);
  #|  --sf-text-heading: var(--e-text-heading, 22px);
  #|  --sf-leading-heading: var(--e-leading-heading, 30px);
  #|  --sf-text-display: var(--e-text-display, 28px);
  #|
  #|  /* Corners: a card's, a field's (and a box in a card), a small mark's; pills and dots are round. */
  #|  --sf-r-card: var(--e-r-card, 20px);
  #|  --sf-r-field: var(--e-r-field, 12px);
  #|  --sf-r-small: calc(var(--sf-r-field) / 2);
  #|  --sf-corner-shape: var(--e-corner-shape, round);
  #|  /* Room: a card's padding, a row's words in from its ground, gaps between things. */
  #|  --sf-card-pad: 20px;
  #|  --sf-text-in: 10px;
  #|  --sf-gap: 12px;
  #|  --sf-gap-s: 6px;
  #|  --sf-gap-l: 20px;
  #|  /* Motion. */
  #|  --sf-dur: 140ms;
  #|  --sf-ease: cubic-bezier(.2, .7, .2, 1);
  #|
  #|  /* ── Codex's names, as aliases ─────────────────────────────────────────────────── */
  #|  --background: var(--sf-page);
  #|  --foreground: var(--sf-ink);
  #|  --card: var(--sf-card);
  #|  --card-foreground: var(--sf-ink);
  #|  --popover: var(--sf-page);
  #|  --popover-foreground: var(--sf-ink);
  #|  --primary: var(--sf-primary);
  #|  --primary-foreground: var(--sf-on-primary);
  #|  --secondary: var(--sf-quiet);
  #|  --secondary-foreground: var(--sf-ink);
  #|  --muted: var(--sf-quiet);
  #|  --muted-foreground: var(--sf-muted);
  #|  --accent: var(--e-accent-bg, color-mix(in srgb, var(--sf-accent) 18%, transparent));
  #|  --accent-foreground: var(--e-accent-text, #982e01);
  #|  --brand: var(--sf-accent);
  #|  --destructive: var(--sf-red);
  #|  --border: var(--sf-line);
  #|  --border-strong: var(--sf-line-strong);
  #|  --input: var(--sf-line-strong);
  #|  --ring: var(--e-field-focus, #646970);
  #|  --hover: var(--sf-hover);
  #|  --selected: var(--sf-selected);
  #|  --shadow: var(--sf-shadow);
  #|  --blue: var(--sf-blue);
  #|  --green: var(--sf-green);
  #|  --orange: var(--sf-accent);
  #|  --red: var(--sf-red);
  #|  --purple: var(--sf-purple);
  #|  --yellow: var(--sf-amber);
  #|  --blue-bg: var(--sf-blue-ground);
  #|  --green-bg: var(--sf-green-ground);
  #|  --orange-bg: var(--accent);
  #|  --red-bg: var(--sf-red-ground);
  #|  --yellow-bg: var(--sf-amber-ground);
  #|  --purple-bg: var(--sf-purple-ground);
  #|  --chart-1: var(--sf-series-1);
  #|  --chart-2: var(--sf-series-2);
  #|  --chart-3: var(--sf-series-3);
  #|  --chart-4: var(--sf-series-4);
  #|  --chart-5: var(--sf-series-5);
  #|  --chart-6: var(--sf-series-6);
  #|  --font-sans: var(--sf-font);
  #|  --font-mono: var(--sf-font-mono);
  #|  --font-size-base: var(--sf-text-body);
  #|  --font-size-small: var(--sf-text-meta);
  #|  --font-size-ui: var(--sf-text-ui);
  #|  --font-size-h1: var(--sf-text-heading);
  #|  --font-size-h2: var(--sf-text-title);
  #|  --font-size-h3: var(--sf-text-body);
  #|  --font-size-display: var(--sf-text-display);
  #|  --line-height: var(--sf-leading-body);
  #|  --radius-card: var(--sf-r-card);
  #|  --radius-field: var(--sf-r-field);
  #|  --radius-small: var(--sf-r-small);
  #|  --corner-shape: var(--sf-corner-shape);
  #|  --dur: var(--sf-dur);
  #|  --ease-out: var(--sf-ease);
  #|
  #|  background: transparent;
  #|  color: var(--sf-ink);
  #|  font: var(--sf-text-body) / var(--sf-leading-body) var(--sf-font);
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
  #|h1, h2, h3, h4 { margin: 0 0 8px; font-weight: 600; }
  #|h1 { font-size: var(--sf-text-heading); line-height: var(--sf-leading-heading); }
  #|h2 { font-size: var(--sf-text-title); line-height: var(--sf-leading-title); }
  #|h3, h4 { font-size: var(--sf-text-body); line-height: var(--sf-leading-body); }
  #|p { margin: 0 0 8px; }
  #|p:last-child { margin-bottom: 0; }
  #|a { color: var(--sf-blue); text-decoration: none; }
  #|a:hover { text-decoration: underline; }
  #|code, kbd, pre { font-family: var(--sf-font-mono); font-size: .92em; }
  #|code { padding: .1em .35em; border-radius: var(--sf-r-small); background: var(--sf-quiet); }
  #|pre { margin: 0 0 8px; padding: 10px 12px; border-radius: var(--sf-r-field); background: var(--sf-quiet); overflow-x: auto; }
  #|pre code { padding: 0; background: none; }
  #|hr { height: 0; margin: 12px 0; border: 0; }
  #|svg { color: var(--sf-ink); }
  #|svg text { fill: currentColor; font-family: var(--sf-font); }
  #|button { font: inherit; color: inherit; }
  #|
  #|/* ── Layout ───────────────────────────────────────────────────────────────────────── */
  #|sf-stack, .widget { display: flex; flex-direction: column; gap: var(--sf-gap); min-width: 0; }
  #|sf-row, .viz-row, .viz-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; min-width: 0; }
  #|sf-grid, .viz-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(var(--min, 160px), 100%), 1fr)); gap: var(--sf-gap); }
  #|sf-card, .card {
  #|  display: flex; flex-direction: column; gap: var(--sf-gap); min-width: 0; padding: var(--sf-card-pad);
  #|  border-radius: var(--sf-r-card); corner-shape: var(--sf-corner-shape); background: var(--sf-card); color: var(--sf-ink);
  #|}
  #|sf-card > :last-child, .card > :last-child { margin-bottom: 0; }
  #|.sf-head { display: flex; flex-direction: column; gap: 2px; }
  #|.sf-title { font-size: var(--sf-text-title); line-height: var(--sf-leading-title); font-weight: 600; }
  #|.sf-sub, sf-note, .viz-note, .text-muted { color: var(--sf-muted); }
  #|sf-note, .viz-note, .sf-sub, .text-small { font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|sf-note { display: block; }
  #|.viz-dotted-background {
  #|  background-image: radial-gradient(color-mix(in srgb, var(--sf-ink) 14%, transparent) 1px, transparent 1px);
  #|  background-size: 14px 14px;
  #|}
  #|
  #|/* ── Text helpers ─────────────────────────────────────────────────────────────────── */
  #|.text-destructive { color: var(--sf-red); }
  #|.text-warning { color: var(--sf-amber); }
  #|.text-success { color: var(--sf-green); }
  #|.text-brand { color: var(--accent-foreground); }
  #|.tabular-nums { font-variant-numeric: tabular-nums; }
  #|.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
  #|.cursor-interaction { cursor: pointer; }
  #|
  #|/* ── A number with its label ──────────────────────────────────────────────────────── */
  #|sf-stat, .viz-stat { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  #|sf-stat { padding: 16px var(--sf-card-pad); border-radius: var(--sf-r-card); corner-shape: var(--sf-corner-shape); background: var(--sf-card); }
  #|sf-stat[plain] { padding: 0; background: none; }
  #|.sf-stat-label, .viz-stat-label { color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.sf-stat-value, .viz-stat-value { font-size: var(--sf-text-display); line-height: 1.25; font-weight: 600; letter-spacing: -.01em; }
  #|.sf-stat-unit { margin-left: 2px; color: var(--sf-muted); font-size: var(--sf-text-title); font-weight: 500; letter-spacing: 0; }
  #|.sf-stat-note { display: flex; align-items: center; gap: 4px; color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|
  #|/* ── Status: a small dot and words; badges: the app's pills ───────────────────────── */
  #|sf-status { display: inline-flex; align-items: center; gap: 6px; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); }
  #|.sf-dot { flex: none; width: 7px; height: 7px; border-radius: 50%; background: var(--sf-muted); }
  #|.sf-dot[data-tone="ok"], .sf-dot[data-tone="green"] { background: var(--sf-green); }
  #|.sf-dot[data-tone="busy"], .sf-dot[data-tone="warn"], .sf-dot[data-tone="amber"] { background: var(--sf-amber); }
  #|.sf-dot[data-tone="error"], .sf-dot[data-tone="red"] { background: var(--sf-red); }
  #|.sf-dot[data-tone="info"], .sf-dot[data-tone="blue"] { background: var(--sf-blue); }
  #|.sf-dot[data-tone="purple"] { background: var(--sf-purple); }
  #|.sf-dot[data-tone="off"] { background: transparent; box-shadow: inset 0 0 0 1.5px var(--sf-muted); }
  #|sf-badge, .viz-badge {
  #|  display: inline-flex; align-items: center; gap: 4px; height: 22px; padding: 0 9px; border-radius: 999px;
  #|  background: var(--sf-quiet); color: var(--sf-muted); font-size: var(--sf-text-meta); font-weight: 500; white-space: nowrap;
  #|  vertical-align: middle;
  #|}
  #|:is(sf-badge, .viz-badge):is([tone="blue"], [tone="info"], .is-blue) { background: var(--sf-blue-ground); color: var(--sf-blue); }
  #|:is(sf-badge, .viz-badge):is([tone="green"], [tone="ok"], .is-green) { background: var(--sf-green-ground); color: var(--sf-green); }
  #|:is(sf-badge, .viz-badge):is([tone="amber"], [tone="warn"], .is-yellow) { background: var(--sf-amber-ground); color: var(--sf-amber); }
  #|:is(sf-badge, .viz-badge):is([tone="red"], [tone="error"], .is-red) { background: var(--sf-red-ground); color: var(--sf-red); }
  #|:is(sf-badge, .viz-badge):is([tone="purple"], .is-purple) { background: var(--sf-purple-ground); color: var(--sf-purple); }
  #|.viz-badge.is-orange { background: var(--accent); color: var(--accent-foreground); }
  #|
  #|/* ── Tables: rows apart by room, no lines; the head quieter ───────────────────────── */
  #|sf-table { display: block; }
  #|.sf-table-scroll, .table-responsive { max-width: 100%; overflow-x: auto; }
  #|sf-table table, .table { width: 100%; border-collapse: collapse; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); }
  #|:is(sf-table, .table) :is(th, td) { padding: 7px var(--sf-text-in); text-align: left; vertical-align: top; }
  #|:is(sf-table, .table) th { color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); font-weight: 500; white-space: nowrap; }
  #|:is(sf-table, .table) :is(th, td):first-child { padding-left: 0; }
  #|:is(sf-table, .table) :is(th, td):last-child { padding-right: 0; }
  #|:is(sf-table, .table) :is(td.num, th.num, [data-num]) { text-align: right; }
  #|sf-card sf-table :is(th, td):first-child, .card .table :is(th, td):first-child { padding-left: 0; }
  #|
  #|/* ── Horizontal bars (a ranking, a share) ─────────────────────────────────────────── */
  #|sf-bars { display: grid; grid-template-columns: minmax(0, max-content) minmax(60px, 1fr) max-content; gap: 8px 12px; align-items: center; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); }
  #|.sf-bar-label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #|.sf-bar-track { height: 8px; border-radius: 999px; background: var(--sf-quiet); overflow: hidden; }
  #|.sf-bar-fill { height: 100%; border-radius: inherit; background: var(--sf-ink); }
  #|.sf-bar-value { color: var(--sf-muted); text-align: right; }
  #|
  #|/* ── Progress ─────────────────────────────────────────────────────────────────────── */
  #|sf-progress { display: flex; flex-direction: column; gap: 6px; }
  #|.sf-progress-head { display: flex; justify-content: space-between; gap: 8px; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); }
  #|.sf-progress-head > :last-child { color: var(--sf-muted); }
  #|.sf-progress-track, .progress { height: 6px; overflow: hidden; border-radius: 999px; background: var(--sf-line); }
  #|.sf-progress-fill, .progress-bar { height: 100%; border-radius: inherit; background: var(--sf-accent); transition: width var(--sf-dur) var(--sf-ease); }
  #|
  #|/* ── Facts: key and value ─────────────────────────────────────────────────────────── */
  #|sf-facts { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 6px 16px; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); }
  #|.sf-fact-key { color: var(--sf-muted); }
  #|.sf-fact-value { min-width: 0; }
  #|
  #|/* ── Steps: a timeline (column) or a flow (row) ───────────────────────────────────── */
  #|sf-steps { display: flex; flex-direction: column; }
  #|.sf-step { position: relative; display: grid; grid-template-columns: 16px minmax(0, 1fr); column-gap: 10px; padding-bottom: 14px; }
  #|.sf-step:last-child { padding-bottom: 0; }
  #|.sf-step-mark { position: relative; display: grid; place-items: center; height: var(--sf-leading-body); }
  #|.sf-step-mark::before { content: ""; width: 10px; height: 10px; border-radius: 50%; box-shadow: inset 0 0 0 1.5px var(--sf-line-strong); background: var(--sf-page); z-index: 1; }
  #|.sf-step:not(:last-child) .sf-step-mark::after { content: ""; position: absolute; top: calc(50% + 7px); left: calc(50% - .75px); width: 1.5px; height: 9999px; background: var(--sf-line); }
  #|.sf-step { overflow: hidden; }
  #|.sf-step[data-state="done"] .sf-step-mark::before { background: var(--sf-ink); box-shadow: none; }
  #|.sf-step[data-state="current"] .sf-step-mark::before { box-shadow: inset 0 0 0 3px var(--sf-ink); }
  #|.sf-step[data-state="error"] .sf-step-mark::before { background: var(--sf-red); box-shadow: none; }
  #|.sf-step-title { font-weight: 500; }
  #|.sf-step[data-state="todo"] .sf-step-title { color: var(--sf-muted); font-weight: 400; }
  #|.sf-step[data-state="current"] .sf-step-title { font-weight: 600; }
  #|.sf-step-note { color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.sf-step-body { min-width: 0; }
  #|sf-steps[row] { flex-direction: row; flex-wrap: wrap; gap: 8px 0; }
  #|sf-steps[row] .sf-step { display: flex; flex-direction: column; align-items: flex-start; gap: 6px; padding: 0 16px 0 0; flex: 1 1 0; min-width: 96px; }
  #|sf-steps[row] .sf-step-mark { width: 100%; justify-content: start; height: 10px; }
  #|sf-steps[row] .sf-step:not(:last-child) .sf-step-mark::after { top: calc(50% - .75px); left: 14px; width: 9999px; height: 1.5px; }
  #|
  #|/* ── Boxes in a flow (Codex's names) ──────────────────────────────────────────────── */
  #|.viz-flow { display: flex; flex-wrap: wrap; align-items: stretch; gap: 8px; }
  #|.viz-flow.is-vertical { flex-direction: column; align-items: flex-start; }
  #|.viz-node {
  #|  display: flex; flex-direction: column; gap: 2px; min-width: 96px; padding: 10px 12px;
  #|  border-radius: var(--sf-r-field); corner-shape: var(--sf-corner-shape); background: var(--sf-quiet);
  #|}
  #|.viz-node-title { font-weight: 500; }
  #|.viz-node-body { color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.viz-node.is-active { background: var(--sf-primary); color: var(--sf-on-primary); }
  #|.viz-node.is-active .viz-node-body { color: color-mix(in srgb, var(--sf-on-primary) 75%, transparent); }
  #|.viz-node.is-blue { background: var(--sf-blue-ground); }
  #|.viz-node.is-green { background: var(--sf-green-ground); }
  #|.viz-node.is-red { background: var(--sf-red-ground); }
  #|.viz-node.is-yellow { background: var(--sf-amber-ground); }
  #|.viz-node.is-purple { background: var(--sf-purple-ground); }
  #|.viz-arrow {
  #|  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; min-width: 40px;
  #|  color: var(--sf-muted); font-size: var(--sf-text-meta); text-align: center;
  #|}
  #|.viz-arrow::after { content: "→"; font-size: 16px; line-height: 1; }
  #|.viz-flow.is-vertical .viz-arrow::after { content: "↓"; }
  #|
  #|/* ── Buttons: the app's pills ─────────────────────────────────────────────────────── */
  #|sf-button { display: inline-flex; }
  #|.sf-button, .btn {
  #|  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 32px; padding: 0 14px;
  #|  border: 1px solid var(--sf-line-strong); border-radius: 999px; background: var(--sf-field); color: var(--sf-ink);
  #|  font: inherit; font-size: var(--sf-text-ui); font-weight: 500; white-space: nowrap; cursor: pointer;
  #|  transition: background var(--sf-dur) var(--sf-ease), border-color var(--sf-dur) var(--sf-ease);
  #|}
  #|:is(.sf-button, .btn):hover:not(:disabled) { background: color-mix(in srgb, var(--sf-ink) 6%, var(--sf-field)); }
  #|:is(.sf-button, .btn):disabled { opacity: .45; cursor: default; }
  #|:is(.sf-button[data-primary], .btn-primary) { border-color: var(--sf-primary); background: var(--sf-primary); color: var(--sf-on-primary); }
  #|:is(.sf-button[data-primary], .btn-primary):hover:not(:disabled) { border-color: var(--e-primary-hover, var(--sf-primary)); background: var(--e-primary-hover, var(--sf-primary)); }
  #|:is(.sf-button[data-quiet], .btn-ghost) { border-color: transparent; background: transparent; }
  #|:is(.sf-button[data-quiet], .btn-ghost):hover:not(:disabled) { background: var(--sf-hover); }
  #|.btn.is-selected { border-color: var(--sf-ink); box-shadow: inset 0 0 0 .5px var(--sf-ink); }
  #|:is(.sf-button[data-small], .btn-sm) { height: 26px; padding: 0 10px; font-size: var(--sf-text-meta); }
  #|
  #|/* ── Choices to answer with (sf-choices): a list card of rows ─────────────────────── */
  #|sf-choices { display: flex; flex-direction: column; gap: 2px; padding: 6px; border-radius: 23px; corner-shape: var(--sf-corner-shape); background: var(--sf-card); }
  #|.sf-choice {
  #|  display: flex; align-items: center; gap: 12px; width: 100%; min-height: 44px; padding: 8px var(--sf-text-in); border: 0;
  #|  border-radius: 18px; corner-shape: var(--sf-corner-shape); background: none; color: var(--sf-ink); text-align: left; cursor: pointer;
  #|  transition: background var(--sf-dur) var(--sf-ease);
  #|}
  #|.sf-choice:hover:not(:disabled) { background: var(--sf-hover); }
  #|.sf-choice:disabled { cursor: default; }
  #|.sf-choice[data-chosen] { background: var(--sf-selected); }
  #|.sf-choice-text { flex: 1; display: flex; flex-direction: column; min-width: 0; }
  #|.sf-choice-title { font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); font-weight: 500; }
  #|.sf-choice-note { color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.sf-choice-end { flex: none; color: var(--sf-muted); font-size: var(--sf-text-meta); }
  #|
  #|/* ── Tabs: the app's segmented choice ─────────────────────────────────────────────── */
  #|sf-tabs { display: flex; flex-direction: column; gap: var(--sf-gap); }
  #|.sf-segmented, .nav-pills {
  #|  display: inline-flex; align-self: flex-start; width: fit-content; max-width: 100%; gap: 2px; padding: 3px; margin: 0;
  #|  border-radius: 999px; background: color-mix(in srgb, var(--sf-ink) 6%, transparent); list-style: none;
  #|}
  #|.nav { display: flex; flex-wrap: wrap; gap: 4px; margin: 0; padding: 0; list-style: none; }
  #|.nav.nav-pills { display: inline-flex; flex-wrap: nowrap; gap: 2px; padding: 3px; }
  #|.nav-justified { display: flex; width: auto; }
  #|.nav-justified > * { flex: 1; }
  #|.sf-segment, .nav-link {
  #|  display: inline-flex; align-items: center; justify-content: center; height: 30px; padding: 0 12px; border: 0;
  #|  border-radius: 999px; background: none; color: var(--sf-muted); font: inherit; font-size: var(--sf-text-ui);
  #|  white-space: nowrap; cursor: pointer; transition: color var(--sf-dur) var(--sf-ease);
  #|}
  #|:is(.sf-segment, .nav-link):hover { color: var(--sf-ink); text-decoration: none; }
  #|:is(.sf-segment, .nav-link):is([aria-selected="true"], .is-selected, .active) { color: var(--sf-ink); font-weight: 500; }
  #|:is(.sf-segmented, .nav-pills) :is(.sf-segment, .nav-link):is([aria-selected="true"], .is-selected, .active) {
  #|  background: var(--sf-lifted); box-shadow: 0 0 2px var(--sf-shadow), 0 0 0 .5px var(--sf-line);
  #|}
  #|
  #|/* ── Forms ────────────────────────────────────────────────────────────────────────── */
  #|.form-label { display: block; margin-bottom: 4px; color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.form-control, .form-select {
  #|  width: 100%; min-height: 36px; padding: 7px 16px; border: 1px solid var(--sf-line-strong); border-radius: 999px;
  #|  background: var(--sf-field); color: var(--sf-ink); font: inherit; font-size: var(--sf-text-body);
  #|}
  #|textarea.form-control { min-height: 72px; padding: 8px 12px; border-radius: var(--sf-r-field); corner-shape: var(--sf-corner-shape); resize: vertical; }
  #|.form-control:hover, .form-select:hover, .form-control:focus, .form-select:focus { border-color: var(--e-field-hover, var(--sf-muted)); outline: none; }
  #|.form-check { display: inline-flex; align-items: center; gap: 6px; font-size: var(--sf-text-ui); cursor: pointer; }
  #|.form-check-input { width: 16px; height: 16px; margin: 0; accent-color: var(--sf-accent); }
  #|.form-check-label { cursor: pointer; }
  #|.form-switch .form-check-input { width: 28px; }
  #|.form-range { width: 100%; accent-color: var(--sf-accent); }
  #|.form-control-color { width: 34px; height: 34px; padding: 2px; border: 1px solid var(--sf-line-strong); border-radius: var(--sf-r-small); background: none; }
  #|
  #|/* ── Charts (sf-chart): coordinate lines only, labels quiet, series by colour and legend ─ */
  #|sf-chart { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
  #|sf-chart svg { display: block; width: 100%; overflow: visible; }
  #|.sf-chart-grid { stroke: var(--sf-line); stroke-width: 1; }
  #|.sf-chart-axis { fill: var(--sf-muted); font-size: var(--sf-text-caption); }
  #|.sf-chart-legend { display: flex; flex-wrap: wrap; gap: 4px 14px; color: var(--sf-muted); font-size: var(--sf-text-meta); line-height: var(--sf-leading-meta); }
  #|.sf-chart-legend > span { display: inline-flex; align-items: center; gap: 6px; }
  #|.sf-chart-legend i { width: 8px; height: 8px; border-radius: 2px; }
  #|.sf-chart-donut { display: flex; flex-wrap: wrap; align-items: center; gap: 16px 24px; }
  #|.sf-chart-donut svg { width: 140px; height: 140px; flex: none; }
  #|.sf-chart-donut .sf-chart-legend { flex-direction: column; flex: 1; min-width: 140px; font-size: var(--sf-text-ui); line-height: var(--sf-leading-ui); color: var(--sf-ink); }
  #|.sf-chart-donut .sf-chart-legend > span { justify-content: space-between; gap: 12px; }
  #|.sf-chart-donut .sf-chart-legend b { font-weight: 400; color: var(--sf-muted); }
  #|.sf-chart-center { fill: var(--sf-ink); font-size: var(--sf-text-title); font-weight: 600; }
  #|.sf-hit { cursor: default; }
  #|.sf-hit:hover { opacity: .8; }
  #|
  #|/* The tooltip the frame draws for any element with data-tooltip (see bridge.js). */
  #|.viz-tooltip {
  #|  position: fixed; z-index: 10; max-width: 240px; padding: 5px 8px; border-radius: var(--sf-r-small);
  #|  background: var(--sf-primary); color: var(--sf-on-primary); font-size: var(--sf-text-meta); line-height: 1.4;
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
  #|// still.fail's components for inline visualizations: <sf-…> elements an agent writes with its data, drawn in
  #|// still.fail's look (ember-viz.css styles them) so a figure seldom needs styles or scripts of its own. Runs in every
  #|// fragment's frame after the bridge (Viz.tsx, the app's viz_file.mbt). How agents use them:
  #|// station/src/skills/stillfail-viz.md. Plain custom elements without a shadow root: the stylesheet and the theme's
  #|// tokens reach what they draw, and charts drawn with var(--sf-…) follow the theme without being drawn again.
  #|(() => {
  #|  const NS = "http://www.w3.org/2000/svg";
  #|  const TONES = ["ok", "busy", "warn", "error", "off", "info", "blue", "green", "amber", "red", "purple"];
  #|  const TONE_INK = {
  #|    ok: "--sf-green", green: "--sf-green", busy: "--sf-amber", warn: "--sf-amber", amber: "--sf-amber",
  #|    error: "--sf-red", red: "--sf-red", info: "--sf-blue", blue: "--sf-blue", purple: "--sf-purple", off: "--sf-muted",
  #|    ink: "--sf-ink", muted: "--sf-muted",
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
  #|    for (const kid of kids.flat()) if (kid !== undefined && kid !== null && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
  #|    return el;
  #|  };
  #|  const s = (tag, attrs = {}, ...kids) => {
  #|    const el = document.createElementNS(NS, tag);
  #|    for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) el.setAttribute(k, String(v));
  #|    for (const kid of kids.flat()) if (kid) el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  #|    return el;
  #|  };
  #|  const ink = (tone, i = 0) => `var(${TONE_INK[tone] ?? `--sf-series-${(i % 6) + 1}`})`;
  #|
  #|  /** The element's data: its `data` attribute, else a <script type="application/json"> inside it. */
  #|  const dataOf = (el) => {
  #|    const raw = el.getAttribute("data") ?? el.querySelector(":scope > script[type='application/json']")?.textContent;
  #|    if (!raw) return null;
  #|    try {
  #|      return JSON.parse(raw);
  #|    } catch (e) {
  #|      el.replaceChildren(h("sf-note", {}, `${el.localName}: its data is not JSON (${e.message})`));
  #|      return undefined;
  #|    }
  #|  };
  #|  const num = (v) => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v.replace(/[,_]/g, ""))) ? Number(v.replace(/[,_]/g, "")) : NaN);
  #|  const fmt = (n, digits = 2) => (Number.isFinite(n) ? n.toLocaleString(undefined, { maximumFractionDigits: digits }) : String(n));
  #|  /** Whether a cell reads as a number (a count, a time, a share, an amount): such a column is set right. */
  #|  const numeric = (v) => typeof v === "number" || (typeof v === "string" && /^[\s+\-−]*[$¥€£]?[\d.,:]+\s*(%|ms|s|m|h|d|k|K|M|G|GB|MB|KB|TB|x|×|分|秒|天|小时|个|次|元)?$/.test(v));
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
  #|          this.replaceChildren(h("sf-note", {}, `${this.localName}: ${e.message}`));
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
  #|  // ── Card: a ground with a title ─────────────────────────────────────────────────────
  #|  define("sf-card", class extends Base {
  #|    draw() {
  #|      const title = this.getAttribute("title");
  #|      const note = this.getAttribute("note");
  #|      if (title || note) {
  #|        this.removeAttribute("title"); // not a tooltip
  #|        this.prepend(h("div.sf-head", {}, title && h("div.sf-title", {}, title), note && h("div.sf-sub", {}, note)));
  #|      }
  #|    }
  #|  });
  #|
  #|  // ── A number with its label ─────────────────────────────────────────────────────────
  #|  define("sf-stat", class extends Base {
  #|    draw() {
  #|      const value = this.getAttribute("value") ?? this.textContent.trim();
  #|      const tone = this.getAttribute("tone");
  #|      const note = this.getAttribute("note");
  #|      this.replaceChildren(
  #|        h("span.sf-stat-label", {}, this.getAttribute("label") ?? ""),
  #|        h("span.sf-stat-value", {}, /^[\s+\-]*[\d.,]+$/.test(value) && Number.isFinite(num(value)) ? fmt(num(value)) : value, this.hasAttribute("unit") && h("span.sf-stat-unit", {}, this.getAttribute("unit"))),
  #|        note && h("span.sf-stat-note", {}, tone && h("i.sf-dot", { "data-tone": tone }), h("span", { style: tone && tone !== "off" ? `color:${ink(tone)}` : undefined }, note)),
  #|      );
  #|    }
  #|  });
  #|
  #|  // ── Status: a dot and words ─────────────────────────────────────────────────────────
  #|  define("sf-status", class extends Base {
  #|    draw() {
  #|      this.prepend(h("i.sf-dot", { "data-tone": this.getAttribute("tone") ?? this.getAttribute("state") ?? "" }));
  #|    }
  #|  });
  #|
  #|  /** What a table's or a list's cell shows: text, a number, or {text, status|badge|tone}. */
  #|  const cell = (v) => {
  #|    if (v === null || v === undefined) return "";
  #|    if (typeof v === "number") return fmt(v);
  #|    if (typeof v !== "object") return String(v);
  #|    const text = v.text ?? v.value ?? "";
  #|    if (v.status) return h("sf-status", { tone: v.status }, h("i.sf-dot", { "data-tone": v.status }), String(text));
  #|    if (v.badge !== undefined) return h("sf-badge", { tone: v.badge === true ? undefined : v.badge }, String(text));
  #|    if (v.tone) return h("span", { style: `color:${ink(v.tone)}` }, String(text));
  #|    if (v.muted) return h("span", { style: "color:var(--sf-muted)" }, String(text));
  #|    return String(text);
  #|  };
  #|  const plain = (v) => (v && typeof v === "object" ? v.text ?? v.value : v);
  #|
  #|  // ── Table: from data, or a <table> inside it ────────────────────────────────────────
  #|  define("sf-table", class extends Base {
  #|    draw() {
  #|      const d = dataOf(this);
  #|      if (d === undefined) return;
  #|      if (!d) {
  #|        const table = this.querySelector("table");
  #|        if (table && !table.parentElement.classList.contains("sf-table-scroll")) table.replaceWith(h("div.sf-table-scroll", {}, table.cloneNode(true)));
  #|        return;
  #|      }
  #|      const rows = d.rows ?? (Array.isArray(d) ? d : []);
  #|      let cols = d.columns ?? (rows[0] && !Array.isArray(rows[0]) ? Object.keys(rows[0]) : []);
  #|      cols = cols.map((c, i) => (typeof c === "string" ? { key: Array.isArray(rows[0]) ? i : c, label: c } : { key: c.key ?? i, label: c.label ?? c.key ?? "", align: c.align }));
  #|      const at = (row, c) => (Array.isArray(row) ? row[typeof c.key === "number" ? c.key : cols.indexOf(c)] : row[c.key]);
  #|      for (const c of cols) {
  #|        const values = rows.map((r) => plain(at(r, c))).filter((v) => v !== undefined && v !== null && v !== "");
  #|        c.num = c.align ? c.align === "right" : values.length > 0 && values.every(numeric);
  #|      }
  #|      this.replaceChildren(h("div.sf-table-scroll", {}, h("table", {},
  #|        h("thead", {}, h("tr", {}, cols.map((c) => h("th", { "data-num": c.num || undefined }, c.label)))),
  #|        h("tbody", {}, rows.map((r) => h("tr", {}, cols.map((c) => h("td", { "data-num": c.num || undefined }, cell(at(r, c))))))),
  #|      )));
  #|    }
  #|  });
  #|
  #|  // ── Horizontal bars: label, bar, value ──────────────────────────────────────────────
  #|  define("sf-bars", class extends Base {
  #|    draw() {
  #|      const d = dataOf(this);
  #|      if (!d) return;
  #|      const items = (Array.isArray(d) ? d : d.items ?? []).map((it) => (Array.isArray(it) ? { label: it[0], value: it[1] } : it));
  #|      const max = num(this.getAttribute("max")) || Math.max(0, ...items.map((it) => num(it.value) || 0)) || 1;
  #|      const unit = this.getAttribute("unit") ?? "";
  #|      this.replaceChildren(...items.flatMap((it) => [
  #|        h("span.sf-bar-label", { title: it.label }, it.label),
  #|        h("span.sf-bar-track", {}, h("span.sf-bar-fill", { style: `display:block;width:${Math.max(0, Math.min(100, ((num(it.value) || 0) / max) * 100))}%;background:${it.tone ? ink(it.tone) : "var(--sf-ink)"}` })),
  #|        h("span.sf-bar-value", {}, it.note ?? `${fmt(num(it.value))}${unit}`),
  #|      ]));
  #|    }
  #|  });
  #|
  #|  // ── Progress ────────────────────────────────────────────────────────────────────────
  #|  define("sf-progress", class extends Base {
  #|    draw() {
  #|      const value = num(this.getAttribute("value")) || 0;
  #|      const max = num(this.getAttribute("max")) || 100;
  #|      const share = Math.max(0, Math.min(1, value / max));
  #|      const label = this.getAttribute("label");
  #|      const said = this.getAttribute("note") ?? (max === 100 ? `${fmt(value, 1)}%` : `${fmt(value)} / ${fmt(max)}`);
  #|      this.replaceChildren(
  #|        (label || said) && h("div.sf-progress-head", {}, h("span", {}, label ?? ""), h("span", {}, said)),
  #|        h("div.sf-progress-track", { role: "progressbar", "aria-valuenow": value, "aria-valuemax": max }, h("div.sf-progress-fill", { style: `width:${share * 100}%` })),
  #|      );
  #|    }
  #|  });
  #|
  #|  // ── Facts: key and value ────────────────────────────────────────────────────────────
  #|  define("sf-facts", class extends Base {
  #|    draw() {
  #|      const d = dataOf(this);
  #|      let pairs = d ? (Array.isArray(d) ? d : Object.entries(d)) : null;
  #|      if (!pairs) {
  #|        const dl = this.querySelector("dl");
  #|        if (!dl) return;
  #|        pairs = [...dl.querySelectorAll("dt")].map((dt) => [dt.textContent, dt.nextElementSibling?.localName === "dd" ? [...dt.nextElementSibling.childNodes].map((n) => n.cloneNode(true)) : ""]);
  #|      }
  #|      this.replaceChildren(...pairs.flatMap(([k, v]) => [h("span.sf-fact-key", {}, k), h("span.sf-fact-value", {}, Array.isArray(v) ? v : cell(v))]));
  #|    }
  #|  });
  #|
  #|  // ── Steps: <sf-step state title note> ───────────────────────────────────────────────
  #|  define("sf-steps", class extends Base {
  #|    draw() {
  #|      const d = dataOf(this);
  #|      const steps = d ? (Array.isArray(d) ? d : d.steps ?? []) : [...this.querySelectorAll(":scope > sf-step")].map((st) => ({
  #|        state: st.getAttribute("state"), title: st.getAttribute("title") ?? "", note: st.getAttribute("note"), body: [...st.childNodes],
  #|      }));
  #|      this.replaceChildren(...steps.map((st) => h("div.sf-step", { "data-state": st.state ?? "todo" },
  #|        h("span.sf-step-mark", {}),
  #|        h("div.sf-step-body", {}, h("div.sf-step-title", {}, st.title), st.note && h("div.sf-step-note", {}, st.note), st.body),
  #|      )));
  #|    }
  #|  });
  #|  define("sf-step", class extends HTMLElement {});
  #|
  #|  // ── Tabs: <sf-tab label> panels under a segmented choice ────────────────────────────
  #|  define("sf-tabs", class extends Base {
  #|    draw() {
  #|      const tabs = [...this.querySelectorAll(":scope > sf-tab")];
  #|      if (!tabs.length) return;
  #|      const pick = (i) => {
  #|        tabs.forEach((t, k) => { t.hidden = k !== i; });
  #|        [...bar.children].forEach((b, k) => b.setAttribute("aria-selected", String(k === i)));
  #|      };
  #|      const bar = h("div.sf-segmented", { role: "tablist" }, tabs.map((t, i) => h("button.sf-segment", { type: "button", role: "tab", onclick: () => pick(i) }, t.getAttribute("label") ?? `${i + 1}`)));
  #|      this.prepend(bar);
  #|      pick(Math.max(0, tabs.findIndex((t) => t.hasAttribute("selected"))));
  #|    }
  #|  });
  #|  define("sf-tab", class extends HTMLElement {});
  #|
  #|  // ── Things to send: what is clicked goes into the chat's composer for the person to send ───────────────────
  #|  const send = (prompt) => window.ember?.sendFollowUpMessage({ prompt }).catch(() => {});
  #|  /** What the widget keeps, by key: merged into widgetState's modelContent so the agent hears it. */
  #|  const keep = (key, value) => {
  #|    const was = window.ember?.widgetState ?? {};
  #|    const modelContent = { ...(was.modelContent ?? {}), [key]: value };
  #|    window.ember?.setWidgetState({ ...was, modelContent }).catch(() => {});
  #|  };
  #|  const kept = (key) => window.ember?.widgetState?.modelContent?.[key];
  #|
  #|  define("sf-choices", class extends Base {
  #|    draw() {
  #|      const key = this.id || `choices${[...document.querySelectorAll("sf-choices")].indexOf(this)}`;
  #|      const items = [...this.querySelectorAll(":scope > sf-choice")].map((c) => ({
  #|        title: c.getAttribute("title") ?? c.textContent.trim(), note: c.getAttribute("note"), end: c.getAttribute("end"),
  #|        send: c.getAttribute("send") ?? c.getAttribute("value") ?? c.getAttribute("title") ?? c.textContent.trim(),
  #|      }));
  #|      const chosen = kept(key);
  #|      const rows = items.map((it) => h("button.sf-choice", {
  #|        type: "button", "data-chosen": chosen === it.title || undefined,
  #|        onclick: (e) => {
  #|          for (const r of rows) r.removeAttribute("data-chosen");
  #|          e.currentTarget.setAttribute("data-chosen", "");
  #|          keep(key, it.title);
  #|          send(it.send);
  #|        },
  #|      }, h("span.sf-choice-text", {}, h("span.sf-choice-title", {}, it.title), it.note && h("span.sf-choice-note", {}, it.note)), it.end && h("span.sf-choice-end", {}, it.end)));
  #|      this.replaceChildren(...rows);
  #|    }
  #|  });
  #|  define("sf-choice", class extends HTMLElement {});
  #|
  #|  define("sf-button", class extends Base {
  #|    draw() {
  #|      const words = this.getAttribute("send");
  #|      const b = h("button.sf-button", {
  #|        type: "button", "data-primary": this.hasAttribute("primary") || undefined, "data-quiet": this.hasAttribute("quiet") || undefined,
  #|        "data-small": this.hasAttribute("small") || undefined, onclick: words ? () => send(words) : undefined,
  #|      }, ...this.childNodes);
  #|      this.replaceChildren(b);
  #|    }
  #|  });
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
  #|  define("sf-chart", class extends Base {
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
  #|        svg.append(s("line", { class: "sf-chart-grid", x1: left, x2: width - right, y1: Y(v), y2: Y(v) }));
  #|        svg.append(s("text", { class: "sf-chart-axis", x: left - 8, y: Y(v), "text-anchor": "end", "dominant-baseline": "middle" }, short(v) + unit));
  #|      }
  #|      const n = Math.max(1, labels.length);
  #|      const band = plotW / n;
  #|      const every = Math.max(1, Math.ceil((labels.reduce((m, l) => Math.max(m, String(l).length), 0) * 6.5 + 12) / band));
  #|      labels.forEach((l, i) => {
  #|        if (i % every) return;
  #|        const x = type === "bar" ? left + band * (i + .5) : left + (n === 1 ? plotW / 2 : (plotW * i) / (n - 1));
  #|        svg.append(s("text", { class: "sf-chart-axis", x, y: height - 6, "text-anchor": n > 1 && type !== "bar" && i === 0 ? "start" : n > 1 && type !== "bar" && i === n - 1 ? "end" : "middle" }, l));
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
  #|            svg.append(s("path", { d: path, fill: sr.color, class: "sf-hit", "data-tooltip": tip(i, sr, v) }));
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
  #|      const legend = series.length > 1 && h("div.sf-chart-legend", {}, series.map((sr) => h("span", {}, h("i", { style: `background:${sr.color}` }), sr.name)));
  #|      this.replaceChildren(...[this.title_(), svg, legend].filter(Boolean));
  #|    }
  #|    title_() {
  #|      const t = this.getAttribute("title");
  #|      if (t) this.setAttribute("data-title", t), this.removeAttribute("title");
  #|      const said = this.getAttribute("data-title");
  #|      return said && h("div.sf-title", {}, said);
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
  #|        svg.append(s("path", { d: d_, fill: color, "fill-rule": "evenodd", class: "sf-hit", "data-tooltip": `${it.label}: ${fmt(v)}${unit} (${fmt((v / total) * 100, 1)}%)` }));
  #|        it.color = color;
  #|        a = b;
  #|      });
  #|      const center = this.getAttribute("center");
  #|      if (r && center !== "") svg.append(s("text", { class: "sf-chart-center", x: c, y: c, "text-anchor": "middle", "dominant-baseline": "central" }, center ?? `${short(total)}${unit}`));
  #|      const legend = h("div.sf-chart-legend", {}, items.map((it) => h("span", {}, h("span", { style: "display:inline-flex;align-items:center;gap:6px" }, h("i", { style: `background:${it.color}` }), it.label), h("b", {}, `${fmt(num(it.value))}${unit}`))));
  #|      this.replaceChildren(...[this.title_(), h("div.sf-chart-donut", {}, svg, legend)].filter(Boolean));
  #|    }
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
