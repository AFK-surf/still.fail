// One view of a station's screen (ember apps/android app/remote/ScreenSession.kt; docs/remote-screens.md, docs/client-core.md
// `screen.view`): the core's call kept open while the viewer is in sight, its values taken apart (the state, a config,
// frames with their bytes), frames handed to the decoder (@ui.Stream: H.264 or JPEG, drawn as the picture the viewer
// shows), each acknowledged once shown (the stream says so) or dropped; input, 只看/控制 and key frames told back to
// the core. While it drives the screen, the screen's clipboard goes both ways (a copy made on it comes as a `{clipboard}`
// value, `screen.clipboard` pastes) and files picked go onto its machine (screen_drops.mbt). Zoomed in, the part of the
// screen shown is told (`screen.look`): the station then sends that part alone, as sharp as this device shows it, each
// config saying which part. Its frames go to a decoder of their own (`part`), drawn over the whole screen's last picture
// where the part is, while its picture is newer than the whole's: so a part's frame shows only once one has come, and
// the whole again only once the whole's has. The connection, the credentials and the reconnecting are the core's; this
// only draws what it says.

///|
/// Where a file dropped into the view goes on the screen's machine (ScreenDrop): the folder, and whether the view can
/// show it there in the machine's file manager.
priv struct DropTo {
  folder : String
  reveal : Bool
} derive(Eq)

///|
/// A part of the screen (0..1 of its width and height): its left, top, width, height.
priv struct Part {
  x : Double
  y : Double
  w : Double
  h : Double
} derive(Eq)

///|
/// A config's part of the screen (`region`), when it says one.
fn part_of(v : Json?) -> Part? {
  match field(v, "region") {
    Some(Object(_)) as r => {
      let p : Part = { x: number(r, "x"), y: number(r, "y"), w: number(r, "w"), h: number(r, "h") }
      if p.w > 0.0 && p.h > 0.0 {
        Some(p)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// A copy made on the screen, for the device's clipboard (ScreenClips.kt Copied): its text, or its PNG.
priv enum Copied {
  CopiedText(String)
  CopiedPng(Bytes)
}

///|
/// A view of `screen` on `station` (its address, `<workspace>/<station>`), kept while its page is in the stack.
priv struct ScreenSess {
  /// where it reads and writes
  src : Source
  station : String
  screen : String
  /// the name the core knows this view by (unique among this app's views)
  view : String
  /// the core's latest state of the view (ScreenViewState, whole each time); None before the first
  mut state : Json?
  /// each state taken that changed more than where the pointer drawn on a picture's layer points (ScreenSess::take):
  /// what the page reads of the state is built again for it, however it was taken
  said : @signals.Signal[Int]
  /// the pointer as the last build had it drawn: on a picture's system video layer by its host (moved there as the
  /// station's pointer moves, nothing built for it: ScreenSess::pointer_moved), or None here, by the app
  mut pointer_layer : PointerLayer?
  /// the call failed (the core said why), rather than the view ending
  failure : @signals.Signal[String?]
  /// the call answered: the view ended (the last state says why)
  finished : @signals.Signal[Bool]
  /// the frames' codec and size, from the latest config
  mut audio_ready : Bool
  mut audio_muted : Bool
  mut codec : String?
  mut size : (Int, Int)?
  /// something was shown since it opened: a frame kept on screen through a reconnect or an end
  mut shown_any : Bool
  /// 控制 (true) or 只看 as the person chose; None until they do: the core opens it in 只看 while someone else (an
  /// agent at work) drives it, else in 控制, so opening a screen never takes it from whoever is on it
  mut wants_control : Bool?
  /// a finger drives it as a trackpad (true) or directly, as chosen here before the prefs say
  mut pad_set : Bool?
  /// the stage it is laid out for (its width and height, and this device's pixels to a point), on a phone or a tablet:
  /// a page of the station's browser is laid out as this device's own browser would; None: as it is
  mut fit : (Double, Double, Double)?
  /// the open call (the core's id of it); 0 while it is not open
  mut call : Int
  /// the last frame acknowledged
  mut acked : Double
  /// the decoder the frames go to, and the picture it shows (made as the view first opens: own_stream)
  mut stream : @ui.Stream?
  /// the decoder a part's frames go to (made as the first part's config comes), its codec; whether the frames now
  /// coming are a part's; the part the next frame shows (from its config), and the part each of its frames shows from
  /// (by the time of the first), oldest first
  mut part : @ui.Stream?
  mut part_codec : String?
  mut parting : Bool
  mut part_next : Part?
  parts : Array[(Double, Part)]
  /// the part of the screen last told the core (`screen.look`): "" the whole
  mut looked : String
  /// the copies made on the screen not yet put on the device's clipboard (the viewer takes them)
  copied : Array[Copied]
  /// the files picked for its machine (screen_drops.mbt)
  drops : Array[ScreenDropItem]
  mut drops_serial : Int
  mut pumping : Bool
  /// a paste under way
  mut pasting : Bool
  /// the frames that came and their bytes, counted as they come (控制中心's 连接 reads a second's of them)
  mut frames : Int
  mut bytes : Int
  /// the 画质 the open view was asked with (prefs `screenQuality`; "": as this device's screen is), and its 帧率 (prefs
  /// `screenFps`; 0: 自动): another chosen is asked of it (`screen.bounds`)
  mut asked : String
  mut asked_fps : Int
  /// the bounds the open view was asked with (画质's, or 自动's: `stage_px`)
  mut asked_bounds : (Int, Int)
  /// the most device pixels the stage it is shown on has had (0 × 0 before it is laid out): 自动 asks that large
  mut stage_px : (Int, Int)
  /// filling the page's login from this device's password manager (screen_fill.mbt): where it is (`listing`,
  /// `choosing`, `getting`, `said`; "" nothing under way), the run of it under way, the logins to pick from, what it
  /// said where it did not fill, and the site it is for
  fill_step : @signals.Signal[String]
  mut fill_run : @hostapi.OpRun?
  mut fill_choices : Array[@hostapi.PasswordLogin]
  mut fill_note : String
  mut fill_host : String
  /// the login picked in the system's autofill service while the view could take no input (its offer's sign-in took
  /// the app out of sight, which lets the view go): its account and password, sent as the view drives again
  mut fill_owed : (String, String)?
  /// a state heard from the view since it was opened (again): input goes to it only then
  mut heard : Bool
  /// signing the page's passkey sign-in on this device (screen_passkey.mbt): where it is (`asking`, `said`; "" nothing
  /// under way), the ask under way, what it said where it did not sign, and the page's ask it is for
  passkey_step : @signals.Signal[String]
  mut passkey_run : @hostapi.PasskeyRun?
  mut passkey_note : String
  mut passkey_id : String
}

///|
/// The views open, by their page's key (screen_key).
let screens_open : Map[String, ScreenSess] = Map([])

///|
/// How many views this app has opened: each one's name (`mbui-<n>`) its own, the same in every run of the same steps.
let screens_made : Ref[Int] = Ref(0)

///|
/// The frame 自动 asks for before the stage it is shown on is laid out (then as large as the stage is: stage_px).
let screen_max_w : Int = 1920

///|
let screen_max_h : Int = 1080

///|
fn screen_key(station : String, screen : String) -> String {
  station + "\u{1}" + screen
}

///|
/// The view of `screen` on `station`, made the first time its page asks.
fn screen_sess(src : Source, station : String, screen : String) -> ScreenSess {
  let key = screen_key(station, screen)
  match screens_open.get(key) {
    Some(s) => s
    None => {
      screens_made.val += 1
      let s : ScreenSess = {
        src,
        station,
        screen,
        view: "mbui-\{screens_made.val}",
        state: None,
        said: @signals.signal(0),
        pointer_layer: None,
        failure: @signals.signal(None),
        finished: @signals.signal(false),
        audio_ready: false,
        audio_muted: false,
        codec: None,
        size: None,
        shown_any: false,
        wants_control: None,
        pad_set: None,
        fit: None,
        call: 0,
        acked: -1.0,
        stream: None,
        part: None,
        part_codec: None,
        parting: false,
        part_next: None,
        parts: [],
        looked: "",
        copied: [],
        drops: [],
        drops_serial: 0,
        pumping: false,
        pasting: false,
        frames: 0,
        bytes: 0,
        asked: "",
        asked_fps: 0,
        asked_bounds: (0, 0),
        stage_px: (0, 0),
        fill_step: @signals.signal(""),
        fill_run: None,
        fill_choices: [],
        fill_note: "",
        fill_host: "",
        fill_owed: None,
        heard: false,
        passkey_step: @signals.signal(""),
        passkey_run: None,
        passkey_note: "",
        passkey_id: "",
      }
      screens_open[key] = s
      s
    }
  }
}

///|
/// The decoder of a part's frames, made the first time one comes (acknowledged as the whole's are).
fn ScreenSess::part_stream(self : ScreenSess) -> @ui.Stream {
  match self.part {
    Some(st) => st
    None => {
      let st = @ui.Stream::new(
        shown=fn(ts) { screen_ack(self.src, self, ts) },
        broken=fn() { screen_tell(self.src, "screen.keyframe", { "view": Json::string(self.view) }) },
        // on the system's video layer too, over the whole's: a frame of the part shown now shown as it comes, one of
        // another part (or while the whole's shows) built, the picture put where its part is
        layer=true,
        quiet=Some(fn(ts) {
          match self.part_shown() {
            Some(now) => self.part_at(ts) == Some(now)
            None => false
          }
        }),
      )
      self.part = Some(st)
      st
    }
  }
}

///|
/// The part a frame of `ts` of the part's decoder shows (the last begun by then).
fn ScreenSess::part_at(self : ScreenSess, ts : Double) -> Part? {
  let mut at = None
  for p in self.parts {
    if p.0 <= ts {
      at = Some(p.1)
    }
  }
  at
}

///|
/// The part of the screen drawn over the whole now, and where: while the part's decoder shows a frame newer than the
/// whole's, the part that frame shows; else none.
fn ScreenSess::part_shown(self : ScreenSess) -> Part? {
  guard self.part is Some(pst) && pst.shown_at() is Some(at) else { return None }
  match self.stream.bind(fn(st) { st.shown_at() }) {
    Some(whole) if whole >= at => return None
    _ => ()
  }
  let mut shown = None
  for p in self.parts {
    if p.0 <= at {
      shown = Some(p.1)
    }
  }
  shown
}

///|
/// The part of the screen shown (None: the whole), in `w` × `h` of this device's pixels: told the core when it is
/// another than the last told (the core asks the station once it has stayed a moment). The whole is told only after a
/// part was.
fn ScreenSess::look(self : ScreenSess, src : Source, part : Part?, w : Double, h : Double) -> Unit {
  let r4 = fn(v : Double) { (v * 10000.0).round() / 10000.0 }
  let key = match part {
    Some(p) => "\{r4(p.x)} \{r4(p.y)} \{r4(p.w)} \{r4(p.h)} \{w.round()} \{h.round()}"
    None => ""
  }
  if key == self.looked || self.call == 0 {
    return
  }
  self.looked = key
  let region = match part {
    Some(p) =>
      Json::object({
        "x": Json::number(r4(p.x)),
        "y": Json::number(r4(p.y)),
        "w": Json::number(r4(p.w)),
        "h": Json::number(r4(p.h)),
      })
    None => Json::null()
  }
  screen_tell(src, "screen.look", {
    "view": Json::string(self.view),
    "region": region,
    "width": Json::number(w.round()),
    "height": Json::number(h.round()),
  })
}

///|
/// Its picture's stream, made as the view is first opened (screen_page's after_build: what it says once shown, the
/// station's frame taken, a key frame asked for, tells the core, which no build does).
fn ScreenSess::own_stream(self : ScreenSess) -> Unit {
  if self.stream is Some(_) {
    return
  }
  self.stream = Some(
    @ui.Stream::new(
      shown=fn(ts) {
        self.shown_any = true
        screen_ack(self.src, self, ts)
      },
      broken=fn() { screen_tell(self.src, "screen.keyframe", { "view": Json::string(self.view) }) },
      // shown by the system's video layer where the host has one: a frame of it builds and draws nothing of the app's,
      // unless a part is drawn over it (a frame of the whole newer than the part's puts the part away: built)
      layer=true,
      quiet=Some(fn(_) { self.part_shown() is None }),
    ),
  )
}

///|
/// A call nobody waits for (`screen.ack`, `screen.input`: StillFailCore.kt tell): sent in order with the rest, its
/// answer (or error) let go.
fn screen_tell(src : Source, name : String, params : Map[String, Json]) -> Unit {
  (src.call)(name, Json::object(params), fn(_) {  })
}

///|
fn screen_ack(src : Source, s : ScreenSess, ts : Double) -> Unit {
  if ts <= s.acked {
    return
  }
  s.acked = ts
  // (its call: where the engine's shell reads the view itself, the ack goes from there: src/stillfail's call)
  screen_tell(src, "screen.ack", {
    "view": Json::string(s.view),
    "ts": Json::number(ts),
    "call": Json::number(s.call.to_double()),
  })
}

///|
/// What the phase is as the viewer shows it: the call's own failure and end over what the state last said.
fn ScreenSess::phase(self : ScreenSess) -> String {
  // this machine's own display: never opened (own_screen), said so in its place
  if own_screen(self.station, self.screen) {
    return "here"
  }
  if self.failure.get() is Some(_) {
    return "failed"
  }
  let p = match opt_text(self.state, "phase") {
    Some(p) => p
    None => "connecting"
  }
  if self.finished.get() && (p == "connecting" || p == "live" || p == "reconnecting") {
    "ended"
  } else {
    p
  }
}

///|
/// Why, in the viewer's words, for a phase that needs saying.
fn ScreenSess::message(self : ScreenSess) -> String? {
  if own_screen(self.station, self.screen) {
    return Some(@sf.t("android-misc.screen.hereWhy"))
  }
  match self.failure.get() {
    Some(f) => Some(f)
    None => opt_text(self.state, "message")
  }
}

///|
/// The view is open (on its way, live, or back on its way), not over.
fn ScreenSess::open_now(self : ScreenSess) -> Bool {
  let p = self.phase()
  p == "connecting" || p == "live" || p == "reconnecting"
}

///|
/// Input goes to the station now: it is live and driven by this viewer.
fn ScreenSess::driving(self : ScreenSess) -> Bool {
  self.phase() == "live" && flag(self.state, "control")
}

///|
/// Input reaches the station now: the view is open (not let go of out of sight) and has said since it opened that it
/// is live and driven by this viewer.
fn ScreenSess::input_goes(self : ScreenSess) -> Bool {
  self.call != 0 && self.heard && self.driving()
}

///|
/// 控制 or 只看 as the view is meant to be now: as chosen, else as the core opened it (只看 while another drives).
fn ScreenSess::controlling(self : ScreenSess) -> Bool {
  match self.wants_control {
    Some(on) => on
    None => !flag(self.state, "takeOver")
  }
}

///|
/// Someone else (an agent) drives it and this view only looks, but may take it over (接管).
fn ScreenSess::can_take_over(self : ScreenSess) -> Bool {
  self.phase() == "live" && flag(self.state, "takeOver")
}

///|
/// 只看 / 控制, while it may be driven and the view is open.
fn ScreenSess::choosable(self : ScreenSess) -> Bool {
  flag(self.state, "may") && self.open_now()
}

///|
/// What the screen's clipboard carries both ways (`text`, `png`), while this viewer drives it: none while only
/// looking, nor from a station (or helper) from before them.
fn ScreenSess::clip_types(self : ScreenSess) -> Array[String] {
  if !self.driving() {
    return []
  }
  items(self.state, "clipboard").filter_map(fn(j) {
    match j {
      String(t) => Some(t)
      _ => None
    }
  })
}

///|
/// The device's clipboard is pasted into the screen (`screen.clipboard`): driving it, and the station carries some.
fn ScreenSess::pastes(self : ScreenSess) -> Bool {
  self.clip_types().iter().any(fn(t) { t == "text" || t == "png" })
}

///|
/// Where a file picked goes on the screen's machine, while driving it (none from a station before files).
fn ScreenSess::drops_to(self : ScreenSess) -> DropTo? {
  if !self.driving() {
    return None
  }
  match field(self.state, "drop") {
    Some(Object(_) as d) => {
      let folder = text(Some(d), "folder")
      if folder == "" {
        None
      } else {
        Some({ folder, reveal: flag(Some(d), "reveal") })
      }
    }
    _ => None
  }
}

///|
/// Why it is not driven though 控制 was chosen, live (the station lacks a grant: macOS's Accessibility), in the
/// station's words; None when it is driven, or only looked at.
fn ScreenSess::undriven(self : ScreenSess) -> String? {
  guard self.state is Some(_) else { return None }
  if self.phase() != "live" ||
    !self.controlling() ||
    flag(self.state, "control") ||
    !flag(self.state, "may") ||
    flag(self.state, "takeOver") {
    return None
  }
  let why = text(field(self.state, "access"), "message")
  if why == "" {
    None
  } else {
    Some(why)
  }
}

///|
/// The screen's display resolution while this viewer drives one whose station changes it (Windows): now, and the modes
/// it takes (landscape, the largest first); None elsewhere, or while only looking.
fn ScreenSess::resolution(self : ScreenSess) -> ((Int, Int), Array[(Int, Int)])? {
  if !self.driving() {
    return None
  }
  match field(self.state, "resolution") {
    Some(Object(_)) as r => {
      let modes = items(r, "modes").filter_map(fn(j) {
        let m = Some(j)
        let (w, h) = (number(m, "width").to_int(), number(m, "height").to_int())
        if w > 0 && h > 0 {
          Some((w, h))
        } else {
          None
        }
      })
      if modes.is_empty() {
        None
      } else {
        Some(((number(r, "width").to_int(), number(r, "height").to_int()), modes))
      }
    }
    _ => None
  }
}

///|
/// The mode of `modes` whose shape is nearest the stage's (`w`×`h`, as this device shows the screen): the one that
/// fills it best, the larger of two as near.
fn resolution_fitting(modes : Array[(Int, Int)], w : Double, h : Double) -> Int {
  if modes.is_empty() || w <= 0.0 || h <= 0.0 {
    return -1
  }
  let want = w / h
  let mut best = 0
  let mut off = @double.infinity
  for i, m in modes {
    // (how many times wider or narrower than the stage's shape, 1 the same)
    let k = m.0.to_double() / m.1.to_double() / want
    let d = if k >= 1.0 { k } else { 1.0 / k }
    // (the largest first: a later one only when nearer by more than a rounding's)
    if d < off - 0.001 {
      best = i
      off = d
    }
  }
  best
}

///|
/// The modes worth offering of `modes` (the largest first): of each shape (its width to its height, to a tenth) the
/// three largest, with the one it is at now (`now`) and the one nearest this device's (`fits`, its index; -1 none) kept
/// whatever their shape; in the order they came. A display offers some two dozen, most of them the same shapes
/// smaller: a list too long to pick from on a phone (the user, 2026-10-29).
fn resolution_shown(modes : Array[(Int, Int)], now : (Int, Int), fits : Int) -> Array[(Int, Int)] {
  let per : Map[Int, Int] = Map([])
  let shown : Array[(Int, Int)] = []
  for i, m in modes {
    let shape = (m.0.to_double() / m.1.to_double() * 10.0).round().to_int()
    let had = per.get(shape).unwrap_or(0)
    per[shape] = had + 1
    if had < 3 || m == now || i == fits {
      shown.push(m)
    }
  }
  shown
}

///|
/// The screen's display scale while this viewer drives one whose station changes it (Windows): now, the one its system
/// recommends, the steps it takes (in percent, lowest first); None elsewhere, or while only looking.
fn ScreenSess::scale(self : ScreenSess) -> (Int, Int, Array[Int])? {
  if !self.driving() {
    return None
  }
  match field(self.state, "scale") {
    Some(Object(_)) as sc => {
      let steps = items(sc, "steps").filter_map(fn(j) {
        match j {
          Number(n, ..) => Some(n.to_int())
          _ => None
        }
      })
      if steps.is_empty() {
        None
      } else {
        Some((number(sc, "percent").to_int(), number(sc, "recommended").to_int(), steps))
      }
    }
    _ => None
  }
}

///|
/// Where the station says its pointer is (0..1 of the frame), when it says.
fn ScreenSess::cursor(self : ScreenSess) -> (Double, Double)? {
  match field(self.state, "cursor") {
    Some(Object(_) as c) =>
      match (field(Some(c), "x"), field(Some(c), "y")) {
        (Some(Number(x, ..)), Some(Number(y, ..))) => Some((x, y))
        _ => None
      }
    _ => None
  }
}

///|
/// The frame's size in pixels: the config's, else the picture's as the stream last showed it.
fn ScreenSess::frame_size(self : ScreenSess) -> (Int, Int)? {
  match self.size {
    Some(s) => Some(s)
    None =>
      match self.stream {
        Some(st) => st.size()
        None => None
      }
  }
}

///|
/// A finger drives it as a trackpad (it moves the pointer, a tap clicks where that points), or directly (a tap clicks
/// where it is): as chosen here, else directly on a page laid out for this device (`fit`: a tap is where it is, as in
/// the device's own browser), else as this device keeps it (`prefs.screenTouch`).
fn ScreenSess::pad(self : ScreenSess, src : Source) -> Bool {
  match self.pad_set {
    Some(on) => on
    None if self.fit is Some(_) && text(self.state, "kind") == "browser" => false
    None => text((src.topic)("prefs", {}).value, "screenTouch") != "direct"
  }
}

///|
/// How large a picture this device asks for (prefs `screenQuality`, 控制中心's 画质): `smooth`, `hd`, `original`, or
/// "" (自动: as large as the stage it is shown on, in device pixels: ScreenSess::bounds).
fn screen_quality(src : Source) -> String {
  match text((src.topic)("prefs", {}).value, "screenQuality") {
    "smooth" | "hd" | "original" as q => q
    _ => ""
  }
}

///|
/// The most frames a second this device asks for (prefs `screenFps`, 控制中心's 帧率): 120, 90, 60, 30 or 15, or 0 (自动:
/// as many as the station and the link give).
fn screen_fps(src : Source) -> Int {
  let n = number((src.topic)("prefs", {}).value, "screenFps").to_int()
  if screen_fps_choices.contains(n) && n > 0 {
    n
  } else {
    0
  }
}

///|
/// 帧率's choices, 自动 (0) first (web/src/screen/frames.ts FPS_CHOICES).
// kept across runs: a table, never written
let screen_fps_choices : Array[Int] = [0, 120, 90, 60, 30, 15]

///|
/// The 画质 and 帧率 a view is asked with besides its size (none for 自动): `screen.view`'s and `screen.bounds`'s.
fn asks_into(params : Map[String, Json], quality : String, fps : Int) -> Unit {
  if quality != "" {
    params["quality"] = Json::string(quality)
  }
  if fps > 0 {
    params["fps"] = Json::number(fps.to_double())
  }
}

///|
/// The bounds a 画质 asks for (web/src/screen/frames.ts QUALITY): `original` the largest a view may ask (the screen's own
/// size); 自动 as large as the stage the picture is shown on, in this device's pixels (the user, 2026-10-29: a 4K
/// window was sent 1920×1080 and its text blurred), screen_max_w × screen_max_h before it is laid out.
fn ScreenSess::bounds(self : ScreenSess, quality : String) -> (Int, Int) {
  match quality {
    "smooth" => (1280, 720)
    "hd" => (1920, 1080)
    "original" => (7680, 4320)
    _ =>
      match self.stage_px {
        (w, h) if w > 0 && h > 0 => (@cmp.minimum(w, 7680), @cmp.minimum(h, 4320))
        _ => (screen_max_w, screen_max_h)
      }
  }
}

///|
/// The stage the picture is shown on laid out `w` × `h` device pixels: 自动 asks that large from now where it is a
/// tenth larger a side than the most it had (a window made larger by a little, as it is dragged, asks nothing again;
/// one made smaller keeps what it asked).
fn ScreenSess::stage_is(self : ScreenSess, w : Int, h : Int) -> Unit {
  let (pw, ph) = self.stage_px
  if w * 10 > pw * 11 || h * 10 > ph * 11 {
    self.stage_px = (@cmp.maximum(w, pw), @cmp.maximum(h, ph))
  }
}

///|
/// Opens the view (again: after a pause, or 重新打开): `screen.view`, the frames it can decode said (H.265 first where
/// the host decodes it, H.264 where it does), as large as 画质 asks, and the 画质 itself (how high the station lets the
/// bit rate go) and the 帧率 (the most frames a second it sends).
fn ScreenSess::open(self : ScreenSess, src : Source) -> Unit {
  if self.call != 0 || own_screen(self.station, self.screen) {
    return
  }
  // again after it ended (重新打开): on its way, not still saying how the last one ended
  if self.finished.get() || self.failure.get() is Some(_) {
    self.state = None
  }
  self.failure.set(None)
  self.finished.set(false)
  // (a call of its own: the part in sight told it again)
  self.looked = ""
  // (input waits for the view opened again to say it is live: the state before is the last one's)
  self.heard = false
  let quality = screen_quality(src)
  let fps = screen_fps(src)
  self.asked = quality
  self.asked_fps = fps
  let (mw, mh) = self.bounds(quality)
  self.asked_bounds = (mw, mh)
  let codecs = if @ui.h264_here() {
    [Json::string("h264"), Json::string("jpeg")]
  } else {
    [Json::string("jpeg")]
  }
  if @ui.h265_here() {
    codecs.insert(0, Json::string("h265"))
  }
  let params : Map[String, Json] = {
    "station": Json::string(self.station),
    "screen": Json::string(self.screen),
    "view": Json::string(self.view),
    "codecs": Json::array(codecs),
    "maxWidth": Json::number(mw.to_double()),
    "maxHeight": Json::number(mh.to_double()),
  }
  asks_into(params, quality, fps)
  if @ui.stream_audio_here() { params["audio"] = Json::string("pcm_s16le") }
  // Shown by the system's video layer (its frames tagged colours honoured, a wide-gamut screen's shown as wide): the
  // Mac's desktop sent in Display P3; the app's canvas (a faded or ended view's picture) has it converted to sRGB.
  if @ui.stream_layers_here() { params["gamut"] = Json::string("p3") }
  match self.fit {
    Some((w, h, scale)) =>
      params["fit"] = Json::object({
        "width": Json::number(w.round()),
        "height": Json::number(h.round()),
        "scale": Json::number(scale),
      })
    None => ()
  }
  // not said until the person chooses: the core decides (only looking while another drives)
  match self.wants_control {
    Some(on) => params["control"] = Json::boolean(on)
    None => ()
  }
  let me = self
  self.call = (src.stream)(
    "screen.view",
    Json::object(params),
    None,
    fn(value, bytes) { me.take(value, bytes) },
    fn(r) {
      me.call = 0
      me.audio_ready = false
      match me.stream { Some(st) => st.audio(Bytes::new(0)); None => () }
      match r {
        Ok(_) => me.finished.set(true)
        Err(e) => me.failure.set(Some(text(Some(e), "message")))
      }
    },
  )
}

///|
/// 画质 or 帧率 chosen otherwise since the open view was asked, or 自动's stage grown (stage_is): the view goes on, its
/// pictures asked this large and this often (`screen.bounds`: the core opens its stream again, the one before kept until the new one has opened, so a
/// Windows desktop keeps the display scale set from it), the frame on screen kept meanwhile.
fn ScreenSess::asked_again(self : ScreenSess, src : Source) -> Unit {
  let quality = screen_quality(src)
  let fps = screen_fps(src)
  let (mw, mh) = self.bounds(quality)
  if self.call == 0 || (self.asked == quality && self.asked_fps == fps && self.asked_bounds == (mw, mh)) {
    return
  }
  self.asked = quality
  self.asked_fps = fps
  self.asked_bounds = (mw, mh)
  let params : Map[String, Json] = {
    "view": Json::string(self.view),
    "maxWidth": Json::number(mw.to_double()),
    "maxHeight": Json::number(mh.to_double()),
  }
  asks_into(params, quality, fps)
  screen_tell(src, "screen.bounds", params)
}

///|
/// Stops viewing (the app went out of sight); the last frame stays, `open` goes on from it.
fn ScreenSess::pause(self : ScreenSess, src : Source) -> Unit {
  self.audio_ready = false
  match self.stream { Some(st) => st.audio(Bytes::new(0)); None => () }
  if self.call != 0 {
    (src.cancel)(self.call)
    self.call = 0
  }
}

///|
/// Ends it for good: the view, the decoder, the files still going up.
fn ScreenSess::close(self : ScreenSess, src : Source) -> Unit {
  self.pause(src)
  self.drops.clear()
  match self.stream {
    Some(st) => st.close()
    None => ()
  }
  match self.part {
    Some(st) => st.close()
    None => ()
  }
}

///|
/// 只看 or 控制: the core opens the view again with it, the frame on screen kept meanwhile.
fn ScreenSess::control(self : ScreenSess, src : Source, on : Bool) -> Unit {
  self.wants_control = Some(on)
  screen_tell(src, "screen.control", { "view": Json::string(self.view), "control": Json::boolean(on) })
}

///|
/// Input for the station (`screen.input`): only while this viewer drives it.
fn ScreenSess::input(self : ScreenSess, src : Source, input : Json) -> Unit {
  if !self.input_goes() {
    return
  }
  screen_tell(src, "screen.input", { "view": Json::string(self.view), "input": input })
}

///|
/// Trackpad or direct, chosen: kept on this device for every screen (`prefs.set screenTouch`, null for the
/// trackpad); `done` gets the core's answer.
fn ScreenSess::choose_pad(
  self : ScreenSess,
  src : Source,
  on : Bool,
  done : (Result[Json, Json]) -> Unit,
) -> Unit {
  self.pad_set = Some(on)
  let v = if on { Json::null() } else { Json::string("direct") }
  (src.call)("prefs.set", Json::object({ "screenTouch": v }), done)
}

///|
/// `text` onto the screen's clipboard and pasted where its focus is (`screen.clipboard`).
fn ScreenSess::paste(
  self : ScreenSess,
  src : Source,
  words : String,
  done : (Result[Json, Json]) -> Unit,
) -> Unit {
  let p : Map[String, Json] = {
    "view": Json::string(self.view),
    "text": Json::string(words),
    "paste": Json::boolean(true),
  }
  (src.call)("screen.clipboard", Json::object(p), done)
}

///|
/// A PNG onto the screen's clipboard and pasted where its focus is (`screen.clipboard`, the picture beside the call).
fn ScreenSess::paste_png(
  self : ScreenSess,
  src : Source,
  png : Bytes,
  done : (Result[Json, Json]) -> Unit,
) -> Unit {
  let p : Map[String, Json] = {
    "view": Json::string(self.view),
    "png": Json::boolean(true),
    "paste": Json::boolean(true),
  }
  (src.call_bytes)("screen.clipboard", Json::object(p), png, done)
}

///|
/// A file dropped onto the machine, shown in its file manager (`screen.input` reveal).
fn ScreenSess::reveal(
  self : ScreenSess,
  src : Source,
  path : String,
  done : (Result[Json, Json]) -> Unit,
) -> Unit {
  let input = Json::object({ "t": Json::string("reveal"), "path": Json::string(path) })
  (src.call)("screen.input", Json::object({ "view": Json::string(self.view), "input": input }), done)
}

///|
/// Whether a value of `screen.view` changes nothing a frame reads, as ScreenSess::take takes it: a frame or a sound's
/// packet alone, handed to the decoder (which says what it shows: what it said is taken as the frame begins) and counted
/// where only 控制中心's second reads it; so the core takes it as it comes and builds nothing for it (@core.quiet, said
/// as the app starts: src/stillfail). A state, a config or a copy made on the screen changes what is shown: not so.
pub fn screen_value_quiet(value : Json) -> Bool {
  guard value is Object(o) else { return false }
  if o.length() > 0 && o.keys().all(fn(k) { k == "frame" || k == "audio" }) {
    return true
  }
  // a state that only moves the pointer of a view whose pointer is on its picture's layer (ScreenSess::take hands it
  // to the host); taken by another view, more changed there, its `said` builds what reads it
  match o.get("state") {
    Some(Object(_) as st) if o.length() == 1 =>
      screens_open.values().any(fn(s) { s.pointer_layer is Some(_) && cursor_moved_only(s.state, st) })
    _ => false
  }
}

///|
/// Where the pointer is on a picture's system video layer, as the last build had it (screen_stage): the stream it is
/// drawn over, the part of the screen that one shows (None: the whole), and whether it follows the station's pointer
/// (not the trackpad's, nor hidden while this device's mouse drives it).
priv struct PointerLayer {
  on : @ui.Stream
  part : Part?
  follows : Bool
}

///|
/// Whether state `new` differs from `old` only in where the station's pointer is (its shape the same).
fn cursor_moved_only(old : Json?, new : Json) -> Bool {
  guard old is Some(Object(a)) && new is Object(b) && a.length() == b.length() else { return false }
  b.iter().all(fn(kv) {
    let (k, v) = kv
    match a.get(k) {
      Some(was) if k == "cursor" =>
        match (was, v) {
          (Object(c0), Object(c1)) =>
            c0.length() == c1.length() &&
            c0.get("shape") == c1.get("shape") &&
            c1.iter().all(fn(e) { e.0 == "shape" || e.0 == "x" || e.0 == "y" })
          _ => false
        }
      Some(was) => was == v
      None => false
    }
  })
}

///|
/// A point of the whole screen (0..1) on the picture of `part` (None: the whole): 0..1 of the part, outside it too.
fn point_on(at : (Double, Double), part : Part?) -> (Double, Double) {
  match part {
    Some(p) => ((at.0 - p.x) / p.w, (at.1 - p.y) / p.h)
    None => at
  }
}

///|
/// The station's pointer moved, nothing else of the state changed: where it is drawn on a picture's layer, the host told
/// (nothing built or painted for it); while it is the trackpad's or hidden, nothing.
fn ScreenSess::pointer_moved(self : ScreenSess) -> Unit {
  guard self.pointer_layer is Some(pl) && pl.follows else { return }
  pl.on.pointer_at(self.cursor().map(fn(at) { point_on(at, pl.part) }))
}

///|
/// The calls of a screen whose answers nobody reads (screen_tell's `screen.ack`): taken as they come, they build nothing
/// (@core.unread, said as the app starts).
pub fn screen_unread_calls() -> Array[String] {
  ["screen.ack"]
}

///|
/// A value of the call: taken apart, the heavy parts handed on (ScreenSession.kt take). What screen_value_quiet says
/// changes nothing a frame reads is taken as it comes, before the frame is built: what a frame or a sound's packet sets
/// here is read by no build.
fn ScreenSess::take(self : ScreenSess, value : Json, bytes : Bytes?) -> Unit {
  guard value is Object(o) else { return }
  match o.get("state") {
    Some(Object(_) as s) => {
      // the pointer alone moved, drawn on a picture's layer: the host told, nothing built (screen_value_quiet)
      let moved = self.pointer_layer is Some(_) && cursor_moved_only(self.state, s)
      self.state = Some(s)
      self.heard = true
      if moved {
        self.pointer_moved()
      } else {
        self.said.set(@signals.untracked(fn() { self.said.get() }) + 1)
      }
    }
    _ => ()
  }
  match o.get("audioConfig") {
    Some(config) => self.audio_ready = text(Some(config), "codec") == "pcm_s16le" && number(Some(config), "sampleRate") == 48000.0 && number(Some(config), "channels") == 2.0
    None => ()
  }
  if o.contains("audio") && self.audio_ready && !self.audio_muted {
    match (self.stream, bytes) { (Some(st), Some(data)) => st.audio(data); _ => () }
  }
  // (the engine's own read of the view numbers what it says: those after it the host may take, ScreenSess::route)
  let seq = match (o.get("frame"), o.get("audio")) {
    (Some(Object(_) as f), _) | (_, Some(Object(_) as f)) =>
      match field(Some(f), "n") {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
    _ => None
  }
  match o.get("config") {
    Some(Object(_) as c) => {
      let kind = text(Some(c), "codec")
      if kind != "" {
        let w = number(Some(c), "width").to_int()
        let h = number(Some(c), "height").to_int()
        // a part's frames to the part's decoder, the whole's to the whole's (whose size the stage is laid out by)
        let part = part_of(Some(c))
        self.parting = part is Some(_)
        self.part_next = part
        let st = if part is Some(_) { Some(self.part_stream()) } else { self.stream }
        match (bytes, st) {
          (Some(b), Some(st)) if kind == "h264" => st.h264(b, w, h)
          (Some(b), Some(st)) if kind == "h265" => st.hevc(b, w, h)
          _ => ()
        }
        if part is Some(_) {
          self.part_codec = Some(kind)
        } else {
          self.codec = Some(kind)
          if w > 0 && h > 0 {
            self.size = Some((w, h))
          }
        }
      }
    }
    _ => ()
  }
  match o.get("clipboard") {
    Some(Object(_) as c) =>
      // for the device's clipboard: text, or a picture (its PNG beside, within the bound)
      match text(Some(c), "type") {
        "text" => {
          let t = text(Some(c), "text")
          if t != "" {
            self.copied.push(CopiedText(t))
          }
        }
        "png" =>
          match bytes {
            Some(b) if b.length() > 0 && b.length() <= clip_png_max && @pixels.is_png(b) =>
              self.copied.push(CopiedPng(b))
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  match o.get("frame") {
    Some(Object(_) as f) => {
      guard field(Some(f), "ts") is Some(Number(ts, ..)) else { return }
      let key = flag(Some(f), "key")
      // a frame that brings nothing to show (no bytes, no codec yet): taken, as far as the station is concerned
      match bytes {
        None => screen_ack(self.src, self, ts)
        Some(b) => {
          self.frames += 1
          self.bytes += b.length()
          // a part's first frame after its config: the part it shows from (the parts its decoder shows no more let go)
          match self.part_next {
            Some(p) => {
              self.part_next = None
              let shown = self.part.bind(fn(st) { st.shown_at() }).unwrap_or(-1.0)
              let later = self.parts.filter(fn(q) { q.0 > shown })
              let now = self.parts.filter(fn(q) { q.0 <= shown }).last()
              self.parts.clear()
              match now {
                Some(q) => self.parts.push(q)
                None => ()
              }
              self.parts.append(later)
              self.parts.push((ts, p))
            }
            None => ()
          }
          let (codec, st) = if self.parting {
            (self.part_codec, self.part)
          } else {
            (self.codec, self.stream)
          }
          match (codec, st) {
            (Some("h264"), Some(st)) | (Some("h265"), Some(st)) =>
              st.frame(b, key, ts)
            (Some("jpeg"), Some(st)) => st.jpeg(b, ts)
            _ => screen_ack(self.src, self, ts)
          }
        }
      }
    }
    _ => ()
  }
  match seq {
    Some(n) => self.route(n)
    None => ()
  }
}

///|
/// The view's frames and sound after the `after`th the engine said (the last taken) taken by the host where they go,
/// straight from the engine (@ui's Stream::route), while that changes nothing the app draws: the frames to the stream
/// they show on (the whole's while no part shows over it, the part's while the last part begun shows), its picture on
/// its system video layer; the sound while it plays. Elsewhere, or as soon as that is not so, they come here as before.
fn ScreenSess::route(self : ScreenSess, after : Double) -> Unit {
  if self.call == 0 {
    return
  }
  let shown = self.part_shown()
  let to_part = self.parting &&
    self.part_next is None &&
    shown is Some(_) &&
    self.parts.last().map(fn(p) { p.1 }) == shown
  let to_whole = !self.parting && shown is None
  let audio = self.audio_ready && !self.audio_muted
  match self.stream {
    Some(st) => st.route(self.call, after, video=to_whole, audio~)
    None => ()
  }
  match self.part {
    Some(st) => st.route(self.call, after, video=to_part, audio=false)
    None => ()
  }
}

///|
/// The frames that came and their bytes: those taken here and those the host took by its route (控制中心's 连接).
fn ScreenSess::came(self : ScreenSess) -> (Int, Int) {
  let mut frames = self.frames
  let mut bytes = self.bytes
  for st in [self.stream, self.part] {
    match st {
      Some(st) => {
        let (f, b) = st.direct_count()
        frames += f
        bytes += b
      }
      None => ()
    }
  }
  (frames, bytes)
}

///|
/// The most a clipboard carries of a picture, each way (client/core-ts/src/screen-frames.ts; ScreenClips.kt).
let clip_png_max : Int = 8 * 1024 * 1024


///|
fn ScreenSess::toggle_audio(self : ScreenSess) -> Unit {
  self.audio_muted = !self.audio_muted
  if self.audio_muted { match self.stream { Some(st) => st.audio(Bytes::new(0)); None => () } }
}
