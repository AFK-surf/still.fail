// mbui's film: a scripted run of an app filmed offscreen, straight into a video. The app's view runs in a Tester, as
// a test runs it (its clock the Tester's, every input the script's: drive.mbt's steps), whose text and pictures are
// this host's (Tester::new's `live`: what this host lays the words out by and draws); each frame the run draws is
// drawn by this host's renderer offscreen as a window's frame is (src/host/apple_render.m) and written into the film
// as the frame of its moment (Tester::film), H.264 in an MP4. No window, no screen, no real time: the same run is the
// same film, made as fast as the machine draws. Beside it, <film>.textrec: the run's text and pictures as this host
// answered them (TEXTREC lines), for a test to see the run again over them (Tester::new(text=)).
//
// An app's film program gives its view to `run` (still.fail's src/sffilm, scripts/film.sh), which reads:
//   MBUI_FILM=<out.mp4> MBUI_FILM_DRIVE=<script> [MBUI_WIN=390x844] [MBUI_FILM_SCALE=2] [MBUI_FILM_PLATFORM=0]
//   [MBUI_DARK=1] [MBUI_FILM_INSET=1: the window's buttons in the app's top row, a Mac's] [MBUI_FILM_FRAMES=3000]
//   [MBUI_FILM_WINDOW_CORNER=16: how round the system draws the window's corners, a Mac's: @hostapi.window_corner]
//   [MBUI_LOCALE=en-US: the app's language, as a device's] [MBUI_FONT_SCALE=1.3: the system's size of words, as a
//   device's set bigger] [MBUI_FILM_LAST=<last.png>: the run's last frame as the renderer drew it]
//   [MBUI_FILM_COPIED=<copied.png.b64>: the picture the app last put on the clipboard, a PNG in base64]
//   [MBUI_FILM_NAV_ABLE=1: the system lays out the app's tabs in bars of its own, an iPhone Duo's (@hostapi.nav_bar_able;
//   what the system draws of them not filmed: the app beside them)]
// The film is H.264, lossy: each frame's pixels are the encoder's guess of them, and a guess that leans on the frames
// before it and on how the encoder spends its bits. A picture compared to the byte (before and after a change) is the
// last frame as drawn (MBUI_FILM_LAST), never one taken out of the film.
// What it cannot show: what is not drawn by mbui (the system's keyboard and dialogs, a native view's content: a
// video playing, a web page), and a stream's frames (none decoded under a Tester).

///|
/// The numbers of an instance (src/ui/scene.mbt).
let inst_size = 60

///|
/// The film's frames a second.
pub let film_fps : Int = 60

///|
/// `script` (drive.mbt's steps) run over `view` in a Tester of this host's text and pictures, `w` × `h` points at
/// `scale` device pixels a point, playing `platform` (@hostapi.platform's: 0 macOS, 1 iOS, 2 Android), the system
/// `dark` or not, and filmed: every frame it draws drawn by this host's renderer offscreen and written into `out` (an
/// MP4, `film_fps` frames a second) from the Tester's first frame to the script's end (or `max` frames of it), the
/// run's text and pictures as this host answered them beside it (`out`.textrec). Whether the film was made and the
/// script passed, what went wrong said.
pub fn film(
  view : (@ui.Ctx) -> Unit,
  tree? : (@view.View) -> Unit,
  script~ : String,
  out~ : String,
  w? : Double = 390.0,
  h? : Double = 844.0,
  scale? : Double = 2.0,
  platform? : Int = 0,
  dark? : Bool = false,
  inset? : Bool = false,
  window_corner? : Double = 0.0,
  max? : Int = 3000,
  last? : String = "",
  copied? : String = "",
) -> Bool {
  if !supported {
    say("film: this host has no film")
    return false
  }
  // (this host, asked before the Tester gives its own: what the Tester's text and pictures are, and what draws)
  let host = @hostapi.host()
  init_offscreen(w, h, scale)
  let t = @ui.Tester::new(
    view,
    tree?,
    w~,
    h~,
    scale~,
    platform~,
    dark~,
    // (what it is pointed with: MBUI_POINTING, finger or mouse, as a program's; else the platform's)
    pointing?=match arg("MBUI_POINTING") {
      "finger" => Some(@ui.Pointing::Finger)
      "mouse" => Some(@ui.Pointing::Mouse)
      _ => None
    },
    // (a keyboard at hand: MBUI_KEYBOARD, 1 or 0, as one plugged in or not; else the platform's)
    keyboard?=match arg("MBUI_KEYBOARD") {
      "1" => Some(true)
      "0" => Some(false)
      _ => None
    },
    // (the app's words in the language the film says: MBUI_LOCALE, as a device's; MBUI_DARK=1, an app's own reading of
    // it (sffix's fixture choosing its dark theme) as a program's)
    env=[("MBUI_TEXT_RECORD", "1"), ("MBUI_LOCALE", arg("MBUI_LOCALE")), ("MBUI_DARK", arg("MBUI_DARK"))],
    // (a film is for people to see a motion as it is, words over words too: what a test holds it to, words_over.mbt,
    // is the tests', not a film's to stop at)
    words_over_held=false,
    live={ host, turn: fn() { spin(1.0) } },
    // A film draws the same logical window and rasterizes text at the same scale as a real window for every frame.
    before=fn() {
      let z = @ui.window_zoom()
      set_offscreen_view(w / z, h / z, scale * z)
    },
    window_corner~,
    // (where the system has bars of its own for the app's tabs: MBUI_FILM_NAV_ABLE, an iPhone Duo's)
    nav_able=arg("MBUI_FILM_NAV_ABLE") == "1",
  )
  // (the window's buttons in the app's top row, as a Mac's window has them: Tester::set_window_inset)
  if inset {
    t.set_window_inset(true)
  }
  match number(arg("MBUI_FONT_SCALE")) {
    Some(f) if f > 0.0 => t.set_font_scale(f)
    _ => ()
  }
  // (this machine's station as its host would say it: MBUI_LOCAL_STATION, its JSON, Tester::set_local_station)
  match arg("MBUI_LOCAL_STATION") {
    "" => ()
    ls => t.set_local_station(ls)
  }
  let pw = (w * scale).round().to_int()
  let ph = (h * scale).round().to_int()
  if !open(out, pw, ph, film_fps) {
    say("film: \{out}: not made")
    return false
  }
  let buf = Ref::new(FixedArray::make(0, 0.0))
  let drawn = Ref::new(0)
  let put = Ref::new(0)
  let lost = Ref::new(0)
  let logs = t.film(
    script,
    fps=film_fps.to_double(),
    max~,
    draw=fn(t) {
      draw_frame(t, buf)
      drawn.val = drawn.val + 1
    },
    put=fn(k) {
      if put_frame(k) {
        put.val = put.val + 1
      } else {
        lost.val = lost.val + 1
      }
    },
  )
  // (the last frame as drawn, before the film is closed: what was drawn last is still the renderer's)
  let shot = last == "" || drawn.val > 0 && snapshot(last)
  let closed = close(put.val)
  // (what the app put on the clipboard as a picture last, as the host drew it: a shot's, Ctx::take_shot)
  let copy = copied == "" ||
    (match t.clipboard_png() {
      Some(png) => write_text(copied, @codec.base64(png))
      None => false
    })
  let text = logs
    .filter(fn(l) { l.has_prefix("TEXTREC ") })
    .map(fn(l) { l.unsafe_substring(start=8, end=l.length()) })
  let kept = write_text(out + ".textrec", text.join("\n") + "\n")
  for l in logs {
    if l.has_prefix("DRIVE") {
      say(l)
    }
  }
  let passed = logs.iter().any(fn(l) { l == "DRIVE PASS" })
  let secs = put.val.to_double() / film_fps.to_double()
  say(
    "film: \{out}: \{put.val} frames (\{secs} s), \{drawn.val} drawn" +
    (if lost.val > 0 { ", \{lost.val} not written" } else { "" }) +
    (if closed { "" } else { ", not finished" }) +
    (if kept { "" } else { ", its text not kept" }) +
    (if shot { "" } else { ", its last frame not written" }) +
    (if copy { "" } else { ", nothing copied to write" }) +
    (if passed { "" } else { ", the script did not pass" }),
  )
  closed && lost.val == 0 && passed && shot && copy
}

///|
/// The frame the Tester presented last drawn by this host's renderer, as the film's picture from now on: its
/// pictures the host's own (Tester::live_image), one the host has not (a stream's frame) left out.
fn draw_frame(t : @ui.Tester, buf : Ref[FixedArray[Double]]) -> Unit {
  let (n, (r, g, b)) = host_frame(t, buf)
  draw(buf.val, n, r, g, b)
}

///|
/// The frame the Tester presented last, copied into `buf` as this host's renderer draws it: its pictures the host's own
/// (Tester::live_image), one the host has not (a stream's frame) left out. How many instances, what is under them.
fn host_frame(t : @ui.Tester, buf : Ref[FixedArray[Double]]) -> (Int, (Double, Double, Double)) {
  let (inst, n, (r, g, b)) = t.presented()
  let len = n * inst_size
  if buf.val.length() < len {
    buf.val = FixedArray::make(len * 2, 0.0)
  }
  let f = buf.val
  inst.blit_to(f, len~)
  for k in 0..<n {
    let at = k * inst_size
    if f[at + 5] == 4.0 {
      match t.live_image(f[at + 20].to_int()) {
        Some(mine) => f[at + 20] = mine.to_double()
        None => {
          // nothing drawn: a rect of no colour, no border, no blur
          f[at + 5] = 0.0
          for j in 6..<12 {
            f[at + j] = 0.0
          }
        }
      }
    }
  }
  (n, (r, g, b))
}

///|
/// A film made of the process's arguments (the head of this file says which), `view` the app's: the process ends
/// with 0 when it was made and the script passed, 1 when not, 2 when it was not asked for rightly.
pub fn run(view : (@ui.Ctx) -> Unit, tree? : (@view.View) -> Unit) -> Unit {
  // (a tool's arguments, from the process: not an app's reads of where it runs)
  let out = arg("MBUI_FILM")
  let drive = arg("MBUI_FILM_DRIVE")
  if out == "" || drive == "" {
    say(
      "film: MBUI_FILM=<out.mp4> MBUI_FILM_DRIVE=<script> [MBUI_WIN=390x844] [MBUI_FILM_SCALE=2] [MBUI_FILM_PLATFORM=0] [MBUI_KEYBOARD=1] [MBUI_DARK=1] [MBUI_FILM_INSET=1] [MBUI_FILM_FRAMES=3000] [MBUI_LOCAL_STATION=<json>]",
    )
    exit(2)
    return
  }
  let script = read_text(drive)
  if script == "" {
    say("film: \{drive}: no script there")
    exit(2)
    return
  }
  let (w, h) = match arg("MBUI_WIN").split("x").map(fn(p) { number(p.to_owned()) }).to_array() {
    [Some(w), Some(h)] if w > 0.0 && h > 0.0 => (w, h)
    _ => (390.0, 844.0)
  }
  let scale = number(arg("MBUI_FILM_SCALE")).unwrap_or(2.0)
  let platform = number(arg("MBUI_FILM_PLATFORM")).unwrap_or(0.0).to_int()
  let max = number(arg("MBUI_FILM_FRAMES")).unwrap_or(3000.0).to_int()
  let window_corner = number(arg("MBUI_FILM_WINDOW_CORNER")).unwrap_or(0.0)
  let ok = film(
    view,
    tree?,
    script~,
    out~,
    w~,
    h~,
    scale~,
    platform~,
    dark=arg("MBUI_DARK") == "1",
    inset=arg("MBUI_FILM_INSET") == "1",
    window_corner~,
    max~,
    last=arg("MBUI_FILM_LAST"),
    copied=arg("MBUI_FILM_COPIED"),
  )
  exit(if ok { 0 } else { 1 })
}

///|
/// The process's argument `name` (an environment variable), "" when it has none: for an app's film program too.
pub fn arg(name : String) -> String {
  ffi_arg(name)
}

///|
fn number(s : String) -> Double? {
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Number(d, ..)) => Some(d)
    _ => None
  }
}

///|
/// This host as a Tester's live host (Tester::new's `live`: its text and pictures this host's), for a program that
/// runs an app in a Tester without filming it (still.fail's src/sflayout). Asked before the Tester gives its own.
pub fn live() -> @ui.Live {
  { host: @hostapi.host(), turn: fn() { spin(1.0) } }
}
