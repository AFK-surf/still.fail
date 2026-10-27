---
name: stillfail-viz
description: Create inline HTML diagrams, charts, comparisons or interactive widgets in still.fail chats. Use when a small visual explains better than prose; Slack receives an attached file.
---

# Inline visualizations

In still.fail (EMBER/…), placed HTML attachments render in the message. An HTML code fence is only code;
an unplaced attachment opens as a file. For a simple flow, sequence, state machine or timeline, use a Mermaid
code fence instead: it renders in still.fail colours without a file.

## Post

Write an HTML fragment in the session workspace, e.g. `release.html`. Attach with
`chat_post(files=["/abs/path/release.html"])` and put `[Release](release.html)` on its own line in the text. Every
still.fail app (web, desktop, phones) draws it there; still say its point around the link: notifications and chat
lists show only your words, and figures are not read aloud.
In Slack, attach but omit the Markdown link; files upload below the text, and still.fail's copy of the thread shows
the file as a card that opens it, not drawn in the message. Say what the figure shows for people staying in Slack.

## Components and tokens

Every fragment has still.fail's design tokens (`--sf-…`, below) and a few components loaded. Compose figures from
the components and plain HTML styled with the tokens; for charts use `<sf-chart>`, not a chart library.

Atoms:

| Element or class | What it is |
|---|---|
| `<sf-stack>`, `<sf-row>`, `<sf-grid>` | a column, a wrapping row, auto columns (`style="--min:240px"` sets the least width) |
| `<sf-card title note>` | a card: its ground, an optional title and a quiet line under it |
| `<sf-stat label value unit note tone delta delta-tone trend>` | a number with its label; `delta="+8%"` (`delta-tone="good\|bad"`), `trend="[…]"` a small line under it; `plain` drops its ground |
| `<sf-status tone>` | a small dot and words: `ok`, `busy`, `warn`, `error`, `off`, `info` |
| `<sf-badge tone>` | a pill: grey, or `blue`, `green`, `amber`, `red`, `purple` |
| `<sf-button primary quiet small send>` | a button; with `send`, a click puts those words in the chat's composer |
| `<sf-progress value max label note>` | a progress bar with what it says |
| `<sf-note>` | quieter words: a source, an aside |
| `<sf-table>` around a `<table>` | a table: head quieter, rows apart by room; `class="num"` on number cells sets them right |
| `.sf-title`, `.sf-sub` | a title, the quiet line under it |
| `.sf-segmented` of `button.sf-segment` (`aria-selected="true"` on the chosen) | a segmented choice: tabs, a pick of a few; your script switches it |
| `.sf-input`, `.sf-select`, `.sf-label`, `label.sf-check` | fields |

Charts, drawn from data in a `data` attribute as JSON (single-quote it) or a `<script type="application/json">`
inside the element:

| Element | Data |
|---|---|
| `<sf-chart type="bar\|line\|area" unit height stacked title>` | `{"labels":[…],"values":[…]}`, or `{"labels":[…],"series":[{"name","values","tone"}]}` |
| `<sf-chart type="hbar" unit max>` | `{"labels":[…],"values":[…]}` or `{"items":[{"label","value","tone","note"}]}`: a ranking, shares |
| `<sf-chart type="donut\|pie" unit center>` | `{"items":[{"label","value","tone"}]}`; `center` sets the middle words |
| `<sf-chart type="scatter" unit x-unit>` | `{"series":[{"name","points":[[x, y, "label"]]}]}` |
| `<sf-spark data tone width height>` | `[…]`: a small trend line inline |

One series is drawn in ink; more take the series colours in order, with a legend. Hovering shows each value.

```html
<sf-stack>
  <sf-grid>
    <sf-stat label="Merged" value="128" delta="+12" delta-tone="good" trend="[90,96,104,128]"></sf-stat>
    <sf-stat label="Failing checks" value="3" tone="error" note="android twice in a row"></sf-stat>
  </sf-grid>
  <sf-card title="PRs merged a day" note="last two weeks">
    <sf-chart type="bar" data='{"labels":["10/26","10/27","10/28"],"values":[7,22,24]}'></sf-chart>
  </sf-card>
  <sf-card title="Checks">
    <sf-table><table>
      <tr><th>Check</th><th>State</th><th class="num">Time</th></tr>
      <tr><td>linux</td><td><sf-status tone="ok">passed</sf-status></td><td class="num">3:41</td></tr>
      <tr><td>android</td><td><sf-status tone="error">failed</sf-status></td><td class="num">9:58</td></tr>
    </table></sf-table>
  </sf-card>
  <sf-row>
    <sf-button primary send="Run the failing checks again">Run again</sf-button>
    <sf-note>From CI, every 10 minutes.</sf-note>
  </sf-row>
</sf-stack>
```

Anything else (a comparison, a timeline, a file tree, a diff) you build from these and plain HTML, with the tokens
and the look below. Components write no words of their own: every label is what you give them, in the chat's
language.

## Look

The components already look like still.fail; what you add must too:

- Grey by default. Colour only what must be noticed (a failure, a warning, done) and chart series past the first;
  normal values, labels and states stay grey or ink. A status is a small dot and words, not a block of colour.
- Mark the current or chosen thing in ink, never in orange: the accent is only a fill (a progress bar, a check box).
- Set things apart with room and grounds (cards), never frames, rules, dividers, banners or coloured callout boxes.
- Use the type sizes as they are; numbers are already all one width.

## Design tokens

Light and dark follow the viewer's theme. Never hard-code colours (no `#fff`, `black`, `slate-500`) or sizes: use
these variables.

- Grounds: `--sf-page` (what the figure lies on), `--sf-card`, `--sf-quiet` (under a pill or a box in a card),
  `--sf-hover`, `--sf-selected`, `--sf-field`.
- Words: `--sf-ink`, `--sf-muted` (the one grey for labels and notes).
- Lines, only for what has nothing in it (a chart's grid, an empty track): `--sf-line`, `--sf-line-strong`.
- `--sf-primary` / `--sf-on-primary` (a solid button), `--sf-accent` (fills only).
- Tones, each an ink and a ground: `--sf-blue`, `--sf-green`, `--sf-amber`, `--sf-red`, `--sf-purple`, and
  `--sf-blue-ground`… Series in order: `--sf-series-1` (ink) … `--sf-series-6`.
- Type: `--sf-font`, `--sf-font-mono`; sizes with their lines: `--sf-text-caption`, `--sf-text-meta` (labels),
  `--sf-text-ui` (controls, tables), `--sf-text-body` (what is read), `--sf-text-title`, `--sf-text-heading`,
  `--sf-text-display` (a big number), each with `--sf-leading-…`. Weights 400, 500 to stand out, 600 for titles.
  Nothing smaller than the caption size.
- Corners: `--sf-r-card`, `--sf-r-field`, `--sf-r-small`; pills and dots `999px`.
- Room: `--sf-card-pad` (20), `--sf-text-in` (10), `--sf-gap` (12), `--sf-gap-s` (6), `--sf-gap-l` (20).
- Motion: `--sf-dur`, `--sf-ease`.

In SVG use `currentColor` or `var(--sf-…)`. For a canvas or a library that needs real colours, read them with
`getComputedStyle(document.documentElement).getPropertyValue("--sf-series-2")` and redraw on the `ember-viz:theme`
event.

Codex's Visualize names also work, as aliases (`--background`, `--foreground`, `--chart-1`…, `.card`, `.btn`,
`.btn-primary`, `.table`, `.nav-pills`, `.viz-flow`, `.viz-node`, `.viz-badge`, `.form-control`, `data-tooltip`…), so
a figure written for it draws in still.fail's look; prefer the components.

## Write

- Fragments omit `<html>`, `<head>` and `<body>`; order `<style>`, markup, then `<script>`. Stay well under 1 MB.
- The sandbox has no fetch, XHR, WebSocket or access to the page, station or files. Scripts/styles may load from
  cdnjs.cloudflare.com, esm.sh, cdn.jsdelivr.net or unpkg.com. Images must be data URIs, SVG or canvas; embed data.
- Design for 736 px down to 320 px: the components wrap by themselves; avoid fixed widths and viewport heights.
- Any element with `data-tooltip="text"` shows it on hover and focus.
- A full document (`<!doctype>` or `<html>`) renders as written in a 16:9 window, not content-sized, without the
  stylesheet or components: about 736×414 down to 320×180. All content and controls must scale together.
  Full-screen pages are better attached unplaced or served via stillfail-jobs.

## Talking back

`window.ember` (the name it had before still.fail; also named `window.openai`, as Codex's Visualize has it):

- `ember.widgetState` — what the widget kept last time it was shown (or null); `ember.setWidgetState(value)` keeps a
  JSON value of up to 16 KiB on the station, restored whenever and wherever the message is shown again. Put what you
  should know in `value.modelContent` (the person's choices, say) and the rest in `value.privateContent`:
  `modelContent` reaches you with the next message they send, as a note beside it; keeping state never starts a turn.
- `ember.sendFollowUpMessage({ prompt })` — puts `prompt` in the chat's composer for the person to send, as if they
  wrote it. Only from their click or key press (a button's handler); it never sends by itself. `<sf-button send>` does it
  for you.

Before posting a large or scripted one, check it renders: open the file in a browser (or a screenshot tool) and fix
what does not draw or throws.
