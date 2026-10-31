# Screens: a station's browser and desktop, seen and driven from a client

> chat EMBER/1792171443.604000 (2026-10-17). Two parts, joined only by the screen-source interface below:
> **the station's browser** (agents drive a Chrome the station keeps) and **remote control** (a person sees a screen
> of the station in a client and drives it). Transport is the mesh only: no WebRTC, no port opened to anyone.

## The station's browser

> chat EMBER/1793439516.811000 (2026-10-31, 用户定): one Chrome for the station, with no window, and in it an
> environment of each chat's own, kept in memory; sign-ins only from the vault (docs/vault.md 登录态). Turned down: a
> Chrome per chat (some 300 MB each before any tab: "我们有用户的"), and a browser embedding Chromium (CEF 156
> off-screen: Google's sign-in refused it, below).

- Each station keeps one real Chrome (Google Chrome, not a bundled Chromium; Chromium/Edge only when no Chrome is
  installed), started on demand with its own profile (`<data>/browser/profile`, the station's own context's) and
  `--remote-debugging-port=0` (a non-default user data dir, so Chrome honours it); the port is read from
  `DevToolsActivePort`. It stays up while used, and goes after a long idle (an hour). It outlives a station process
  (as jobs do): the next one finds it by `DevToolsActivePort` and takes it up; one that dies in use is started again,
  on the same port when it is free (`station/src/browser/`).
- It opens no window on the machine: headless (`--headless=new`; headful only where asked, `chromeHost({headless:
  false})`), its tabs seen and driven from people's apps. Every tab is still opened as in a window of its own, behind
  the others (`Target.createTarget` with `newWindow: true, background: true`), and nothing brings a tab forward: a
  view does not, and a session's `Target.activateTarget` and `Page.bringToFront` are answered as done and not passed
  on (a headful one, measured on a Mac, Edge 156, 2026-10-29: a tab opened in front, or brought forward, made the
  browser the front app; one opened so stayed behind and gave screenshots of its page).
- Sites must see a person's browser: no automation switches, and two tells undone: Chrome reports
  `navigator.webdriver = true` for any debuggable browser (`--disable-blink-features=AutomationControlled`), and
  headless says `HeadlessChrome` in its user agent (given the headful one's). With either, Google's sign-in answers
  "This browser or app may not be secure"; without them it goes on to the next step (Chrome 155, 2026-10-17; Chrome
  156, 2026-10-31: headless, headful, and in a context made over DevTools alike reached Google's 验证身份 step, and
  Cloudflare's check passed; CEF 156's sample client off-screen was refused at once).
- **A chat's own environment** (`station/src/browser/browsers.ts`). Each chat has a browser context of its own in the
  one Chrome (`Target.createBrowserContext`), made when its agent first asks for the browser: its tabs, cookies,
  storage and cache are its own, in memory only (nothing of a chat's is written to the station's disk), and go with
  the chat (archived or deleted: `Target.disposeBrowserContext`) or with Chrome (ended: a chat asking again has a new
  one). Which context is whose is kept beside the browser (`<data>/browser/contexts.json`, with the Chrome they are
  in), so the next station process takes them up with it. A tab in a chat's context is that chat's: people see which
  chat a tab is, and it opens that chat. The station's own context (the profile's) holds the tabs it opens itself, no
  chat's: a login's page for a person to finish there (docs/remote-login.md, 在 station 的浏览器中登录;
  `StationBrowser.openTab`), closed as the login ends; and the sign-ins made there before chats had their own, which
  an agent may keep in the vault from it (`secret_save {kind: "browser", browser: "station"}`).
- **A chat's way in** (`station/src/browser/proxy.ts`, `gate.ts`). The `browser` tool gives each session its own
  address on the agents' door, `ws://127.0.0.1:<door>/browser/<session key, base64url>`: a WebSocket to Chrome's
  DevTools through a gate that lets the session reach its chat's context only. It reads every message the agent sends:
  one on a target session goes only to a session of its own target's; one on the browser's own target only for the
  methods it knows (the Target domain's for its own targets, cookies, permissions and downloads put as its context's,
  `Browser.getVersion` and the like), a new tab opened in its context, `Target.getBrowserContexts` answered with its
  context as the default (so Playwright's `contexts()[0]` and puppeteer's default context are it); the browser's own
  session (`Target.attachToBrowserTarget`), `Browser.close`, tracing and anything else refused as an unknown method
  is. Of what Chrome sends it reads only the browser's news of targets and the answers it asked to look at: news of
  another chat's target never reaches the agent, and one Chrome attached it to on its own (auto-attach) is let go of
  at once (`Target.detachFromTarget`, the gate's own, its answer kept from the agent). Measured with Playwright 1.63
  on Chrome 156 (station/side/browser.test.ts): two chats each sign in or not on the same site, see only their own
  pages and cookies, and are refused another's tab and the browser's close. The address stays when Chrome is started
  again or another station process takes the door (the door's socket is the launcher's), so a client that lost its
  connection connects to it again; connecting starts the browser if it is not running. Only programs on this machine
  reach it (the door's rule for `/peer`). Chrome's own port is not given to agents; the agents run as the station's
  system user, so one bent on it could still find it: the gate holds agents to their chat as they are given to work,
  not against the machine's own user.
- **Sign-ins from the vault.** A sign-in granted (docs/vault.md 登录态) is put into its chat's context
  (`Storage.setCookies` with the context's id, its sites' cookies only) and taken out when its grant ends (each of them
  set again to have expired), its cookies as they were then given back to the vault; one whose grant ended while the
  browser was closed is taken out before the chat's agent has it again. A context made anew gets the sign-ins still
  granted again.
- Every tab is a screen source (`browser:<targetId>`): CDP screencast for frames, `Input.dispatch*` for input, on a
  CDP connection of the view's own. Chrome draws (and casts) only the front tab of a window: a tab is alone in its
  window (above), but for one a page opens itself, which goes in front of the page that opened it there; that one casts
  nothing until the other is closed.

## Remote control

### Sources (station/src/screens/source.ts)

A `ScreenSource` is something a person can see and drive: `desktop` (the station machine's display), `browser` (a tab
of the station's browser) or `simulator` (an iOS Simulator booted on a Mac station, below). The `Screens` registry lists them and opens views. A view is pull-driven: the next frame is
captured/encoded only when the pace (below) lets one go, so a slow link lowers the bit rate and then the frame rate
instead of queueing. Each source picks its codec among those the client accepts: the desktop is H.265 where the client
decodes it and the Mac encodes it, else H.264 (hardware encoder; Windows H.264 only), a browser tab JPEG (CDP
screencast).

The station's own users of a screen (the agents' computer-use tool) open views in the process with
`ScreenHub.openAs(id, options, {name, control})` (station/src/screens/hub.ts): the view is the source's, with no member
link in between (its `input` posted as a person's is), and while it is open `name` (e.g. `agent: <chat title>`) is in
the screen's `viewers`, and with `control` in `controlledBy`, told to people on it and in the list like theirs. The
desktop gives H.264 when the codecs take it and else a JPEG a picture (quality 0.8, same bounds, pull-driven alike);
JPEG frames are all key frames and their config has no `description`.

### Wire (member link, ALPN `stillfail/admin/1`)

- **List**: `GET /admin/api/screens` →
  `{"screens":[{id, kind, title, width, height, viewers, controlledBy, access?, clipboard?, drop?, closable?, openedBy?}]}`; changes come on
  the station's event stream as `screens` (same shape). `viewers`: the names of those with a view of it open;
  `controlledBy`: those of them whose input is taken. `access`, only when something is missing:
  `{capture, control, message, app?, path?}` (`message` in the asker's language says what to turn on where; the desktop
  without macOS's grants, or on a machine it is not supported on). `clipboard`: the types a view that drives it carries
  both ways (`"text"`, `"png"`; the desktop both, a browser tab text); `drop`: `{folder, reveal}`, where a file a person
  drops into a view is put on the machine (with the drive's upload, `root` the folder: docs/drive.md) and whether the
  view can show it in the machine's file manager. `peek`: it can be previewed (a tab of the browser). A station from
  before them says none of these: clients offer none. `closable`: a member (not a viewer) may close it, a tab of the
  browser: **Close** `POST /admin/api/screens/<id>/close` → `{}` (404 no such screen, 405 not closed from here, 502
  the browser refused), and it leaves the list as Chrome tells it went. `openedBy`: the session that opened it (whose
  a tab is, above); clients show the chat that session is in, among the viewer's chats, and open it. An old station answers this route 404: a client
  opens a view only on a station that listed the screen (an old one would read the view's head as a request whose
  body never ends).
- **View**: a stream whose head line carries a `screen` object:
  `{"method":"POST","path":"/admin/api/screens/<id>/view","headers":{},"screen":{"maxWidth":1920,"maxHeight":1080,"codecs":["h264","jpeg"],"control":true}}`.
  With `"quality": "smooth" | "hd" | "original"` (the 画质 chosen on the client; none for 自动) the station lets the
  bit rate go higher than the source's own (Pace, "Bit rate"); a station from before it lets it be, and a client that
  says none gets the source's own as before. A preview's is not read.
  With `"fps": 120 | 90 | 60 | 30 | 15` (the 帧率 chosen on the client; none for 自动) no more frames a second go
  than that (Pace, "Frame rate"), and the desktop captures and encodes at it; a station from before it, or a value
  not among these, lets it be: as many as the source makes and the link carries, as before. A preview's is not read.
  With `"audio": "pcm_s16le"` a capable source also sends system output audio (never microphone audio).
  The desktop captures it on Windows and macOS; the mbui app plays it on macOS, iOS, Windows and Android (Android
  only while its window is on the screen). Older sources ignore the request.
  Previews never request or capture audio. No audio frames are sent without negotiation.
  Colours: a video's are sRGB's, tagged so in its VUI (colour_primaries 1, transfer 13, matrix 1, studio range; the
  Windows desktop's BT.709's transfer). With `"gamut": "p3"` (the client shows a video tagged Display P3 as such) this
  Mac's desktop is captured in Display P3 and its VUI says so (colour_primaries 12): wider colours on a wide-gamut
  phone. Without it they are sRGB's, whatever the Mac's display is: its own space (a wide-gamut OLED's, P3's) shown as
  sRGB came out washed out. The Apple app asks it where its frames go on the system's video layer
  (@hostapi.stream_layers: Core Animation shows the decoded IOSurface in its tagged colour space); a frame it draws
  itself there (a faded or ended view's) is converted to sRGB first (apple_stream.m). A client that draws the frames
  into an sRGB canvas (the web, Android) or shows them on a layer as sRGB (Windows' app: @hostapi.stream_layers_tagged
  false) asks none. Other sources and older stations ignore it.
  With `"peek": true` it is a preview (a link's card in a chat, below): it only looks (`control` is false), is not in
  `viewers`, and brings no tab forward (a tab behind another casts nothing then); only of a screen the list says
  `peek` (a tab of the browser: the desktop's view wakes its display), else 501.
  With `"fit": {width, height, scale}` (a phone's or a tablet's stage, in its CSS pixels, 200..2000 a side, and their
  scale, 1..4; only with `control`) a tab of the browser is laid out for it while the view is open, as that device's own
  browser would lay it out: Chrome's device emulation on the view's own CDP session (`Emulation.setDeviceMetricsOverride`
  with `mobile`, the scale at most 2), cast as large as that; it goes with the view (cleared as it ends). Other sources
  take no notice of it. Clients send it from a touch device's viewer, and a finger then taps such a tab where it is (no
  trackpad).
  The station answers `{"status":200,"headers":{"content-type":"application/x-stillfail-screen"}}`, or an error status
  with `{error, access?}` (404 no such screen, 400 no codec it knows, 415 none it sends, 501 not supported here, 503
  not now: no grant, the capture failed), then both directions carry frames: a kind byte, the payload's length
  (4 bytes big-endian), the payload. Input frames of more than 64 KB end the view.

| kind | direction | payload |
|---|---|---|
| 1 `config` | station → client | JSON `{codec:"h265"\|"h264"\|"jpeg", width, height, description?, region?}`: `description` is the hvcC (H.265) or avcC (H.264), base64; `region` `{x, y, w, h}` (0..1 of the screen) the part of the screen the frames after it show (after a `look`, below), none the whole. Sent first and whenever size, codec or part changes; the next video frame after it is a key frame. |
| 2 `video` | station → client | 1 byte flags (bit 0: key frame), 8 bytes timestamp (µs, big-endian), then the frame: H.265 or H.264 as length-prefixed NALs (parameter sets in the config only), or one JPEG. |
| 3 `state` | station → client | JSON `{cursor?: {x, y, shape}, title?, control?, access?, viewers?: [names], controlledBy?: [names], scale?: {percent, recommended, steps}, resolution?: {width, height, modes: [{width, height}]}, video?: {capture, encoder?, hardware?}, latency?: {frame, before}, login?: {host, field} | null, passkey?: {id, host, rpId, clientData, allow, userVerification} | null, ended?: reason}`: first `{title, control, access?, video?}` (`video`: what captures the pictures and whether the encoder is the hardware's, for the statistics) (`control`: whether this view's input is taken), then what changes; `latency` each second while frames come (screen-pace.ts `FrameLatency`: ms from a picture's capture to its drawing on the device, and to its going out of the station); `scale`, to a view that drives a screen whose display scale is changed (Windows' desktop), as it opens and after each change it asked; `resolution` likewise, its display's resolution and the modes it takes; `cursor`: the screen's pointer (0..1 of the screen, whatever part the frames show, its shape a CSS cursor's name, `none` hidden) as it moves, from a source whose pictures leave it out (the desktop's video); `login`: to a view that drives a tab of the browser, the login field its focus is in (`field` `username` or `password`, `host` the tab's as the browser has its address), null as it leaves one (Filling a login, below); `passkey`: to a view that drives a tab of the browser, its page's sign-in with a passkey, null as it goes (Signing in with a passkey, below); `ended`: `finished` (the client finished), `gone` (the source went: the core says the view's phase is `gone` then, over for good, as for a screen no longer listed), `stopping` (the station stops) |
| 4 `clipboard` | station → client | 1 byte type (1 text in UTF-8, 2 PNG), the content: the screen's clipboard each time it changes (a copy made on it), only to a view that drives it; not what it held as the view opened. |
| 5 `audioConfig` | station → client | JSON `{codec:"pcm_s16le", sampleRate:48000, channels:2}` before the first audio packet. |
| 6 `audio` | station → client | 8-byte timestamp (µs, big-endian) followed by exactly 3840 bytes: 960 stereo frames of interleaved signed little-endian PCM16 (20 ms). |
| 16 `input` | client → station | JSON, coordinates normalised to 0..1 of the screen (the whole of it, whatever part the frames show): `{t:"pointer", x, y, buttons, kind:"down"\|"up"\|"move"}`, `{t:"wheel", x, y, dx, dy}`, `{t:"key", kind:"down"\|"up", key, code, mods}`, `{t:"text", text}` (IME/paste result), `{t:"scale", percent}` (the display's scale, one of the `steps` its `scale` said; from a view that drives it), `{t:"resolution", width, height}` (the display's resolution, one of the `modes` its `resolution` said; from a view that drives it), `{t:"reveal", path}` (the file manager showing a file dropped into the view; a screen whose `drop` says `reveal`), `{t:"fill", host, username?, password?}` (a login form filled from the person's password manager, for the `host` its state's `login` said; from a view that drives it: Filling a login, below), `{t:"passkey", id, credential, authenticatorData, signature, userHandle?}` or `{t:"passkey", id, error}` (the page's passkey sign-in answered from the person's device; from a view that drives it: Signing in with a passkey, below) |
| 17 `ack` | client → station | 8 bytes: the timestamp of the last frame it decoded (drawn). What the station sends next goes by them (Pace, below). |
| 18 `keyframe` | client → station | empty: decoder lost its state, send a key frame |
| 19 `clipboard` | client → station | 1 byte flags (bit 0: paste it), 1 byte type (1 text, 2 PNG), the content: sets the screen's clipboard and, with paste, pastes it where its focus is. Only from a view that drives it, of a type its `clipboard` names; text at most 1 MB, a PNG 8 MB (a larger frame ends the view, as any client frame past its bound does) |
| 20 `look` | client → station | JSON `{region: {x, y, w, h} \| null, maxWidth?, maxHeight?}`: the part of the screen the client shows (zoomed in), and the device pixels it is shown in; null, or about all of it, the whole at the view's own bounds (Regions, below). A station from before it lets it be. |

- Read-only members (`viewer` role) may view but not send input (`control` ignored, input and clipboard frames
  dropped). The clipboard goes only to and from a view that drives the screen (never one that only looks, nor an
  agent's), and is not looked at while no such view is open.
  Anyone else may drive. Every active view shows in `controlledBy` / `viewers`, so people and the agent see who is on it.
- Ending: either side finishes the stream (the station says `ended` first). When the stream or its connection breaks,
  the view ends with it; the source's capture stops either way. A client killed with a view open (Android's force
  stop) says nothing as it goes: when its endpoint connects again, the station asks its older connections whether
  their other end is still there and closes those that do not answer within 3 s, so the dead view leaves the screen
  then rather than at QUIC's idle timeout, half a minute on (station/src/mesh/superseded.ts). Another live client
  with the same key (a tab of Chrome on Android) answers and keeps its own.

### Pace (station/src/mesh/screen-pace.ts)

How many frames are on the way and how large they are follows the client's `ack`s; nothing else is asked of the
client, so any client that acknowledges what it drew is paced.

- **Frames on the way.** Before the first `ack`, 2. Then frames go while the oldest not acknowledged has waited no
  longer than the quickest round trip (sent → acknowledged) of the last 10 s and 30 ms or half the round trip, whichever
  is more (`queueMs`: a far link's round trip varies more), at most 16: a far link holds
  as many frames as its round trip takes, so it carries 60 a second as a near one does (a fixed 2 gave 2 a round trip:
  13 a second at 150 ms). Once the oldest waits longer, a queue is building in front of the link (frames larger than
  it carries, a packet lost and sent again) and none goes until an `ack`.
- **Bit rate.** Frames held back (the oldest waited too long as the next was ready) again and again for longer than
  two round trips and 200 ms mean the link carries less than the frames: the source is asked (`ScreenView.rate`) for
  85% of what went through in the last second, never less than half of what it was asked before (`CUT`) nor 300
  kbit/s, again each round trip and 200 ms it stays. Only frames held back lower it: an acknowledgement late alone (a
  still screen's large picture, a screen that changes little, a packet lost and sent again, which holds the frames
  behind it for about a round trip and then they all come) lowers nothing, as what went through then says nothing of
  the link. Once nothing was held back for 1 s it goes up by 15% each 0.5 s, to the most the view is asked at
  (`rateCeiling`): the source's own (`ownRate`: the picture's pixels × 3 a second, at least 1 Mbit/s), or by the 画质
  the view asked, 原画 its pixels × 8 and 高清 × 4 (at least its own, at most 60 Mbit/s: 1080p 16.6 and 8.3 Mbit/s,
  4K 60): a desktop's text at its own rate stayed soft on a LAN even at 原画. So a slow link gets as many frames,
  smaller, rather than fewer and late.
  A frame's round trip and the oldest's wait are counted without the moments the station's own loop stood still
  (screen-pace.ts `LoopStall`: a 10 ms tick, how late it came): a Mac host's loop stood still 40–140 ms every few
  seconds (2026-10-29, busy with searches asked again and again) on a LAN of 4 ms with nothing lost, its
  acknowledgements read that late were taken for frames held back by the link, and the rate went down to what the
  source made (a screen changing little makes little), to 300 kbit/s and the picture to 720p. A frame held at the
  client (decoded slowly) or on the link (a queue, a packet lost) is held as before.
- **Frame rate.** A view that asked a 帧率 (`fps`) gets no more frames than that: each frame takes the next slot of
  1000/fps ms, one that went up to half a slot late letting the next come that much sooner (`Pacer.wait`), so no
  second carries more than fps + 1 and a source that captures at that very rate (and is a little early or late) keeps
  all of its frames; the pace waits for the slot before it asks the source for the next. The source is opened with it
  too (`ViewOptions.fps`): still.fail Helper's ScreenCaptureKit captures no more often (`minimumFrameInterval`);
  stillfail-screen's capture is asked no more often (`MinUpdateInterval`, Windows 11 24H2 on; before, the pace holds
  the rest back) and it pushes none sooner than its slot (native/screen/src/pace.rs). The encoders are set for that
  many a second but never more than 60 (VideoToolbox's `ExpectedFrameRate`; stillfail-screen's frame rate, GOP and
  each picture's duration, `encoder_fps`; 自动: 60, as before): asked 120, a 4K desktop on NVENC encoded ~55 a second,
  and an encoder set for 120 sized each picture for 120 and sent half the bits (1.6 MB/s against 3.3 at 30). Key
  frames come at least every 10 s by the clock (VideoToolbox's `MaxKeyFrameIntervalDuration`; stillfail-screen asks
  one 10 s after the last, `KeyClock`), not every so many pictures. 90 and 120 come only where the display draws that
  many (a 60 Hz display gives 60). A browser tab's and a simulator's frames are held to it by the pace alone. The bit
  rate stays a rate: fewer frames a second, each of them larger.
- **Start.** A view opens at 1.5 Mbit/s (`ViewOptions.bitrate`, the helper's `bitrate`) and goes up by half each 0.5 s
  until it is first lowered: its first frame is a whole picture, its largest, and one at the source's own rate held a
  1 Mbit/s link up for a second. Rate is lowered only once 0.5 s of acknowledgements say what went through.
- **Size.** Unless the view asked 原画 (whose picture is never made smaller): while the rate stays at a quarter or less
  of what the picture's size is encoded at for 3 s, the source is
  asked for a picture fitted into 1280×720 (`ScreenView.bounds`; the helper's message 8): fewer pixels, each sharper,
  where a 1080p picture at a few hundred kbit/s blurs its text. Once the smaller picture's rate stays at its own for
  3 s, the view's own size again. Each change is a config and a key frame, as any change of size is. The desktop's helper changes its encoder's average bit rate from the
  next frame (macOS: VideoToolbox's `AverageBitRate`; Windows: the encoder's `CODECAPI_AVEncCommonMeanBitRate`); a
  browser tab's JPEGs keep theirs. NVIDIA's encoders (both codecs) take that value without heeding it, keeping the rate
  they started at: theirs is started anew at the rate asked (its output type set again with it, under a millisecond,
  the next frame a key frame with the same parameter sets) once the rate asked is 0.8 of it or less and a second went
  since it last started, 1.5 times it or more and a second went, or differs by 5 % with a key frame going anyway
  (stillfail-screen's pace.rs `restarts`).
- **Regions.** A client that zooms the picture in (two fingers on a phone) shows a part of the screen as large as its
  stage: a whole 1920×1080 picture enlarged five times there blurs its text. It says the part it shows (`look`,
  0..1 of the screen, and the device pixels it is shown in) once it has stayed 200 ms (the core's `LOOK_MS`: a pinch
  or a pan asks once, as it settles), and the station asks the source (`ScreenView.bounds` with a region, the helper's
  message 8 with `region`) for that part alone, fitted into those pixels (no larger than the view asked for the
  whole, nor than the screen's own pixels there: never enlarged); the Sizer goes on as before, its smaller bounds within
  the part's. The source frames it from the next picture on (the screen still or not), as a key frame after a config
  whose `region` says the part as it was cut (on even pixels: what 4:2:0 crops at); the helpers say it before that
  frame (message 7 out). Zoomed out, `look` with no region, and the whole at the view's own bounds. Input and the
  pointer stay 0..1 of the whole screen, so a click lands where it is whatever part the frames show and while they
  change. The client draws a part's frames on a decoder of their own, over the whole screen's last picture where the
  part is, and only while its picture is newer than the whole's: a new part shows once its first frame has come (the
  part before stays till then), and zoomed out, the part stays till the whole's first frame has; panned past the part,
  the whole's last picture shows round it till the new part comes. still.fail Helper captures the whole display at as
  many pixels as the part needs (ScreenCaptureKit, at most its own) and cuts the part from each picture it encodes
  (VTPixelTransferSession); a simulator's part is cut from its framebuffer as it is scaled; stillfail-screen's video
  processor scales the part alone (its source rectangle). A source that frames no parts (a tab of the browser:
  Chrome's screencast; a helper from before them, whose info does not say `regions: true`) is not asked, and its
  frames stay whole, which the client draws as it did; so does a station from before `look`. The core asks a stream
  opened again for the part at once.
- **Still.** A source makes a picture only when the screen changed, so a still screen shows its last frame's picture as
  it was encoded: a view's first at the start rate, a whole desktop in a few kilobytes, stayed a blur for as long as
  nothing on it moved (a Mac's desktop left alone, for minutes). Once no frame has gone for 0.5 s (`STILL_MS`) and the
  rate asked has gone up past 1.1 times the one the last frame was encoded at, the source is asked for a key frame
  (`ScreenView.keyframe`: the helper encodes the same picture again, at the rate asked now); its acknowledgement lets
  the rate go up a step, and so on to the source's own (screen-pace.ts `Sharpener`): the picture sharp a few steps after
  the screen stopped, as a still image is refined. A screen that keeps changing never waits that long; a link that
  cannot carry the larger picture lowers the rate, and nothing more is sent. A source with no rate of its own (a tab's
  JPEGs, each as sharp as the next) is not asked. The desktop's helpers encode such a picture (a key frame asked while
  the screen did not change) finer than the moving ones where the rate asked is 4 Mbit/s or more: its QP at most 28 and
  twice the bit rate for that frame (macOS: VideoToolbox's `MaxAllowedFrameQP`, the next moving picture as before, so
  moving frames keep their latency; Windows: `CODECAPI_AVEncVideoMaxQP` where the encoder takes it, set on another
  encoder of the same kind made for that picture, as one that started takes it without heeding it, NVIDIA's at least;
  the next moving picture is then a key frame of the view's encoder).
- **H.265** where both ends have it: a Mac's hardware encoder (VideoToolbox), a Windows machine's hardware HEVC MFT
  (Main; stillfail-screen builds the hvcC from the stream's VPS, SPS and PPS), decoded by WebCodecs on the web, and in
  the app by VideoToolbox on macOS and iOS where the hardware decodes it (`@ui.h265_here`; the app asks `h265` first
  there, its hvcC made a format with CMVideoFormatDescriptionCreateFromHEVCParameterSets), and on Windows where the GPU
  decodes HEVC Main through the system's decoder (Windows' HEVC Video Extensions: win_stream.cpp, its hvcC's parameter
  sets put before each key frame). The app elsewhere (Android, Linux, the browser) asks H.264. The station picks H.265 whenever the codecs asked include it. A web client
  whose decoder fails on it before its first frame opens the view again asking H.264 (for as long as the page runs).
- **The link.** The mesh's QUIC uses Cubic (station/native/mesh), which halves what goes at each loss: at 1% loss and
  40 ms, a screen falls to 24 frames a second and a file to 2.8 Mbit/s (noq's BBR measured there: 52, 31 Mbit/s). BBR
  was used from #1203 until 2026-10-28, when on real ways with nothing lost it held what went to a device at 20–30
  KB/s for hours (a 17 KB window at 80 ms) where Cubic sent 2–4 MB/s.
  Station settings keep an **Advanced network settings** fold at the bottom. Its congestion controller defaults to
  CUBIC; managers can opt into experimental BBR. The saved `network.congestion` (`cubic` or `bbr`) is taken by the
  running endpoint as saved (mesh.ts `applyNetwork`, iroh's `set_transport_config`) for the connections made from then
  on; a connection made keeps its own, so saving does not interrupt existing transfers. BBR in noq 1.3.0 has the idle/app-limited bandwidth
  estimation defect tracked in n0-computer/noq#852, so it stays opt-in. This changes the station's sender only.
  A **Relay over UDP** switch beside it (2026-10-29/30) had the station's datagrams go over its relays' UDP way
  instead of their WebSocket; taken out again. Over the WebSocket each leg to the relay is TCP of its own, under
  QUIC's recovery. Measured through a local relay (20 ms a leg, 50 Mbit/s, relay only, 2026-10-29): with 0.5% random
  loss a leg, a file went at 20 Mbit/s over UDP with BBR (4.8 over the WebSocket with Cubic) and 60 fps of 20 KB
  frames came in 60 ms at p50 (1.5 s); with Cubic, UDP was slower there than the WebSocket (its two TCP legs each
  recover at half the round trip), and faster with loss only from a narrow link (20 Mbit/s: a file 13–14 against 10
  Mbit/s, frames p99 58 ms against 83–595 ms). Not measured on real ways; some networks drop UDP 443 altogether.


`station/side/screen-net.ts` measures it: a view over iroh through a proxy on this machine that delays, drops and
limits the packets (a LAN, 40 ms, 150 ms, with loss, with a narrow link), the frames from a source of an encoder's
sizes or (`SOURCE=helper`) still.fail Helper's made-up pictures encoded on the Mac's hardware; it says the frames a
second drawn, how late (capture to drawn), the stalls over 200 ms and the bit rate that came.

### The desktop (station/src/screens/desktop.ts, station/native/helper; Windows: win-desktop.ts, station/native/screen)

macOS and Windows (elsewhere it is listed with `access` saying it is not supported, and opens nothing). On macOS still.fail Helper
(`still.fail Helper.app`, bundle id `fail.still.helper`, beside `mesh.node` in the release; docs/station-ts-native.md
§4) does it: ScreenCaptureKit captures the main display scaled into `maxWidth`×`maxHeight`; VideoToolbox encodes on the
hardware encoder with low-latency rate control, H.265 (Main, the hvcC as `description`) when the client takes it and the
Mac has the encoder (the helper's `info` says which: a helper from before H.265 says nothing and makes H.264), else
H.264 (constrained baseline, the avcC as `description`), no reordering, at the bit rate the pace asks; a picture only when one is asked for and the screen changed (a still screen sends nothing), a key frame
on request; CGEvent posts the input (mouse with click counts, wheel in pixels, keys by their `code` as the Mac's virtual
keys, text as Unicode). A view is a connection to the helper's socket. A display asleep is captured black but for the
cursor: opening a view wakes it (as a person touching the Mac does) and keeps it on until the view ends (an IOKit
assertion), after which it sleeps as the Mac's settings say.

Screen Recording and Accessibility are granted to the helper app, not to the station: LaunchServices starts it as its
own process, and a grant, which takes effect only once the process holding it starts again, restarts the helper alone
(the station and its sessions run on; a view open then ends and the client opens it again). Opening the desktop while a
grant is missing puts the helper's window up on that Mac (as Cue's Computer Use has it, with PermissionFlow): a row per
grant, Allow opens the System Settings pane with a panel holding the app to drag into its list. The 503 and the list's
`access` say what is missing and that the window is up (`asking`), or that opening the screen puts it up. The system's
own prompt is not used (it would fight the window).

On Windows stillfail-screen (`stillfail-screen.exe`, beside `mesh.node` in the release; docs/station-ts-native.md §5)
does it, with nothing to grant: the station runs in its person's session (the logon task), where the display can be
captured and driven. A view is a process of its own (`stillfail-screen view`, the helper's messages on its standard
input and output, ended as its input is). One that ends by itself (the display went or another became the main one, the
graphics driver started again, a crash) is started again and the view goes on from a key frame with its config; past
three times a minute the view ends. Windows.Graphics.Capture captures the main display (the cursor left out of a video, drawn in a JPEG; no
yellow border on Windows 11; a picture where nothing changed, by its dirty regions on 11 24H2 on, is not a new one); the
GPU's video processor scales it into `maxWidth`×`maxHeight` as NV12; Media Foundation encodes H.265 (when the client takes it and the
hardware has an HEVC encoder) or H.264 on the hardware encoder (its MFT given the D3D11 textures; Microsoft's software
encoder where there is none) with low latency
(constrained baseline, no B-frames, the parameter sets taken out of band into the avcC), a key frame on request; a view
without H.264 gets WIC's JPEGs. SendInput posts the input: the pointer in the virtual desktop's absolute units, a page's
wheel pixels as Windows' units (120 a notch, about a page's 100 pixels), keys by their `code` as the key's scan code
(station/src/screens/win-input.ts; Windows counts double clicks and keeps the modifiers itself, and a key that comes with
modifiers not pressed before it, as a phone's keys row sends it, has them pressed round it; the Meta key is the Windows
key), text as Unicode. Opening a view wakes a display gone to sleep (a pointer nudge) and keeps it on while it is open
(`SetThreadExecutionState`). What Windows keeps from any app in the session is not had: the sign-in and UAC's secure
desktop are not captured, and windows of apps run as administrator take no input.

The display's scale (Settings › Display › Scale) is a person's to change from the view, as UU Remote has it: on a phone
the desktop's windows and text are made larger, readable at the phone's size. `stillfail-screen scale [percent]` reads
the main display's (`{percent, recommended, steps}`) and sets it as Settings does (DisplayConfigSetDeviceInfo's DPI
scale, relative to the recommended step; it takes at once, nobody signed out). The station tells a view that drives it
the scale as it opens, sets it as asked (`{t:"scale", percent}`), and, once the last view of the desktop ended, puts it
back as it was before the first change, so the machine is not left at a phone's scale. The clients offer it while
driving: 控制中心 › 缩放 with a mouse, a button in the foot (and 全屏's tools) on a phone.

Its resolution (Settings › Display › Display resolution) is too, as UU Remote's 分辨率: a mode nearer the phone's shape
fills its screen with less of it left black. `stillfail-screen resolution [WxH]` reads the main display's
(`{width, height, modes: [{width, height}…]}`: the sizes its adapter lists at its colour depth, landscape, at least 800
wide, the largest first) and sets one (ChangeDisplaySettingsExW, its refresh rate kept where the size has it; for now, not
written to the registry, so a station gone before putting it back leaves nothing past the session). The station tells a
view that drives it the resolution as it opens, sets it as asked (`{t:"resolution", width, height}`), says the desktop
changed (its size another), and puts it back as it was once the last view ended. The app offers it in 控制中心 ›
分辨率, the mode nearest the shape it shows the screen in said as 推荐.

The same app opens the drive's folders macOS protects (`files.*`, docs/drive.md): its window then shows only the rows
asked for (`permissions.show {grants}`), a folder's row asking macOS's own prompt (the only way a folder is granted).

### Simulators (station/src/screens/simulator.ts, sim-input.ts; native/helper's SimulatorView.swift)

Each iOS Simulator booted on a Mac station is a screen, `simulator:<udid>`, titled with its device and runtime ("iPhone
17 · iOS 26.2") and sized as its device type's screen (its `capabilities.plist`), for people to see and use the app they
are building and for agents to drive it with the `computer` tool. Which are booted is `simctl list`'s (CoreSimulator's
own simctl, not `xcrun simctl`: Xcode's is a script that, where CoreSimulator is older than the Xcode, first runs
`xcodebuild -runFirstLaunch`, which asks for an administrator's password in a window of macOS's, again each look),
looked at again when CoreSimulator rewrites a device's `device.plist` (as it boots and shuts down: the station watches
each device's folder, not what is below it, which a running device writes all the time) and as the screens are asked
for; a device that shuts down leaves the list and its views end. A Mac without Xcode lists none.

still.fail Helper does it (`simulator.view {udid, codec, maxWidth, maxHeight, bitrate?}`), with serve-sim's capture and
input (vendor/serve-sim): the device's framebuffer read through CoreSimulator's IOSurface as it changes, each picture
scaled into the view's bounds (VTPixelTransferSession) and encoded as the desktop's are (ScreenView.swift's encoders
and messages: H.265/H.264 on the hardware encoder, or a JPEG a picture; a still screen sends nothing); the input goes
to the device through SimulatorKit's HID client. Nothing of macOS's is granted for it and Simulator.app need not run;
the view's statistics name its capture `CoreSimulator`. A Mac that is itself a virtual machine has no working
hardware encoder for any view (the desktop's neither): JPEG views work there.

The device is a touchscreen (sim-input.ts): the left button held is a finger (one going down within the bottom 3% or
the top 2% of the screen is a system gesture: the home indicator's swipe, the pull down), a wheel a finger dragging,
a key its USB HID usage by its `code` (modifiers only named in `mods`, as a phone's keys row sends them, pressed round
it), typed text a US keyboard's keys and anything else pasted (the device's pasteboard set with `simctl pbcopy`, then
⌘V). Simulator.app's shortcuts press its buttons: ⌘⇧H home, ⌃⌘⇧H the app switcher, ⌘L lock, ⌘K the software
keyboard. The web viewer has them as buttons too (a column beside the device with a mouse, a row over the foot on a
phone), and one more that saves the picture shown as a PNG (as large as the view is, not the device's own pixels).
The device is not turned: SimulatorKit takes an orientation only through Simulator.app. The web client touches
a simulator directly on a phone (no trackpad to choose), a finger held being the device's long press; the mbui app
drives it as any screen for now (its 触控板 switched off for direct touch). No clipboard,
cursor or dropped files yet. `station/side/screen-simulator.test.ts` makes and boots a simulator of its own, views it
through the real helper and says how soon a picture follows a finger and the frames a second.

### Grants (station/src/helper/grants.ts, api/routes/permissions.ts)

What macOS lets the helper do is one look the station keeps (the helper's `status`), shared by the desktop's screen, the
drive, the station's page and the agents: fresh where it matters (a view opened, a grant asked for), looked at again
when the helper says a grant changed (its window sees each change while it is up) or comes back, and in the background
once a page reads it 30 s after the last look. The window too is one: it is put up for a grant once, not again (nor
brought forward) while it is up asking for it, nor for 3 minutes after it was shown for it when an agent or the drive
asks; a person's own ask (the station's page) puts it up again however lately it was shown.

- The overview (`GET /overview`) carries `permissions` on a Mac's station: `{grants: [{grant, state}], asking, screen,
  request}`, the grants in order (`capture`, `control`, `documents`, `desktop`, `downloads`, `removable`, `network`;
  state `granted`, `denied` (a folder refused before), `unknown` (not granted)), those the window asks for now,
  whether the screen can be seen and driven (Screen Recording and Accessibility both), and whether the viewer may ask
  (not a read-only member). It is told again (`overview`) as they change. Elsewhere, and on a station from before them,
  there is none: clients show nothing.
- `POST /permissions/request {grant}` puts the window up for that grant on the Mac (a folder's Allow then asks macOS's
  own prompt; a disk's needs one of its kind mounted, which macOS asks about) and answers `{window: "up"|"granted",
  screen}`, however lately it was shown (a client's retry is answered once, by its idempotency key); refused in the
  asker's words: 409 no disk of its kind, 503 not shown, 400 no such
  grant; a read-only member's 403. With `screen`, the client opens the desktop (`screen/desktop`, the viewer as a link
  opens it: driving it unless someone else does), so the person clicks in the window and System Settings from wherever
  they are; without, it says to go to that Mac and click Allow there, the grants on the page changing as they do.
- The agents' `permissions` tool lists them and, with `request`, puts the window up for one and says what to post with
  need_human: the desktop's link when the screen can be driven, else to go to the Mac.
- `localNetwork`, last, is the station's own, not the helper's: macOS's Local Network for the app the station runs in
  (the desktop app, or the launcher under launchd), told as `localNetworkName`. The station sends a byte to the first
  address of each LAN it is on (mesh/lan.ts `lanReach`): not let, macOS refuses it at once ("No route to host"), and
  devices on that LAN reach the station only past a router or a relay (a firewall refusing the LAN is told the same).
  Listed only while the station is on a LAN. No window asks for it (macOS asks once, as the app first reaches the LAN):
  asked for, System Settings' Local Network list comes up on the Mac, as rarely as the window does; it takes once the
  app starts again.

### Filling a login

> chat EMBER/1793439516.811000 (2026-10-31): the person's own 1Password, on their device, fills a page of the
> station's browser they drive, as it would one of their own browser's.

While a person drives a tab of the browser, its view hears the login field the page's focus is in: a hook in the
tab's top document (`LOGIN_HOOK`, a binding of the view's session, as the clipboard's: browser/view.ts) says which kind
of field it is (a password field; an account's: marked `autocomplete` username or email, or a text field of a form with
a password field, or named so), and the station adds the tab's host as the browser has its address (`Target.
getTargetInfo`: never what the page says, which may call the binding as it likes), told as the view's state `login`.
The person's app asks their password manager for that site's logins (mbui hostapi passwords.mbt: 1Password's
command-line tool `op`, signed in through its desktop app, which asks them itself; macOS and Windows), they pick one
where there are more, and its account and password come back as an input `{t: "fill", host, …}`. The station fills the
form only while the tab is still on that host: in a world of the page's top frame of its own (`Page.createIsolatedWorld`,
so the page's scripts do not change how it goes), each field's value set as its own setter does and `input` and `change`
told, as typing leaves them. Nothing of it is logged; an agent's view of the tab (the `computer` tool) hears no login.

Android has no such tool: there the system's autofill service is asked (2026-11-01; mbui hostapi autofill.mbt,
dev.mbui.Autofills), as a browser asks it for its pages. While the app asks, its view says it holds a login form of
that site (an account's field and a password's, virtual, under the tab's host as their web domain), and the request is
the person's (`AutofillManager.requestAutofill`, on 填入): the service (1Password, Google's, whichever they chose in
the system's settings) offers its logins for the site itself, and the one they pick, filled into that form, goes to the
station as above. The session is cancelled once it came, so nothing is offered to be saved. A service may trust a web
domain only from browsers it knows; one that does not offers nothing for it.

### Signing in with a passkey

> chat EMBER/1793439516.811000 (2026-11-01): a site that signs in with a passkey takes one of the person's own, on
> their device, as their own browser would; Windows first.

While a person drives a tab of the browser, a hook in the tab's top document, run before the page's own scripts
(`PASSKEY_HOOK`, a binding of the view's session: browser/view.ts), takes the page's `navigator.credentials.get` with
`publicKey` and tells the platform has an authenticator (`isUserVerifyingPlatformAuthenticatorAvailable`,
`isConditionalMediationAvailable`), so that sites offer passkeys. What it asks (the relying party, the challenge, the
passkeys it takes, the verification) the station checks against the tab's address as the browser has it: a secure
origin (https, or this machine's own), and a relying party that is the host or a domain of more than one label it is
under (`rpFor`); else the page is answered `NotAllowedError` at once. The station makes the client data itself
(`{type: "webauthn.get", challenge, origin, crossOrigin: false}`, the origin the tab's), and says it, with the site,
as the view's state `passkey` (`{id, host, rpId, clientData, allow, userVerification}`, null as it goes: answered, the
page's signal, the page left). One is asked at a time: a later ask answers the one before it as given up.

The person's app (mbui hostapi passkeys.mbt) offers 用通行密钥登录 with the site; pressed, the device signs the client
data as it is for the relying party: on Windows its WebAuthn API (webauthn.dll's `WebAuthNAuthenticatorGetAssertion`,
which asks the person itself with Windows Hello, a phone, a security key or a passkey provider such as 1Password, in
its own window over the app's). What it signed comes back as an input `{t: "passkey", id, credential,
authenticatorData, signature, userHandle?}` (base64url), and a no as `{t: "passkey", id, error: "NotAllowedError"}`.
The station answers the page only the ask said last, only while the tab is still on the origin it was asked on, with a
credential made as the browser makes one (its prototype `PublicKeyCredential`'s, `rawId`, `response`'s
`clientDataJSON` the station's own as it was signed, `toJSON`). Making a passkey (`navigator.credentials.create`) goes
to the browser as before.

On macOS (14 and later) the app asks as a browser does (AuthenticationServices: `ASAuthorizationWebBrowserPublicKeyCredentialManager`,
a platform passkey's and a security key's assertion with `ASPublicKeyCredentialClientData`), which macOS lets only an
app entitled `com.apple.developer.web-browser.public-key-credential` do (Apple grants it on a request of the developer
account's holder, "macOS Browsers Passkeys"): until the app's signature carries it, `passkeys` is false and nothing is
offered. macOS writes the client data itself of the challenge and origin given, so its own comes back with the
signature (`clientData`), and the station answers the page with it only where it says the same type, challenge and
origin as the station's (`sameClientData`).

### Clipboard and files

While a person drives a screen, its clipboard goes both ways. The desktop: the helper sets NSPasteboard (text, or PNG
with a TIFF beside it; on Windows the clipboard, text or PNG with a bitmap beside it, opened again for a moment while
another app holds it) and, to paste, posts ⌘V (Ctrl+V) after the input before it; while a view that drives it is open it looks
at NSPasteboard's changeCount (the clipboard's sequence number) every half a second (nothing else is read until it changes, and what the view set is not
said back) and sends what was copied: text first, else a picture as PNG; what is past its bound is not sent. A tab of
the station's browser: text only. The view's own CDP session adds a binding (`Runtime.addBinding`, no `Runtime.enable`)
and a script that calls it with what the page copies (a copy or cut, as the page set it or as it was selected;
`navigator.clipboard.writeText`), both taken away as the view ends (Chrome then stops telling of the binding; a page
open then keeps the function until it loads again); a paste is `Input.insertText` where the focus is.

The clients carry the types the view's state names (`clipboard`; none from a station or helper before them, so nothing
of another type is offered or sent): a copy made on the screen goes onto the device's clipboard, and their paste sets
the screen's and pastes it there. The web: as the browser lets it (web/src/screen/Transfer.tsx). Android
(remote/ScreenClips.kt): text, or a picture as a PNG file in its cache the clip points at (`image/png`, through its
FileProvider; the newest three kept); Android 13 and later show their own preview of it, before that the viewer says
so. Its 粘贴 sends the phone's picture where the screen carries pictures (a PNG as it is, another kind converted; past
8 MB it says so and sends nothing), else its text.

A file dropped into the view (the web) or picked (Android) goes up with the drive's upload (`drive.upload.part`, root
the screen's `drop.folder`, a free name beside one already there) while its progress shows; once there the page says
where it is, offers to show it in the machine's file manager (`reveal`) and to paste its path (`clipboard` with paste).
The folder is the machine's Downloads, where files from elsewhere land (a browser's, AirDrop's) and file dialogs look
first; the home where there is none (drive/drive.ts `dropFolder`). Only the folder's entry is looked at to say so,
never what is in it: on macOS listing a protected folder can put a privacy prompt up and hold the station until it is
answered. A station macOS keeps from Downloads is refused as any upload there is (`permission`, said on the file's
row) until the drive reaches protected folders through still.fail Helper.

### Clients

The core (client/core-ts/src/screens.ts; docs/client-core.md, the `screens` topic and the `screen.*` calls) holds each
station's list (read as its stream opens, then its `screens` events; kept with the station's documents, station/memory.ts) and opens views. A view's frames
go to the page as they come, their bytes beside the JSON rather than in it (the web's worker transfers them; in the apps,
apps/mbui, the engine hands them to the host beside the message, a tapped screen's straight from the shell to its
decoder); the
page decodes (WebCodecs or `createImageBitmap` on the web, which asks H.265 where WebCodecs plays it; the app's host
decoders, which ask H.265 where the host decodes it: VideoToolbox on macOS and iOS) and acknowledges each frame it drew. What the page draws of the view (its phase, 只看/控制, who else is on it) the core says whole as it
changes; it opens the view again when the link drops or 只看/控制 changes. Opened with no `control` asked (a link, the
station's page), it only looks while someone other than the viewer drives the screen (an agent at work, another
person); the viewer's own views, however many the list names (another window, or those an app killed with the view
open left), are not someone else. A station from before screens answers `GET /screens` 404: its list is empty and says
it needs an update, and a link to one of its screens says so without opening a stream (such a station would take the
stream for a request and wait for a body).

The screen's pointer is one: the desktop's video leaves it out and the station says where it is (`cursor`). The page
draws it, an arrow as large as a pointer on the screen looks at the picture's size (a 90th of its width, 10 to 18 px),
except while this device's own mouse is over the picture and drives it: then that mouse is the pointer, shown in the
screen's shape (a text cursor over text), and nothing is drawn. Hidden on the screen (`none`), neither is. The app
(apps/mbui, `@sf.pointer_image`) draws its pointer at its own size in the screen's shape too, as a Mac draws each (the
arrow, a text cursor, a hand, the resizing arrows, a cross, a hand grabbing, not allowed, waiting), the point each points
with where the station says. Where the picture shows on a system video layer (macOS, iOS: @hostapi.stream_layers), the app's pointer is a
sublayer of it drawn by the host (@hostapi.stream_pointer), composited with the picture: the station's pointer moving
alone is taken as it comes and told the host, nothing of the app built or drawn for it.

On a phone (Android, the phone web) a finger drives a screen as a trackpad unless the device keeps `direct`
(`prefs.screenTouch`, switched on the viewer's foot): one finger moves the pointer (relative, faster strokes further:
`padGain`), a tap clicks where it points, tapped again and moved (or held) it drags, two fingers tapped right-click, two
moving together scroll. The page draws its own pointer while the finger moves it and takes the station's `cursor` again
once the finger has been still 600 ms. Directly, a tap clicks where it is, a press held right-clicks, a drag drags. Either
way two fingers spreading zoom the picture (the zoom never sent as input); zoomed, the trackpad's pointer is kept in sight,
and the station sends the part in sight alone, as sharp as the phone shows it (Pace, "Regions").
A keys row under the picture while driving has the mouse's two buttons first (左键, 右键: a click where the pointer is,
the trackpad's or else the screen's own), sends what a phone's keyboard lacks (Esc, Tab, the arrows) and holds ⌘ ⌃ ⌥ ⇧
for the next key or click, typed or tapped (⌘ then c: `{t:"key", code:"KeyC", mods:4}`; ⌘ then 左键: ⌘'s key down
round the click). Where the row is not there (全屏 and sideways, the keyboard down) the two buttons stay in sight while
driving, side by side as a mouse has them over the frame's foot corner (全屏 and sideways), each a round button
floating on its own, the two dragged anywhere together by either as the folded tools are (back to their corner once
the window turns). 控制中心's 鼠标左右键 hides them all, the keys row's too
(`prefs.screenMouse`: `off`). Each is felt as it goes down (a haptic: the right button as a context click), as a click
made by a tap is; a press on them, as on anything over the stage, is theirs alone: the stage's gestures never see it. On Android a stage made shorter by the
keyboard keeps the picture as large as it was, the pointer in sight (`ViewZoom.refit`), rather than fitting it smaller. 全屏 puts
the screen alone on the phone: Android hides the system bars, turns sideways and draws it edge to edge; the phone web
asks the browser's full screen and, where it lets a page, to turn sideways. The tools fold into one button over the
corner (the letterbox, for a screen wider than the phone).

With a mouse (the desktop app, the web on a computer) the viewer's bar is always there and the picture is fitted below
it, so the top of the screen (its windows' title bars) is never under it. Its line says 只看/控制 and who else is on it.
Beside 只看/控制 (web/src/screen/ScreenPanel.tsx), as a remote desktop's window has them: a signal mark with this
device's round trip to the station (the `stationNet` view, in its colour), which opens the view's figures (frames and
bits a second as they came, packets lost, the way, the picture's size and codec, what captures it and whether it is encoded on the hardware); and 控制中心, a menu: 画质, the
picture's bounds this device asks for (`prefs.screenQuality`: 自动 as the window is in device pixels, the web at most 1920×1080 or 2560×1440, the mbui
app as large as its stage has been, asked again as it grows a tenth a side; 流畅 1280×720, 高清 1920×1080, 原画
the screen's own size; said to the station as `quality` too, 高清 and 原画 letting the bit rate go higher; another opens
the view again), 帧率 (`prefs.screenFps`: 自动 as many as the station and the link give, or at most 120, 90, 60, 30 or
15 a second, said to the station as `fps`; another opens the view again, `screen.bounds` saying it with the 画质), 组合键 while driving (the keys this device's system keeps for
itself, as the station's system names them: ⌘Tab, Alt+Tab, the Windows key…, each a key with its `mods`; Ctrl+Alt+Del
cannot be sent, Windows keeps it from any app), 常用键 while driving in the mbui app (F1–F12, Del, Home, End, PgUp,
PgDn, with the modifiers the keys row holds; 控制中心 stays open for the next), sending files, a window of its own, 全屏 and 断开. 在新窗口打开 moves the view to a window of its own (`?window`: back closes it).

The mbui app goes by its native input (apps/mbui/docs/architecture.md, `@sf.soft_keyboard()`): with touch as Android
above, with keyboard and mouse as the web on a computer (apps/mbui/src/sfapp/screen_view.mbt): the library's viewer bar
across the window's top (clear of the window's buttons, dragging the window; back, the name and the core's line, the
signal mark and how long, 控制中心, 只看/控制), the picture under it, no trackpad, keyboard button or keys row. The mouse is
the screen's pointer where it is: its moves over the picture, its primary button down, moved and up (a press began on
the picture held past its edge at its edge), its secondary button a right click, its wheel in pixels (a trackpad's pinch
not sent), with ⇧ ⌃ ⌥ ⌘ held as a button goes down their keys sent round it (a key catcher never hears a modifier
alone); a press on the stage gives it the keyboard (a key catcher: words as text, keys with modifiers as keys), ⌘V
(Ctrl+V) pastes this device's clipboard there where the screen carries one, and over the picture the station's pointer
is not drawn, the mouse's own taking its shape. 全屏 fills the screen with the window, the bar kept, and closing the
screen puts the window back.

### Asking a person to take over

The agents' `screen` tool lists the station's screens and gives a link to one: `<cloud>/w/<workspace>/s/<station>/screen/<id>`.
The agent posts it with `chat_post` (need_human: "log in here", "solve the captcha") and ends its turn; clients open
the link in their screen viewer (web: a page; Android: a full-screen activity; in a chat, `link.parse` → `screen`).

In a message the link alone on its line is the screen's card (the core's `screenCard` topic: its title and line from
the list, `gone` once the list has it no more); within a sentence, its title. A screen the list says `peek` shows live
in its card: a preview view (JPEG, about the card's width in device pixels) while the card is on the screen and the
app shown, each frame acknowledged half a second after the one before, so about two pictures a second; its mark until
the first comes.

On a chat's page (web: pages/ChatPage.tsx) a card not `gone` also opens its screen beside the chat, from a button at
the end of its words: a tab of the side panel (`screen:["<station>","<id>"]`, client/core-ts/src/chat-tabs.ts), named
as the card is, its viewer's bar only 只看/控制 and its tools, and a way to the screen's own page. Its view is open
while its tab is in front, so someone debugging an app sees and drives its simulator while the chat goes on.

### A chat's screens

A chat reaches the screens of the station it runs on in one press, without an agent posting a link to one. The core puts
them in the chat's view (`ChatView.screens`, client/core-ts/src/views/views.ts: built from the `screens` topic it
watches for the chat), each with `agent` while an agent drives it; the station's own display (`desktop`) comes first
in every list of its screens. A station with none to show (offline, before screens, no display) gives none, and
nothing shows. Clients:

- The chat's bar (web: pages/ChatPage.tsx `ScreensButton`; the app's wide frame: sfdesk/chat_page.mbt
  `screen_trigger`) has a screen button beside its services': the one screen alone opens beside the chat (its tab, as
  a card's does), more a menu of them. A dot on it while an agent drives one.
- An agent's card (web: mobile/AgentSheet.tsx; the app: sfapp/sheets.mbt), under its station, has a 屏幕 row: the
  display's name, or that an agent drives one; it opens the same way (the screen's page over the chat on 小屏).
- `chat.screen` (⌘⇧D, ⌘K, the Mac's menu bar) opens the first, its display.

The display has no live picture there: a preview of it would wake the machine's display (`peek` is a tab's or a
simulator's only, above).

### Agents on a screen (station/src/tools/computer.ts)

The agents' `computer` tool operates a screen the way a person's view does, on the same contract: `screenshot`, then
`click`/`move`/`drag`/`scroll`/`type`/`key` (and `wait`), with a fresh screenshot after each action unless
`screenshot: false` (`wait` ms first, 500 by default). A session keeps one view per screen open while it uses it
(`codecs: ["jpeg"]`, scaled into 1280×1280), closed after 60 s unused or when its chat is archived; it joins the
screen's people as `agent: <chat title>` with control, so it is in `controlledBy` and a person watching sees it work.
The screenshot is the newest frame the view had (a source sends one only when the screen changed), given as MCP image
content with its size and its scale to the source's; coordinates are the screenshot's pixels, sent as 0..1. A click
is move, down, up (twice for a double click); a drag is move, down, 8 moves held, up; a key combination (`cmd+c`) is
the modifiers down, the key down and up, the modifiers up; text goes as `text`, a newline as Enter. While a person
(any view in `controlledBy` that is not an agent's) drives the screen, the agent's input is refused with a message to
wait or ask; screenshots still work. A missing grant answers with the access message and the screen's link, for the
agent to post with need_human. Clients open a view with `control: false` while a person only watches, so the agent is
not held off by a watcher.

On the desktop an agent also reads an app's window as its accessibility tree and acts on its elements by ref, with
[agent-desktop](https://github.com/vercel-labs/agent-desktop) (screens/ui.ts; `ui` on the desktop's source). `tree`
with `app` answers the window as text, a line an element (`e12 button "Save" [disabled]`, indented by depth; `ref`
reads only the part under that element, `skeleton` only the outline, `window` one of several windows); `tree` without
`app` names the apps running in the foreground. `click` (left, right, double), `type`, `set` (the element's value
replaced with `text`; Windows refuses `type` by ref, which needs the focus there) and `scroll` (`dx`/`dy` in units of
100 px) take `ref`, an element of the session's latest tree
on that screen; `key` with `app` sends the keys to that app's process. These go through the accessibility API: no
picture is taken and no view opened, the pointer and the keyboard focus stay where they are, a window behind others
works, and a person driving the screen does not hold them off. Each answers with the app's tree read again (`wait` ms
later, 200 by default; `tree: false` not). agent-desktop's refusals (`STALE_REF`, `AMBIGUOUS_TARGET` with the windows
to choose from, …) reach the agent with its suggestion and whether trying again is safe. On macOS agent-desktop runs in
still.fail Helper (the `ui` op: Ui.swift runs the copy beside its executable), so it has the Helper's Accessibility
grant and needs no grant of its own; on Windows the station starts `agent-desktop.exe` from beside its code, in the
person's session. Elsewhere the desktop has no trees. station/test/ui-live.test.ts drives a real editor through the
tool with the real agent-desktop: Notepad on GitHub's Windows in the pipeline's `ui-windows` job, TextEdit on a Mac by
hand (`STILLFAIL_UI_LIVE=1`, `STILLFAIL_AGENT_DESKTOP`).

### System audio

Windows WASAPI shared loopback continuously drains the default output endpoint, retaining up to 300 ms of consecutive
20 ms packets. On macOS still.fail Helper captures it in the same ScreenCaptureKit stream as the picture
(`capturesAudio`, 48 kHz stereo, `excludesCurrentProcessAudio`, the microphone never: SystemAudio.swift), only for a
view opened with `audio: true` (the `screen.view` request; its info then says `audio: true`); Screen Recording, which
the view has already, is all it takes. Its float samples become interleaved PCM16 in exact 960-frame packets, each
stamped with its first frame's capture time (the clock the video's timestamps use), 300 ms kept as on Windows; sound
that does not follow on from the last (ScreenCaptureKit sends nothing while nothing plays) starts a packet of its own,
the part before it dropped. The helper's messages are stillfail-screen's: 9 in asks for a packet, 8 out says the format
(or an error: no more audio), 9 out is a packet. A helper from before it ignores `audio` and its info says none: no
audio is pulled. The station pulls one packet per completed transport write, independently of video
changes. PCM uses 1.536 Mbit/s before framing. Apple playback starts after a 60 ms jitter reserve and caps its queue at 300 ms and clears it on mute,
reconnect and close. Timestamps describe capture; playback currently starts on arrival rather than aligning
to the video presentation clock. Muting is local; capture and transport continue until the view closes.
