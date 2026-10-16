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

- **List**: `GET /admin/api/screens` → `{"screens":[{id, kind, title, width, height, viewers, controlledBy, access?}]}`;
  changes come on the station's event stream as `screens` (same shape). `viewers`: the names of those with a view of it
  open; `controlledBy`: those of them whose input is taken. `access`, only when something is missing:
  `{capture, control, message, app?, path?}` (`message` in the asker's language says what to turn on where; the desktop
  without macOS's grants, or on a machine it is not supported on). An old station answers this route 404: a client
  opens a view only on a station that listed the screen (an old one would read the view's head as a request whose
  body never ends).
- **View**: a stream whose head line carries a `screen` object:
  `{"method":"POST","path":"/admin/api/screens/<id>/view","headers":{},"screen":{"maxWidth":1920,"maxHeight":1080,"codecs":["h264","jpeg"],"control":true}}`.
  The station answers `{"status":200,"headers":{"content-type":"application/x-stillfail-screen"}}`, or an error status
  with `{error, access?}` (404 no such screen, 400 no codec it knows, 415 none it sends, 501 not supported here, 503
  not now: no grant, the capture failed), then both directions carry frames: a kind byte, the payload's length
  (4 bytes big-endian), the payload. Input frames of more than 64 KB end the view.

| kind | direction | payload |
|---|---|---|
| 1 `config` | station → client | JSON `{codec:"h264"\|"jpeg", width, height, description?}`: `description` is the avcC (base64) for H.264. Sent first and whenever size or codec changes; the next video frame after it is a key frame. |
| 2 `video` | station → client | 1 byte flags (bit 0: key frame), 8 bytes timestamp (µs, big-endian), then the frame: H.264 in AVCC (length-prefixed NALs), or one JPEG. |
| 3 `state` | station → client | JSON `{cursor?: {x, y, shape}, title?, control?, access?, viewers?: [names], controlledBy?: [names], ended?: reason}`: first `{title, control, access?}` (`control`: whether this view's input is taken), then what changes; `ended`: `finished` (the client finished), `gone` (the source went), `stopping` (the station stops) |
| 16 `input` | client → station | JSON, coordinates normalised to 0..1 of the frame: `{t:"pointer", x, y, buttons, kind:"down"\|"up"\|"move"}`, `{t:"wheel", x, y, dx, dy}`, `{t:"key", kind:"down"\|"up", key, code, mods}`, `{t:"text", text}` (IME/paste result) |
| 17 `ack` | client → station | 8 bytes: the timestamp of the last frame it decoded. The station keeps at most 2 frames unacknowledged. |
| 18 `keyframe` | client → station | empty: decoder lost its state, send a key frame |

- Read-only members (`viewer` role) may view but not send input (`control` ignored, input frames dropped).
  Anyone else may drive. Every active view shows in `controlledBy` / `viewers`, so people and the agent see who is on it.
- Ending: either side finishes the stream (the station says `ended` first). When the stream or its connection breaks,
  the view ends with it; the source's capture stops either way.

### The desktop (station/src/screens/desktop.ts, station/native/screen)

macOS only (elsewhere it is listed with `access` saying it is not supported, and opens nothing). A helper per view,
`stillfail-screen` (Swift, a native part beside `mesh.node` in the release): ScreenCaptureKit captures the main display
scaled into `maxWidth`×`maxHeight`; VideoToolbox encodes H.264 on the hardware encoder with low-latency rate control
(constrained baseline, no reordering, AVCC with the avcC as `description`), a picture only when one is asked for and
the screen changed (a still screen sends nothing), a key frame on request; CGEvent posts the input (mouse with click
counts, wheel in pixels, keys by their `code` as the Mac's virtual keys, text as Unicode). macOS grants Screen
Recording and Accessibility to the process responsible for the helper: the station's launcher `stillfail-station`
(`~/.stillfail/app/mesh/target/release/`, signed `fail.still.station` in releases, so a grant outlasts updates) under
launchd, the app in the desktop app. A view refused for want of a grant asks macOS once (its prompt on that Mac lists
the launcher in System Settings), and `access.message` names it and its path.

### Clients

The core (client/core-ts/src/screens.ts; docs/client-core.md, the `screens` topic and the `screen.*` calls) holds each
station's list (read as its stream opens, then its `screens` events; in memory only) and opens views. A view's frames
go to the page as they come, their bytes beside the JSON rather than in it (the web's worker transfers them, the
desktop's utility process posts them on the page's port, Android's engine hands them to Kotlin with `emitBytes`); the
page decodes (WebCodecs or `createImageBitmap` on the web, MediaCodec or a bitmap on Android) and acknowledges each
frame it drew. What the page draws of the view (its phase, 只看/控制, who else is on it) the core says whole as it
changes; it opens the view again when the link drops or 只看/控制 changes. A station from before screens answers
`GET /screens` 404: its list is empty and says it needs an update, and a link to one of its screens says so without
opening a stream (such a station would take the stream for a request and wait for a body).

### Asking a person to take over

The agents' `screen` tool lists the station's screens and gives a link to one: `<cloud>/w/<workspace>/s/<station>/screen/<id>`.
The agent posts it with `chat_post` (need_human: "log in here", "solve the captcha") and ends its turn; clients open
the link in their screen viewer (web: a page; Android: a full-screen activity; in a chat, `link.parse` → `screen`).
