// A visualization's file as both frames show it (ember apps/android shared/ui/Viz.kt, chat/screens/VizFiles.kt; web
// Viz.tsx): the web's stylesheet and bridge and tokens round it, its CSP, what its widget keeps (`widget.state`,
// `widget.setState`), fetched once a file (`station.file`); served to a page of its own (a service's page's `file:`,
// service_page.mbt) with what it kept. Drawing it is each frame's own.


///|
pub fn viz_tr(key : String, args? : Array[(String, String)] = []) -> String {
  fill(key, args)
}

///|
/// A fragment's frame is as tall as its content, however tall (web Viz.tsx RUNAWAY): content sized to its window
/// (100vh, min-height:100%) grows with each height it is given; grown a little each time this many times running, it
/// is held where it got to.
pub let viz_runaway : Int = 60

///|
/// What a widget may keep, as Codex's Visualize allows.
pub let viz_max_state : Int = 16 * 1024

///|
/// The height a page that has not said its own takes (Viz.kt: 120).
pub let viz_first_height : Int = 120

///|
/// The tokens a page is given, as --e-<name> (the web's names, web/src/styles/global.css.ts; Viz.tsx TOKENS), for the
/// theme shown: the app's own palette and sizes of type, as the rest of the app draws them, not a copy of the web's.
pub fn viz_tokens(dark : Bool) -> Array[(String, String)] {
  let p = @sf.palette_of(dark)
  let t = @sf.theme().t
  let scale = @ui.font_scale()
  let px = fn(v : Double) { (v * scale).to_string() + "px" }
  [
    ("canvas", viz_css_color(p.canvas)),
    ("raised", viz_css_color(p.raised)),
    ("text", viz_css_color(p.text)),
    ("muted", viz_css_color(p.muted)),
    ("subtle", viz_css_color(p.subtle)),
    ("line", viz_css_color(p.line)),
    ("line-strong", viz_css_color(p.line_strong)),
    ("hover", viz_css_color(p.hover)),
    ("selected", viz_css_color(p.selected)),
    // a card on the page (the web's paper: its grey card on its white page; the app's white one on its paper)
    ("paper", viz_css_color(p.card)),
    ("accent", viz_css_color(p.accent)),
    ("accent-text", viz_css_color(p.accent_text)),
    ("accent-bg", viz_css_color(p.accent_bg)),
    ("blue", viz_css_color(p.blue)),
    ("blue-bg", viz_css_color(p.blue_bg)),
    ("code-inline", viz_css_color(p.code_ink)),
    ("green", viz_css_color(p.green_ink)),
    ("green-bg", viz_css_color(p.green_bg)),
    ("amber", viz_css_color(p.warn_ink)),
    ("amber-bg", viz_css_color(p.amber_bg)),
    ("red", viz_css_color(p.red)),
    ("red-bg", viz_css_color(p.red_bg)),
    ("neutral-bg", viz_css_color(p.neutral_bg)),
    // a segmented choice's thumb (the web's --lifted): the canvas, in the dark the ink at 12% (a step lighter)
    ("lifted", viz_css_color(if dark { (p.text & 0xFFFFFF00L) | 0x1FL } else { p.canvas })),
    ("shadow", viz_css_color(p.shadow)),
    ("primary", viz_css_color(p.primary)),
    ("primary-hover", viz_css_color(p.primary_hover)),
    ("on-primary", viz_css_color(p.on_primary)),
    ("field-hover", viz_css_color((if dark { @ui.Theme::narrow_dark() } else { @ui.Theme::narrow_light() }).field_hover)),
    ("field-focus", viz_css_color(p.muted)),
    ("r-field", "12px"),
    ("r-card", "20px"),
    ("corner-shape", "round"),
    ("text-caption", px(t.caption)),
    ("leading-caption", px(t.caption_line)),
    ("text-meta", px(t.meta)),
    ("leading-meta", px(t.meta_line)),
    ("text-ui", px(t.ui)),
    ("leading-ui", px(t.ui_line)),
    ("text-body", px(t.body)),
    ("leading-body", px(t.body_line)),
    ("text-title", px(t.title)),
    ("leading-title", px(t.title_line)),
    ("text-heading", px(t.heading)),
    ("leading-heading", px(t.heading_line)),
    ("text-display", px(t.display)),
    // the faces the app is set in (faces.mbt), after them the page's own for what they have no character for; ""
    // none chosen: the stylesheet's own (what people wrote: as the app's words)
    ("font-body", viz_family(@hostapi.face_ui, viz_body_faces)),
    ("font-text", viz_family(@hostapi.face_text, viz_body_faces)),
    ("font-mono", viz_family(@hostapi.face_code, viz_mono_faces)),
  ].map(fn(e) { ("--e-" + e.0, e.1) })
}

///|
/// The page's own faces after a chosen one (web/src/fonts.ts BODY, MONO).
let viz_body_faces : String = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", \"PingFang SC\", \"Hiragino Sans GB\", sans-serif"

///|
let viz_mono_faces : String = "ui-monospace, SFMono-Regular, Menlo, monospace"

///|
/// A place's face as the page sets it (host face `at`): its family, then `rest`; "" none chosen.
fn viz_family(at : Int, rest : String) -> String {
  let family = faces_web[at].0
  if family == "" {
    ""
  } else {
    family + ", " + rest
  }
}

///|
/// The stylesheets of the faces chosen that still.fail keeps, each once: linked in a page (its CSP lets their origin in).
pub fn viz_sheets() -> Array[String] {
  let out : Array[String] = []
  for i in 1..<faces_web.length() {
    let css = faces_web[i].1
    if css.has_prefix("https://") && !out.contains(css) {
      out.push(css)
    }
  }
  out
}

///|
/// A URL's origin (scheme and host), "" when it has none.
fn viz_origin(url : String) -> String {
  guard url.has_prefix("https://") else { return "" }
  let rest = url.unsafe_substring(start=8, end=url.length())
  match rest.find("/") {
    Some(i) => "https://" + rest.unsafe_substring(start=0, end=i)
    None => url
  }
}

///|
pub fn viz_tokens_json(dark : Bool) -> String {
  let m : Map[String, Json] = {}
  for t in viz_tokens(dark) {
    m[t.0] = Json::string(t.1)
  }
  Json::object(m).stringify()
}

///|
pub let viz_cdns : String = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com"

///|
pub fn viz_csp(sheets? : Array[String] = []) -> String {
  let faces = StringBuilder::new()
  let seen : Array[String] = []
  for sheet in sheets {
    let o = viz_origin(sheet)
    if o != "" && !seen.contains(o) {
      seen.push(o)
      faces.write_string(" " + o)
    }
  }
  [
    "default-src 'none'",
    "script-src 'unsafe-inline' 'unsafe-eval' " + viz_cdns,
    "style-src 'unsafe-inline' " + viz_cdns + " https://fonts.googleapis.com" + faces.to_string(),
    "font-src data: " + viz_cdns + " https://fonts.gstatic.com" + faces.to_string(),
    "img-src data: blob:",
    "media-src data: blob:",
    "connect-src 'none'",
  ].join("; ")
}

///|
/// What the bridge says to its page (it posts to its parent, which in a view of its own is itself), handed to the
/// app: its height, what it keeps, a failure, words to send (Viz.kt RELAY, to mbuiHost in StillFailViz's place).
pub let viz_relay : String = "addEventListener(\"message\",function(e){if(e.source===window&&e.data&&e.data.emberViz&&e.data.type!==\"theme\"){try{mbuiHost.post(JSON.stringify(e.data))}catch(_){}}});"

///|
/// What shows under a page that draws nothing there (the message's ground, as the Android app's WebView, which is
/// see-through, shows it): the root's ground, over the stylesheet's transparent one.
pub fn viz_ground_style(ground : Int64) -> String {
  "<style id=\"mbui-ground\">:root:root{background:" + viz_css_color(ground) + "}</style>"
}

///|
/// A colour as CSS has it (#rrggbb, #rrggbbaa when it is not opaque).
pub fn viz_css_color(c : Int64) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  out.write_char('#')
  for k in 0..<(if (c & 0xFFL) == 0xFFL { 6 } else { 8 }) {
    let d = ((c >> (28 - 4 * k)) & 15L).to_int()
    out.write_char(digits.get_char(d).unwrap())
  }
  out.to_string()
}

///|
/// Whether an HTML file is a fragment (as the viz skill has agents write them), to be drawn in the stylesheet.
pub fn viz_is_fragment(html : String) -> Bool {
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
pub fn viz_document(html : String, state : Json?, dark : Bool, ground : Int64, scroll? : Bool = false) -> String {
  // (one with no value left out: an empty one would stand in place of the stylesheet's own)
  let vars = viz_tokens(dark).filter(fn(t) { t.1 != "" }).map(fn(t) { t.0 + ":" + t.1.replace_all(old="<", new="").replace_all(old=">", new="") }).join(";")
  let sheets = viz_sheets()
  let theme = if dark { "dark" } else { "light" }
  let kept = Json::object({ "widgetState": state.unwrap_or(Json::null()) }).stringify().replace_all(old="<", new="\\u003c")
  "<!doctype html><html data-theme=\"" +
  theme +
  "\"><head><meta charset=\"utf-8\">" +
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
  "<meta http-equiv=\"Content-Security-Policy\" content=\"" +
  viz_csp(sheets~) +
  "\">" +
  sheets.map(fn(h) { "<link rel=\"stylesheet\" href=\"" + h.replace_all(old="\"", new="").replace_all(old="<", new="").replace_all(old=">", new="") + "\">" }).join("") +
  "<style>:root{-webkit-text-size-adjust:100%;text-size-adjust:100%;color-scheme:" +
  theme +
  ";" +
  vars +
  "}</style><style>" +
  viz_css +
  "</style>" +
  (if scroll { "<style>html{overflow:auto}</style>" } else { "" }) +
  viz_ground_style(ground) +
  "<script type=\"application/json\" id=\"ember-viz-state\">" +
  kept +
  "</script>" +
  "<script type=\"application/json\" id=\"viz-icons\">" +
  viz_icons +
  "</script>" +
  "<script>" +
  viz_relay +
  "</script><script>" +
  viz_bridge +
  "</script><script>" +
  viz_components +
  "</script></head><body>" +
  html +
  "</body></html>"
}

///|
/// Where the first of `tags` (an opening tag's start, lower case) ends in `html`, after its `>`; -1 none.
pub fn viz_tag_end(html : String, tag : String) -> Int {
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
pub fn viz_page_document(html : String) -> String {
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
pub fn viz_served(html : String, state : Json?, dark : Bool, ground : Int64, script : String) -> String {
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
pub fn is_viz(name : String) -> Bool {
  let n = name.to_lower()
  n.has_suffix(".html") || n.has_suffix(".htm")
}

// ── a visualization's file: fetched with what its widget kept ──────────

///|
/// A visualization's page and what its widget kept (VizFiles.kt Loaded), fetched once per file: a file sent never
/// changes.
pub(all) struct VizLoad {
  html : @signals.Signal[String?]
  /// what its widget kept, as last read or kept here (None: nothing); whether that has been read
  state : @signals.Signal[Json?]
  state_read : @signals.Signal[Bool]
  failed : @signals.Signal[Bool]
  // (plain: asked once, as it is first read; nothing shown reads it)
  mut asked : Bool
}

///|
/// The files fetched, by station, session and path.
pub let viz_loads : Map[String, VizLoad] = Map([])

///|
pub fn viz_id(station : String, key : String, path : String) -> String {
  station + "/" + key + "/" + path
}

///|
/// The file's page and what it kept: asked of the core the first time (`station.file`, `widget.state`; what an older
/// station cannot say is nothing kept), both kept on the device there, the page by its `size` as its message says (none
/// known: not kept), so it is drawn at once when the chat is next opened, the app run again. None while it comes;
/// Some(Err) when it cannot be read.
pub fn viz_load(
  c : @ui.Ctx,
  src : Source,
  station : String,
  key : String,
  path : String,
  size? : Double = 0.0,
) -> Result[(String, Json?), Unit]? {
  let id = viz_id(station, key, path)
  let l = match viz_loads.get(id) {
    Some(l) => l
    None => {
      let l : VizLoad = { html: @signals.signal(None), state: @signals.signal(None), state_read: @signals.signal(false), failed: @signals.signal(false), asked: false }
      viz_loads[id] = l
      l
    }
  }
  if !l.asked {
    l.asked = true
    c.tell("viz/load/" + id, fn() {
      let p : Map[String, Json] = {
        "station": Json::string(station),
        "key": Json::string(key),
        "name": Json::string(viz_base_name(path)),
      }
      chat_keep(p, size)
      (src.read_bytes)(
        "station.file",
        Json::object(p),
        fn(r) {
          match r {
            Ok((_, bytes)) => l.html.set(Some(@utf8.decode_lossy(bytes)))
            Err(_) => l.failed.set(true)
          }
        },
      )
      (src.call)(
        "widget.state",
        Json::object({ "station": Json::string(station), "key": Json::string(key), "path": Json::string(path) }),
        fn(r) {
          match r {
            Ok(v) =>
              l.state.set(match field(Some(v), "state") {
                Some(Null) | None => None
                Some(s) => Some(s)
              })
            Err(_) => ()
          }
          l.state_read.set(true)
        },
      )
    })
  }
  if l.failed.get() {
    return Some(Err(()))
  }
  match l.html.get() {
    Some(h) if l.state_read.get() => Some(Ok((h, l.state.get())))
    _ => None
  }
}

///|
/// Keeps what a visualization's widget keeps next: here at once, on its station after (VizFiles.kt keepViz).
pub fn viz_keep(src : Source, station : String, key : String, path : String, state : Json) -> Unit {
  match viz_loads.get(viz_id(station, key, path)) {
    Some(l) => {
      l.state.set(match state {
        Null => None
        s => Some(s)
      })
      l.state_read.set(true)
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


///|
/// A path's last part (its file's name).
pub fn viz_base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_string()
    None => path
  }
}

///|
/// A request of a visualization's page answered from here (Preview.kt's serve): its page (any path with no
/// extension, reloaded with what it kept since), and nothing else there is.
pub fn file_serve(f : FilePage, req : @ui.SiteRequest, reply : @ui.SiteReply) -> Unit {
  let bare = match req.path.find("?") {
    Some(i) => req.path.view(end_offset=i).to_owned()
    None => req.path
  }
  let last = match bare.rev_find("/") {
    Some(i) => bare.view(start_offset=i + 1).to_owned()
    None => bare
  }
  let served = req.verb == "GET" && !last.contains(".")
  if !served {
    reply.head(404, [("Content-Type", "text/plain; charset=utf-8")])
    reply.chunk(@utf8.encode("Not found"))
    reply.end()
    return
  }
  let doc = viz_served(f.html, f.state.get(), @sf.theme().dark, 0xFFFFFFFFL, page_script_served(false))
  reply.head(200, [("Content-Type", "text/html; charset=utf-8"), ("Cache-Control", "no-store")])
  reply.chunk(@utf8.encode(doc))
  reply.end()
}

///|
/// What a visualization's page says to the app (its bridge's relay: Viz.kt VizKeeper): here only what its widget keeps.
pub fn file_said(src : Source, f : FilePage, words : String) -> Unit {
  match (try Some(@json.parse(words)) catch { _ => None }) {
    Some(Object(m)) if m.get("type") == Some(Json::string("state")) => {
      let s = m.get("state").unwrap_or(Json::null())
      if s.stringify().length() <= viz_max_state {
        f.state.set(match s {
          Null => None
          x => Some(x)
        })
        viz_keep(src, f.station, f.key, f.path, s)
      }
    }
    _ => ()
  }
}
