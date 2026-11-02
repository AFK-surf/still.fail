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
  #|  /* The page's faces as its person set them (正文, else 界面; their stylesheets linked ahead of this one). */
  #|  --font-sans: var(--e-font-text, var(--e-font-body, -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif));
  #|  --font-mono: var(--e-font-mono, ui-monospace, SFMono-Regular, Menlo, monospace);
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
  #|  /* The chat's own ground, not transparent: a frame is composited apart from its page, and a part of it not yet drawn
  #|     as the chat scrolls is filled with its ground made opaque, black for a transparent one (2026-10-29, a black band
  #|     along a frame's edge as it scrolled in). */
  #|  background: var(--background);
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
  #|/* Icons: still.fail's own, 16 and their line 1.75, in the words' colour (data-icon; the runtime draws them). */
  #|[data-icon], [data-lucide], .viz-icon { width: 16px; height: 16px; flex: none; vertical-align: -3px; }
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
  #|  display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 36px; padding: 0 16px;
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
  #|.btn-lg { height: 40px; padding: 0 18px; }
  #|.btn-sm { height: 28px; padding: 0 12px; }
  #|.btn-xs { height: 24px; padding: 0 10px; font-size: var(--font-size-small); }
  #|/* An icon alone (the app's IconButton): a 32 square, its icon grey, a ground only while pointed at or pressed. */
  #|.btn-icon {
  #|  display: inline-grid; place-items: center; flex: none; width: 32px; height: 32px; padding: 0; border: 0;
  #|  border-radius: var(--radius-lg); corner-shape: var(--corner-shape); background: transparent; color: var(--muted-foreground);
  #|  cursor: pointer; transition: background var(--dur) var(--ease-out), color var(--dur) var(--ease-out);
  #|}
  #|.btn-icon:hover:not(:disabled) { background: var(--hover); color: var(--foreground); }
  #|.btn-icon:is([aria-pressed="true"], [aria-selected="true"], .is-selected) { background: var(--selected); color: var(--foreground); }
  #|.btn-icon:disabled { opacity: .45; cursor: default; }
  #|.btn-block { display: flex; width: 100%; }
  #|/* An icon at an end (the runtime marks which: data-icon-at) sits in from it by less than words do: the drawing stops
  #|   short of its box and is lighter than words, so an even padding leaves it looking farther from the edge. */
  #|.btn[data-icon-at~="start"] { padding-left: 12px; }
  #|.btn[data-icon-at~="end"] { padding-right: 12px; }
  #|.btn-lg[data-icon-at~="start"] { padding-left: 14px; }
  #|.btn-lg[data-icon-at~="end"] { padding-right: 14px; }
  #|.btn-sm[data-icon-at~="start"] { padding-left: 9px; }
  #|.btn-sm[data-icon-at~="end"] { padding-right: 9px; }
  #|.btn-xs[data-icon-at~="start"] { padding-left: 7px; }
  #|.btn-xs[data-icon-at~="end"] { padding-right: 7px; }
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
  #|/* ── Tables: as a message's Markdown tables, framed as a card (a line round it, a faint ground, its head tinted), the
  #|   rows ruled between them only, as wide as their content ─────────────────────────────────────────────────────── */
  #|.table-responsive { max-width: 100%; overflow-x: auto; }
  #|.table {
  #|  width: auto; max-width: 100%; border-collapse: separate; border-spacing: 0; overflow: hidden;
  #|  border: 1px solid var(--border); border-radius: var(--radius-xl); corner-shape: var(--corner-shape);
  #|  background: color-mix(in srgb, var(--foreground) 2%, var(--background));
  #|  font-size: var(--font-size-ui); line-height: var(--line-height-ui);
  #|}
  #|.table :is(th, td) { min-width: 4em; padding: 7px 12px; border-bottom: 1px solid var(--border); text-align: left; vertical-align: middle; }
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
  #|      // A face chosen since the frame was written: its stylesheet too.
  #|      for (const href of event.data.sheets ?? []) {
  #|        if (![...document.querySelectorAll("link[rel=stylesheet]")].some((l) => l.href === href)) document.head.append(Object.assign(document.createElement("link"), { rel: "stylesheet", href }));
  #|      }
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
  #|  // Shown only once it is drawn in its own faces (Viz.tsx hides it till then): no empty or unstyled frame flashing first.
  #|  addEventListener("load", () => {
  #|    sendHeight();
  #|    document.fonts.ready.then(() => { sendHeight(); post({ type: "ready" }); });
  #|  });
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
  #|  // ── Icons: <i data-icon="name"> (or Codex's data-lucide) as still.fail's own, given beside this (design/icons, in
  #|  // #viz-icons); a Lucide name still.fail has under another name is taken as its; one it has not at all, Lucide's own
  #|  // (from a CDN the frame may load), so a figure written for Codex still draws ───────────────────────────────────────
  #|  const OWN = (() => { try { return JSON.parse(document.getElementById("viz-icons")?.textContent || "{}"); } catch { return {}; } })();
  #|  const LUCIDE = {
  #|    x: "close", "rotate-cw": "refresh", "rotate-ccw": "retry", "refresh-cw": "refresh", "refresh-ccw": "refresh", ellipsis: "more",
  #|    "more-horizontal": "more", pencil: "edit", "square-pen": "edit", "pen-line": "edit", "trash-2": "trash", "external-link": "external",
  #|    "circle-check": "check-circle", "check-circle-2": "check-circle", clipboard: "paste", "clipboard-paste": "paste", funnel: "filter",
  #|    "circle-info": "info", image: "photo", smartphone: "phone", globe: "web", "sliders-horizontal": "sliders",
  #|    "chart-column": "chart", "bar-chart": "chart", "bar-chart-3": "chart", "chart-bar": "chart", "message-circle": "chat",
  #|    "messages-square": "chats", sparkles: "sparks", "volume-2": "volume", maximize: "expand", "maximize-2": "expand",
  #|    minimize: "shrink", "minimize-2": "shrink", "panel-left-open": "panel-open", "panel-left-close": "panel-close",
  #|    "hard-drive": "disk", "mouse-pointer": "cursor", "mouse-pointer-2": "cursor", type: "text-size", columns: "view-columns",
  #|    "columns-2": "view-columns", "list-tree": "view-tree", "log-in": "log-in", "log-out": "log-out", "user-round": "user",
  #|    "users-round": "users", "file-image": "photo", "folder-open": "folder", "square-terminal": "command", terminal: "command",
  #|    "skip-back": "skip-back", "skip-forward": "skip-forward", "circle-stop": "stop", octagon: "stop", "loader": "wait",
  #|  };
  #|  /** Draws every icon mark not yet drawn; again after a script adds some (window.vizIcons()). */
  #|  const icons = () => {
  #|    let foreign = false;
  #|    for (const el of document.querySelectorAll("[data-icon]:not(svg), [data-lucide]:not(svg)")) {
  #|      const asked = el.getAttribute("data-icon") ?? el.getAttribute("data-lucide");
  #|      const name = OWN[asked] ? asked : LUCIDE[asked];
  #|      if (!name || !OWN[name]) { foreign = true; continue; }
  #|      const svg = document.createElementNS(NS, "svg");
  #|      for (const a of el.attributes) if (a.name !== "data-lucide" && a.name !== "data-icon") svg.setAttribute(a.name, a.value);
  #|      Object.entries({ viewBox: "0 0 24 24", width: 16, height: 16, fill: "none", stroke: "currentColor", "stroke-width": 1.75, "stroke-linecap": "round", "stroke-linejoin": "round", "data-icon": name }).forEach(([k, v]) => svg.setAttribute(k, v));
  #|      svg.classList.add("viz-icon");
  #|      svg.innerHTML = OWN[name];
  #|      el.replaceWith(svg);
  #|    }
  #|    // which end of a button an icon is at (ember-viz.css sets it in by less there): what is first or last in it, words
  #|    // aside from blank ones
  #|    for (const b of document.querySelectorAll(".btn")) {
  #|      const parts = [...b.childNodes].filter((n) => n.nodeType === 1 || n.textContent.trim());
  #|      const icon = (n) => n?.nodeType === 1 && (n.localName === "svg" || n.localName === "i" || n.hasAttribute("data-icon") || n.hasAttribute("data-lucide"));
  #|      const at = parts.length > 1 ? [icon(parts[0]) && "start", icon(parts[parts.length - 1]) && "end"].filter(Boolean).join(" ") : "";
  #|      if (at) b.setAttribute("data-icon-at", at);
  #|      else b.removeAttribute("data-icon-at");
  #|    }
  #|    if (!foreign) return;
  #|    const lucide = () => globalThis.lucide?.createIcons({ attrs: { width: 16, height: 16, "stroke-width": 1.75, class: "viz-icon" } });
  #|    if (globalThis.lucide) return lucide();
  #|    document.head.append(Object.assign(document.createElement("script"), { src: "https://unpkg.com/lucide@1.17.0/dist/umd/lucide.js", onload: lucide }));
  #|  };
  #|  window.vizIcons = icons;
  #|  addEventListener("DOMContentLoaded", () => {
  #|    for (const list of document.querySelectorAll('.nav[role="tablist"]')) {
  #|      const tab = list.querySelector('[role="tab"][aria-selected="true"]') ?? list.querySelector('[role="tab"].active') ?? list.querySelector('[role="tab"]');
  #|      if (tab) pick(tab);
  #|    }
  #|    icons();
  #|  });
  #|})();

///|
/// apps/mbui/assets/preview/page.js, as it is.
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

///|
/// design/icons/*.svg: each one's inside, by its name, as JSON (for a <script> element: no `<`).
// kept across runs: a file's words, never written
pub let viz_icons : String =
  #|{"agent":"\u003cpath d=\"M11 9.5H8Q3.5 9.5 3.5 13.5V17Q3.5 20.5 8 20.5H11Q15.5 20.5 15.5 17V13.5 M14 10L20.5 3.5 M15.5 3.5H20.5V8.5\"/>\u003ccircle cx=\"7\" cy=\"15\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"12\" cy=\"15\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>","archive":"\u003cpath d=\"M4.5 4H19.5Q20.5 4 20.5 5V7.5Q20.5 8.5 19.5 8.5H4.5Q3.5 8.5 3.5 7.5V5Q3.5 4 4.5 4Z M5 8.5V17Q5 20.5 8.5 20.5H15.5Q19 20.5 19 17V8.5 M10 12.5H14\"/>","arrow-down":"\u003cpath d=\"M12 4V20 M6 14L12 20L18 14\"/>","arrow-left":"\u003cpath d=\"M20 12H4 M10 6L4 12L10 18\"/>","arrow-right":"\u003cpath d=\"M4 12H20 M14 6L20 12L14 18\"/>","arrow-up-right":"\u003cpath d=\"M5 19L18.5 5.5 M9.5 5H19V14.5\"/>","arrow-up":"\u003cpath d=\"M12 20V4 M6 10L12 4L18 10\"/>","back-15":"\u003cpath d=\"M14.2 2.8L12 5L14.2 7.2 M12 5A7.5 7.5 0 1 1 5.5 8.75\"/>","bell":"\u003cpath d=\"M12 3V5 M6.5 17V11Q6.5 5 12 5Q17.5 5 17.5 11V17 M4.5 17H19.5 M10 20.5H14\"/>","bot":"\u003cpath d=\"M12 3.5V6 M12 6C18 6 20.5 8 20.5 12V16C20.5 19 17.5 20.5 12 20.5C6.5 20.5 3.5 19 3.5 16L4 12C4 8 6.5 6 12 6Z M9.5 17H14.5\"/>\u003ccircle cx=\"8.5\" cy=\"12\" r=\"1.25\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"15.5\" cy=\"12\" r=\"1.25\" fill=\"currentColor\" stroke=\"none\"/>","boxes":"\u003cpath d=\"M9 3.5H15Q17 3.5 17 5.5V8Q17 10 15 10H9Q7 10 7 8V5.5Q7 3.5 9 3.5Z M5 14H8Q10 14 10 16V18.5Q10 20.5 8 20.5H5Q3 20.5 3 18.5V16Q3 14 5 14Z M16 14H19Q21 14 21 16V18.5Q21 20.5 19 20.5H16Q14 20.5 14 18.5V16Q14 14 16 14Z M12 10V12H6.5V14 M12 12H17.5V14\"/>","brain":"\u003cpath d=\"M12 6.5C12 2.5 6 2.5 6 7C3 7 2.5 12 5 13.5C3.5 17 6 21 9 20.5Q12 20.5 12 17V6.5C12 2.5 18 2.5 18 7C21 7 21.5 12 19 13.5C20.5 17 18 21 15 20.5Q12 20.5 12 17 M6 7Q8.5 7 8.5 9.5 M18 7Q15.5 7 15.5 9.5\"/>","camera":"\u003cpath d=\"M8 6.5L9 3.5H15L16 6.5H17Q20.5 6.5 20.5 10V16.5Q20.5 20 17 20H7Q3.5 20 3.5 16.5V10Q3.5 6.5 7 6.5Z\"/>\u003ccircle cx=\"12\" cy=\"13\" r=\"3.5\"/>","captions":"\u003cpath d=\"M7 5H17Q20.5 5 20.5 8.5V15.5Q20.5 19 17 19H7Q3.5 19 3.5 15.5V8.5Q3.5 5 7 5Z M7.5 12.5H10.5 M13 12.5H16.5 M7.5 15.5H14\"/>","chart":"\u003cpath d=\"M3.5 20.5H20.5 M6.5 16.5V12 M12 16.5V5 M17.5 16.5V9\"/>","chat":"\u003cpath d=\"M12 3.5C17.5 3.5 20.5 6 20.5 11C20.5 16 17 18 12 18H10L5 20.5L5.5 16C4 14.5 3.5 13 3.5 11C3.5 6 6.5 3.5 12 3.5Z\"/>","chats":"\u003cpath d=\"M8 5V4.5Q8 3 10 3H17Q20.5 3 20.5 6.5V11Q20.5 13 18.5 13.5 M7 8H12.5Q16 8 16 11.5V15Q16 18.5 12.5 18.5H9L4 21V17.5Q3 16.5 3 15V12Q3 8 7 8Z\"/>","check-circle":"\u003cpath d=\"M20.5 12C20.5 17.5 17.5 20.5 12 20.5C6.5 20.5 3.5 17.5 3.5 12C3.5 6.5 6.5 3.5 12 3.5C17.5 3.5 20.5 6.5 20.5 12Z M7.5 12L10.5 15L16.5 8.5\"/>","check":"\u003cpath d=\"M4.5 12L9.5 17L19.5 6.5\"/>","chevron-down":"\u003cpath d=\"M6 9L12 15L18 9\"/>","chevron-left":"\u003cpath d=\"M15 6L9 12L15 18\"/>","chevron-right":"\u003cpath d=\"M9 6L15 12L9 18\"/>","chevron-up":"\u003cpath d=\"M6 15L12 9L18 15\"/>","chevrons-up-down":"\u003cpath d=\"M8 8L12 4L16 8 M8 16L12 20L16 16\"/>","close":"\u003cpath d=\"M6 6L18 18 M18 6L6 18\"/>","command":"\u003cpath d=\"M4.5 6.5L10 12L4.5 17.5 M12.5 18H20\"/>","compose":"\u003cpath d=\"M11 4H8Q3.5 4 3.5 8.5V16Q3.5 20.5 8 20.5H15.5Q20 20.5 20 16V13 M9 11.5L16.3 4.2Q17.5 3 18.7 4.2L19.8 5.3Q21 6.5 19.8 7.7L12.5 15L8 16Z M15 5.5L18.5 9\"/>","copy":"\u003cpath d=\"M8 6.5Q8 3.5 11 3.5H17Q20.5 3.5 20.5 7V13Q20.5 16 17.5 16 M7 8H13Q16 8 16 11V17Q16 20.5 12.5 20.5H7Q3.5 20.5 3.5 17V11.5Q3.5 8 7 8Z\"/>","cursor":"\u003cpath d=\"M5.5 3.5L18.5 10.5L12.5 12.5L10 18.5Z M12.5 12.5L18 18\"/>","devices":"\u003cpath d=\"M12 15.5H6.5Q3 15.5 3 12V7Q3 3.5 6.5 3.5H15Q18.5 3.5 18.5 7V7.5 M8 20H12 M9.5 15.5V20 M17 10H19.5Q21.5 10 21.5 12V18.5Q21.5 20.5 19.5 20.5H17Q15 20.5 15 18.5V12Q15 10 17 10Z\"/>","disk":"\u003cpath d=\"M6.5 6.5H17.5L20.5 13V16Q20.5 19.5 17 19.5H7Q3.5 19.5 3.5 16V13Z M3.5 13H20.5 M13.5 16.25H16\"/>\u003ccircle cx=\"7.5\" cy=\"16.25\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>","download-ring":"\u003cpath d=\"M12 7.5V16.5 M8.5 13L12 16.5L15.5 13\"/>","download":"\u003cpath d=\"M12 3.5V15 M7.5 10.5L12 15L16.5 10.5 M4.5 20H19.5\"/>","edit":"\u003cpath d=\"M5 14.5L15.2 4.3Q16.7 2.8 18.2 4.3L19.7 5.8Q21.2 7.3 19.7 8.8L9.5 19L3.5 20.5Z M13.5 6L18 10.5 M5 14.5L9.5 19\"/>","expand":"\u003cpath d=\"M14.5 5H19V9.5 M18.5 5.5L13.5 10.5 M9.5 19H5V14.5 M5.5 18.5L10.5 13.5\"/>","external":"\u003cpath d=\"M11 4H8Q3.5 4 3.5 8.5V16Q3.5 20.5 8 20.5H15.5Q20 20.5 20 16V13 M11 13L20 4 M14.5 3.5H20.5V9.5\"/>","eye":"\u003cpath d=\"M2.5 12Q12 3 21.5 12Q12 21 2.5 12Z\"/> \u003ccircle cx=\"12\" cy=\"12\" r=\"2.6\"/>","file-audio":"\u003cpath d=\"M7 3.5H13.5L20 10V17Q20 20.5 16.5 20.5H7.5Q4 20.5 4 17V7Q4 3.5 7 3.5Z M13.5 3.5V8Q13.5 10 15.5 10H20 M13 16.5V12.5L16 12\"/>\u003cpath d=\"M9 17a2 1.5 0 1 0 4 0a2 1.5 0 1 0 -4 0Z\"/>","file-code":"\u003cpath d=\"M13.5 3.5H8Q4.5 3.5 4.5 7V17Q4.5 20.5 8 20.5H16Q19.5 20.5 19.5 17V9L13.5 3.5Z M13 4V7.5Q13 10 15.5 10H19 M10 12.5L8 14.75L10 17 M14 12.5L16 14.75L14 17\"/>","file-pdf":"\u003cpath d=\"M7 3.5H13.5L20 10V17Q20 20.5 16.5 20.5H7.5Q4 20.5 4 17V7Q4 3.5 7 3.5Z M13.5 3.5V8Q13.5 10 15.5 10H20\"/>\u003crect x=\"7.5\" y=\"13.5\" width=\"9\" height=\"3.5\" rx=\"1\"/>","file-text":"\u003cpath d=\"M13.5 3.5H8Q4.5 3.5 4.5 7V17Q4.5 20.5 8 20.5H16Q19.5 20.5 19.5 17V9L13.5 3.5Z M13 4V7.5Q13 10 15.5 10H19 M8.5 13.5H15.5 M8.5 17H13\"/>","file-video":"\u003cpath d=\"M13.5 3.5H8Q4.5 3.5 4.5 7V17Q4.5 20.5 8 20.5H16Q19.5 20.5 19.5 17V9L13.5 3.5Z M13 4V7.5Q13 10 15.5 10H19 M10.2 13Q10.2 12.2 10.9 12.6L14.4 14.7Q15.1 15.2 14.4 15.7L10.9 17.8Q10.2 18.2 10.2 17.4Z\"/>","file":"\u003cpath d=\"M13.5 3.5H8Q4.5 3.5 4.5 7V17Q4.5 20.5 8 20.5H16Q19.5 20.5 19.5 17V9L13.5 3.5Z M13 4V7.5Q13 10 15.5 10H19\"/>","filter":"\u003cpath d=\"M4 6H20 M7 12H17 M10 18H14\"/>","folder-plus":"\u003cpath d=\"M3.5 7.5Q3.5 4.5 6.5 4.5H9.5L12 7H17.5Q20.5 7 20.5 10V16.5Q20.5 19.5 17.5 19.5H6.5Q3.5 19.5 3.5 16.5Z M12 10.5V16 M9.25 13.25H14.75\"/>","folder":"\u003cpath d=\"M3.5 7.5Q3.5 4.5 6.5 4.5H9.5L12 7H17.5Q20.5 7 20.5 10V16.5Q20.5 19.5 17.5 19.5H6.5Q3.5 19.5 3.5 16.5Z\"/>","forward-15":"\u003cpath d=\"M9.8 2.8L12 5L9.8 7.2 M12 5A7.5 7.5 0 1 0 18.5 8.75\"/>","im":"\u003cpath d=\"M11 4.5H8Q3.5 4.5 3.5 9V14Q3.5 18 7 18H8V21L12.5 18H15.5Q20 18 20 13.5V12 M12 11L20.5 3.5 M15 3.5H20.5V9\"/>","image-upload":"\u003cpath d=\"M11.5 3.5H7Q3.5 3.5 3.5 7V17Q3.5 20.5 7 20.5H17Q20.5 20.5 20.5 17V13 M4 17L9 12L15 18 M17.5 11V3.5 M14 7L17.5 3.5L21 7\"/>","info":"\u003cpath d=\"M20.5 12C20.5 17.5 17.5 20.5 12 20.5C6.5 20.5 3.5 17.5 3.5 12C3.5 6.5 6.5 3.5 12 3.5C17.5 3.5 20.5 6.5 20.5 12Z M10.5 11H12V16H13.5\"/>\u003ccircle cx=\"12\" cy=\"7.5\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>","key-back":"\u003cpath d=\"M8.5 5.5H18Q20.5 5.5 20.5 8V16Q20.5 18.5 18 18.5H8.5L3 12Z\"/> \u003cpath d=\"M11.5 9.5L16.5 14.5 M16.5 9.5L11.5 14.5\"/>","key-board":"\u003crect x=\"3\" y=\"4.5\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"7.8\" y=\"4.5\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"12.6\" y=\"4.5\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"17.4\" y=\"4.5\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/> \u003crect x=\"3\" y=\"9.6\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"7.8\" y=\"9.6\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"12.6\" y=\"9.6\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003crect x=\"17.4\" y=\"9.6\" width=\"3.6\" height=\"3.6\" rx=\"1\" fill=\"currentColor\" stroke=\"none\"/> \u003crect x=\"6.5\" y=\"15.6\" width=\"11\" height=\"2.6\" rx=\"1.3\" fill=\"currentColor\" stroke=\"none\"/>","key-shift-lock":"\u003cpath fill=\"currentColor\" d=\"M12 2.5L20 10.5H15.5V16H8.5V10.5H4Z\"/> \u003cpath d=\"M8.5 20.5H15.5\"/>","key-shift-once":"\u003cpath fill=\"currentColor\" d=\"M12 4.5L20 12.5H15.5V19H8.5V12.5H4Z\"/>","key-shift":"\u003cpath d=\"M12 4.5L20 12.5H15.5V19H8.5V12.5H4Z\"/>","key-swap":"\u003cpath d=\"M14.5 4.5H16Q19.5 4.5 19.5 8 M9.5 19.5H8Q4.5 19.5 4.5 16\"/>","key":"\u003ccircle cx=\"15.5\" cy=\"8.5\" r=\"5\"/>\u003cpath d=\"M12 12L3.5 20.5 M5 19L7 21 M8 16L10 18\"/>","keyboard":"\u003crect x=\"3.5\" y=\"6\" width=\"17\" height=\"12\" rx=\"3\"/>\u003cpath d=\"M7 10H7.2 M12 10H12.2 M17 10H17.2 M8 14.5H16\"/>","landscape":"\u003cpath d=\"M6 9H18Q21 9 21 12V16Q21 19 18 19H6Q3 19 3 16V12Q3 9 6 9Z M8 5.5Q12 3 16.5 5.2 M14.8 3.4L16.5 5.2L14.3 6.4\"/>","ling":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.021 1.693L11.468 2.149L10.914 2.621L10.365 3.116L9.825 3.638L9.298 4.190L8.771 4.761L8.236 5.342L7.692 5.933L7.139 6.535L6.596 7.163L6.088 7.841L5.607 8.563L5.145 9.319L4.689 10.099L4.911 10.301L5.646 9.777L6.358 9.250L7.034 8.708L7.665 8.143L8.244 7.549L8.796 6.948L9.339 6.358L9.874 5.778L10.400 5.208L10.908 4.640L11.386 4.062L11.837 3.477L12.266 2.890L12.679 2.307Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M11.321 2.307L11.734 2.890L12.163 3.477L12.614 4.062L13.092 4.640L13.600 5.208L14.126 5.778L14.661 6.358L15.204 6.948L15.756 7.549L16.335 8.143L16.966 8.708L17.642 9.250L18.354 9.777L19.089 10.301L19.311 10.099L18.855 9.319L18.393 8.563L17.912 7.841L17.404 7.163L16.861 6.535L16.308 5.933L15.764 5.342L15.229 4.761L14.702 4.190L14.175 3.638L13.635 3.116L13.086 2.621L12.532 2.149L11.979 1.693Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M11.267 10.800L11.545 11.228L11.779 11.661L11.989 12.091L12.199 12.521L12.425 12.959L12.646 13.432L12.841 13.953L13.009 14.523L13.150 15.143L13.264 15.812L13.356 16.529L13.425 17.295L13.467 18.112L13.480 18.978L14.920 19.022L14.957 18.105L14.959 17.227L14.921 16.390L14.842 15.592L14.720 14.836L14.558 14.122L14.359 13.447L14.121 12.813L13.844 12.221L13.507 11.683L13.088 11.227L12.605 10.861L12.079 10.588L11.533 10.400Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M13.906 13.131L13.448 13.256L12.994 13.406L12.548 13.587L12.115 13.803L11.697 14.054L11.290 14.329L10.888 14.621L10.493 14.930L10.104 15.256L9.737 15.615L9.417 16.030L9.141 16.492L8.903 16.988L8.690 17.506L8.910 17.694L9.388 17.428L9.851 17.174L10.286 16.917L10.687 16.646L11.052 16.353L11.405 16.058L11.762 15.779L12.123 15.516L12.488 15.269L12.853 15.030L13.212 14.788L13.569 14.545L13.928 14.303L14.294 14.069Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M14.369 18.229L13.939 18.166L13.506 18.116L13.069 18.081L12.630 18.063L12.189 18.063L11.745 18.077L11.300 18.102L10.853 18.137L10.404 18.182L9.956 18.251L9.510 18.358L9.069 18.501L8.633 18.672L8.201 18.861L8.399 19.739L8.851 19.739L9.294 19.740L9.729 19.733L10.155 19.712L10.573 19.673L10.988 19.631L11.400 19.598L11.810 19.576L12.217 19.563L12.623 19.557L13.027 19.554L13.429 19.554L13.830 19.559L14.231 19.571Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M8.031 19.401L8.159 19.785L8.328 20.158L8.545 20.512L8.810 20.836L9.123 21.124L9.468 21.384L9.838 21.624L10.231 21.845L10.647 22.047L11.094 22.209L11.579 22.300L12.092 22.327L12.625 22.300L13.173 22.237L13.227 21.963L12.770 21.684L12.349 21.412L11.956 21.162L11.583 20.946L11.222 20.770L10.879 20.604L10.562 20.426L10.270 20.236L10.004 20.036L9.753 19.833L9.504 19.636L9.256 19.438L9.009 19.228L8.769 18.999Z\"/>","link":"\u003cpath d=\"M10 13.5C11.5 15 14 15 15.5 13.5L19.5 9.5C21 8 21 5.5 19.5 4C18 2.5 15.5 2.5 14 4L12 6 M14 10.5C12.5 9 10 9 8.5 10.5L4.5 14.5C3 16 3 18.5 4.5 20C6 21.5 8.5 21.5 10 20L12 18\"/>","list":"\u003cpath d=\"M9 6.5H20 M9 12H20 M9 17.5H20\"/>\u003ccircle cx=\"4.75\" cy=\"6.5\" r=\"1.2\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"4.75\" cy=\"12\" r=\"1.2\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"4.75\" cy=\"17.5\" r=\"1.2\" fill=\"currentColor\" stroke=\"none\"/>","log-in":"\u003cpath d=\"M13 3.5H16Q20 3.5 20 7.5V16.5Q20 20.5 16 20.5H13 M3.5 12H14.5 M10 7.5L14.5 12L10 16.5\"/>","log-out":"\u003cpath d=\"M11 3.5H8Q4 3.5 4 7.5V16.5Q4 20.5 8 20.5H11 M10 12H20.5 M16 7.5L20.5 12L16 16.5\"/>","minus":"\u003cpath d=\"M4.5 12H19.5\"/>","monitor":"\u003cpath d=\"M8 3.5H16Q20.5 3.5 20.5 8V12Q20.5 16 16 16H8Q3.5 16 3.5 12V8Q3.5 3.5 8 3.5Z M12 16V20.5 M8 20.5H16\"/>","moon":"\u003cpath d=\"M19.5 14.5Q17.5 16 14.5 16Q8 16 8 9.5Q8 6.5 9.5 4.5Q3.5 6 3.5 12.5Q3.5 20.5 11.5 20.5Q18 20.5 19.5 14.5Z\"/>","more":"\u003ccircle cx=\"5\" cy=\"12\" r=\"1.4\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"12\" cy=\"12\" r=\"1.4\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"19\" cy=\"12\" r=\"1.4\" fill=\"currentColor\" stroke=\"none\"/>","mouse-left":"\u003crect x=\"6\" y=\"3\" width=\"12\" height=\"18\" rx=\"6\"/>\u003cpath d=\"M6 10.5H18 M12 3V10.5\"/>\u003cpath d=\"M11.1 4.1V9.6H6.9V9A5.1 5.1 0 0 1 11.1 4.1Z\" fill=\"currentColor\" stroke=\"none\"/>","mouse-right":"\u003crect x=\"6\" y=\"3\" width=\"12\" height=\"18\" rx=\"6\"/>\u003cpath d=\"M6 10.5H18 M12 3V10.5\"/>\u003cpath d=\"M12.9 4.1V9.6H17.1V9A5.1 5.1 0 0 0 12.9 4.1Z\" fill=\"currentColor\" stroke=\"none\"/>","move":"\u003cpath d=\"M12 3.5V20.5 M3.5 12H20.5 M9.5 6L12 3.5L14.5 6 M9.5 18L12 20.5L14.5 18 M6 9.5L3.5 12L6 14.5 M18 9.5L20.5 12L18 14.5\"/>","num-1":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M5.9 8.4 L15.6 1.8 L13.1 20.8 L10.1 22 L11.3 6.8Z\"/>","num-2":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M5.2 7.9 L8.4 2.9 L14.5 1.8 L18.4 5.2 L17.1 9.1 L6.8 17.9 L17.9 16.5 L16.4 21.2 L4.3 20.2 L4.8 18.4 L13.8 8.3 Q15.3 6.6 13.5 4.9 L10.4 4.2Z\"/>","num-3":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M5.3 5.8 L12.8 1.8 L17.9 4.6 L16.4 8.7 L12.8 11 L18 13.6 L16.8 18.1 L11.2 22 L4.9 18.7 L10.7 19.5 L14.1 16.3 L12.5 13.5 L8.5 13 L9.3 11 L13.3 8.1 L14 5.8 L11.5 4.4Z\"/>","num-4":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.7 1.8 L6.3 14.1 L20 12.6 L18.7 15.8 L3.7 16 L3.4 14.5Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M17.2 6.1 L15.7 18.8 L12 22 L11.8 19.3Z\"/>","num-5":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M7.7 3.6 L18.9 1.8 L16.9 5.8 L8.6 5.1 L7.7 10.8 L13.4 9 L18 12.9 L16.8 18.1 L11 22 L4.8 18.6 L10.6 19.5 L14 16 L13.4 12.8 L10.8 11.5 L5.9 13Z\"/>","num-6":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M18.1 1.7 L10.3 9.7 L8 15.1 L11.5 19.8 L14.9 16.3 L13.5 12.4 L9.5 12.9 L12.1 10.3 L16.2 10.9 L18 15.8 L14.3 21 L9.5 21.8 L5.5 17.5 L6.3 12 L11.8 5.6Z\"/>","num-7":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M4.5 2.6 L10.6 4 L19.7 1.9 L19 5 L14.9 11.4 L11.7 22 L8 20.6 L12.6 10.9 L16.9 5.2 L6.1 6.3Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M8 13.4 L17.1 10.2 L16.4 12.4 L7.7 14.2Z\"/>","num-8":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.9 1.7 L17.9 4.5 L16.7 8.2 L13.5 10.8 L18.3 14.4 L16.6 19.6 L10.9 22 L5.3 18.6 L6.3 14.4 L9.8 11.5 L6.2 8.5 L7.6 3.9Z M12.6 9.9 L15.2 6.6 L11.2 3.5 L8.9 6.8Z M11 12.4 L8 16.6 L12.5 20 L15.4 16.5Z\"/>","num-9":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M5.9 22.1 L13.7 14.1 L16 8.7 L12.5 4 L9.1 7.5 L10.5 11.4 L14.5 10.9 L11.9 13.5 L7.8 12.9 L6 8 L9.7 2.8 L14.5 2 L18.5 6.3 L17.7 11.8 L12.2 18.2Z\"/>","num-more":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.8 3.3 L15 5.5 L11.9 18.9 L9.7 20.7 L10.4 12.5Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M3.7 12.1 L20.5 9.7 L18.8 13 L5.2 13.6Z\"/>","option-1":"\u003c!-- Inter SemiBold 1, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M14.007 7.198V16.802H12.299V8.732H12.234L9.993 10.344V8.704L12.104 7.198Z\"/>","option-2":"\u003c!-- Inter SemiBold 2, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M8.74 16.866V15.628L12.072 12.346Q12.542 11.868 12.861 11.493Q13.181 11.119 13.346 10.765Q13.512 10.412 13.512 10.004Q13.512 9.55 13.302 9.221Q13.093 8.892 12.734 8.715Q12.376 8.538 11.916 8.538Q11.435 8.538 11.079 8.733Q10.723 8.927 10.528 9.285Q10.333 9.643 10.333 10.135H8.691Q8.691 9.226 9.106 8.552Q9.522 7.877 10.254 7.505Q10.987 7.134 11.937 7.134Q12.901 7.134 13.627 7.495Q14.354 7.856 14.761 8.484Q15.169 9.112 15.169 9.917Q15.169 10.451 14.967 10.962Q14.765 11.474 14.25 12.113Q13.735 12.752 12.794 13.657L11.124 15.358V15.43H15.309V16.866Z\"/>","option-3":"\u003c!-- Inter SemiBold 3, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M11.986 16.931Q10.975 16.931 10.192 16.584Q9.409 16.237 8.955 15.622Q8.501 15.007 8.48 14.197H10.214Q10.239 14.59 10.475 14.88Q10.71 15.17 11.104 15.328Q11.497 15.485 11.982 15.485Q12.5 15.485 12.898 15.305Q13.296 15.124 13.523 14.8Q13.751 14.475 13.751 14.051Q13.751 13.61 13.52 13.276Q13.289 12.943 12.857 12.753Q12.424 12.563 11.813 12.563H10.962V11.233H11.813Q12.311 11.233 12.692 11.057Q13.074 10.88 13.286 10.565Q13.499 10.25 13.499 9.828Q13.499 9.421 13.314 9.117Q13.129 8.814 12.792 8.644Q12.456 8.474 12.003 8.474Q11.56 8.474 11.184 8.633Q10.809 8.791 10.577 9.082Q10.345 9.372 10.332 9.78H8.677Q8.694 8.979 9.139 8.369Q9.584 7.758 10.336 7.414Q11.087 7.069 12.02 7.069Q12.976 7.069 13.685 7.43Q14.394 7.791 14.783 8.394Q15.172 8.997 15.172 9.726Q15.172 10.534 14.697 11.084Q14.222 11.633 13.443 11.808V11.881Q14.113 11.973 14.577 12.281Q15.041 12.589 15.28 13.064Q15.52 13.539 15.52 14.138Q15.52 14.945 15.064 15.577Q14.609 16.208 13.81 16.569Q13.012 16.931 11.986 16.931Z\"/>","option-4":"\u003c!-- Inter SemiBold 4, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M8.273 15.014V13.646L12.354 7.198H13.488V9.155H12.794L10.033 13.519V13.596H15.727V15.014ZM12.844 16.802V14.601L12.871 13.98V7.198H14.495V16.802Z\"/>","option-5":"\u003c!-- Inter SemiBold 5, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M11.933 16.866Q10.994 16.866 10.256 16.513Q9.519 16.161 9.086 15.543Q8.654 14.926 8.629 14.133H10.302Q10.327 14.523 10.551 14.826Q10.774 15.129 11.136 15.298Q11.499 15.467 11.933 15.467Q12.448 15.467 12.847 15.233Q13.246 14.998 13.472 14.581Q13.699 14.165 13.699 13.626Q13.699 13.077 13.464 12.651Q13.229 12.225 12.822 11.984Q12.415 11.743 11.884 11.743Q11.448 11.743 11.031 11.906Q10.614 12.068 10.372 12.334L8.812 12.081L9.31 7.134H14.869V8.574H10.74L10.465 11.13H10.516Q10.787 10.815 11.276 10.612Q11.764 10.409 12.344 10.409Q12.994 10.409 13.547 10.643Q14.1 10.877 14.509 11.305Q14.918 11.733 15.144 12.314Q15.371 12.894 15.371 13.586Q15.371 14.538 14.933 15.278Q14.495 16.019 13.721 16.442Q12.947 16.866 11.933 16.866Z\"/>","option-6":"\u003c!-- Inter SemiBold 6, centred on its ink: scripts/option-digits.py --> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.103 16.931Q11.418 16.931 10.763 16.695Q10.108 16.46 9.585 15.923Q9.061 15.387 8.752 14.491Q8.443 13.595 8.443 12.275Q8.443 11.042 8.704 10.078Q8.966 9.113 9.459 8.441Q9.952 7.77 10.646 7.419Q11.34 7.069 12.203 7.069Q13.101 7.069 13.8 7.423Q14.498 7.777 14.931 8.388Q15.364 9 15.466 9.78H13.775Q13.642 9.231 13.236 8.896Q12.83 8.561 12.203 8.561Q11.535 8.561 11.069 8.953Q10.602 9.345 10.36 10.076Q10.118 10.807 10.118 11.823H10.186Q10.419 11.41 10.782 11.113Q11.145 10.815 11.607 10.658Q12.069 10.501 12.582 10.501Q13.425 10.501 14.098 10.902Q14.771 11.304 15.164 12.011Q15.557 12.718 15.557 13.63Q15.557 14.574 15.125 15.321Q14.693 16.068 13.916 16.499Q13.139 16.931 12.103 16.931ZM12.094 15.532Q12.607 15.532 13.012 15.282Q13.417 15.033 13.653 14.61Q13.888 14.187 13.888 13.662Q13.888 13.145 13.659 12.727Q13.429 12.308 13.028 12.063Q12.628 11.817 12.115 11.817Q11.732 11.817 11.404 11.964Q11.075 12.11 10.829 12.368Q10.583 12.626 10.446 12.961Q10.308 13.296 10.308 13.67Q10.308 14.175 10.54 14.598Q10.772 15.021 11.178 15.276Q11.584 15.532 12.094 15.532Z\"/>","other":"\u003cpath d=\"M16.808 3.656L14.475 5.99L15.182 8.818L18.01 9.525L20.344 7.192C20.91 9.03 20.415 10.939 18.859 12.212C17.303 13.485 15.465 13.768 13.697 13.131L8.111 18.718C7.333 19.495 6.06 19.495 5.282 18.718C4.505 17.94 4.505 16.667 5.282 15.889L10.869 10.303C10.232 8.535 10.515 6.697 11.788 5.141C13.061 3.585 14.97 3.09 16.808 3.656Z\"/>","panel-close":"\u003cpath d=\"M8 4H16Q20.5 4 20.5 8.5V15.5Q20.5 20 16 20H8Q3.5 20 3.5 15.5V8.5Q3.5 4 8 4Z M14.5 4.5V19.5 M6.5 12H11.5 M9 9L12 12L9 15\"/>","panel-open":"\u003cpath d=\"M8 4H16Q20.5 4 20.5 8.5V15.5Q20.5 20 16 20H8Q3.5 20 3.5 15.5V8.5Q3.5 4 8 4Z M14.5 4.5V19.5 M7 12H12 M9.5 9L6.5 12L9.5 15\"/>","paste":"\u003cpath d=\"M8.5 5H7Q4.5 5 4.5 7.5V18Q4.5 20.5 7 20.5H17Q19.5 20.5 19.5 18V7.5Q19.5 5 17 5H15.5 M10 3H14Q15.5 3 15.5 4.5V5.5Q15.5 7 14 7H10Q8.5 7 8.5 5.5V4.5Q8.5 3 10 3Z\"/>","pause":"\u003cpath d=\"M7 5V19 M17 5V19\"/>","phone":"\u003crect x=\"6\" y=\"2.5\" width=\"12\" height=\"19\" rx=\"2.5\"/> \u003cpath d=\"M10 6H14 M11 18H13\"/>","photo":"\u003cpath d=\"M8 3.5H16Q20.5 3.5 20.5 8V16Q20.5 20.5 16 20.5H8Q3.5 20.5 3.5 16V8Q3.5 3.5 8 3.5Z M4 17L9 11.5L14 16.5L17 13.5L20.5 17\"/>\u003ccircle cx=\"15.5\" cy=\"8\" r=\"1.2\" fill=\"currentColor\" stroke=\"none\"/>","pin":"\u003cpath d=\"M8.5 3.5H15.5 M9.5 3.5V9L6.5 12.5Q5.5 13.5 5.5 14.5V15H18.5V14.5Q18.5 13.5 17.5 12.5L14.5 9V3.5 M12 15V20.5\"/>","play-mark":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M9.43 5.57L19.47 11.19Q20.91 12 19.47 12.81L9.43 18.43Q7.51 19.5 7.51 17.3L7.51 6.7Q7.51 4.5 9.43 5.57Z\"/>","play":"\u003cpath d=\"M7 5.8Q7 4.3 8.3 5L18.4 11Q19.6 12 18.4 13L8.3 19Q7 19.7 7 18.2Z\"/>","plug":"\u003cpath d=\"M8.5 3.5V8 M15.5 3.5V8 M6 8H18V11Q18 16 12 16Q6 16 6 11Z M12 16V18Q12 20.5 15 20.5H17\"/>","plus":"\u003cpath d=\"M12 4.5V19.5 M4.5 12H19.5\"/>","power":"\u003cpath d=\"M12 3.5V11 M7 5.5C4.5 7 3.5 9 3.5 12C3.5 17.5 6.5 20.5 12 20.5C17.5 20.5 20.5 17.5 20.5 12C20.5 9 19.5 7 17 5.5\"/>","quota":"\u003cpath d=\"M6.5 6H16Q19.5 6 19.5 9.5V14.5Q19.5 18 16 18H6.5Q3 18 3 14.5V9.5Q3 6 6.5 6Z M22 10V14 M7 10V14 M11 10V14\"/>","quote":"\u003cpath d=\"M9.5 11H4.5V5.5H9.5V12Q9.5 16.5 5 18.5 M20 11H15V5.5H20V12Q20 16.5 15.5 18.5\"/>","read":"\u003cpath d=\"M13.5 3.5H8Q4.5 3.5 4.5 7V17Q4.5 20.5 8 20.5H16Q19.5 20.5 19.5 17V9L13.5 3.5Z M7 13Q12 6.5 17 13Q12 19.5 7 13Z\"/>\u003ccircle cx=\"12\" cy=\"13\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>","received":"\u003cpath d=\"M12 3.5V14 M7.5 10L12 14.5L16.5 10 M4 15V17Q4 20.5 7.5 20.5H16.5Q20 20.5 20 17V15\"/>","redo":"\u003cpath d=\"M20 9H12Q3.5 9 3.5 15Q3.5 20.5 10 20.5H14 M15 3.5L20.5 9L15 14.5\"/>","refresh":"\u003cpath d=\"M20 9Q18.5 3.5 12 3.5Q7.5 3.5 5 7 M20 4V9H15 M4 15Q5.5 20.5 12 20.5Q16.5 20.5 19 17 M4 20V15H9\"/>","retry":"\u003cpath d=\"M4 9H12Q20.5 9 20.5 15Q20.5 20.5 14 20.5H10 M9 3.5L3.5 9L9 14.5\"/>","said":"\u003cpath d=\"M8 4H16Q20.5 4 20.5 8.5V14Q20.5 18 16.5 18H10L5 20.5V17.5Q3.5 16.5 3.5 14V8.5Q3.5 4 8 4Z M8 9H16 M8 13H13\"/>","scribble":"\u003cpath d=\"M3.5 17.5Q6 11 9 8Q12 5 12.5 7.5Q13 10 9.5 14.5Q7 18.5 10 18.5Q13 18.5 16.5 12.5Q18.5 9.5 20.5 11\"/>","search":"\u003cpath d=\"M17.5 10.5C17.5 15 15 17 11 17C6.5 17 3.5 14.6 3.5 10.5C3.5 6.3 6.1 3.5 10.5 3.5C14.7 3.5 17.5 6 17.5 10.5Z M16 16L20.5 20.5\"/>","send":"\u003cpath d=\"M4 9L19.5 3.5Q21 3 20.5 4.5L15 20L11 13Z M11 13L16 8\"/>","server":"\u003cpath d=\"M8 3.5H16Q20.5 3.5 20.5 8V16Q20.5 20.5 16 20.5H8Q3.5 20.5 3.5 16V8Q3.5 3.5 8 3.5Z M4 12H20 M11 8H16 M11 16H16\"/>\u003ccircle cx=\"7.5\" cy=\"8\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"7.5\" cy=\"16\" r=\"1\" fill=\"currentColor\" stroke=\"none\"/>","settings":"\u003cpath d=\"M10.5000 5.0000L10.5000 3.0000L13.5000 3.0000L13.5000 5.0000L15.8891 5.9896L17.3033 4.5754L19.4246 6.6967L18.0104 8.1109L19.0000 10.5000L21.0000 10.5000L21.0000 13.5000L19.0000 13.5000L18.0104 15.8891L19.4246 17.3033L17.3033 19.4246L15.8891 18.0104L13.5000 19.0000L13.5000 21.0000L10.5000 21.0000L10.5000 19.0000L8.1109 18.0104L6.6967 19.4246L4.5754 17.3033L5.9896 15.8891L5.0000 13.5000L3.0000 13.5000L3.0000 10.5000L5.0000 10.5000L5.9896 8.1109L4.5754 6.6967L6.6967 4.5754L8.1109 5.9896Z\"/>\u003ccircle cx=\"12\" cy=\"12\" r=\"3\"/>","shield-check":"\u003cpath d=\"M12 3.5Q16 6 20 6V12C20 16.5 16.5 19 12 20.5C7.5 19 4 16.5 4 12V6Q8 6 12 3.5Z M8 12L10.5 14.5L16 9\"/>","shrink":"\u003cpath d=\"M18.5 10H14V5.5 M14.5 9.5L19.5 4.5 M5.5 14H10V18.5 M9.5 14.5L4.5 19.5\"/>","skip-back":"\u003cpath d=\"M6 5V19 M18 5.8Q18 4.3 16.7 5L8.6 11Q7.4 12 8.6 13L16.7 19Q18 19.7 18 18.2Z\"/>","skip-forward":"\u003cpath d=\"M18 5V19 M6 5.8Q6 4.3 7.3 5L15.4 11Q16.6 12 15.4 13L7.3 19Q6 19.7 6 18.2Z\"/>","sliders":"\u003cpath d=\"M6 3.5V7 M6 12V20.5 M18 3.5V12 M18 17V20.5\"/>\u003crect x=\"4\" y=\"7\" width=\"4\" height=\"5\" rx=\"1.5\"/>\u003crect x=\"16\" y=\"12\" width=\"4\" height=\"5\" rx=\"1.5\"/>","sparks":"\u003cpath d=\"M9.5 8C10.5 12 12 13.5 16 14.5C12 15.5 10.5 17 9.5 21C8.5 17 7 15.5 3 14.5C7 13.5 8.5 12 9.5 8Z M17 3C17.5 5.5 18.5 6.5 21 7C18.5 7.5 17.5 8.5 17 11C16.5 8.5 15.5 7.5 13 7C15.5 6.5 16.5 5.5 17 3Z\"/>","spawned":"\u003cpath d=\"M6.5 9V13.5Q6.5 18 11 18H14\"/>\u003ccircle cx=\"6.5\" cy=\"6\" r=\"2.5\" fill=\"currentColor\" stroke=\"none\"/>\u003ccircle cx=\"17\" cy=\"18\" r=\"3\"/>","square":"\u003cpath d=\"M8 4.5H16Q19.5 4.5 19.5 8V16Q19.5 19.5 16 19.5H8Q4.5 19.5 4.5 16V8Q4.5 4.5 8 4.5Z\"/>","star-fill":"\u003cpath d=\"M12 3.5L14.6 8.8L20.4 9.6L16.2 13.7L17.2 19.5L12 16.8L6.8 19.5L7.8 13.7L3.6 9.6L9.4 8.8Z\"/>","star":"\u003cpath d=\"M12 3.5L14.6 8.8L20.4 9.6L16.2 13.7L17.2 19.5L12 16.8L6.8 19.5L7.8 13.7L3.6 9.6L9.4 8.8Z\"/>","stop":"\u003cpath d=\"M8.5 4.5H15.5Q19.5 4.5 19.5 8.5V15.5Q19.5 19.5 15.5 19.5H8.5Q4.5 19.5 4.5 15.5V8.5Q4.5 4.5 8.5 4.5Z\"/>","sun":"\u003ccircle cx=\"12\" cy=\"12\" r=\"4\"/>\u003cpath d=\"M12 2.5V4.5 M12 19.5V21.5 M2.5 12H4.5 M19.5 12H21.5 M5.3 5.3L6.7 6.7 M17.3 17.3L18.7 18.7 M5.3 18.7L6.7 17.3 M17.3 6.7L18.7 5.3\"/>","text-size":"\u003cpath d=\"M3 7V4.5H13.5V7 M8.25 4.5V19.5 M14 12.5V11H21V12.5 M17.5 11V19.5\"/>","text":"\u003cpath d=\"M5 7V4.5H19V7 M12 4.5V19.5 M9 19.5H15\"/>","think":"\u003cpath d=\"M12 3.5C13 8.5 15 10.5 20.5 12C15 13 13 15.5 12 20.5C10.5 15.5 8.5 13.5 3.5 12C8.5 10.5 10.5 8.5 12 3.5Z\"/>","thread":"\u003cpath d=\"M12 3.5C6.5 3.5 3.5 6 3.5 11C3.5 16 6.5 18.5 12 18.5H14L19.5 20.5L18.5 16.5Q20.5 14.5 20.5 11C20.5 6 17.5 3.5 12 3.5Z M8 7.5H16 M8 11H16 M8 14.5H13\"/>","ticket":"\u003cpath d=\"M5.5 5H18.5Q20.5 5 20.5 7V9.5A2.5 2.5 0 0 0 20.5 14.5V17Q20.5 19 18.5 19H5.5Q3.5 19 3.5 17V14.5A2.5 2.5 0 0 0 3.5 9.5V7Q3.5 5 5.5 5Z M14 8.5V15.5\"/>","trackpad":"\u003crect x=\"3.5\" y=\"4.5\" width=\"17\" height=\"15\" rx=\"3.5\"/>\u003cpath d=\"M3.5 15H20.5 M12 15V19.5\"/>","trash":"\u003cpath d=\"M4 7H20 M9 6.5V3.5H15V6.5 M6 7L6.5 17Q6.5 20.5 10 20.5H14Q17.5 20.5 17.5 17L18 7 M10 11V16 M14 11V16\"/>","unplug":"\u003cpath d=\"M8.5 3.5V8 M15.5 3.5V6 M6 8H12 M18 11V12Q18 17 12 17Q6 17 6 12V8 M12 17V20.5 M3.5 20.5L20.5 3.5\"/>","update":"\u003ccircle cx=\"12\" cy=\"12\" r=\"8.5\"/> \u003cpath d=\"M12 16V8 M9 11L12 8L15 11\"/>","upload":"\u003cpath d=\"M12 15V3.5 M7.5 8L12 3.5L16.5 8 M4.5 20H19.5\"/>","user-plus":"\u003cpath d=\"M13 7.5Q13 11.5 9 11.5Q5 11.5 5 7.5Q5 3.5 9 3.5Q13 3.5 13 7.5Z M3.5 20.5V19Q3.5 15 9 15Q11.5 15 13 16 M18 11.5V18.5 M14.5 15H21\"/>","user":"\u003cpath d=\"M16 7.5Q16 11.5 12 11.5Q8 11.5 8 7.5Q8 3.5 12 3.5Q16 3.5 16 7.5Z M4.5 20.5V19Q4.5 15 12 15Q19.5 15 19.5 19V20.5\"/>","users":"\u003cpath d=\"M12 8Q12 11.5 8.5 11.5Q5 11.5 5 8Q5 4.5 8.5 4.5Q12 4.5 12 8Z M3 20V18.5Q3 15 8.5 15Q14 15 14 18.5V20 M15 4.5Q19 4.5 19 8Q19 11.5 15 11.5 M17 15Q21 15.5 21 18.5V20\"/>","view-columns":"\u003cpath d=\"M6 4.5H18Q20.5 4.5 20.5 7V17Q20.5 19.5 18 19.5H6Q3.5 19.5 3.5 17V7Q3.5 4.5 6 4.5Z M9.5 4.5V19.5 M15 4.5V19.5\"/>","view-tree":"\u003cpath d=\"M4 5.5H11 M10 12H20 M10 18.5H20 M6.5 8V16Q6.5 18.5 9 18.5H10 M6.5 12H10\"/>","volume-x":"\u003cpath d=\"M4.5 9H7.5L12 5V19L7.5 15H4.5Q3 15 3 13.5V10.5Q3 9 4.5 9Z M16 9.5L21 14.5 M21 9.5L16 14.5\"/>","volume":"\u003cpath d=\"M4.5 9H7.5L12 5V19L7.5 15H4.5Q3 15 3 13.5V10.5Q3 9 4.5 9Z M15.5 9Q17 10.3 17 12Q17 13.7 15.5 15 M18 6.5Q21 8.8 21 12Q21 15.2 18 17.5\"/>","wait":"\u003cpath d=\"M18 7.5A7.5 7.5 0 1 0 18 16.5\"/> \u003cpath d=\"M11.5 12h.01\"/> \u003cpath d=\"M15.5 12h.01\"/> \u003cpath d=\"M19.5 12h.01\"/>","watch":"\u003ccircle cx=\"12\" cy=\"12\" r=\"1.8\" fill=\"currentColor\" stroke=\"none\"/> \u003cpath d=\"M7.8 7.8A6 6 0 0 0 7.8 16.2 M16.2 7.8A6 6 0 0 1 16.2 16.2\"/> \u003cpath d=\"M4.6 4.6A10.5 10.5 0 0 0 4.6 19.4 M19.4 4.6A10.5 10.5 0 0 1 19.4 19.4\"/>","web":"\u003cpath d=\"M20.5 12C20.5 17.5 17.5 20.5 12 20.5C6.5 20.5 3.5 17.5 3.5 12C3.5 6.5 6.5 3.5 12 3.5C17.5 3.5 20.5 6.5 20.5 12Z M12 3.5C7.5 8 7.5 16 12 20.5C16.5 16 16.5 8 12 3.5Z M4 12H20\"/>","zap":"\u003cpath d=\"M13 3L4.5 13.5H11.5L10.5 21L19.5 10.5H12.5L13 3Z\"/>","zou":"\u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M11.728 1.761L11.512 2.795L11.422 3.298L11.275 4.274L11.218 4.750L11.134 5.676L11.074 7.008L11.071 7.861L11.088 8.690L11.194 11.065L11.236 12.632L11.271 16.267L11.301 17.954L11.373 20.038L11.474 22.015L12.224 22.053L12.508 20.086L12.694 18.420L12.764 17.570L12.816 16.716L12.850 15.863L12.864 15.017L12.850 13.770L12.819 12.963L12.775 12.219L12.768 11.407L12.717 10.202L12.629 9.000L12.363 6.110L12.272 4.782L12.232 3.365L12.248 2.361L12.272 1.839Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M9.909 2.325L9.359 2.995L9.021 3.448L8.715 3.913L8.445 4.392L8.218 4.889L8.041 5.407L7.921 5.943L7.884 6.218L7.863 6.497L7.859 6.779L7.871 7.065L7.901 7.352L7.949 7.642L8.013 7.933L8.095 8.226L8.362 8.964L8.630 9.566L8.853 9.953L9.094 10.277L9.612 10.885L9.858 10.835L9.926 10.517L9.966 10.194L9.971 9.869L9.937 9.540L9.894 9.317L9.798 8.972L9.465 8.066L9.329 7.608L9.281 7.385L9.217 6.949L9.200 6.735L9.193 6.308L9.217 5.877L9.271 5.438L9.353 4.985L9.464 4.517L9.601 4.031L9.765 3.529L9.953 3.012L10.165 2.483Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M10.100 6.074L9.498 6.635L9.200 6.942L8.612 7.602L8.324 7.953L7.763 8.691L7.491 9.076L6.969 9.872L6.719 10.280L6.246 11.111L6.024 11.531L5.608 12.373L5.415 12.792L5.061 13.619L4.751 14.423L4.486 15.190L4.716 15.288L5.302 14.214L6.196 12.687L7.174 11.114L7.942 9.947L8.726 8.826L9.254 8.121L9.783 7.462L10.048 7.154L10.578 6.586Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M14.152 2.607L14.459 3.818L14.548 4.238L14.612 4.621L14.657 5.130L14.654 5.433L14.626 5.722L14.528 6.163L14.413 6.488L14.244 6.850L13.914 7.430L13.721 7.805L13.559 8.163L13.372 8.673L13.249 9.150L13.177 9.595L13.096 10.804L13.320 10.916L13.515 10.718L13.699 10.506L13.873 10.282L14.115 9.927L14.409 9.419L15.010 8.246L15.440 7.479L15.666 6.991L15.752 6.751L15.821 6.512L15.872 6.276L15.904 6.041L15.918 5.809L15.913 5.580L15.891 5.357L15.852 5.138L15.799 4.925L15.650 4.515L15.457 4.121L15.227 3.734L14.378 2.503Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M12.801 5.262L13.076 5.529L13.646 6.131L14.235 6.808L14.834 7.543L15.432 8.319L16.018 9.118L16.581 9.925L17.108 10.722L17.803 11.865L18.182 12.566L18.340 12.892L18.585 13.479L18.668 13.733L18.751 14.159L18.846 14.447L19.000 14.751L19.289 15.239L19.509 15.239L19.756 14.803L19.851 14.589L19.897 14.444L19.927 14.296L19.941 14.146L19.939 13.992L19.910 13.757L19.732 13.090L19.610 12.744L19.462 12.386L19.097 11.636L18.645 10.852L18.118 10.048L17.829 9.643L17.210 8.839L16.544 8.054L15.846 7.306L15.129 6.609L14.406 5.979L13.695 5.432L13.349 5.194L13.011 4.982Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M7.417 19.818L7.613 19.543L8.030 19.009L8.698 18.241L9.627 17.270L11.612 15.281L12.505 14.328L11.631 14.506L11.968 14.914L12.330 15.319L12.714 15.715L13.116 16.099L13.532 16.467L14.171 16.983L14.600 17.299L15.231 17.728L16.198 18.315L16.560 17.901L15.848 17.024L15.176 16.264L14.451 15.491L13.174 14.171L12.679 13.633L11.495 13.432L10.447 14.581L9.842 15.279L9.227 16.053L8.826 16.608L8.442 17.192L8.259 17.493L7.914 18.112L7.605 18.747L7.466 19.069L7.221 19.720Z\"/> \u003cpath fill=\"currentColor\" stroke=\"none\" d=\"M8.613 21.197L10.861 19.329L12.390 17.960L11.623 18.023L11.889 18.393L12.333 18.938L12.654 19.289L12.992 19.626L13.342 19.945L13.698 20.243L14.056 20.519L14.408 20.772L14.915 21.103L15.374 21.378L15.572 21.180L15.178 20.559L14.687 19.880L14.131 19.178L12.987 17.808L12.611 17.326L11.610 17.048L11.050 17.533L10.626 17.940L10.208 18.391L9.936 18.717L9.540 19.244L9.161 19.814L8.796 20.421L8.441 21.059Z\"/>"}
