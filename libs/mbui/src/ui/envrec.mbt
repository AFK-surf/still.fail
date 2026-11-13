// The system's settings the app is drawn by, kept with its frames as its input is (MBUI_DRAW_LOG=1, a Tester's tape):
// motion reduced, transparency reduced, the system dark, the window's buttons in the app's top row; and whether the host
// decodes H.264 (@ui.h264_here: what a stream asks its sender for, stream.mbt). Read as each frame
// begins; an ENV line before the first frame's DRAWHASH, and again before the frame where one of them changed. A
// Tester made with the run (Tester::new's `run`) draws its first frame by those it began with; its `replay_frames`
// sets the later ones again at their place (its fake host's: Tester::set_reduce_motion,
// set_reduce_transparency, set_dark, set_window_inset), so a run is drawn again by the settings it was drawn by.
//
//   ENV {"motion":0|1,"glass":0|1,"dark":0|1,"inset":0|1,"h264":0|1,"feed":0|1,"layer":0|1|2,"ime":H,"copy":0|1,"font":S}
//       motion reduced, transparency reduced (glass solid), dark, the window's inset, H.264 decoded (a tape without it:
//       not), its decoder driven from here (stream_feed.mbt; a tape without it: not), a stream shown by the host's video
//       layer (stream.mbt; 2 one that shows it as sRGB; a tape without it: not), H.265 decoded ("h265":1, said only then), the soft
//       keyboard's height (points; each step of its motion a line), the system saying a copy itself (device.mbt), the
//       system's size of words (font_scale; said only when not 1, a line without it: 1)

///|
/// The settings last kept on the tape ("" none yet).
let env_kept : Ref[String] = Ref("")

///|
/// The system's settings as this frame begins, kept on the tape when they are not as last kept.
fn env_at_frame() -> Unit {
  if !taping() {
    return
  }
  let m : Map[String, Json] = {
    "motion": Json::number(if reduced_motion() { 1.0 } else { 0.0 }),
    "glass": Json::number(if h_reduce_transparency() { 1.0 } else { 0.0 }),
    "dark": Json::number(if system_dark() { 1.0 } else { 0.0 }),
    "inset": Json::number(if window_inset() { 1.0 } else { 0.0 }),
    "audio": Json::number(if stream_audio_here() { 1.0 } else { 0.0 }),
    "h264": Json::number(if h_h264_here() { 1.0 } else { 0.0 }),
    "feed": Json::number(if h_stream_feeds() { 1.0 } else { 0.0 }),
    "layer": Json::number(
      if !h_stream_layers() {
        0.0
      } else if h_stream_layers_tagged() {
        1.0
      } else {
        2.0
      },
    ),
    "ime": Json::number(g().dev.ime_inset),
    "copy": Json::number(if copy_shown() { 1.0 } else { 0.0 }),
  }
  // (said only where it does: a tape without it, not)
  if h265_here() {
    m["h265"] = Json::number(1.0)
  }
  let fs = font_scale()
  if fs != 1.0 {
    m["font"] = Json::number(fs)
  }
  let line = "ENV " + Json::object(m).stringify()
  if line != env_kept.val {
    env_kept.val = line
    tape_line(line)
  }
}

///|
/// What a core trace is told of the host's settings (trace_settings), and what it was told last ("" nothing yet).
// kept across runs: the app's own, set once as it starts (a Tester sets it only where it tests it)
let settings_tracer : Ref[((Map[String, Json]) -> Unit)?] = Ref(None)

///|
// kept across runs: settings_tracer's, put back as that is set (trace_settings)
let settings_kept : Ref[String] = Ref("")

///|
/// What the host gives the app from now on given to `line` as a frame begins, whenever it is not as last given: the
/// window's size and its device pixels a point as the host gives them (before the app's own zoom), the system it is
/// (`platform`, `pointing`: native_pointing, 0 a mouse, 1 a finger), the minutes it is off UTC, and the system's
/// settings an ENV line says (motion, glass, dark, inset, ime, copy, font always said):
/// `{"settings":{"w":W,"h":H,"scale":S,"platform":P,"pointing":N,"utc":M,"motion":0|1,…,"font":F}}`, what a core
/// trace keeps for its replay (src/sfreplay: Flow::start reads the first, Tester::view_said the later ones), so a
/// replay is drawn by what the run was drawn by, never by defaults of its own.
/// A trace kept from before these were recorded carries one written in for it with `"from":"replay"`: what its replay
/// had always been drawn by (a phone's window at 2 device pixels a point, UTC, the settings off), not what its run's
/// host gave, which nothing kept (the user's, 2026-11-10: recorded again, it is the run's).
pub fn trace_settings(line : (Map[String, Json]) -> Unit) -> Unit {
  settings_tracer.val = Some(line)
  settings_kept.val = ""
}

///|
/// Who is told the moment of each frame as it begins (trace_frames): a run's record of its display's frames.
// kept across runs: the app's own, set once as it starts
let frames_tracer : Ref[((Double) -> Unit)?] = Ref(None)

///|
/// The moment the host gives each frame from now on (on_frame's `t`, as the host gave it, not measured after) given to
/// `line` as the frame begins: what a core trace keeps beside its messages (`{"frame":T}`, src/stillfail's CORETRACE
/// frame), for a replay's frames to fall where the run's display drew them (src/sfreplay: the strict pass, Tester::
/// set_frame_times), not on a grid of its own a phase apart.
pub fn trace_frames(line : (Double) -> Unit) -> Unit {
  frames_tracer.val = Some(line)
}

///|
fn frame_begun_told(t : Double) -> Unit {
  match frames_tracer.val {
    Some(line) => line(t)
    None => ()
  }
}

///|
fn settings_at_frame(w : Double, h : Double, scale : Double) -> Unit {
  guard settings_tracer.val is Some(line) else { return }
  let m : Map[String, Json] = {
    "w": Json::number(w),
    "h": Json::number(h),
    "scale": Json::number(scale),
    "platform": Json::number(platform().to_double()),
    "pointing": Json::number(if native_pointing() is Finger { 1.0 } else { 0.0 }),
    "utc": Json::number(h_utc_offset_now().to_double()),
    "motion": Json::number(if reduced_motion() { 1.0 } else { 0.0 }),
    "glass": Json::number(if h_reduce_transparency() { 1.0 } else { 0.0 }),
    "dark": Json::number(if system_dark() { 1.0 } else { 0.0 }),
    "inset": Json::number(if window_inset() { 1.0 } else { 0.0 }),
    "ime": Json::number(g().dev.ime_inset),
    "copy": Json::number(if copy_shown() { 1.0 } else { 0.0 }),
    "font": Json::number(font_scale()),
  }
  let said = Json::object(m).stringify()
  if said == settings_kept.val {
    return
  }
  settings_kept.val = said
  line({ "settings": Json::object(m) })
}

///|
/// One ENV line set again on the fake host (Tester::replay_frames).
fn replay_env(f : FakeHost, line : String) -> Unit {
  guard line.find("ENV ") is Some(i) else { return }
  let j = @json.parse(line.exact_view(start=i + 4).to_owned()) catch { _ => return }
  guard j is Object(m) else { return }
  let on = fn(k : String, was : Bool) -> Bool {
    match m.get(k) {
      Some(Number(d, ..)) => d != 0.0
      _ => was
    }
  }
  f.reduce_motion = on("motion", f.reduce_motion)
  f.reduce_transparency = on("glass", f.reduce_transparency)
  f.dark = on("dark", f.dark)
  f.inset = on("inset", f.inset)
  f.h264 = on("h264", f.h264)
  f.audio_here = on("audio", false)
  f.h265_here = on("h265", false)
  f.stream_feeds = on("feed", f.stream_feeds)
  f.stream_layers = on("layer", f.stream_layers)
  f.stream_layers_srgb = match m.get("layer") {
    Some(Number(d, ..)) => d == 2.0
    _ => f.stream_layers_srgb
  }
  f.dev.copy_shown = on("copy", f.dev.copy_shown)
  match m.get("ime") {
    Some(Number(d, ..)) => f.dev.ime_inset = d
    _ => ()
  }
  f.font_scale = match m.get("font") {
    Some(Number(d, ..)) if d > 0.0 => d
    _ => 1.0
  }
  f.wants = true
}

///|
/// The settings a run began with (its ENV lines before its first DRAWHASH), what its host said of its views by then
/// (VIEWSAID: hostcall.mbt's view_say) and what came from outside (MSG: the system's bars), set on the fake host before a Tester draws its first frame (Tester::new's
/// `run`), so the frames replayed are the run's, one for one.
fn env_before_frames(f : FakeHost, run : String) -> Unit {
  for v in run.split("\n") {
    let line = v.to_owned()
    if line.find("DRAWHASH ") is Some(_) {
      return
    }
    if line.find("ENV ") is Some(_) {
      replay_env(f, line)
    }
    match line.find("VIEWSAID ") {
      Some(i) => ignore(fake_view_said(f, line.exact_view(start=i + 9).to_owned()))
      None => ()
    }
    // what came from outside before it (the system's bars round an edge-to-edge window): the first frame takes it
    if is_message_line(line) {
      replay_message(f, line)
    }
  }
}

///|
/// Motion reduced or not, as the person's setting, from the next frame on.
pub fn Tester::set_reduce_motion(self : Tester, on : Bool) -> Unit {
  host_setting_set("set_reduce_motion")
  self.fake.reduce_motion = on
  self.fake.wants = true
}

///|
/// A run's `{"settings":{…}}` line (trace_settings') given to the fake host from the next frame on: its window's size
/// and scale, the system's settings and the minutes it is off UTC, each as the run's host gave it. False for a line
/// that is not one. What the system is and how it is pointed at (`platform`, `pointing`) are the Tester's own from
/// when it is made (Tester::new's: settings_of), and change in no run.
pub fn Tester::settings_said(self : Tester, line : String) -> Bool {
  let j = @json.parse(line) catch { _ => return false }
  guard j is Object(o) && o.get("settings") is Some(Object(m)) else { return false }
  let num = fn(k : String) -> Double? {
    match m.get(k) {
      Some(Number(d, ..)) => Some(d)
      _ => None
    }
  }
  let f = self.fake
  let on = fn(k : String, was : Bool) -> Bool {
    match num(k) {
      Some(d) => d != 0.0
      None => was
    }
  }
  f.reduce_motion = on("motion", f.reduce_motion)
  f.reduce_transparency = on("glass", f.reduce_transparency)
  f.dark = on("dark", f.dark)
  f.inset = on("inset", f.inset)
  f.dev.copy_shown = on("copy", f.dev.copy_shown)
  match num("ime") {
    Some(d) => f.dev.ime_inset = d
    None => ()
  }
  match num("font") {
    Some(d) if d > 0.0 => f.font_scale = d
    _ => ()
  }
  match num("utc") {
    Some(d) => f.utc_offset = d.to_int()
    None => ()
  }
  match num("scale") {
    Some(d) if d > 0.0 => f.scale = d
    _ => ()
  }
  match (num("w"), num("h")) {
    (Some(w), Some(h)) if w != self.w || h != self.h => self.resize_next(w, h)
    _ => ()
  }
  f.wants = true
  true
}

///|
/// What a Tester is made by of a run's first `{"settings":{…}}` line (Tester::new's `w`, `h`, `scale`, `platform`,
/// `native`, `dark`), or why it cannot be: a field it lacks, said by name. A run's own line, never a default in its
/// place (src/sfreplay: Flow::start).
pub fn settings_of(j : Json) -> Result[(Double, Double, Double, Int, Pointing, Bool), String] {
  guard j is Object(o) && o.get("settings") is Some(Object(m)) else { return Err("no {\"settings\":…}") }
  let need = fn(k : String) -> Double raise Failure {
    match m.get(k) {
      Some(Number(d, ..)) => d
      _ => fail(k)
    }
  }
  try {
    let w = need("w")
    let h = need("h")
    let scale = need("scale")
    let platform = need("platform").to_int()
    let pointing = if need("pointing") != 0.0 { Finger } else { Mouse }
    let dark = need("dark") != 0.0
    for k in ["font", "utc", "motion", "glass", "inset", "ime", "copy"] {
      ignore(need(k))
    }
    Ok((w, h, scale, platform, pointing, dark))
  } catch {
    Failure(k) => Err("its {\"settings\":…} has no " + k)
  }
}
