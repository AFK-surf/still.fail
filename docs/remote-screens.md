# Screens: a station's browser and desktop, seen and driven from a client

> chat EMBER/1792171443.604000 (2026-10-17). Two parts, joined only by the screen-source interface below:
> **the station's browser** (agents drive a Chrome the station keeps) and **remote control** (a person sees a screen
> of the station in a client and drives it). Transport is the mesh only: no WebRTC, no port opened to anyone.

## The station's browser

- Each station keeps one real Chrome (Google Chrome, not a bundled Chromium; Chromium/Edge only when no Chrome is
  installed), started on demand as a normal browser with its own persistent profile (`<data>/browser/profile`) and
  `--remote-debugging-port=0` (a non-default user data dir, so Chrome honours it); the port is read from
  `DevToolsActivePort`. It stays up while used, and goes after a long idle (an hour); logins persist in the profile.
  It outlives a station process (as jobs do): the next one finds it by `DevToolsActivePort` and takes it up; one that
  dies in use is started again, on the same port when it is free (`station/src/browser/`).
- Sites must see a person's browser: headful wherever the machine shows windows (`--headless=new` only where it
  shows none), no automation switches, and two tells undone: Chrome reports `navigator.webdriver = true` for any
  debuggable browser (`--disable-blink-features=AutomationControlled`), and headless says `HeadlessChrome` in its user
  agent (given the headful one's). With either, Google's sign-in answers "This browser or app may not be secure";
  without them it goes on to the next step, headful or headless, with Playwright attached (Chrome 155, 2026-10-17).
- Agents get its CDP endpoint (`http://127.0.0.1:<port>`, and the `ws://127.0.0.1:<port>/devtools/browser/<id>` it
  names) from the `browser` tool and drive it with chrome-devtools-mcp (`--browserUrl`/`--wsEndpoint`) or Playwright
  (`connectOverCDP`). Sessions share the browser (and its logins) and open their own tabs.
- Every tab is a screen source (`browser:<targetId>`): CDP screencast for frames, `Input.dispatch*` for input, on a
  CDP connection of the view's own. Chrome draws (and casts) only the front tab of a window, so a view brings its tab
  to the front when it opens, when a key frame is asked for and when the person clicks.

## Remote control

### Sources (station/src/screens/source.ts)

A `ScreenSource` is something a person can see and drive: `desktop` (the station machine's display) or `browser` (a tab
of the station's browser). The `Screens` registry lists them and opens views. A view is pull-driven: the next frame is
captured/encoded only when the previous ones were taken, so a slow link lowers the frame rate instead of queueing.
Each source picks its codec among those the client accepts: the desktop is H.264 (hardware encoder), a browser tab may
be JPEG (CDP screencast) or H.264. Clients decode both.

### Wire (member link, ALPN `stillfail/admin/1`)

- **List**: `GET /admin/api/screens` → `{"screens":[{id, kind, title, width, height, viewers}]}`; changes come on the
  station's event stream as `screens` (same shape).
- **View**: a stream whose head line carries a `screen` object:
  `{"method":"POST","path":"/admin/api/screens/<id>/view","headers":{},"screen":{"maxWidth":1920,"maxHeight":1080,"codecs":["h264","jpeg"],"control":true}}`.
  The station answers `{"status":200,"headers":{"content-type":"application/x-stillfail-screen"}}` (or an error status
  with `{error}`), then both directions carry frames: a kind byte, the payload's length (4 bytes big-endian), the payload.

| kind | direction | payload |
|---|---|---|
| 1 `config` | station → client | JSON `{codec:"h264"\|"jpeg", width, height, description?}`: `description` is the avcC (base64) for H.264. Sent first and whenever size or codec changes; the next video frame after it is a key frame. |
| 2 `video` | station → client | 1 byte flags (bit 0: key frame), 8 bytes timestamp (µs, big-endian), then the frame: H.264 in AVCC (length-prefixed NALs), or one JPEG. |
| 3 `state` | station → client | JSON `{cursor?: {x, y, shape}, title?, controlledBy?: [names], ended?: reason}` |
| 16 `input` | client → station | JSON, coordinates normalised to 0..1 of the frame: `{t:"pointer", x, y, buttons, kind:"down"\|"up"\|"move"}`, `{t:"wheel", x, y, dx, dy}`, `{t:"key", kind:"down"\|"up", key, code, mods}`, `{t:"text", text}` (IME/paste result) |
| 17 `ack` | client → station | 8 bytes: the timestamp of the last frame it decoded. The station keeps at most 2 frames unacknowledged. |
| 18 `keyframe` | client → station | empty: decoder lost its state, send a key frame |

- Read-only members (`viewer` role) may view but not send input (`control` ignored, input frames dropped).
  Anyone else may drive. Every active view shows in `controlledBy` / `viewers`, so people and the agent see who is on it.
- Ending: either side finishes the stream.

### Asking a person to take over

The agents' `screen` tool lists the station's screens and gives a link to one: `<cloud>/w/<workspace>/s/<station>/screen/<id>`.
The agent posts it with `chat_post` (need_human: "log in here", "solve the captcha") and ends its turn; clients open
the link in their screen viewer (web: a page; Android: a full-screen activity; in a chat, `link.parse` → `screen`).
