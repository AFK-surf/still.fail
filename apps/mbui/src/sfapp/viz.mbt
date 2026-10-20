// Visualizations (ember apps/android shared/ui/Viz.kt, chat/screens/VizFiles.kt, Prose.kt; web/src/Viz.tsx): an HTML
// file an agent placed in its message's text (`[title](figure.html)` on a line of its own), drawn there in a page's
// view (src/ui/native.mbt NativeView::page) instead of shown as a card, with ways under it to open it over the whole
// screen or as a page of its own (PreviewFile, service.mbt); a ```mermaid block drawn the same way, by mermaid (from
// the CDN the web loads it from), shown as code while it will not draw.
//
// The page is the web's: its stylesheet and bridge (web/src/viz, web_assets.mbt), the web's tokens for the theme shown
// (as --e-*), the same CSP (scripts and styles from a few public CDNs, no requests of its own). It is as tall as its
// content (the bridge says), keeps what the widget asks to keep (widget.setState, on the station, given back by
// widget.state as it loads), and puts what it asks to send (sendFollowUpMessage, on a tap) in the chat's composer for
// the person to send. What the bridge posts to its own window is relayed to the app (`mbuiHost.post`): none of it is
// trusted, a field that is not what it should be is let go.

///|
// kept across runs: a table, never written
let viz_zh : Map[String, String] = {
  "android-misc.viz.cantRead": "无法读取此文件",
  "android-misc.viz.cantSend": "此对话当前无法发送消息",
  "android-misc.viz.followupDrafted": "已添加到输入框，确认后发送",
  "android-misc.viz.fullscreen": "全屏",
  "android-misc.viz.mermaidFailed": "mermaid 加载失败",
  "android-misc.viz.openAside": "在侧边打开",
  "android-chat.preview.unreadable": "无法读取「{name}」",
  "common.opening": "正在打开",
}

///|
fn viz_tr(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = match viz_zh.get(key) {
    Some(w) => w
    None => tr(key)
  }
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// Past this the page scrolls within itself.
let viz_max_height : Int = 1200

///|
/// What a widget may keep, as Codex's Visualize allows.
let viz_max_state : Int = 16 * 1024

///|
/// The height a page that has not said its own takes (Viz.kt: 120).
let viz_first_height : Int = 120

///|
/// The web's tokens a page is given, as --e-<name> (web/src/styles/global.css.ts, as its root has them).
// kept across runs: a table, never written
let viz_light : Array[(String, String)] = [
  ("canvas", "oklch(100% 0 0)"),
  ("raised", "#e4e4e8"),
  ("text", "oklch(27% .009 255)"),
  ("muted", "oklch(52% .012 255)"),
  ("subtle", "oklch(57% .01 255)"),
  ("line", "oklch(91% .005 85)"),
  ("line-strong", "oklch(82% .008 255)"),
  ("hover", "oklch(25% .02 85 / .065)"),
  ("selected", "oklch(93% .009 85)"),
  ("paper", "oklch(96.3% .012 88)"),
  ("accent", "oklch(68% .175 39)"),
  ("accent-text", "oklch(48% .155 38)"),
  ("accent-bg", "oklch(96.5% .025 45)"),
  ("blue", "oklch(49% .18 260)"),
  ("blue-bg", "oklch(96% .02 260)"),
  ("code-inline", "#7C3FA0"),
  ("green", "oklch(46% .11 158)"),
  ("green-bg", "oklch(96% .02 158)"),
  ("amber", "oklch(48% .10 73)"),
  ("amber-bg", "oklch(97% .028 85)"),
  ("red", "oklch(48% .15 22)"),
  ("red-bg", "oklch(97% .02 22)"),
  ("neutral-bg", "oklch(95% .004 255)"),
  ("shadow", "oklch(20% .01 255 / .10)"),
  ("primary", "#24272b"),
  ("primary-hover", "#41464c"),
  ("on-primary", "#fff"),
  ("field-hover", "#9a9ea3"),
  ("field-focus", "#646970"),
  ("r-field", "12px"),
  ("r-card", "20px"),
  ("corner-shape", "round"),
]

///|
/// The dark theme's, over the light's.
// kept across runs: a table, never written
let viz_dark : Map[String, String] = {
  "canvas": "#1f2023",
  "raised": "#2a2c31",
  "text": "#e9e9ea",
  "muted": "#a3a5a9",
  "subtle": "#8c8f94",
  "line": "#2d2e32",
  "line-strong": "#3d3f44",
  "hover": "rgb(255 255 255 / .05)",
  "selected": "#323338",
  "paper": "#26272b",
  "accent": "oklch(72% .16 42)",
  "accent-text": "oklch(78% .13 45)",
  "accent-bg": "oklch(30% .05 40)",
  "blue": "oklch(75% .12 260)",
  "code-inline": "#C9A2E6",
  "blue-bg": "oklch(30% .05 260)",
  "green": "oklch(76% .12 158)",
  "green-bg": "oklch(30% .04 158)",
  "amber": "oklch(80% .12 80)",
  "amber-bg": "oklch(32% .05 80)",
  "red": "oklch(74% .14 22)",
  "red-bg": "oklch(30% .05 22)",
  "neutral-bg": "#2a2b2f",
  "shadow": "oklch(0% 0 0 / .45)",
  "primary": "#eceded",
  "primary-hover": "#d3d4d6",
  "on-primary": "#1f2023",
  "field-hover": "#5d6066",
  "field-focus": "#8a8d93",
}

///|
/// The tokens for the theme shown, as --e-<name>, in the light theme's order.
fn viz_tokens(dark : Bool) -> Array[(String, String)] {
  viz_light.map(fn(t) {
    let v = if dark {
      match viz_dark.get(t.0) {
        Some(d) => d
        None => t.1
      }
    } else {
      t.1
    }
    ("--e-" + t.0, v)
  })
}

///|
fn viz_tokens_json(dark : Bool) -> String {
  let m : Map[String, Json] = {}
  for t in viz_tokens(dark) {
    m[t.0] = Json::string(t.1)
  }
  Json::object(m).stringify()
}

///|
let viz_cdns : String = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com"

///|
fn viz_csp() -> String {
  [
    "default-src 'none'",
    "script-src 'unsafe-inline' 'unsafe-eval' " + viz_cdns,
    "style-src 'unsafe-inline' " + viz_cdns + " https://fonts.googleapis.com",
    "font-src data: " + viz_cdns + " https://fonts.gstatic.com",
    "img-src data: blob:",
    "media-src data: blob:",
    "connect-src 'none'",
  ].join("; ")
}

///|
/// What the bridge says to its page (it posts to its parent, which in a view of its own is itself), handed to the
/// app: its height, what it keeps, a failure, words to send (Viz.kt RELAY, to mbuiHost in StillFailViz's place).
let viz_relay : String = "addEventListener(\"message\",function(e){if(e.source===window&&e.data&&e.data.emberViz&&e.data.type!==\"theme\"){try{mbuiHost.post(JSON.stringify(e.data))}catch(_){}}});"

///|
/// What shows under a page that draws nothing there (the message's ground, as the Android app's WebView, which is
/// see-through, shows it): the root's ground, over the stylesheet's transparent one.
fn viz_ground_style(ground : Int64) -> String {
  "<style id=\"mbui-ground\">:root:root{background:" + viz_css_color(ground) + "}</style>"
}

///|
/// A colour as CSS has it (#rrggbb).
fn viz_css_color(c : Int64) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  out.write_char('#')
  for k in 0..<6 {
    let d = ((c >> (28 - 4 * k)) & 15L).to_int()
    out.write_char(digits.get_char(d).unwrap())
  }
  out.to_string()
}

///|
/// Whether an HTML file is a fragment (as the viz skill has agents write them), to be drawn in the stylesheet.
fn viz_is_fragment(html : String) -> Bool {
  let head = if html.length() > 2048 { html.view(end_offset=2048).to_owned() } else { html }
  let lower = head.to_lower()
  if lower.contains("<!doctype") {
    return false
  }
  // <html followed by a space or >
  let mut at = 0
  while lower.view(start_offset=at).find("<html") is Some(i) {
    let k = at + i + 5
    if k < lower.length() {
      let ch = lower.get_char(k).unwrap_or(' ')
      if ch == '>' || ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
        return false
      }
    }
    at = k
  }
  true
}

///|
/// The page: the content in the stylesheet, the bridge (and what the widget kept) ahead of it, the theme as the app
/// shows it now (Viz.kt documentOf).
fn viz_document(html : String, state : Json?, dark : Bool, ground : Int64) -> String {
  let vars = viz_tokens(dark).map(fn(t) { t.0 + ":" + t.1.replace_all(old="<", new="").replace_all(old=">", new="") }).join(";")
  let theme = if dark { "dark" } else { "light" }
  let kept = Json::object({ "widgetState": state.unwrap_or(Json::null()) }).stringify().replace_all(old="<", new="\\u003c")
  "<!doctype html><html data-theme=\"" +
  theme +
  "\"><head><meta charset=\"utf-8\">" +
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
  "<meta http-equiv=\"Content-Security-Policy\" content=\"" +
  viz_csp() +
  "\">" +
  "<style>:root{color-scheme:" +
  theme +
  ";" +
  vars +
  "}</style><style>" +
  viz_css +
  "</style>" +
  viz_ground_style(ground) +
  "<script type=\"application/json\" id=\"ember-viz-state\">" +
  kept +
  "</script>" +
  "<script>" +
  viz_relay +
  "</script><script>" +
  viz_bridge +
  "</script></head><body>" +
  html +
  "</body></html>"
}

///|
/// Where the first of `tags` (an opening tag's start, lower case) ends in `html`, after its `>`; -1 none.
fn viz_tag_end(html : String, tag : String) -> Int {
  let lower = html.to_lower()
  let mut at = 0
  while lower.view(start_offset=at).find(tag) is Some(i) {
    let k = at + i + tag.length()
    let next = lower.get_char(k).unwrap_or('x')
    if next == '>' || next == ' ' || next == '\n' || next == '\t' || next == '\r' {
      match lower.view(start_offset=k).find(">") {
        Some(j) => return k + j + 1
        None => return -1
      }
    }
    at = k
  }
  -1
}

///|
/// A whole page's document (a file that is not a fragment: a player, an app, a page made to fill a window), drawn as
/// written: only the sandbox's CSP and the bridge (with the relay) go into its head, after its doctype, html or head
/// tag so it keeps its mode (Viz.kt pageDocument).
fn viz_page_document(html : String) -> String {
  let head = "<meta http-equiv=\"Content-Security-Policy\" content=\"" +
    viz_csp() +
    "\"><script>" +
    viz_relay +
    "</script><script>" +
    viz_bridge +
    "</script>"
  let at = match viz_tag_end(html, "<head") {
    -1 =>
      match viz_tag_end(html, "<html") {
        -1 => viz_tag_end(html, "<!doctype")
        n => n
      }
    n => n
  }
  if at >= 0 {
    html.view(end_offset=at).to_owned() + head + html.view(start_offset=at).to_owned()
  } else {
    head + html
  }
}

///|
/// A visualization's document as a page of the preview serves it (Viz.kt vizServed): the file in the stylesheet with
/// what its widget kept (a whole page as written), and `script` (the preview's own page script) inline ahead of the
/// rest, as the page's CSP lets no script of the page's host in.
fn viz_served(html : String, state : Json?, dark : Bool, ground : Int64, script : String) -> String {
  let doc = if viz_is_fragment(html) { viz_document(html, state, dark, ground) } else { viz_page_document(html) }
  let tag = "<script>" + script.replace_all(old="</script", new="<\\/script") + "</script>"
  let at = match viz_tag_end(doc, "<head") {
    -1 => viz_tag_end(doc, "<html")
    n => n
  }
  if at >= 0 {
    doc.view(end_offset=at).to_owned() + tag + doc.view(start_offset=at).to_owned()
  } else {
    tag + doc
  }
}

///|
/// Whether a file is a visualization (an HTML file: Prose.kt HTML).
fn is_viz(name : String) -> Bool {
  let n = name.to_lower()
  n.has_suffix(".html") || n.has_suffix(".htm")
}

// ── a visualization's file: fetched with what its widget kept ──────────

///|
/// A visualization's page and what its widget kept (VizFiles.kt Loaded), fetched once per file: a file sent never
/// changes.
priv struct VizLoad {
  mut html : String?
  /// what its widget kept, as last read or kept here (None: nothing); whether that has been read
  mut state : Json?
  mut state_read : Bool
  mut failed : Bool
  mut asked : Bool
}

///|
/// The files fetched, by station, session and path.
let viz_loads : Map[String, VizLoad] = Map([])

///|
fn viz_id(station : String, key : String, path : String) -> String {
  station + "/" + key + "/" + path
}

///|
/// The file's page and what it kept: asked of its station the first time (`station.file`, `widget.state`; what an older
/// station cannot say is nothing kept). None while it comes; Some(Err) when it cannot be read.
fn viz_load(c : @ui.Ctx, src : Source, station : String, key : String, path : String) -> Result[(String, Json?), Unit]? {
  let id = viz_id(station, key, path)
  let l = match viz_loads.get(id) {
    Some(l) => l
    None => {
      let l : VizLoad = { html: None, state: None, state_read: false, failed: false, asked: false }
      viz_loads[id] = l
      l
    }
  }
  if !l.asked {
    l.asked = true
    c.tell("viz/load/" + id, fn() {
      (src.read_bytes)(
        "station.file",
        Json::object({
          "station": Json::string(station),
          "key": Json::string(key),
          "name": Json::string(base_name(path)),
        }),
        fn(r) {
          match r {
            Ok((_, bytes)) => l.html = Some(@utf8.decode_lossy(bytes))
            Err(_) => l.failed = true
          }
        },
      )
      (src.call)(
        "widget.state",
        Json::object({ "station": Json::string(station), "key": Json::string(key), "path": Json::string(path) }),
        fn(r) {
          match r {
            Ok(v) =>
              l.state = match field(Some(v), "state") {
                Some(Null) | None => None
                Some(s) => Some(s)
              }
            Err(_) => ()
          }
          l.state_read = true
        },
      )
    })
  }
  if l.failed {
    return Some(Err(()))
  }
  match l.html {
    Some(h) if l.state_read => Some(Ok((h, l.state)))
    _ => None
  }
}

///|
/// Keeps what a visualization's widget keeps next: here at once, on its station after (VizFiles.kt keepViz).
fn viz_keep(src : Source, station : String, key : String, path : String, state : Json) -> Unit {
  match viz_loads.get(viz_id(station, key, path)) {
    Some(l) => {
      l.state = match state {
        Null => None
        s => Some(s)
      }
      l.state_read = true
    }
    None => ()
  }
  (src.call)(
    "widget.setState",
    Json::object({
      "station": Json::string(station),
      "key": Json::string(key),
      "path": Json::string(path),
      "state": state,
    }),
    fn(_) {  },
  )
}

// ── the page itself ────────────────────────────────────────────────────

///|
/// A page drawn (Viz.kt VizFrame): its view, the height it said, whether it is shown yet (once it has drawn itself:
/// what is under it shows meanwhile), the theme it was told.
priv struct VizFrame {
  view : @ui.NativeView
  html : String
  page : Bool
  mut height : Int
  mut shown : Bool
  mut dark : Bool
  mut ground : Int64
}

///|
/// The pages drawn, by where they are drawn (their message's place and file, a chart's code, the full screen's).
let viz_frames : Map[String, VizFrame] = Map([])

///|
/// Heights pages were last drawn at (by their content), so one drawn again takes its room at once.
let viz_heights : Map[String, Int] = Map([])

///|
/// What a page says to the app (the bridge's messages, relayed): who hears what it keeps, a failure, words to send.
priv struct VizHears {
  keep : ((Json) -> Unit)?
  failed : ((String) -> Unit)?
  /// words for the chat's composer: whether it took them
  follow_up : ((String) -> Bool)?
}

///|
/// What a page's view says, read (it says what it likes: a field that is not what it should be is let go).
fn viz_said(f : VizFrame, hears : VizHears, words : String) -> Unit {
  let m = match (try Some(@json.parse(words)) catch { _ => None }) {
    Some(Object(m)) => m
    _ => return
  }
  match m.get("type") {
    Some(String("height")) =>
      if !f.page {
        match m.get("height") {
          Some(Number(h, ..)) if h == h && h < 1.0e9 && h > -1.0e9 => {
            let tall = h.ceil().to_int()
            let shown = if tall > viz_max_height { viz_max_height } else { tall }
            viz_heights[f.html] = shown
            f.height = shown
            f.shown = true
          }
          _ => ()
        }
      }
    Some(String("state")) => {
      let s = m.get("state").unwrap_or(Json::null())
      if s.stringify().length() <= viz_max_state {
        match hears.keep {
          Some(k) => k(s)
          None => ()
        }
      }
    }
    Some(String("failed")) =>
      match (m.get("message"), hears.failed) {
        (Some(String(why)), Some(f)) => f(why)
        _ => ()
      }
    Some(String("followup")) =>
      match m.get("prompt") {
        Some(String(p)) => {
          let words = p.trim().to_owned()
          if words != "" {
            let cut = if words.length() > 4000 { words.view(end_offset=4000).to_owned() } else { words }
            let took = match hears.follow_up {
              Some(f) => f(cut)
              None => false
            }
            app.toast = viz_tr(if took { "android-misc.viz.followupDrafted" } else { "android-misc.viz.cantSend" })
            app.toast_n += 1
          }
        }
        _ => ()
      }
    _ => ()
  }
}

///|
/// The page of `html` (what its widget kept: `state`) drawn as `key`: as tall as its content (`fill`: the room it is
/// given), shown once it has drawn itself. Made once per place: a new page would lose what it holds; the theme is told
/// to it as it changes.
fn viz_frame(
  c : @ui.Ctx,
  key : String,
  html : String,
  state : Json?,
  hears : VizHears,
  fill? : Bool = false,
  ground? : Int64 = @sf.theme().p.bg,
) -> Unit {
  let dark = @sf.theme().dark
  let f = match viz_frames.get(key) {
    Some(f) => f
    None => {
      let page = !viz_is_fragment(html)
      let doc = if page { viz_page_document(html) } else { viz_document(html, state, dark, ground) }
      let cell : Ref[VizFrame?] = Ref(None)
      let view = @ui.NativeView::page(doc, said=fn(w) {
        match cell.val {
          Some(f) => viz_said(f, hears, w)
          None => ()
        }
      })
      // in a list, an upright drag on the page moves the list (Viz.kt passVerticalDrags); a page of its own keeps them
      if !fill {
        view.touch(@ui.Touch::VerticalOut)
      }
      let f : VizFrame = {
        view,
        html,
        page,
        height: viz_heights.get(html).unwrap_or(0),
        shown: false,
        dark,
        ground,
      }
      cell.val = Some(f)
      viz_frames[key] = f
      f
    }
  }
  // the theme told only when it changes (a page told it as it loads draws again: a chart redrawn)
  if f.dark != dark || f.ground != ground {
    f.dark = dark
    f.ground = ground
    let scheme = if dark { "dark" } else { "light" }
    let g = viz_css_color(ground)
    c.tell("viz/theme/" + key, fn() {
      f.view.script(
        "postMessage({emberViz:true,type:\"theme\",tokens:" +
        viz_tokens_json(dark) +
        ",scheme:\"" +
        scheme +
        "\"},\"*\");var g=document.getElementById(\"mbui-ground\");if(g)g.textContent=\":root:root{background:" +
        g +
        "}\"",
      )
    })
  }
  // a whole page (or a fragment that never says its height) is shown once it has loaded
  if f.view.state() == 1 && (f.page || f.height == 0) {
    f.shown = true
  }
  // what is under it shows till it has drawn itself: the ground (a page's paper), drawn over it
  let cover = fn(style : @ui.Style) {
    if !f.shown {
      c.layer(fn() { c.box(style~, fn() {  }) |> ignore }) |> ignore
    }
  }
  if fill {
    c.box(style=viz_fill, fn() {
      c.native(f.view) |> ignore
      cover(viz_ground)
    })
    |> ignore
  } else if f.page {
    // a whole page sizes itself to its window: in a message a screen-shaped one (16:9 of the message's width, at most
    // 80% of the screen's height), its corners the card's, on the paper
    let box = c.id("viz/box/" + key)
    let w = match c.laid_size(box) {
      Some((w, _)) => w
      None => c.width
    }
    let h = dmin((w * viz_page_ratio).floor(), (c.height * viz_page_most).floor())
    c.box(style=viz_page_frame.then(@ui.style(h=Fixed(h))), id=box, fn() {
      c.native(f.view) |> ignore
      cover(viz_paper_cover)
    })
    |> ignore
  } else {
    let h = if f.height > 0 { f.height } else { viz_first_height }
    c.box(style=@ui.style(w=Full, h=Fixed(h.to_double())), fn() {
      c.native(f.view) |> ignore
      cover(viz_ground)
    })
    |> ignore
  }
}

///|
/// A whole page's window in a message: 16:9 of its width, at most this share of the screen's height.
let viz_page_ratio : Double = 9.0 / 16.0

///|
let viz_page_most : Double = 0.8

///|
/// All the room it is given (a page of its own).
// kept across runs: a value (no field of it changes)
let viz_fill : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// What shows under a page not drawn yet: the chat's ground.
// kept across runs: a value (no field of it changes)
let viz_ground : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
/// A whole page in a message: its corners the card's (Smooth 20), on the paper (Viz.kt: #F6F2EA, dark #26272B).
// kept across runs: a value (no field of it changes)
let viz_page_frame : @ui.Style = @ui.style(w=Full, radius=@sf.viz_card_radius, clip=true, bg=@sf.viz_paper, dark=@ui.patch(bg=@sf.viz_paper_dark))

///|
// kept across runs: a value (no field of it changes)
let viz_paper_cover : @ui.Style = @ui.style(w=Full, h=Full, bg=@sf.viz_paper, dark=@ui.patch(bg=@sf.viz_paper_dark))

///|
/// The pages drawn as `prefix…` let go (their place gone: the chat left, the full screen closed).
fn viz_close(prefix : String) -> Unit {
  let gone = []
  for k, f in viz_frames {
    if k.has_prefix(prefix) {
      f.view.close()
      gone.push(k)
    }
  }
  for k in gone {
    viz_frames.remove(k)
  }
}

///|
/// A chat left: its pages let go.
fn viz_chat_left(station : String, session : String) -> Unit {
  viz_close("chat/" + station + ":" + session + "/")
}

// ── in a message (VizFiles.kt VizFile) ─────────────────────────────────

///|
/// Where a visualization's words to send go: the chat's composer (its draft: the words after what is there, then the
/// field focused), as Prose.kt's followUp.
fn viz_follow_up(station : String, session : String) -> (String) -> Bool {
  fn(words) {
    let d = match drafts.get(station + ":" + session) {
      Some(d) => d
      None => return false
    }
    d.text = if d.text.trim() == "" { words } else { d.text.trim_end().to_owned() + "\n" + words }
    d.put_text = Some(d.text)
    d.focus = -1
    true
  }
}

///|
/// A placed HTML file `a` of the message `ts`, drawn there, with the ways to open it on its own under it (the whole
/// screen, or a page of its own: 在侧边打开); `failed`: what shows instead when the file cannot be read (its card).
fn viz_file(c : @ui.Ctx, src : Source, here : Here, ts : String, a : Attachment, failed : () -> Unit) -> Unit {
  let station = here.station
  let key = owner_of(here, a)
  let t = @sf.theme()
  match viz_load(c, src, station, key, a.path) {
    Some(Err(_)) => failed()
    // its place, breathing as every wait's shapes, till the page comes
    None =>
      c.box(style=viz_wait_under, fn() {
        let i = c.box(style=viz_wait, fn() {  })
        c.look(i, { ..@ui.still_look, alpha: @sf.breath(c) })
      })
      |> ignore
    Some(Ok((html, state))) => {
      let place = "chat/" + here.station + ":" + here.session + "/" + ts + "/" + a.path
      c.box(style=viz_file_box, fn() {
        viz_frame(c, place, html, state, {
          keep: Some(fn(s) { viz_keep(src, station, key, a.path, s) }),
          failed: None,
          follow_up: Some(viz_follow_up(here.station, here.session)),
        })
        // under the page, out of its way: the ways to open it on its own, icons in the chat's grey
        c.box(style=viz_ways, fn() {
          let full = c.id("viz/full/" + place)
          if c.clicked(full) {
            viz_open_full(a.name, station, key, a.path, here)
          }
          viz_icon(c, full, "expand", viz_tr("android-misc.viz.fullscreen"))
          let aside = c.id("viz/aside/" + place)
          if c.clicked(aside) {
            app.nav.push(PreviewFile(station, key, a.path, a.name))
          }
          viz_icon(c, aside, "panel-open", viz_tr("android-misc.viz.openAside"))
        })
        |> ignore
      })
      |> ignore
      ignore(t)
    }
  }
}

///|
/// One of the ways under a page (VizFiles.kt): a 22 box (corners Smooth 6), a 14 icon in the web's subtle grey.
fn viz_icon(c : @ui.Ctx, id : Int, icon : String, label : String) -> Unit {
  ignore(label)
  c.box(style=viz_way, id~, fn() { @sf.icon(c, icon, size=14.0, color=ink().subtle) |> ignore }) |> ignore
}

///|
/// Its place while it comes: 120 high, its corners Smooth 12, the bubble's grey, 8 under it.
// kept across runs: a value (no field of it changes)
let viz_wait_under : @ui.Style = @ui.style(w=Full, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let viz_wait : @ui.Style = @ui.style(w=Full, h=@sf.viz_wait_h, radius=Xl, bg=Neutral)

///|
/// The page and the ways under it, 4 under them.
// kept across runs: a value (no field of it changes)
let viz_file_box : @ui.Style = @ui.style(w=Full, pb=S1)

///|
/// The ways under the page: 2 under it, 22 high, at its end, 2 apart.
// kept across runs: a value (no field of it changes)
let viz_ways : @ui.Style = @ui.style(row=true, w=Full, pt=S0_5, h=S6, gap=S0_5, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let viz_way : @ui.Style = @ui.style(
  w=@sf.viz_way_side,
  h=@sf.viz_way_side,
  radius=Md,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=Hover),
)

// ── over the whole screen (Viz.kt VizFull, VizFiles.kt VizOpen) ────────

///|
/// A visualization open over the whole screen: its name, its file (to fetch, or fetched), the chat whose composer its
/// words go to.
priv struct VizFull {
  name : String
  station : String
  key : String
  path : String
  session : String
  /// opened by a link within a sentence (VizOpen): its wait said under the words till it covers the screen
  linked : Bool
}

///|
let viz_full : Ref[VizFull?] = Ref(None)

///|
fn viz_open_full(name : String, station : String, key : String, path : String, here : Here, linked? : Bool = false) -> Unit {
  viz_close("full/")
  viz_full.val = Some({ name, station, key, path, session: here.session, linked })
}

///|
fn viz_close_full() -> Unit {
  viz_close("full/")
  viz_full.val = None
}

///|
/// The visualization over the whole screen, if one is open: call after the pages are drawn. The page as tall as the
/// screen, its name and a close over it; back closes it.
fn viz_full_layer(c : @ui.Ctx, src : Source) -> Unit {
  let v = match viz_full.val {
    Some(v) => v
    None => return
  }
  match viz_load(c, src, v.station, v.key, v.path) {
    // fetched once; a link's wait is said under its words (viz_opening)
    None => return
    Some(Err(_)) => {
      viz_close_full()
      app.toast = viz_tr("android-misc.viz.cantRead")
      app.toast_n += 1
      return
    }
    Some(Ok((html, state))) => {
      let t = @sf.theme()
      c.on_back(fn() { viz_close_full() })
      c.layer(fn() {
        c.box(style=viz_ground, fn() {
          c.box(style=viz_full_bar, fn() {
            c.box(style=viz_full_name_box, fn() { c.text(v.name, style=viz_full_name) |> ignore }) |> ignore
            let close = c.id("viz/full/close")
            if c.clicked(close) {
              viz_close_full()
            }
            c.box(style=viz_full_close, id=close, fn() { @sf.icon(c, "close", size=18.0, color=t.p.text) |> ignore })
            |> ignore
          })
          |> ignore
          c.box(style=viz_full_page, fn() {
            viz_frame(
              c,
              "full/" + v.station + "/" + v.key + "/" + v.path,
              html,
              state,
              {
                keep: Some(fn(s) { viz_keep(src, v.station, v.key, v.path, s) }),
                failed: None,
                follow_up: Some(viz_follow_up(v.station, v.session)),
              },
              fill=true,
              ground=t.p.bg,
            )
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// Over the page: its name (18 in, 15, the ink, one line) and a close at its end (36 round, 8 in), 48 high.
// kept across runs: a value (no field of it changes)
let viz_full_bar : @ui.Style = @ui.style(row=true, w=Full, h=S12, pl=@sf.viz_full_in, pr=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let viz_full_name_box : @ui.Style = @ui.style(w=Full, clip=true)

///|
// kept across runs: a value (no field of it changes)
let viz_full_name : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let viz_full_close : @ui.Style = @ui.style(
  w=S9,
  h=S9,
  radius=Full,
  align=ACenter,
  justify=JCenter,
  pressed=@ui.patch(bg=Hover),
)

///|
/// The page under it, 12 in at its sides.
// kept across runs: a value (no field of it changes)
let viz_full_page : @ui.Style = @ui.style(w=Full, h=Full, px=S3)

///|
// kept across runs: a value (no field of it changes)
let viz_opening_box : @ui.Style = @ui.style(pt=S1_5, pb=S1_5)

///|
/// Under the words whose link opened a visualization, while it is fetched (VizFiles.kt VizOpen: 正在打开).
fn viz_opening(c : @ui.Ctx, src : Source, here : Here) -> Unit {
  match viz_full.val {
    Some(v) if v.linked && v.station == here.station && v.session == here.session =>
      if viz_load(c, src, v.station, v.key, v.path) is None {
        c.box(style=viz_opening_box, fn() { @sf.wait_line(c, viz_tr("common.opening"), key="viz-open") }) |> ignore
      }
    _ => ()
  }
}

// ── a mermaid chart (Viz.kt Mermaid) ───────────────────────────────────

///|
let viz_mermaid : String = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"

///|
/// A mermaid chart's page: the source, drawn by mermaid in the web's colours, drawn again when the theme changes.
fn viz_mermaid_document(code : String) -> String {
  "<pre class=\"mermaid-src\" hidden>" +
  code.replace_all(old="&", new="&amp;").replace_all(old="<", new="&lt;") +
  "</pre><div id=\"chart\" style=\"display:flex;justify-content:center\"></div>\n" +
  "<script type=\"module\">\n" +
  "  const post = (m) => parent.postMessage({ emberViz: true, ...m }, \"*\");\n" +
  "  const source = document.querySelector(\".mermaid-src\").textContent;\n" +
  "  let mermaid;\n" +
  "  try { mermaid = (await import(\"" +
  viz_mermaid +
  "\")).default; } catch (e) { post({ type: \"failed\", message: \"" +
  viz_tr("android-misc.viz.mermaidFailed") +
  "\" }); }\n" +
  "  const pixel = document.createElement(\"canvas\").getContext(\"2d\", { willReadFrequently: true });\n" +
  "  const rgb = (color) => { pixel.clearRect(0, 0, 1, 1); pixel.fillStyle = \"#000\"; pixel.fillStyle = color; pixel.fillRect(0, 0, 1, 1); const [r, g, b] = pixel.getImageData(0, 0, 1, 1).data; return \"rgb(\" + r + \", \" + g + \", \" + b + \")\"; };\n" +
  "  const v = (name) => { const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim(); return name === \"--font-sans\" ? value : rgb(value); };\n" +
  "  let n = 0;\n" +
  "  async function draw() {\n" +
  "    if (!mermaid) return;\n" +
  "    try {\n" +
  "      mermaid.initialize({ startOnLoad: false, securityLevel: \"strict\", theme: \"base\", fontFamily: v(\"--font-sans\"), themeVariables: {\n" +
  "        darkMode: document.documentElement.dataset.theme === \"dark\", fontSize: \"14px\",\n" +
  "        background: v(\"--background\"), primaryColor: v(\"--card\"), primaryTextColor: v(\"--foreground\"), primaryBorderColor: v(\"--border-strong\"),\n" +
  "        secondaryColor: v(\"--accent\"), tertiaryColor: v(\"--muted\"), lineColor: v(\"--muted-foreground\"), textColor: v(\"--foreground\"),\n" +
  "        noteBkgColor: v(\"--accent\"), noteTextColor: v(\"--foreground\"), noteBorderColor: v(\"--brand\"),\n" +
  "        actorBkg: v(\"--card\"), actorBorder: v(\"--border-strong\"), actorTextColor: v(\"--foreground\"), signalColor: v(\"--foreground\"), signalTextColor: v(\"--foreground\"),\n" +
  "      } });\n" +
  "      const { svg } = await mermaid.render(\"chart-\" + ++n, source);\n" +
  "      document.getElementById(\"chart\").innerHTML = svg;\n" +
  "    } catch (e) { post({ type: \"failed\", message: String(e?.message ?? e) }); }\n" +
  "  }\n" +
  "  addEventListener(\"ember-viz:theme\", draw);\n" +
  "  draw();\n" +
  "</script>"
}

///|
/// Charts that would not draw (mermaid not reachable, or the source does not parse): shown as code from then on.
let viz_unmade : Map[String, Bool] = Map([])

///|
/// A ```mermaid block: drawn as a chart (`place`: the message it is in); shown as code while it will not draw.
fn viz_mermaid_block(c : @ui.Ctx, place : String, code : String) -> Unit {
  if viz_unmade.contains(code) {
    @sf.code_block(c, code, "mermaid")
    return
  }
  c.box(style=viz_mermaid_box, fn() {
    viz_frame(c, place + "/mermaid/" + code, viz_mermaid_document(code), None, {
      keep: None,
      failed: Some(fn(_why) { viz_unmade[code] = true }),
      follow_up: None,
    })
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let viz_mermaid_box : @ui.Style = @ui.style(w=Full)
