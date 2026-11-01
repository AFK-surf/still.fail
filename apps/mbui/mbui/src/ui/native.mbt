// Native views in the canvas: a system view (a video player, a web page) the app paints where it shows, an instance
// of kind 9 whose image is the view's (@hostapi.view_tex_base + its id) and whose c2 is the part of its content seen.
// A host that keeps its views under the app's surface (macOS, iOS, Windows, the browser) leaves the canvas clear there
// (transparent, written without blending): a hole it shows through. Android draws each view into a picture of its own
// and draws that there, in the frame, so a view moves with a list in step with what is around it (a page taller than a
// picture can be, the part of it near what is seen: NativeViews.Page; c2 is still the part of all of it). What is painted
// after it draws over the view (a bar, a video's controls, frosted or not); what is painted around it, or a clip, hides
// the rest of it. The host places the view where its node was painted, every frame it moves (where it takes a touch),
// and hides it on the frames it is not painted (a page gone under another, scrolled away). Views that show at once
// are stacked as they were painted, the one painted last on top (`stack_views`).
//
// A video's bytes come only through the app: the player asks for ranges (`view_read_next`), the view's `read`
// fetches them (still.fail: `station.file.part`, `drive.read` through the core) and answers each as its bytes come
// (the player goes on with the first of them while the rest is on its way), and stops reading one the player let go
// of (it went elsewhere) or the view's that closes.
//
// How a view stands (`view_info`: its length, where it is, whether it plays, its size, …) is the host's to say as it
// changes, not the app's to ask each frame: the host tells as it does (hostcall.mbt's outside_stood), each change its
// own event (a player playing: each frame of its video shown, or its clock's tick where it shows no picture); the app
// reads it then into the view's signals, and what reads them (a time shown, a timeline) is told.
//
// Hosts: Android (NativeViews.java: Media3's ExoPlayer on a TextureView, a WebView), macOS and iOS (apple_views.m:
// AVPlayerLayer, WKWebView), the browser (web/host.js: <video>, a sandboxed <iframe>), Windows (win_views.cpp: WebView2,
// its players a page of its own with a <video>; no view where WebView2's runtime is not installed: `here` is false, the
// app says it cannot show it), Linux (linux_views.c: WebKitGTK 6.0's pages and sites, none without it; its players
// linux_player.h's, GStreamer's playbin, their pictures drawn in the canvas as Android's are, none without GStreamer).
//
// Also here: PDFs drawn by the host page by page into images (`Pdf`, shown with `Ctx::image(pdf.page_src(i))`), and
// an image drawn at a rect of its own within its box (`Ctx::picture`: zoomed, panned).

///|
/// A native view: a player or a page.
pub struct NativeView {
  priv id : Int
  priv kind : Int
  priv read : ((Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit)?
  /// its reads under way, by the host's number for each: how each is let go of
  priv reading : Map[Int, () -> Unit]
  /// how it stands, as its host last said (view_info's numbers, its state: `stood`), each a signal of its own
  priv info : FixedArray[@signals.Signal[Double]]
  priv state : @signals.Signal[Int]
  /// the frame it was last painted in, and where: content x y w h, clip x0 y0 x1 y1, its corners (top left, then round it)
  priv mut painted : Int
  /// where in that frame's paint it was (how many instances were before it): the views are stacked so
  priv mut seq : Int
  priv at : FixedArray[Double]
  /// its hole as painted there (x y w h; w 0: none), to follow it to where the frame took it after (Ctx::follow_holes)
  priv hole : FixedArray[Double]
  /// what the host was last told: the same 12 and shown
  priv told : FixedArray[Double]
  priv mut told_shown : Bool
  priv mut closed : Bool
  /// a video's frames' times asked of the host, and read once it said them (asked for in every frame it plays)
  priv mut frames_asked : Bool
  priv mut frame_times : Array[Double]?
  /// a site's: who answers its requests, who hears of a link left by, the replies under way, where its page is
  priv serve : ((SiteRequest, SiteReply) -> Unit)?
  priv leave : (String) -> Unit
  priv replies : Map[Int, SiteReply]
  priv mut path : String
  priv mut can_back : Bool
  priv mut can_forward : Bool
  priv mut loading : Bool
  priv mut title : String
  priv mut scale : Double
  priv mut told_zoom : Double
  priv mut told_page_scale : Double
  /// a page's: who hears what its page says to the app (`mbuiHost.post`), how a request is answered when its answer
  /// is late or read too slowly (the app's words for it), what takes a touch on it
  priv said : ((String) -> Unit)?
  priv no_answer : String
  priv too_slow : String
  priv mut touch : Touch
  priv mut keeps_cookies : Bool
  /// how many presses' rects the frame had when it was painted (those after it are drawn over it), and the rects of
  /// those over it the host was last told (`covers`)
  priv mut hits_before : Int
  /// the node of the window's tree hosting the old view it is in, as its targets were last found (none: no tree)
  priv mut island : @view.NodeId?
  priv mut told_covers : String
}

///|
/// Who takes a finger on a page's view (`NativeView::touch`): the page (`All`, as a browser's); the canvas under it
/// (`Through`: the page sees none, as a picture would be); the page until a second finger comes down, the canvas from
/// then (`PinchOut`: two fingers zoom what holds the page); the page until the finger has gone further up or down
/// than across, past the slop the canvas's own drags start at, the canvas from there, unless it went sideways past the
/// slop first, which keeps it the page's to its end (`VerticalOut`: a page in a list that scrolls the list, as
/// Android's Viz.kt passVerticalDrags). The page told the touch is called off (a cancel) when the canvas takes it; the
/// canvas given it from where it went down (a pinch's first finger then where it is now). A mouse's wheel goes the
/// same way: `VerticalOut` and `Through` give the canvas the wheel's upright scroll; `PinchOut` keeps a trackpad's
/// pinch from the page (the canvas takes none of its own on the Mac yet).
pub(all) enum Touch {
  All
  Through
  PinchOut
  VerticalOut
} derive(Eq, Show)

///|
fn touch_name(t : Touch) -> String {
  match t {
    All => "all"
    Through => "through"
    PinchOut => "pinch"
    VerticalOut => "vertical"
  }
}

///|
/// How long a site's request waits for the head of its answer before the app's words for that (`site`'s `no_answer`)
/// answer it instead (PreviewWeb.kt HEAD_WAIT_S): the host says when (`{"late":N}`), what the app sees is that event.
pub let site_head_wait_ms : Double = 60000.0

///|
/// How much of a site's answer may wait in the host for its page to read it before the answer is stopped (PreviewWeb.kt
/// BUFFERED_MAX): the host says when (`{"slow":N}`), and the answer ends with the app's words for it (`too_slow`).
pub let site_backlog_max : Int = 32 * 1024 * 1024

///|
/// A request a site's page made of its own host: its method (`verb`), its path (with its query), its headers, whether it is
/// for a page (the main frame, or one asking for HTML), its body (empty where the host's web view does not hand it
/// over).
pub struct SiteRequest {
  verb : String
  path : String
  headers : Array[(String, String)]
  page : Bool
  body : Bytes
}

///|
/// How a request is answered: its head, then its body a piece at a time, then its end; the page may let it go first.
pub struct SiteReply {
  priv view : Int
  priv req : Int
  priv mut headed : Bool
  priv mut ended : Bool
  priv mut gone : Bool
  priv mut on_gone : () -> Unit
}

///|
/// The answer's status and headers (once; before any of its body).
pub fn SiteReply::head(self : SiteReply, status : Int, headers : Array[(String, String)]) -> Unit {
  if self.headed || self.ended || self.gone {
    return
  }
  self.headed = true
  let a = headers.map(fn(h) { Json::array([Json::string(h.0), Json::string(h.1)]) })
  h_view_site_head(self.view, self.req, status, Json::array(a).stringify())
}

///|
/// The next piece of its body.
pub fn SiteReply::chunk(self : SiteReply, data : Bytes) -> Unit {
  if !self.ended && !self.gone && data.length() > 0 {
    h_view_site_chunk(self.view, self.req, data)
  }
}

///|
/// Its end: whole (`error` ""), or broken off with why.
pub fn SiteReply::end(self : SiteReply, error? : String = "") -> Unit {
  if self.ended || self.gone {
    return
  }
  self.ended = true
  h_view_site_end(self.view, self.req, error)
}

///|
/// Whether the page let it go (nothing more of it is taken).
pub fn SiteReply::gone(self : SiteReply) -> Bool {
  self.gone
}

///|
/// What to do when the page lets it go (stop asking for it).
pub fn SiteReply::when_gone(self : SiteReply, f : () -> Unit) -> Unit {
  self.on_gone = f
  if self.gone {
    f()
  }
}

///|
/// The views open, polled and placed each frame.
let open_views : Array[NativeView] = []

///|
/// The views shown in the last frame, in the order the host was last told to stack them (`stack_views`).
let stacked_views : Array[Int] = []

///|
// kept across runs: scratch the host writes into before each read, read at once: nothing is carried in it
let read_out : FixedArray[Double] = FixedArray::make(2, 0.0)

///|
fn NativeView::make(
  kind : Int,
  arg : String,
  read : ((Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit)?,
  serve? : ((SiteRequest, SiteReply) -> Unit)? = None,
  leave? : (String) -> Unit = fn(_) {  },
  said? : ((String) -> Unit)? = None,
  no_answer? : String = "",
  too_slow? : String = "",
) -> NativeView {
  let v = {
    id: h_view_open(kind, arg),
    kind,
    said,
    no_answer,
    too_slow,
    touch: All,
    keeps_cookies: false,
    hits_before: 0,
    island: None,
    told_covers: "",
    read,
    reading: {},
    serve,
    leave,
    replies: {},
    path: if kind == 3 { arg } else { "" },
    can_back: false,
    can_forward: false,
    loading: kind == 3,
    title: "",
    scale: 1.0,
    told_zoom: 1.0,
    told_page_scale: 1.0,
    info: FixedArray::makei(10, fn(_) { @signals.signal(0.0, same=fn(a, b) { a == b }) }),
    state: @signals.signal(0, same=fn(a, b) { a == b }),
    painted: -1,
    seq: 0,
    at: FixedArray::make(12, 0.0),
    hole: FixedArray::make(4, 0.0),
    told: FixedArray::make(12, -1.0),
    told_shown: false,
    closed: false,
    frames_asked: false,
    frame_times: None,
  }
  if v.id == 0 {
    v.state.set(-1)
  } else {
    open_views.push(v)
    // (how it stands as it opens; from now on, as its host says it changes)
    v.stood()
    // a site's host told how long a request waits for its head and how much of an answer may wait to be read
    if kind == 3 {
      h_view_tell(
        v.id,
        3,
        Json::object({
          "head_wait_ms": Json::number(site_head_wait_ms),
          "backlog": Json::number(site_backlog_max.to_double()),
        }).stringify(),
      )
    }
  }
  v
}

///|
/// A player of the video (or audio) of MIME type `type_`, its bytes read through `read(offset, length, answer)`:
/// `answer(bytes, total, more)` with its next bytes as they come, from `offset` on (all of them at most `length`,
/// fewer is fine, none only at the end), the file's whole size (-1 not known; -2: it could not be read) and whether
/// more of it comes (the last answer may bring none). What `read` gives back stops the read: called when the player
/// lets go of it or the view closes before its last answer (nothing more of it is taken). Paused until `play`.
/// `direct` ("": none) says how a host with a reader of its own reads those bytes itself, past the app (view_tell 6):
/// its reads then never wait on the app's frames; one asked before it is told, or of a host with no such reader,
/// goes through `read`.
pub fn NativeView::video(
  type_ : String,
  read : (Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit,
  direct? : String = "",
) -> NativeView {
  let v = NativeView::make(1, type_, Some(read))
  if v.id != 0 && direct != "" {
    h_view_tell(v.id, 6, direct)
  }
  v
}

///|
/// A page of `html` (its scripts on, nothing of the device's files or the app's reachable, its links not followed).
/// What its scripts say to the app (`mbuiHost.post(text)`, in the page and its frames; in the browser's, which only
/// tests and previews, in the page alone: none of it to be trusted, any script in the page may say anything) goes to
/// `said`, a text at a time, in the order said, as a frame begins.
pub fn NativeView::page(html : String, said? : (String) -> Unit) -> NativeView {
  NativeView::make(2, html, None, said~)
}

///|
/// A site served by the app (still.fail's preview of a service: Preview.kt, PreviewWeb.kt): a web view of a host of
/// its own at `start` (a path), each request its page makes of that host handed to `serve` to answer, as a browser
/// would have it from a server (its scripts on, its cookies kept by the app as it answers); a link elsewhere is not
/// followed but told to `leave`. Android's WebView and Windows' WebView2 (their requests intercepted), Apple's
/// WKWebView and Linux's WebKitGTK (a scheme of its own); the browser has none. What its scripts say to the app goes to `said`, as a page's
/// (`NativeView::page`). A request whose head has not come in `site_head_wait_ms` is answered 502 with `no_answer`;
/// one whose page reads it so slowly that more than `site_backlog_max` of it waits is stopped with `too_slow` (the
/// app's words for each: a person may read them on the page), and let go of (its `when_gone`).
pub fn NativeView::site(
  start : String,
  serve : (SiteRequest, SiteReply) -> Unit,
  leave? : (String) -> Unit = fn(_) {  },
  said? : (String) -> Unit,
  no_answer? : String = "no answer in 60 s",
  too_slow? : String = "read too slowly: stopped",
) -> NativeView {
  NativeView::make(3, start, None, serve=Some(serve), leave~, said~, no_answer~, too_slow~)
}

///|
/// A script run in a page's (or a site's) page: in the page that is there once it has loaded, or once it has said
/// something to the app since it started (a script sent while a page loads waits for it), in the order sent. On a
/// run's tape as `VIEWSCRIPT view length hash`, so that a run replayed that sends another parts there.
pub fn NativeView::script(self : NativeView, js : String) -> Unit {
  if self.id != 0 && !self.closed {
    if taping() {
      tape_line("VIEWSCRIPT \{self.id} \{js.length()} \{script_hash(js)}")
    }
    h_view_tell(self.id, 1, js)
  }
}

///|
/// A script's hash on a run's tape (its UTF-16 code units, FNV-1a, 32 bits in hex).
fn script_hash(js : String) -> String {
  let mut h = 0x811c9dc5U
  for i in 0..<js.length() {
    h = (h ^ js.unsafe_charcode_at(i).reinterpret_as_uint()) * 0x01000193U
  }
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  for k in 0..<8 {
    let d = ((h >> (28 - 4 * k)) & 15U).reinterpret_as_int()
    out.write_char(digits.get_char(d).unwrap())
  }
  out.to_string()
}

///|
/// Who takes a finger on this page's view from now on (`Touch`; `All` at first).
pub fn NativeView::touch(self : NativeView, mode : Touch) -> Unit {
  if self.id != 0 && !self.closed && mode != self.touch {
    self.touch = mode
    h_view_tell(self.id, 2, "\{touch_name(mode)} \{touch_slop() * window_zoom_drawn.val}")
  }
}

///|
/// A site's page back a step in its own history.
pub fn NativeView::go_back(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 5, 0.0)
  }
}

///|
pub fn NativeView::go_forward(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 6, 0.0)
  }
}

///|
pub fn NativeView::reload(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 7, 0.0)
  }
}

///|
/// A site's page at `path` of its host.
pub fn NativeView::load(self : NativeView, path : String) -> Unit {
  if self.id != 0 && !self.closed {
    self.path = path
    h_view_site_load(self.id, path)
  }
}

///|
/// A site's page laid out at its rect's size over `k` and drawn at `k` times (a phone's or a desktop's width shown in
/// the room there is); 1 as it is.
pub fn NativeView::set_scale(self : NativeView, k : Double) -> Unit {
  if self.id != 0 && !self.closed && k > 0.0 && k != self.scale {
    self.scale = k
    self.told_page_scale = k * window_zoom_drawn.val
    h_view_control(self.id, 8, self.told_page_scale)
  }
}

///|
/// Where a site's page is: its path on its host (or the address it went to elsewhere), whether it can go back and
/// forward, whether it is loading, its title.
pub fn NativeView::page_at(self : NativeView) -> (String, Bool, Bool, Bool, String) {
  (self.path, self.can_back, self.can_forward, self.loading, self.title)
}

///|
/// Whether a site's host keeps its cookies as a browser does (a request's Cookie from its jar, an answer's Set-Cookie
/// kept there, the page's document.cookie theirs: Android's WebView): else they are the app's to keep and send.
pub fn NativeView::keeps_cookies(self : NativeView) -> Bool {
  self.keeps_cookies
}

///|
/// Whether this host has such a view (none: the browser's sites, Windows without WebView2, Linux without WebKitGTK 6.0
/// for pages and sites or GStreamer for players).
pub fn NativeView::here(self : NativeView) -> Bool {
  self.id != 0
}

///|
/// Gone: its player stopped, its page closed. It shows no more.
pub fn NativeView::close(self : NativeView) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  // its reads under way stopped: nothing more of them is wanted
  let reading = self.reading.values().collect()
  self.reading.clear()
  for stop in reading {
    stop()
  }
  if self.id != 0 {
    h_view_close(self.id)
    open_views.retain(fn(v) { !physical_equal(v, self) })
    stacked_views.retain(fn(id) { id != self.id })
    // a grab it was asked and had not answered is answered no more (a host tells a closed view's nothing)
    outside_end(outside_grab, self.id)
  }
}

///|
pub fn NativeView::play(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 1, 0.0)
  }
}

///|
/// A video's frames' times (ms, in time order), read from its file as the system reads it (Android's MediaExtractor
/// over the same reads as its player; Apple's sample cursor; Linux's parsebin, nothing decoded): asked once, None until
/// they are here (and where the host reads none); empty when there were none to read.
pub fn NativeView::frames(self : NativeView) -> Array[Double]? {
  if self.id == 0 || self.closed {
    return None
  }
  if !self.frames_asked {
    self.frames_asked = true
    h_view_control(self.id, 20, 0.0)
  }
  if self.frame_times is Some(_) {
    return self.frame_times
  }
  // (said once, all of them: read once, not again in each frame, a long film's tens of thousands of times)
  self.frame_times = match h_view_text(self.id, 1) {
    Some(t) =>
      Some(
        t
        .split(",")
        .filter_map(fn(x) {
          let v : Json? = try Some(@json.parse(x.to_owned())) catch { _ => None }
          match v {
            Some(Number(n, ..)) => Some(n)
            _ => None
          }
        })
        .to_array(),
      )
    None => None
  }
  self.frame_times
}

///|
/// The video's frame showing at `ms` grabbed whole at its own size, as a PNG (`grabbed` once it is here); a page's (or
/// a site's) view, what its page shows now, at its view's size in device pixels (`ms` not read). One grab of a view at
/// a time: asked again before the last one's `grabbed` is taken, it aborts.
pub fn NativeView::grab_frame(self : NativeView, ms : Double) -> Unit {
  if self.id != 0 && !self.closed {
    // (one grab of a view at a time: its ticket is the view's)
    if outside_tickets.contains(outside_key(outside_grab, self.id)) {
      let s = "NativeView::grab_frame: view \{self.id} grabs a frame already: one at a time, its `grabbed` taken first"
      println(s)
      abort(s)
    }
    outside_start(outside_grab, self.id, "a frame of view \{self.id} grabbed")
    h_view_control(self.id, 21, ms)
  }
}

///|
/// A video's frame as it shows now (the player's picture, not the file's frame read again: at once), at most `side`
/// pixels on its longer side, as a JPEG (`grabbed` once it is here, empty when it could not be: no frame shown yet, a
/// host that grabs none): what a viewer closing into its thumbnail goes with. One grab of a view at a time, as
/// grab_frame's.
pub fn NativeView::grab_shown(self : NativeView, side : Double) -> Unit {
  if self.id != 0 && !self.closed {
    if outside_tickets.contains(outside_key(outside_grab, self.id)) {
      let s = "NativeView::grab_shown: view \{self.id} grabs a frame already: one at a time, its `grabbed` taken first"
      println(s)
      abort(s)
    }
    outside_start(outside_grab, self.id, "the frame view \{self.id} shows grabbed")
    h_view_control(self.id, 22, side)
  }
}

///|
/// Whether a grab of this view is on its way (grab_frame's, grab_shown's): its `grabbed` not taken yet.
pub fn NativeView::grabbing(self : NativeView) -> Bool {
  self.id != 0 && outside_tickets.contains(outside_key(outside_grab, self.id))
}

///|
/// A frame grabbed: None while it is grabbed (or none was asked), Some(png) once here (taken once), Some(empty) when it
/// could not be.
pub fn NativeView::grabbed(self : NativeView) -> Bytes? {
  if self.id == 0 || !answer_here(outside_grab, self.id) {
    return None
  }
  let got = match h_view_text(self.id, 2) {
    Some("2") => Some(h_view_still(self.id))
    Some("-1") => Some(b"")
    _ => None
  }
  if got is Some(_) {
    answer_taken(outside_grab, self.id)
    outside_end(outside_grab, self.id)
  }
  got
}

///|
pub fn NativeView::pause(self : NativeView) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 2, 0.0)
  }
}

///|
/// To `ms` into it, exactly: the frame showing then (a frame's start, to the µs, shows that frame: Android's host
/// gives Media3 whole ms, floored, and it shows the first frame from there; Apple's seeks to the µs).
pub fn NativeView::seek(self : NativeView, ms : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 3, ms)
    self.info[1].set(ms)
  }
}

///|
/// To about `ms` in, at once: the nearest point the player can show without working through the frames before it (a
/// key frame: Android's CLOSEST_SYNC, Apple's seek with any tolerance), for a jump (±15 s, a tap on the timeline) where
/// the very frame does not matter and waiting for it would; `seek` goes to the very frame.
pub fn NativeView::seek_near(self : NativeView, ms : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 11, ms)
    self.info[1].set(ms)
  }
}

///|
/// A finger along its timeline (`on`), until it is let go (`false`): its seeks come one after another, each shown
/// before the next is taken up and those asked meanwhile skipped but the last, its sound off meanwhile (Android: Media3's
/// scrubbing mode; Apple's host takes its seeks one at a time always). Without it each seek gives up the one before,
/// and while the finger moves no frame shows.
pub fn NativeView::scrub(self : NativeView, on : Bool) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 9, if on { 1.0 } else { 0.0 })
  }
}

///|
/// How loud it plays, 0 (none) to 1 (as it is): a host with no say over it (a page's) plays it as it is.
pub fn NativeView::volume(self : NativeView, volume : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 10, volume)
  }
}

///|
/// Played at `rate` times its speed.
pub fn NativeView::rate(self : NativeView, rate : Double) -> Unit {
  if self.id != 0 && !self.closed {
    h_view_control(self.id, 4, rate)
  }
}

///|
/// -1 failed (or no such view here), -2 a player's format unsupported, -3 its file not parseable, -4 unsupported or
/// damaged, 0 opening, 1 ready.
pub fn NativeView::state(self : NativeView) -> Int {
  self.state.get()
}

///|
/// Its host's number for it (what a Tester's view_reads and set_player take, and its views() lines say); 0 before the
/// host opened it.
pub fn NativeView::id(self : NativeView) -> Int {
  self.id
}

///|
/// Its length in ms (-1 not known yet).
pub fn NativeView::duration(self : NativeView) -> Double {
  self.info[0].get()
}

///|
/// Where it is, in ms.
pub fn NativeView::position(self : NativeView) -> Double {
  self.info[1].get()
}

///|
pub fn NativeView::playing(self : NativeView) -> Bool {
  self.info[2].get() > 0.0
}

///|
/// The picture's own size in pixels ((0, 0) until known).
pub fn NativeView::natural(self : NativeView) -> (Double, Double) {
  (self.info[3].get(), self.info[4].get())
}

///|
/// The bytes it has been given.
pub fn NativeView::bytes(self : NativeView) -> Double {
  self.info[5].get()
}

///|
/// Whether a frame has been drawn (a page: it has loaded).
pub fn NativeView::shown(self : NativeView) -> Bool {
  self.info[6].get() > 0.0
}

///|
/// Whether its host said it is done opening it (a page: its content ready to be drawn, WebView's visual state;
/// failed too), the event the app's run waits on as the host works (hostcall.mbt's outside_view): later than
/// `state` (a page: loaded)
pub fn NativeView::host_done(self : NativeView) -> Bool {
  views_told.contains(self.id)
}

///|
pub fn NativeView::buffering(self : NativeView) -> Bool {
  self.info[7].get() > 0.0
}

///|
/// How far on it has what it needs to play, in ms (its position when the host does not say).
pub fn NativeView::buffered(self : NativeView) -> Double {
  let ahead = self.info[8].get()
  if ahead > 0.0 {
    ahead
  } else {
    self.info[1].get()
  }
}

///|
/// Whether it has played to its end (and stopped there).
pub fn NativeView::ended(self : NativeView) -> Bool {
  self.info[9].get() > 0.0
}

///|
/// Where `v` shows: a node of `w` × `h` (filling its parent by default), the view's content at `content` within it
/// (x, y, w, h from the node's top left; the whole node when None: a video's picture is stretched to it), seen only
/// inside the node and whatever clips it, its content's corners round by `radius` (points: a page laid out as a
/// phone's screen, its screen's corners; the host cuts the view itself, the canvas's hole is as round), or each its own
/// by `corners` (top left, then round it: a page alone in a panel, each corner concentric with the panel's there).
/// What is painted after it draws over it.
pub fn Ctx::native(
  self : Ctx,
  v : NativeView,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  content? : (Double, Double, Double, Double)? = None,
  radius? : Double = 0.0,
  corners? : (Double, Double, Double, Double),
) -> Int {
  let i = self.box(w~, h~, fn() {  })
  let n = self.nodes[i]
  n.kind = kind_native
  let r = match corners {
    Some((r0, r1, r2, r3)) => FixedArray::from_array([dmax(r0, 0.0), dmax(r1, 0.0), dmax(r2, 0.0), dmax(r3, 0.0)])
    None => FixedArray::make(4, dmax(radius, 0.0))
  }
  native_nodes[i] = (v, content, r)
  // (a view of the system's, placed where it is each frame: a part kept builds it each frame, kept_part.mbt)
  part_live()
  i
}

///|
/// The native views' nodes the last build made, by their index in the pool: the view, where its content is, its
/// corners (top left, then round it).
let native_nodes : Map[Int, (NativeView, (Double, Double, Double, Double)?, FixedArray[Double])] = Map([])

///|
fn Ctx::paint_native(self : Ctx, i : Int, n : Node) -> Unit {
  // (a shot shows no native view: it is the window's, where the page has it)
  if shooting.val {
    return
  }
  let (v, content, radii) = match native_nodes.get(i) {
    Some(x) => x
    None => return
  }
  if v.closed || v.id == 0 {
    return
  }
  let (x, y, w, h) = match content {
    Some((cx, cy, cw, ch)) => (n.x + cx, n.y + cy, cw, ch)
    None => (n.x, n.y, n.fw, n.fh)
  }
  // seen within the node and the clip it is painted in, as that shows (not a recording's band: clip_shown)
  let ((cx0, cy0, cx1, cy1), _) = clip_shown()
  let x0 = dmax(n.x, cx0)
  let y0 = dmax(n.y, cy0)
  let x1 = dmin(n.x + n.fw, cx1)
  let y1 = dmin(n.y + n.fh, cy1)
  if x1 <= x0 || y1 <= y0 {
    return
  }
  // where it shows: where the content is, within that, on whole device pixels (no edge row half covered)
  let snap = fn(v : Double) { device_px(v, self.scale) }
  let hx0 = snap(dmax(x, x0))
  let hy0 = snap(dmax(y, y0))
  let hx1 = snap(dmin(x + w, x1))
  let hy1 = snap(dmin(y + h, y1))
  let cx = snap(x)
  let cy = snap(y)
  let cw = snap(x + w) - cx
  let ch = snap(y + h) - cy
  if hx1 > hx0 && hy1 > hy0 && cw > 0.0 && ch > 0.0 {
    // round: the content's own rounded rect, cut by the clips it is painted in (its corners where the content's are,
    // not where the clip cuts it)
    let radius = dmax(dmax(radii[0], radii[1]), dmax(radii[2], radii[3]))
    let round = radius > 0.0
    let (sx, sy, sw, sh) = if round {
      (cx, cy, cw, ch)
    } else {
      (hx0, hy0, hx1 - hx0, hy1 - hy0)
    }
    // (its image the view's, the part of its content there: a host that draws the view's picture draws that)
    self.push_inst(
      sx,
      sy,
      sw,
      sh,
      radius,
      9.0,
      0.0,
      0.0,
      0xFFFFFFFFL,
      1.0,
      (sx - cx) / cw,
      (sy - cy) / ch,
      sw / cw,
      sh / ch,
    )
    self.corners_last_each(radii[0], radii[1], radii[2], radii[3])
    self.inst[(self.ninst - 1) * inst_size + 20] = (@hostapi.view_tex_base + v.id).to_double()
    v.hole[0] = sx
    v.hole[1] = sy
    v.hole[2] = sw
    v.hole[3] = sh
  } else {
    v.hole[2] = 0.0
  }
  // (by build: a frame built again paints again, and what the last build did not paint is not shown)
  v.painted = self.build_no
  v.seq = self.ninst
  // (where it is among the frame's targets: what is over it after it, its covers; found with them where they are found
  // alone, Ctx::node_targets)
  if !dr.targets_said {
    v.hits_before = self.next_hit_ids.length()
    v.island = None
  }
  // (its content on whole device pixels too, as where it shows is: placed between pixels, the row its edge half
  // covers shows what is under the canvas, a line along the picture's edge)
  v.at[0] = cx
  v.at[1] = cy
  v.at[2] = cw
  v.at[3] = ch
  v.at[4] = snap(x0)
  v.at[5] = snap(y0)
  v.at[6] = snap(x1)
  v.at[7] = snap(y1)
  for k in 0..<4 {
    v.at[8 + k] = radii[k]
  }
}

///|
/// `v` (points) on the nearest whole device pixel at `scale` device pixels a point (a Mac's 2, a phone's 3, an
/// Android's 2.625): where a native view, its clip and the hole it shows through are all put, the one rule for all
/// of them, so that their edges meet on the same pixel (none half covered, showing what is under the canvas).
fn device_px(v : Double, scale : Double) -> Double {
  (v * scale).round() / scale
}

///|
/// The views whose host said how they stand changed (outside_stood), not read yet: read as the next frame begins.
let views_stirred : Array[Int] = []

///|
// kept across runs: scratch the host writes into before each read, read at once: nothing is carried in it
let info_out : FixedArray[Double] = FixedArray::make(10, 0.0)

///|
/// How it stands, read of its host now into its signals: what reads them told where it changed.
fn NativeView::stood(self : NativeView) -> Unit {
  if self.closed || self.id == 0 {
    return
  }
  let state = h_view_info(self.id, info_out)
  @signals.start_batch()
  for k in 0..<self.info.length() {
    self.info[k].set(info_out[k])
  }
  self.state.set(state)
  @signals.end_batch()
}

///|
/// Its host said how view `id` stands changed (hostcall.mbt's outside_stood): a frame, which reads it as it begins.
fn view_stood(id : Int) -> Unit {
  if !views_stirred.contains(id) {
    views_stirred.push(id)
  }
  h_frame_owed()
}

///|
/// As a frame begins, before it is decided what it does again (frame_watch.mbt): each view whose host said how it
/// stands changed read of it (its signals set: what reads them is built again).
fn views_arrive() -> Unit {
  // (a Tester's fake pages run what was sent to them once they are there, as a frame begins)
  match fake.val {
    Some(f) => for v in open_views { fake_scripts_flush(f, v.id) }
    None => ()
  }
  if views_stirred.is_empty() {
    return
  }
  let ids = views_stirred.copy()
  views_stirred.clear()
  for v in open_views {
    if ids.contains(v.id) {
      v.stood()
    }
  }
}

///|
/// After a frame is painted: each open view placed where it was painted (hidden where it was not), and the reads its
/// player waits on handed to its `read`.
fn Ctx::sync_views(self : Ctx) -> Unit {
  if open_views.length() == 0 {
    return
  }
  self.follow_holes()
  self.stack_views()
  for v in open_views.copy() {
    if v.closed {
      continue
    }
    let shown = v.painted == self.build_no
    let z = window_zoom_drawn.val
    let mut moved = shown != v.told_shown || z != v.told_zoom
    if z != v.told_zoom && v.touch != All {
      h_view_tell(v.id, 2, "\{touch_name(v.touch)} \{touch_slop() * z}")
    }
    if (v.kind == 2 || v.kind == 3) && v.told_page_scale != v.scale * z {
      v.told_page_scale = v.scale * z
      h_view_control(v.id, 8, v.told_page_scale)
    }
    if shown {
      for j in 0..<12 {
        if (v.at[j] - v.told[j]).abs() > 0.01 {
          moved = true
        }
      }
    }
    if shown {
      v.tell_covers(self)
    }
    if moved {
      for j in 0..<12 {
        v.told[j] = v.at[j]
      }
      v.told_shown = shown
      v.told_zoom = z
      // on a run's log (MBUI_DRAW_LOG): where it was told to go, in device pixels, for the host's own saying where it
      // put it (VIEWAT) to be compared with (scripts/host_contract.sh HOST views): its rect, its clip, its roundest
      // corner, then each corner (top left, then round it)
      if draw_logging() && fake.val is None && shown {
        let px = StringBuilder()
        let most = dmax(dmax(v.at[8], v.at[9]), dmax(v.at[10], v.at[11]))
        for x in [v.at[0], v.at[1], v.at[2], v.at[3], v.at[4], v.at[5], v.at[6], v.at[7], most, v.at[8], v.at[9], v.at[10], v.at[11]] {
          px.write_string(" " + (x * self.scale).to_string())
        }
        h_log("VIEWTOLD \{v.id}" + px.to_string())
      }
      h_view_place(
        v.id,
        v.at[0],
        v.at[1],
        v.at[2],
        v.at[3],
        v.at[4],
        v.at[5],
        v.at[6],
        v.at[7],
        v.at[8],
        v.at[9],
        v.at[10],
        v.at[11],
        shown,
      )
    }
    if v.serve is Some(_) || v.said is Some(_) {
      v.take_site()
    }
    v.take_reads()
  }
}

///|
/// The reads its player waits on handed to its `read` (and those it let go of stopped): after a frame is painted, and
/// as its host says it waits on the app (hostcall.mbt's outside_view, 0), which it does with no frame coming too (the
/// app's window off the screen: a player still reading ahead, or playing a song, is not left waiting until it shows).
fn NativeView::take_reads(self : NativeView) -> Unit {
  let v = self
  if v.closed {
    return
  }
  match v.read {
    Some(read) =>
      for _ in 0..<64 {
        let req = h_view_read_next(v.id, read_out)
        if req == 0 {
          break
        }
        // one the player let go of: stopped, its answers taken no more
        if req < 0 {
          match v.reading.get(-req) {
            Some(stop) => {
              v.reading.remove(-req)
              stop()
            }
            None => ()
          }
          continue
        }
        let id = v.id
        // (answered to its end, or let go of: nothing more of it handed on)
        let ended = Ref(false)
        let gone = Ref(false)
        let stop = read(read_out[0], read_out[1].to_int(), fn(data, total, more) {
          if ended.val || gone.val || v.closed {
            return
          }
          if !more {
            ended.val = true
            v.reading.remove(req)
          }
          h_view_read_answer(id, req, data, total, more)
        })
        if !ended.val {
          v.reading[req] = fn() {
            gone.val = true
            stop()
          }
        }
      }
    None => ()
  }
}

///|
/// The views shown this frame stacked on the host as they were painted, the one painted last on top: where a later
/// one's hole shows, that view is seen, not another one under the canvas there (a file's page opened over a chat with
/// a visualization in it, the chat still painted under the page). Hosts that keep their views under the canvas stack
/// them in the order they were opened (or first placed), which is not the order they are painted in once one is opened
/// while another shows, or one comes back into view under another. Each shown view is raised to the top in turn
/// (`view_tell` 5) when the order of those shown is not the one told last; one alone is over nothing.
fn Ctx::stack_views(self : Ctx) -> Unit {
  let shown = open_views.filter(fn(v) { !v.closed && v.id != 0 && v.painted == self.build_no })
  shown.sort_by_key(fn(v) { v.seq })
  let ids = shown.map(fn(v) { v.id })
  if ids == stacked_views {
    return
  }
  stacked_views.clear()
  stacked_views.push_iter(ids.iter())
  if ids.length() < 2 {
    return
  }
  for v in shown {
    h_view_tell(v.id, 5, "")
  }
  // on a run's log (MBUI_DRAW_LOG): the order told, for the host's own saying how it stacked them (VIEWSTACK) to be
  // compared with (scripts/host_contract.sh HOST views)
  if draw_logging() && fake.val is None {
    h_log("VIEWSTACKTOLD " + ids.map(fn(id) { id.to_string() }).join(" "))
  }
}

///|
/// Each view painted this frame put where its hole ended up: what was painted is moved after (a look on what holds it,
/// as a list's rows sliding while words sent fly; a row drawn again lower), its hole with it; the view, placed where its
/// node was laid out, stayed there, out of step with its hole. The hole's move (and scale) taken to the view's content
/// and clip, the clip cut by where the hole's own clip was taken.
fn Ctx::follow_holes(self : Ctx) -> Unit {
  let at : Map[Int, Int] = {}
  let a = self.inst
  for k in 0..<self.ninst {
    let b = k * inst_size
    if a[b + 5] == 9.0 {
      at[a[b + 20].to_int() - @hostapi.view_tex_base] = b
    }
  }
  if at.is_empty() {
    return
  }
  for v in open_views {
    if v.closed || v.painted != self.build_no || v.hole[2] <= 0.0 || v.hole[3] <= 0.0 {
      continue
    }
    let b = match at.get(v.id) {
      Some(b) => b
      None => continue
    }
    let (kx, ky) = (a[b + 2] / v.hole[2], a[b + 3] / v.hole[3])
    let (bx, by) = (a[b] - kx * v.hole[0], a[b + 1] - ky * v.hole[1])
    if kx == 1.0 && ky == 1.0 && bx == 0.0 && by == 0.0 {
      continue
    }
    v.at[0] = kx * v.at[0] + bx
    v.at[1] = ky * v.at[1] + by
    v.at[2] = kx * v.at[2]
    v.at[3] = ky * v.at[3]
    v.at[4] = dmax(kx * v.at[4] + bx, a[b + 16])
    v.at[5] = dmax(ky * v.at[5] + by, a[b + 17])
    v.at[6] = dmin(kx * v.at[6] + bx, a[b + 18])
    v.at[7] = dmin(ky * v.at[7] + by, a[b + 19])
    for k in 8..<12 {
      v.at[k] = v.at[k] * dmin(kx, ky)
    }
  }
}

///|
/// The most rects of presses over a view the host is told (`covers`).
let covers_most : Int = 32

///|
/// Where what takes a press is drawn over the view (painted after it: a menu, a panel raised over the page, its
/// ground that puts it away, a bar's button over a page scrolled under it): a finger there is the canvas's, not the
/// page's, as the app's own presses go to what is on top. The host is told them as they change (view_tell 4: "x0 y0
/// x1 y1 …" in points, the window's; "" none), each cut to where the view is seen.
fn NativeView::tell_covers(self : NativeView, c : Ctx) -> Unit {
  let v = self
  let seen = (v.at[4], v.at[5], v.at[6], v.at[7])
  let over : Array[(Double, Double, Double, Double)] = []
  let tree = view_app.val
  // (in the window's tree: where the node hosting its old view takes no finger, all of it the tree's (a modal layer of
  // the tree's over it, the node leaving, said to take none or only some of it): Tree::finger_areas)
  match (tree, v.island) {
    (Some(t), Some(h)) =>
      match t.finger_areas(h) {
        InWindow(rs) => over.append(rects_less(seen, rs))
        AsItHosts => ()
      }
    _ => ()
  }
  // (what of the old views' takes a press after it: each where the node hosting its old view takes a finger, where it
  // is drawn, as big: painted where it is laid out, placed as its targets are, old_hits_moved)
  let rects = c.next_hit_rects
  for j in v.hits_before..<c.next_hit_ids.length() {
    let r = (rects[j * 4], rects[j * 4 + 1], rects[j * 4 + 2], rects[j * 4 + 3])
    let island = next_old_hits.iter().find_first(fn(o) { j >= o.from && j < o.to })
    let r = match island {
      Some(o) => {
        let (at_x, at_y, on, _) = old_hits_moved(c, o, tree)
        if on {
          (at_x(r.0), at_y(r.1), at_x(r.2), at_y(r.3))
        } else {
          (0.0, 0.0, 0.0, 0.0)
        }
      }
      None => r
    }
    let held = match (tree, island) {
      (Some(t), Some(o)) => Some(t.finger_areas(o.id))
      _ => None
    }
    match held {
      Some(InWindow(rs)) => for a in rs { over.push(rect_meet(r, a)) }
      _ => over.push(r)
    }
  }
  // (what of the tree's own takes a finger drawn over the node hosting it: Tree::taken_over)
  match (tree, v.island) {
    (Some(t), Some(h)) => over.append(t.taken_over(h))
    _ => ()
  }
  let out = StringBuilder()
  let mut n = 0
  for r in over {
    if n >= covers_most {
      break
    }
    let (x0, y0, x1, y1) = rect_meet(r, seen)
    if x1 > x0 && y1 > y0 {
      if n > 0 {
        out.write_string(" ")
      }
      let z = window_zoom_drawn.val
      out.write_string("\{x0 * z} \{y0 * z} \{x1 * z} \{y1 * z}")
      n += 1
    }
  }
  let said = out.to_string()
  if said != v.told_covers {
    v.told_covers = said
    h_view_tell(v.id, 4, said)
  }
}

///|
/// Where rects `a` and `b` (x0, y0, x1, y1) meet (empty: x1 <= x0 or y1 <= y0).
fn rect_meet(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
) -> (Double, Double, Double, Double) {
  (dmax(a.0, b.0), dmax(a.1, b.1), dmin(a.2, b.2), dmin(a.3, b.3))
}

///|
/// What of rect `a` none of `cut` is over, as rects (x0, y0, x1, y1).
fn rects_less(
  a : (Double, Double, Double, Double),
  cut : Array[(Double, Double, Double, Double)],
) -> Array[(Double, Double, Double, Double)] {
  let mut left = [a]
  for k in cut {
    let next = []
    for r in left {
      let (x0, y0, x1, y1) = rect_meet(r, k)
      if x1 <= x0 || y1 <= y0 {
        next.push(r)
        continue
      }
      // (what is above it, below it, then beside it between those)
      for p in [(r.0, r.1, r.2, y0), (r.0, y1, r.2, r.3), (r.0, y0, x0, y1), (x1, y0, r.2, y1)] {
        if p.2 > p.0 && p.3 > p.1 {
          next.push(p)
        }
      }
    }
    left = next
  }
  left
}

///|
/// What a page's or a site's host has said since the last frame, in the order said: what its page said to the app
/// (`said`), requests handed to `serve`, requests let go, answered late or read too slowly, links left by; where its
/// page is now.
fn NativeView::take_site(self : NativeView) -> Unit {
  let v = self
  let mut heard = false
  for _ in 0..<64 {
    let said = h_view_site_next(v.id)
    if said == "" {
      break
    }
    let e = @json.parse(said) catch { _ => continue }
    let num = fn(k : String) -> Int {
      match e {
        Object(m) =>
          match m.get(k) {
            Some(Number(n, ..)) => n.to_int()
            _ => -1
          }
        _ => -1
      }
    }
    let str = fn(k : String) -> String {
      match e {
        Object(m) =>
          match m.get(k) {
            Some(String(x)) => x
            _ => ""
          }
        _ => ""
      }
    }
    match e {
      Object(m) if m.get("said") is Some(String(words)) => {
        heard = true
        match v.said {
          Some(f) => f(words)
          None => ()
        }
        continue
      }
      _ => ()
    }
    let gone = num("gone")
    if gone >= 0 {
      match v.replies.get(gone) {
        Some(r) => {
          r.gone = true
          v.replies.remove(gone)
          (r.on_gone)()
        }
        None => ()
      }
      continue
    }
    // no head in site_head_wait_ms: answered with the app's words for it; read too slowly: stopped with them; either
    // way let go (what the app asks for it stopped)
    let late = num("late")
    let slow = num("slow")
    if late >= 0 || slow >= 0 {
      let req = if late >= 0 { late } else { slow }
      match v.replies.get(req) {
        Some(r) if !r.ended && !r.gone => {
          if late >= 0 && !r.headed {
            r.head(502, [("Content-Type", "text/plain; charset=utf-8")])
            r.chunk(@utf8.encode(v.no_answer))
            r.end()
          } else if slow >= 0 {
            r.end(error=v.too_slow)
          }
          if r.ended {
            r.gone = true
            v.replies.remove(req)
            (r.on_gone)()
          }
        }
        _ => ()
      }
      continue
    }
    match e {
      Object(m) if m.contains("leave") => {
        (v.leave)(str("leave"))
        continue
      }
      _ => ()
    }
    let req = num("req")
    if req < 0 {
      continue
    }
    let headers : Array[(String, String)] = []
    match e {
      Object(m) =>
        match m.get("headers") {
          Some(Array(hs)) =>
            for h in hs {
              match h {
                Array([String(k), String(x)]) => headers.push((k, x))
                _ => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
    let page = match e {
      Object(m) => m.get("page") is Some(True)
      _ => false
    }
    let serve = match v.serve {
      Some(f) => f
      None => continue
    }
    let reply : SiteReply = { view: v.id, req, headed: false, ended: false, gone: false, on_gone: fn() {  } }
    v.replies[req] = reply
    let body = if str("method") == "GET" || str("method") == "HEAD" {
      Bytes::new(0)
    } else {
      h_view_site_body(v.id, req)
    }
    serve({ verb: str("method"), path: str("path"), headers, page, body }, reply)
  }
  // what the page said comes as an input does: the next frames the framework's
  if heard {
    input_came()
  }
  // ended replies kept no longer
  let done = []
  for k, r in v.replies {
    if r.ended {
      done.push(k)
    }
  }
  for k in done {
    v.replies.remove(k)
  }
  let st = h_view_site_state(v.id)
  if st != "" {
    match (try Some(@json.parse(st)) catch { _ => None }) {
      Some(Object(m)) => {
        let flag = fn(k : String) { m.get(k) is Some(True) }
        let was = (v.path, v.can_back, v.can_forward, v.loading, v.title)
        match m.get("path") {
          Some(String(p)) if p != "" => v.path = p
          _ => ()
        }
        v.keeps_cookies = flag("cookies")
        v.can_back = flag("back")
        v.can_forward = flag("forward")
        v.loading = flag("loading")
        match m.get("title") {
          Some(String(t)) => v.title = t
          _ => ()
        }
        if was != (v.path, v.can_back, v.can_forward, v.loading, v.title) {
          g().read_changed("view \{v.id}'s page (where it is, its title, whether it loads)")
        }
      }
      _ => ()
    }
  }
}

// ── PDFs ───────────────────────────────────────────────────────────────

///|
/// A PDF the host draws (host_native.mbt pdf_*).
pub struct Pdf {
  priv doc : Int
  /// how many pages (-1: it could not be opened, or this host draws none)
  pages : Int
  /// each page's size in points
  sizes : Array[(Double, Double)]
}

///|
// kept across runs: scratch the host writes into before each read, read at once: nothing is carried in it
let pdf_out : FixedArray[Double] = FixedArray::make(2, 0.0)

///|
/// The PDF in `data`, opened.
pub fn Pdf::open(data : Bytes) -> Pdf {
  let doc = h_pdf_open(data)
  let pages = if doc == 0 { -1 } else { h_pdf_pages(doc) }
  let sizes = []
  for p in 0..<pages {
    h_pdf_page_size(doc, p, pdf_out)
    sizes.push((pdf_out[0], pdf_out[1]))
  }
  { doc, pages, sizes }
}

///|
/// The source `Ctx::image` shows page `page` (from 0) by: drawn at the size it is shown at.
pub fn Pdf::page_src(self : Pdf, page : Int) -> String {
  "pdf:\{self.doc}/\{page}"
}

///|
/// Let go: its pages' images are dropped too.
pub fn Pdf::close(self : Pdf) -> Unit {
  if self.doc == 0 {
    return
  }
  let prefix = "pdf:\{self.doc}/"
  let gone = []
  for src, list in image_cache {
    if src.has_prefix(prefix) {
      for e in list {
        h_image_free(e.id)
      }
      gone.push(src)
    }
  }
  for src in gone {
    image_cache.remove(src)
    image_forget(src)
  }
  h_pdf_close(self.doc)
}

///|
/// A page's image, `src` being "pdf:<doc>/<page>": its id, as an image's load gives.
fn pdf_page_load(src : String, max_px : Int) -> Int {
  let rest = src.unsafe_substring(start=4, end=src.length())
  let parts = rest.split("/").map(fn(s) { s.to_owned() }).to_array()
  if parts.length() != 2 {
    return 0
  }
  match (digits(parts[0]), digits(parts[1])) {
    (Some(doc), Some(page)) => h_pdf_page_load(doc, page, max_px)
    _ => 0
  }
}

///|
/// A whole number written in digits.
fn digits(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for ch in s {
    let d = ch.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      return None
    }
    n = n * 10 + d
  }
  Some(n)
}

// ── a picture at a rect of its own ─────────────────────────────────────

///|
/// The rects pictures are drawn at, by node, as the last build said.
let picture_at : Map[Int, (Double, Double, Double, Double, Int)] = Map([])

///|
/// The image from `src` drawn stretched to (x, y, w, h) from the top left of a node filling its parent (or `w_` ×
/// `h_`), which may be bigger than the node (zoomed in): only what is inside the clip it is painted in shows. Loaded at
/// the size it is drawn, at most `max_px` on its longer side. `bg` stands in until decoded; with `matte` it is also
/// composited under the picture, within the node, before its edge is cut, as for image.
pub fn Ctx::picture(
  self : Ctx,
  src : String,
  x~ : Double,
  y~ : Double,
  w~ : Double,
  h~ : Double,
  w_? : Size = Fill(1.0),
  h_? : Size = Fill(1.0),
  max_px? : Int = 4096,
  bg? : Int64 = 0L,
  matte? : Bool = false,
) -> Int {
  let i = self.image(src, w=w_, h=h_, fit=FitFill, bg~, fade=false, matte~)
  let at = (x, y, w, h, max_px)
  picture_at[i] = at
  // (said again of its node where what built it is kept, its nodes put back elsewhere among the frame's: a part or a
  // row holding a picture kept as any other, not built every frame for it)
  built_again(fn(by) { picture_at[i + by] = at })
  i
}

// ── a box that takes the pointer as its own ────────────────────────────

///|
/// Boxes that take the pointer as their own (`capture`): what is under them (a list) is not dragged or wheeled,
/// their own drags are not taken for a list's, and the wheel over them is theirs (`wheel`).
let captures : Map[Int, Bool] = Map([])

///|
let wheels : Map[Int, Double] = Map([])

///|
/// The wheel's sideways part over a box that keeps it, and what was held with it last.
let wheels_x : Map[Int, Double] = Map([])

///|
let wheel_mods : Map[Int, Int] = Map([])

///|
/// What a wheel came with (`wheel_of`'s third): ⇧, ⌃, ⌥, ⌘ held, and a trackpad's pinch (a wheel with ⌃, as a browser
/// gives a pinch: a page zooms by it, no list scrolls).
pub let wheel_mod_shift : Int = 1

///|
pub let wheel_mod_ctrl : Int = 2

///|
pub let wheel_mod_alt : Int = 4

///|
pub let wheel_mod_cmd : Int = 8

///|
pub let wheel_mod_pinch : Int = 16

///|
/// The box of `id` (given to it this frame) takes the pointer: a finger dragging on it keeps it pressed (`pressed`,
/// `pointer`: a pan), nothing under it scrolls, and the wheel over it is kept for `wheel`.
pub fn capture(c : Ctx, id : Int) -> Unit {
  ignore(c)
  captures[id] = true
}

///|
/// What the wheel moved over `id` since last asked (its dy, as a list would scroll by it).
pub fn wheel(c : Ctx, id : Int) -> Double {
  ignore(c)
  wheels_x.remove(id)
  wheel_mods.remove(id)
  match wheels.get(id) {
    Some(d) => {
      wheels.remove(id)
      d
    }
    None => 0.0
  }
}

///|
/// What the wheel moved over `id` since last asked, both ways (dx, dy, as a list would scroll by them), and what was
/// held with it last (wheel_mod_*): a picture pans by it, and zooms with ⌃ or ⌘ (or a pinch).
pub fn wheel_of(c : Ctx, id : Int) -> (Double, Double, Int) {
  ignore(c)
  let dx = wheels_x.get(id).unwrap_or(0.0)
  let dy = wheels.get(id).unwrap_or(0.0)
  let mods = wheel_mods.get(id).unwrap_or(0)
  wheels.remove(id)
  wheels_x.remove(id)
  wheel_mods.remove(id)
  (dx, dy, mods)
}

///|
/// How an image shown from `src` stands: 1 one of its decodes is ready, -1 it could not be decoded, 0 not yet.
pub fn image_state(src : String) -> Int {
  // (followed: as the host says a decode of it is ready, or failed)
  image_decodes_read(src)
  match image_cache.get(src) {
    Some(list) => {
      let mut failed = list.length() > 0
      // (as the host's words have said it, at their moments: image_decoded)
      for e in list {
        if e.state == 1 {
          return 1
        }
        if e.state != -1 {
          failed = false
        }
      }
      if failed {
        -1
      } else {
        0
      }
    }
    None => 0
  }
}

///|
/// The size in pixels of the image shown from `src`, once a decode of it is ready.
pub fn image_natural(src : String) -> (Double, Double)? {
  image_size(src)
}

///|
/// A line on the host's log (a test's fake host keeps it).
pub fn log(s : String) -> Unit {
  h_log(s)
}

// ── a second finger ────────────────────────────────────────────────────

///|
/// The second finger on a touch screen: x, y, down (1) (hosts that have one send it as pointer kinds 4, 5, 6).
let second_ptr : FixedArray[Double] = FixedArray::make(3, 0.0)

///|
fn on_second(kind : Int, x : Double, y : Double) -> Unit {
  second_ptr[0] = x
  second_ptr[1] = y
  second_ptr[2] = if kind == 6 { 0.0 } else { 1.0 }
}

///|
/// A second finger, while one is down beside the first (a pinch): where it is.
pub fn Ctx::second_pointer(self : Ctx) -> (Double, Double)? {
  // (read so: a second finger's are the hand's events, hand.mbt)
  hand.down.get() |> ignore
  hand_presses_read()
  if self.down && second_ptr[2] > 0.0 {
    Some((second_ptr[0], second_ptr[1]))
  } else {
    None
  }
}
