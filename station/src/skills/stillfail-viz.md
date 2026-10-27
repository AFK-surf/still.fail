---
name: stillfail-viz
description: Create inline HTML diagrams, charts, comparisons or interactive widgets in still.fail chats. Use when a small visual explains better than prose; Slack receives an attached file.
---

# Inline visualizations

- Make one only when people need to see or explore something in the chat and it explains better than words. A table
  someone asks for is a Markdown table; a static structure that labeled nodes and edges explain fully is a Mermaid code
  fence (it draws in still.fail's colours without a file). Use HTML for numbers, motion, adjustable inputs and the rest.
- A request for a site, an app page or a change to a project is not one: build that in the project.

## Post

Write an HTML fragment in the session workspace, e.g. `release.html`. Attach with
`chat_post(files=["/abs/path/release.html"])` and put `[Release](release.html)` on its own line in the text. Every
still.fail app (web, desktop, phones) draws it there. Say its point around the link in a sentence or two:
notifications and chat lists show only your words, and figures are not read aloud. Don't repeat its data in the text.
In Slack, attach but omit the Markdown link; files upload below the text, and still.fail's copy of the thread shows
the file as a card that opens it, not drawn in the message. Say what the figure shows for people staying in Slack.

## Fragment

- Only a fragment: no `<!doctype>`, `<html>`, `<head>` or `<body>` (a full document is drawn as written in a 16:9
  window without any of the below). Keep it under 1 MB: aggregate or downsample big data.
- Give its root a unique id and find things with `document.getElementById`. Check that every script runs, every
  element it looks for exists and the main interaction updates the figure.
- The sandbox has no fetch, XHR or WebSocket, nor the page, station or files. Scripts, styles and fonts may load only
  from cdnjs.cloudflare.com, esm.sh, cdn.jsdelivr.net, unpkg.com, fonts.googleapis.com and fonts.gstatic.com. Images
  are data URIs, SVG or canvas.
- Keep the figure to the figure: no explanatory paragraphs or instructions inside it, only the labels, legends and
  values it needs, and a screen-reader summary.

## Design system

The frame loads still.fail's stylesheet: one set of tokens and a set of utility classes under the names you know from
shadcn and Bootstrap. Use them as they are; never restyle a utility (its size, spacing, border, corner, colour or
states) and never hard-code a colour (`#fff`, `black`, `slate-500`): light and dark follow the viewer.

### Tokens

- Pairs, a ground and what is on it: `--background`/`--foreground` (the page), `--card`/`--card-foreground`,
  `--primary`/`--primary-foreground` (ink: the solid control, what is chosen), `--secondary` and `--muted` (a quiet
  ground) with `--muted-foreground` (the one grey for secondary words), `--accent`/`--accent-foreground` (a soft
  highlight), `--popover`/`--popover-foreground`.
- `--border` (only for what has nothing in it: a chart's grid, an empty track), `--input`, `--ring`, `--destructive`.
- Tones, each an ink and a ground: `--blue`, `--green`, `--yellow`, `--red`, `--purple`, `--orange` and `--blue-bg`….
- Chart series: `--viz-series-1` (ink, for one measure or the active state) to `--viz-series-6`.
- `--font-size-base`: everything else follows it, and a phone's is a size up.

### How it looks

- Grey by default. Colour only what must be noticed (a failure, a warning, done) and series past the first; values,
  labels and states that are normal stay `--foreground` or `--muted-foreground`. A status is `.viz-dot` and words.
- What is chosen, current or pressed is ink (`--primary`), never orange. The brand's orange is only a fill the
  stylesheet already gives (a progress bar, a checked box).
- Set things apart with room and grounds. No borders, outlines, dividers, banners or coloured callout boxes; no
  shadows. The figure's own surface is transparent and unframed and fills the width.
- Type: the body size by default, `.text-small` for secondary labels, `h1` for a figure's one title and `h2` for a
  panel's; weights 400, 500 and 600 for titles. Never set font sizes or line heights; numbers are already one width.

### Surfaces and layout

- `.widget`: a column for the whole figure. `.viz-grid`: equal columns as fit, stacking when narrow (2–3 at full
  width). `.viz-row`: a wrapping row of related values or actions. `.viz-controls`: a wrapping row of controls.
- `.card`: the only card. Use it for a number with its label, a selected item's summary, or a bounded interactive
  field; never around a chart, a table, a map or the whole figure, never one in another, never to frame a section.
- `.viz-stat` on a `.card`: `.viz-stat-label`, `.viz-stat-value` (a unit in `<small>`), and at most one short line
  after it (a delta: `<span class="text-success">↑ 8%</span>`). Show 2–4 near the top only when they explain the
  question; never invent a row of them.
- `.viz-badge` (add `.is-green`, `.is-red`, `.is-yellow`, `.is-blue`, `.is-purple`): a display-only pill.
- `.viz-dot` (same tones, and `.is-off`): a status dot before words.
- `.viz-flow` of `.viz-node` (`.viz-node-title`, `.viz-node-body`; `.is-active` for the current one, a tone only for
  one that is wrong) with `.viz-arrow` between them: a few boxes in a line.
- `.progress` > `.progress-bar style="width:40%"`, with `role="progressbar"` and its values.
- `.viz-dotted-background`: a quiet dot grid behind a mockup.

### Controls

- `.btn`; `.btn-primary` for the one main action, `.btn-secondary`, `.btn-ghost` for low emphasis; `.btn-xs`,
  `.btn-sm`, `.btn-lg`; `.btn-block` to fill the row. `aria-pressed="true"`, `aria-selected="true"` or
  `.is-selected` mark one chosen. `.btn.viz-tile` is a selectable cell of a dense grid.
- `.form-label` above `.form-control` (input or textarea) or `.form-select`; `-sm`/`-xs` for smaller ones.
  `<label class="form-check">` around `.form-check-input` and `.form-check-label`; `.form-switch`; `.form-range`
  with its value before it.
- Tabs, switched for you: `.nav.nav-pills[role="tablist"]` of `button.nav-link[role="tab"]` with `id`,
  `aria-controls` and `aria-selected` (the first `.active`), and `[role="tabpanel"]` panels, the others `hidden`:

```html
<div class="nav nav-pills" role="tablist" aria-label="Range">
  <button class="nav-link active" id="week" role="tab" aria-controls="week-panel" aria-selected="true" type="button">Week</button>
  <button class="nav-link" id="month" role="tab" aria-controls="month-panel" aria-selected="false" type="button">Month</button>
</div>
<div id="week-panel" role="tabpanel" aria-labelledby="week">…</div>
<div id="month-panel" role="tabpanel" aria-labelledby="month" hidden>…</div>
```

- `data-tooltip="text"` on any element shows it on hover, focus and touch; put a truncated label's full text there.
- Icons: `<i data-lucide="search" aria-hidden="true"></i>` (Lucide's names); never draw icon SVG yourself. After adding
  icons from a script, call `lucide.createIcons()`.
- Native `button`, `input`, `select`, `textarea` only; essential content and actions never only on hover.

### Tables and text

- `.table` on a semantic table (`thead` for the head), in `.table-responsive` when it may be too wide; `.table-sm`;
  `.text-end` on number cells, `.text-center`, `.text-nowrap`.
- `.text-small`, `.text-muted` (never for essential values), `.text-destructive` (only errors), `.text-success`,
  `<code>`, `<pre><code>`, `.sr-only`.

## Charts

`<viz-chart>` draws a chart from data in its `data` attribute (JSON, single-quoted) or a
`<script type="application/json">` inside it, in the tokens' colours, sized to its container, with values on hover:

| `type` | data |
|---|---|
| `bar`, `line`, `area` (`stacked` for bars) | `{"labels":[…],"values":[…]}` or `{"labels":[…],"series":[{"name","values","tone"}]}` |
| `hbar` (`max`) | `{"labels":[…],"values":[…]}` or `{"items":[{"label","value","tone","note"}]}`: a ranking, shares |
| `donut`, `pie` (`center` sets the middle words) | `{"items":[{"label","value","tone"}]}` |
| `scatter` (`x-unit`) | `{"series":[{"name","points":[[x, y, "label"]]}]}` |

Also `unit`, `height` and `title`. One series is ink; more take `--viz-series-2…` in order with a legend; `tone`
(`red`, `green`, `yellow`, `blue`, `purple`) only for a series that must stand out. `<viz-spark data="[…]" tone width
height>` is a small trend line, e.g. in a table cell.

- Put the chart straight on the figure's surface under an `h1`/`h2` title; never in a `.card`.
- Start from the chart for named numbers or a one-off analysis; put takeaways in your message, not in cards above it.
- For what `<viz-chart>` does not draw (timelines of parallel work, distributions, small multiples, maps), use D3
  (`<script src="https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js"></script>`) or handwritten SVG with the same
  look: `var(--viz-series-n)` for marks, `var(--muted-foreground)` for axis text at 11px or more, thin `var(--border)`
  grid lines, no frame or fill behind the plot, axis titles with units, `data-tooltip` on each mark. Size each SVG from
  its container with a `ResizeObserver`; never scale down a fixed-width `viewBox`. For a canvas or a library that needs
  real colours, read them with `getComputedStyle(document.documentElement).getPropertyValue("--viz-series-2")` and
  redraw on the `ember-viz:theme` event.

## Composition

- Choose the smallest composition that answers: one dominant visual, controls only when asked for or essential, one
  mechanism per state. Never invent search, filter or reset controls, KPI rows, legends that repeat labels, or panels
  to fill space.
- Fill the width and work from 736 px down to 320 px: let rows wrap and grids stack; no fixed outer widths, internal
  scrolling, `position: fixed` or viewport heights. Text never overlaps or clips.
- A mockup of a product's screen uses that product's own colours and type, defined in the fragment
  (`light-dark(…, …)`), never these tokens or utilities; `.viz-dotted-background` may sit behind it.

## Talking back

`window.ember` (also named `window.openai`, as Codex has it):

- `ember.widgetState` — what the widget kept last time it was shown (or null); `ember.setWidgetState(value)` keeps a
  JSON value of up to 16 KiB on the station, restored whenever and wherever the message is shown again. Put what you
  should know in `value.modelContent` (the person's choices, say) and the rest in `value.privateContent`:
  `modelContent` reaches you with the next message they send, as a note beside it; keeping state never starts a turn.
  Save after meaningful interactions, never on load.
- `ember.sendFollowUpMessage({ prompt })` — puts `prompt` in the chat's composer for the person to send, as if they
  wrote it. Only from their click or key press; it never sends by itself. Use it for drill-downs ("explain this
  week's spike") with the selected values in the prompt, and label the button for what it asks.

Before posting a large or scripted one, check it renders: open the file in a browser (or a screenshot tool) and fix
what does not draw or throws.
