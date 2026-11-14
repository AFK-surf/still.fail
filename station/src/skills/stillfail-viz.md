---
name: stillfail-viz
description: Create inline native mbui widgets (.mbui), sandboxed Wasm mini-programs (.wasm), charts, comparisons or interactive diagrams in still.fail chats. Use when a visual or interactive widget explains better than prose; Slack receives an attached file.
---

# Inline visualizations (`.mbui` & `.wasm`)

- Make one only when people need to see or explore something in the chat and it explains better than words. A table
  someone asks for is a Markdown table; a static structure that labeled nodes and edges explain fully is a Mermaid code
  fence (it draws natively in still.fail's colours without a file). Use a `.mbui` widget or `.wasm` mini-program for
  charts, metrics, comparisons, interactive calculators/simulators, tabs/toggles, checklists and follow-up actions.
- Prefer `.mbui` / `.wasm` over `.html`: `.mbui` and `.wasm` widgets are rendered natively by still.fail's `mbui` engine
  (`@view.View` + `@sf` components + `@signals.Signal` + Skia canvas) with zero WebView overhead, synchronous layout
  height on the very first frame, 120 fps scrolling, automatic light/dark theme tokens, and direct rendering in
  chat-to-image exports.
- A request for a site, an app page or a change to a project is not an inline widget: build that in the project. For a
  mockup of `still.fail`'s own UI, write real `mbui` code (`sffixture`) and render screenshots/video with
  `apps/mbui/scripts/media.sh` (see `stillfail-show`).

## Post

Write a `.mbui` JSON file (or a `.wasm` binary mini-program) in the session workspace, e.g. `release.mbui` or
`sim.wasm`. Attach with `chat_post(files=["/abs/path/release.mbui"])` and put `[Release](release.mbui)` on its own line
in the text. Every still.fail app (desktop, iOS, Android, web) draws it inline in the message and supports full-screen
expansion. Say its point around the link in a sentence or two: notifications and chat lists show only your words. Don't
repeat its data in the text. In Slack, attach the file and omit the Markdown link; say what the figure shows for people
staying in Slack.

## `.mbui` Widget Schema

A `.mbui` file is a UTF-8 JSON object with optional initial `state` and a `body` array of declarative `mbui` nodes:

```json
{
  "title": "0.1.9102 发版概览",
  "subtitle": "双平台安装包与回归状态",
  "state": {
    "canary_only": true
  },
  "body": [
    {
      "type": "grid",
      "cols": 3,
      "children": [
        { "type": "stat", "label": "首帧耗时", "value": "0.4", "unit": "ms", "delta": "↓ 98%", "tone": "green", "spark": [18, 15, 9, 4, 1, 0.4] },
        { "type": "stat", "label": "WebView 进程", "value": "0", "unit": "个", "delta": "纯原生渲染", "tone": "blue" },
        { "type": "stat", "label": "滚动帧率", "value": "120", "unit": "fps", "delta": "零异步高度跳变", "tone": "green" }
      ]
    },
    {
      "type": "tabs",
      "id": "main_tab",
      "items": [
        {
          "id": "charts",
          "label": "概览图表",
          "body": [
            {
              "type": "chart",
              "chart": "bar",
              "title": "各阶段耗时对比 (ms)",
              "unit": "ms",
              "height": 180,
              "labels": ["解析", "首帧布局", "主题切换", "长图导出"],
              "series": [
                { "name": "mbui 原生", "values": [0.2, 0.4, 0.1, 1.2], "tone": "green" },
                { "name": "HTML WebView", "values": [14.0, 48.0, 18.0, 95.0], "tone": "yellow" }
              ]
            }
          ]
        },
        {
          "id": "checklist",
          "label": "发版检查单",
          "body": [
            { "type": "switch", "key": "canary_only", "label": "仅向 Canary 渠道灰度推送", "note": "开启后首日限流 10% 设备" },
            {
              "type": "row",
              "children": [
                { "type": "button", "label": "生成灰度发布指令", "variant": "primary", "follow_up": "按 canary_only={canary_only} 生成 0.1.9102 发布指令" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

### Node types

#### Layout & containers
- `column` / `widget`: vertical stack (`gap` in px, default 10; `children` / `body`).
- `row` / `controls`: horizontal row (`gap` in px, default 8; `wrap`: `true` by default; `align`: `"center"` or `"top"`; `children`).
- `grid`: responsive multi-column grid (`cols`: 1–4, default 2; stacks automatically on narrow screens < 460 px; `gap`; `children`).
- `card`: surface container (`title`, `subtitle`, `badge`, `tone`, `children`). Use for stats, bounded controls or grouped fields; never wrap a chart or table in a card.
- `divider` / `sep`: thin horizontal rule.

#### Text, status & badges
- `h1`, `h2`, `text`: text block (`text` / `value`, `muted`: bool, `small`: bool, `mono`: bool, `bold`: bool, `tone`).
- `badge`: pill badge (`text` / `label`, `tone`: `"green"`, `"red"`, `"yellow"`, `"blue"`, `"purple"`, `"orange"`).
- `dot` / `status`: coloured status dot + label (`text` / `label`, `tone`: same tones or `"off"`).
- `callout`: highlighted note (`title`, `text`, `tone`).
- `code`: monospace code block (`text` / `code`, `lang`).

#### Metrics, tables & flows
- `stat`: metric card (`label`, `value`, `unit`, `delta`, `tone`, optional inline `spark`: `[numbers]`). Show 2–4 in a `grid` near the top when key numbers answer the question.
- `kv`: key-value list (`items`: `[{"label", "value", "mono", "tone", "badge"}]`).
- `table`: framed data table (`columns` / `headers`: `[strings]`, `align`: `["left"|"right"|"center"]`, `rows`: `[[cells]]`, `sm`: bool). Each cell can be a string/number or an object `{"text", "tone", "mono", "bold", "badge", "spark": [...]}`.
- `flow`: step pipeline (`nodes`: `[{"title", "body", "active": bool, "tone"}]`) with arrows between steps, wrapping cleanly on narrow screens.
- `progress`: progress bar (`label`, `value`, `max` default 100, `value_text`, `tone`).

#### Native charts & vector graphics
- `chart`: native Skia chart with hover/tap crosshair inspection and automatic series legend:
  - `"chart"`: `"bar"` (`"stacked": true` optional), `"line"`, `"area"`, `"hbar"` (`"max"` optional), `"donut"`, `"pie"` (`"center"` text optional), `"scatter"` (`"x_unit"` optional).
  - `"title"`, `"subtitle"`, `"unit"`, `"height"` (default 180).
  - Data formats:
    - Single series: `"labels": ["A", "B"], "values": [10, 20]`
    - Multi-series (`bar`, `line`, `area`): `"labels": […], "series": [{"name": "S1", "values": […], "tone": "blue"}]`
    - Ranked / proportional items (`hbar`, `donut`, `pie`): `"items": [{"label": "A", "value": 42, "tone": "green", "note": "42%"}]`
    - Scatter (`scatter`): `"series": [{"name": "S1", "tone": "blue", "points": [[x, y, "label"]]}]`
- `spark`: compact sparkline (`"values": [1, 4, 2, 8]`, `"tone"`, `"width"`, `"height"`).
- `svg`: native vector canvas (`"svg"`: SVG markup with `<path>`, `<rect>`, `<circle>`, `<line>`, `<polyline>`, `<polygon>`, `<g>`, `"viewBox": "0 0 W H"` or `"width"`/`"height"`).

#### Interactive controls & state (`@signals.Signal[Json]`)
- `tabs`: interactive pill tabs (`"id"`, optional `"state_key"`, `"active"`, `"items": [{"id", "label", "badge", "body": […]}]`).
- `details` / `collapse`: expandable section (`"id"`, `"title"`, `"subtitle"`, `"open": bool`, `"body": […]`).
- `switch`: boolean toggle row (`"key"`, `"label"`, `"note"`, `"value"`). Toggling updates `state[key]` and persists widget state.
- `check`: interactive checkbox row (`"key"`, `"label"`, `"note"`, `"value"`). Toggling updates `state[key]` and persists widget state.
- `button` / `action`: interactive button (`"label"`, `"variant"`: `"primary"` | `"secondary"` | `"ghost"`, `"set"`: `{"key": value}`, `"inc"`: `"key"`, `"toggle"`: `"key"`, `"wasm_call"`: `"export_fn"`, `"follow_up"`: `"prompt text"`).
- Conditional visibility on any node: `"when": "key"` (truthy in `state`), `"when": "!key"` (falsy), or `"when": "key=val"`.
- State interpolation in text & `follow_up`: `{key}` or `${key}` in text, badges, progress bars, or a button's `follow_up` prompt is replaced with the live value of `state[key]`, and the prompt is placed in the chat composer for the user to review and send. State changes are saved automatically to the station (`modelContent` is sent to you alongside the user's next message).

## Sandboxed Wasm 1.0 Mini-Programs (`.wasm` & `"wasm"`)

When a widget needs custom computation (simulations, live aggregations, pricing/capacity calculators, or dynamic view
generation), use the built-in sandboxed Wasm 1.0 bytecode runtime (`viz_wasm_vm.mbt`):
- **Cross-platform & iOS-ready**: interpreted in pure MoonBit at ~880 MIPS (~0.02 ms for 20k instructions; 0 ms during
  list scrolling/animations) with zero JIT requirement.
- **Deterministic sandbox**:
  - Capability-based host import allowlist (`mbui` / `env` only; WASI, filesystem, and network imports are rejected at
    instantiation).
  - Per-invocation instruction gas metering (`"gas_limit"`, default `1,000,000` instructions per event) that traps
    infinite loops without blocking the UI thread.
  - Hard linear memory cap (`64` pages = `4 MiB`) and call stack depth limit (`256`).
- **Two ways to package**:
  1. **Embedded controller in `.mbui`**: add `"wasm": "<base64-encoded .wasm>"` (or `"wasm_hex"`) to your `.mbui` JSON.
     Buttons can invoke any exported function via `"wasm_call": "fn_name"` (with optional `"args": [...]` and `"into": "state_key"`),
     and state changes automatically invoke exported `mbui_event` or `mbui_update`.
  2. **Standalone `.wasm` file**: attach `app.wasm` and link `[Title](app.wasm)`. On load, `mbui_init()` runs and emits
     the initial `.mbui` JSON tree via `mbui.set_tree(ptr, len)` (or returns a `(ptr << 32) | len` `i64` slice).
- **Host imports (`"mbui"` or `"env"` module)**:
  - `state_get_i32(key_ptr: i32, key_len: i32, fallback: i32) -> i32`
  - `state_set_i32(key_ptr: i32, key_len: i32, val: i32)`
  - `state_get_f64(key_ptr: i32, key_len: i32, fallback: f64) -> f64`
  - `state_set_f64(key_ptr: i32, key_len: i32, val: f64)`
  - `state_get_str(key_ptr: i32, key_len: i32, dst_ptr: i32, dst_cap: i32) -> i32`
  - `state_set_str(key_ptr: i32, key_len: i32, val_ptr: i32, val_len: i32)`
  - `set_tree(json_ptr: i32, json_len: i32)`: update the widget's `.mbui` JSON tree.
  - `set_state(json_ptr: i32, json_len: i32)`: merge a JSON object into reactive `state`.
  - `follow_up(text_ptr: i32, text_len: i32)`: draft a follow-up message in the chat composer.
  - `input_len() -> i32` and `input_copy(dst_ptr: i32, max_len: i32) -> i32`: read the JSON event payload passed to `mbui_init` / `mbui_event`.

## Design rules

- Choose the smallest composition that answers: one dominant visual, controls only when useful, no filler panels.
- Grey by default. Use `tone` (`green`, `red`, `yellow`, `blue`, `purple`, `orange`) only for status, deltas, anomalies or series distinction.
- Never place a `chart` or `table` inside a `card`.

## Legacy HTML fallback (`.html`)

Only when a visualization requires custom D3 force layouts or custom Canvas scripting that `.mbui` nodes cannot express,
you may attach an HTML fragment (`.html`) instead. Keep fragments under 1 MB with no `<!doctype>`/`<html>`, using
still.fail's CSS tokens (`--foreground`, `--muted-foreground`, `--border`, `--viz-series-1…6`) and `window.openai`
(`openai.widgetState`, `openai.setWidgetState`, `openai.sendFollowUpMessage`). For everything else, use `.mbui`.
