// The one player of films and songs (web/ui viewer/Player.tsx, the web's one player too): a video is a video,
// whether a chat's recording of a screen or a film of a station's drive, and is watched both ways. To look closely:
// paused, a step to the frame before or after (the file's own frames, read by the host), the time to the millisecond
// and which frame of how many at what rate, slow speeds (0.1×, 0.25×, 0.5×), the picture zoomed and moved, the frame
// shown saved as a picture. To watch: opened where it was left on this device (viewer_file.mbt place; from its start
// again when it was left within 5 s of its end), the subtitle beside it (names.mbt side_subtitle), faster speeds,
// 15 s back and on, the folder's others of its kind as its playlist, the next one played at its end after a moment.
// A film is shown on black, the controls over it a deep tint with words near white, whatever the theme; a song has no
// picture, and is on the page's own colours. How it plays is mbui's player's (@kit.Media: the system's player in a
// native view, its bytes asked a part at a time of the file's `stream`).
//
// On a desktop's layout (`player_view` in the wide frame): the bar every file opened has along the top
// (viewer_bar.mbt), the controls floating over the foot (media.mbt), both there till a click or a finger's tap takes
// them away and another brings them back, or while the pointer is over where they are. A double click or tap as on a
// phone: in the middle it plays or pauses, on the left or right third it jumps 15 s; the wheel with ⌘ or ⌃ (a trackpad's pinch) zooms round the pointer, the wheel
// alone moves what is zoomed in. Keys: Space or K plays or pauses; paused, ← → and , . step a frame, playing ← → jump
// 15 s; J L jump 15 s; ↑ ↓ the sound; M mutes; F fills the screen; C the subtitle; ⇧N ⇧P the next one and the one
// before; + − 0 1 zoom as a picture's. 选集 docks the others at the right.
//
// With a finger (a phone's): a tap brings or takes the controls, a double tap on the left or right third jumps 15 s, in
// the middle plays or pauses; held, it plays at 2× until let go; a finger along it moves through the time, down it
// closes it; two fingers zoom. Paused, its controls step frames; playing, they jump 15 s. Sideways, filling the screen
// or fitted; 选集 a sheet of the page's.

///|
/// `m:ss`, or `h:mm:ss` past an hour (to the second).
pub fn clock(ms : Double) -> String {
  let total = ((if ms < 0.0 { 0.0 } else { ms }) + 500.0).to_int64() / 1000L
  let h = total / 3600L
  let m = total % 3600L / 60L
  let s = total % 60L
  if h > 0L {
    "\{h}:\{two_digits(m)}:\{two_digits(s)}"
  } else {
    "\{m}:\{two_digits(s)}"
  }
}

///|
/// `m:ss.mmm` (`h:mm:ss.mmm` past an hour): a frame's time, to the millisecond (web/ui viewer/playing.ts clockMs).
pub fn clock_ms(ms : Double) -> String {
  let all = (if ms < 0.0 { 0.0 } else { ms }).round().to_int64()
  let total = all / 1000L
  let h = total / 3600L
  let m = total % 3600L / 60L
  let s = total % 60L
  let r = all % 1000L
  let mmm = if r < 10L { "00\{r}" } else if r < 100L { "0\{r}" } else { "\{r}" }
  if h > 0L {
    "\{h}:\{two_digits(m)}:\{two_digits(s)}.\{mmm}"
  } else {
    "\{m}:\{two_digits(s)}.\{mmm}"
  }
}

///|
fn two_digits(n : Int64) -> String {
  if n < 10L {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// A speed as it is shown: 1×, 1.5×, 0.25×.
pub fn speed_label(speed : Double) -> String {
  let whole = speed.floor()
  (if whole == speed { whole.to_int().to_string() } else { speed.to_string() }) +
  "×"
}

///|
/// The speeds it plays at: slow ones to look closely, fast ones to get through.
pub let player_speeds : Array[Double] = [0.1, 0.25, 0.5, 1.0, 1.25, 1.5, 2.0]

///|
/// A player for a page (`key` keeps its widgets apart from another's), its waits said once they have waited later_ms;
/// its controls there till a tap (a click) on its picture hides them, never going of themselves (the user, 2026-10-28).
pub fn new_media(key : String) -> @kit.Media {
  @kit.Media::new(key~, speeds=player_speeds, wait_ms=later_ms, rest_ms=0.0)
}

///|
/// A file played, kept while its page is open: its player, whether it was opened, the subtitle asked for (its name),
/// the places kept (each next one player_keep_ms after it).
pub(all) struct Playing {
  media : @kit.Media
  /// the file as last given (where it is is kept with it)
  mut file : ViewerFile?
  opened : @signals.Signal[Bool]
  mut subtitle_of : String
  mut keeps : Int
}

///|
/// The files played, by their key (let go of as their page goes: player_let_go).
let playings : Map[String, Playing] = Map([])

///|
/// The file played as `key` (a new player the first time).
pub fn playing_for(key : String) -> Playing {
  match playings.get(key) {
    Some(p) => p
    None => {
      let p : Playing = { media: new_media("drive-play"), file: None, opened: @signals.signal(false), subtitle_of: "", keeps: 0 }
      playings[key] = p
      p
    }
  }
}

///|
/// How long where a file was left is waited on before it plays from the start.
pub let player_place_ms : Double = 1000.0

///|
/// How often where it is is kept while it plays.
pub let player_keep_ms : Double = 5000.0

///|
/// Left this near its end, it plays from its start again.
let player_near_end_ms : Double = 5000.0

///|
/// A subtitle bigger than this is not read.
let player_subtitle_most : Double = 8.0 * 1024.0 * 1024.0

///|
/// The file played as `key` this frame: opened once where it was left is known (or waited on player_place_ms), the
/// subtitle beside it read once the folder names one, where it is kept every player_keep_ms while it plays. Its player.
pub fn player_media(c : @ui.Ctx, key : String, file : ViewerFile, siblings : Array[ViewerEntry]) -> @kit.Media {
  let pl = playing_for(key)
  pl.file = Some(file)
  // where it was left, held on this device: waited on a moment at most from when it is first drawn (`after` asks for
  // the frame it is up on)
  let waited = @kit.after(c, "play-place", !pl.opened.get(), player_place_ms)
  if !pl.opened.get() {
    let start = match (file.place)() {
      LeftAt(at, of) =>
        // left near its end: from the start again
        Some(if at > 0.0 && (of <= 0.0 || at < of - player_near_end_ms) { at } else { 0.0 })
      NeverLeft => Some(0.0)
      NotKnown => if waited { Some(0.0) } else { None }
    }
    match start {
      Some(start) => {
        pl.opened.set(true)
        pl.media.open({ name: file.name, mime: file.mime, audio: file.kind == "audio", read: player_read(file) }, start~)
      }
      None => ()
    }
  }
  // the subtitle beside it, once the folder names one
  match (side_subtitle(file.name, siblings.filter(fn(e) { !e.dir }).map(fn(e) { e.name })), file.beside) {
    (Some(sub), Some(beside)) if sub != pl.subtitle_of =>
      match siblings.iter().find_first(fn(e) { e.name == sub && !e.dir }) {
        Some(side) if side.size <= player_subtitle_most => {
          // (asked once by the folder as it lists it: the same in each build of the frame)
          pl.subtitle_of = sub
          pl.media.set_subtitle(true, [])
          beside(side, fn(r) {
            match r {
              Ok(bytes) => {
                let cues = @codec.parse_subtitles(sub, bytes)
                @ui.log("player: subtitle \{sub}: \{cues.length()} lines")
                pl.media.set_subtitle(true, cues)
              }
              Err(e) => @ui.log("player: subtitle \{sub} not read: \{e}")
            }
          })
        }
        _ => ()
      }
    _ => ()
  }
  // where it is, kept every 5 s while it is open
  // (the place kept now and then: nothing shown waits for it; the next wait starts in the frame this one ends)
  if pl.media.started() && pl.media.duration() > 0.0 {
    let kept = fn() { @kit.after(c, "play-keep/" + key + "/\{pl.keeps}", true, player_keep_ms, later=true) }
    if kept() {
      // (once the frame's builds are over: a build let go of keeps nothing)
      c.after_build("play-keep", fn() {
        player_keep(pl, file)
        pl.keeps = pl.keeps + 1
        kept() |> ignore
      })
    }
  }
  pl.media
}

///|
/// How the player reads `file` a part at a time: as it streams, or from its bytes here already, or (neither) read
/// whole once and answered from that (a read let go of meanwhile answered no more).
fn player_read(file : ViewerFile) -> (Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit {
  match (file.stream, file.bytes) {
    (Some(stream), _) => stream
    (None, Some(b)) =>
      fn(offset, length, answer) {
        answer(player_slice(b, offset, length), b.length().to_double(), false)
        fn() {  }
      }
    (None, None) => {
      let whole : Ref[Bytes?] = Ref(None)
      let waiting : Array[(Double, Int, (Bytes, Double, Bool) -> Unit, Ref[Bool])] = []
      let asked = Ref(false)
      fn(offset, length, answer) {
        match whole.val {
          Some(b) => {
            answer(player_slice(b, offset, length), b.length().to_double(), false)
            fn() {  }
          }
          None => {
            let gone = Ref(false)
            waiting.push((offset, length, answer, gone))
            if !asked.val {
              asked.val = true
              (file.read)(-1, fn(_) {  }, fn(r) {
                match r {
                  Ok(b) => {
                    whole.val = Some(b)
                    for w in waiting {
                      if !w.3.val {
                        (w.2)(player_slice(b, w.0, w.1), b.length().to_double(), false)
                      }
                    }
                  }
                  Err(_) =>
                    for w in waiting {
                      if !w.3.val {
                        (w.2)(b"", -2.0, false)
                      }
                    }
                }
                waiting.clear()
              })
            }
            fn() { gone.val = true }
          }
        }
      }
    }
  }
}

///|
/// `length` bytes of `b` from `offset` (none past its end).
fn player_slice(b : Bytes, offset : Double, length : Int) -> Bytes {
  let from = offset.to_int()
  let to = if from + length < b.length() { from + length } else { b.length() }
  if from >= to {
    b""
  } else {
    b[from:to].to_bytes()
  }
}

///|
/// Where it is, kept with its file (its time and its length, in ms).
fn player_keep(pl : Playing, file : ViewerFile) -> Unit {
  let pos = pl.media.position()
  let dur = pl.media.duration()
  if dur <= 0.0 {
    return
  }
  (file.keep_place)(pos.round(), dur.round())
}

///|
/// The page playing `key` gone: where it was kept, its player stopped and let go of.
pub fn player_let_go(key : String) -> Unit {
  match playings.get(key) {
    Some(pl) => {
      match pl.file {
        Some(f) if pl.media.started() => player_keep(pl, f)
        _ => ()
      }
      // (its view's 选集 stays open for the next one played in its place: the same player's key)
      pl.media.close()
    }
    None => ()
  }
  playings.remove(key)
}

///|
/// The folder's others of its kind, in their names' order: the playlist.
pub fn playlist_for(file : ViewerFile, siblings : Array[ViewerEntry]) -> Array[String] {
  playlist_of(siblings.filter(fn(e) { !e.dir && e.kind == file.kind }).map(fn(e) { e.name }), fn(_) { true })
}

///|
/// A file played as `key` on its page: its player made ready (player_media), drawn as a phone's or a desktop's
/// (player_view), `on_go` another of the folder's played in its place.
pub fn player(
  c : @ui.Ctx,
  key : String,
  file : ViewerFile,
  siblings : Array[ViewerEntry],
  back_label~ : String,
  on_back~ : () -> Unit,
  on_go~ : (String) -> Unit,
) -> Unit {
  let m = player_media(c, key, file, siblings)
  player_view(c, m, file, playlist_for(file, siblings), back_label~, on_back~, on_go~)
}

// ── what a view holds of its own ──────────────────────────────────────────

///|
/// What a player's view holds while it is open (by its player's key): 选集 open, the speeds' menu open, where the
/// pointer was (its moves wake the controls), whether it made the window fill the screen; the picture's zoom; a frame
/// being saved and which; the speed a held finger made 2× (-1: none held); a finger's drag on the picture (along it
/// through the time, down it to close it, moving what is zoomed in) and where it is; two fingers' last distance and
/// middle; the end whose next was let go of; the end whose next's wait was first drawn; where its picture was last
/// drawn.
priv struct PlayerView {
  mut listing : Bool
  mut list_closing : Bool
  mut rates : Bool
  mut fulled : Bool
  zoom : @kit.Zoom
  mut grabbing : Bool
  mut grab_at : Int
  mut held : Double
  mut drag : PlayerDrag
  mut drag_from : Double
  mut drag_to : Double
  mut drag_dy : Double
  mut last : (Double, Double)
  mut pinch : (Double, Double, Double)
  mut pinched : Bool
  /// the finger came down on the picture flinging (zoomed in), and stopped it there: no tap
  mut caught : Bool
  mut ended_off : String
  mut file : String
  mut placed : (Double, Double, Double, Double)?
  /// taken down past the line and let go: going, its picture left where the finger left it, its controls away
  mut taken_down : Bool
}

///|
/// What a finger dragging the picture does.
priv enum PlayerDrag {
  NoDrag
  AlongTime
  DownClose
  MoveZoom
} derive(Eq)

///|
/// The views open, by their player's key.
let player_views : Map[String, PlayerView] = Map([])

///|
fn view_for(key : String) -> PlayerView {
  match player_views.get(key) {
    Some(v) => v
    None => {
      let v : PlayerView = {
        listing: false,
        list_closing: false,
        rates: false,
        fulled: false,
        // (a film edge to edge in its stage, enlarged as players do: no margin round it)
        zoom: @kit.Zoom::new(margin=fn(_) { 0.0 }, enlarge=true),
        grabbing: false,
        grab_at: 0,
        held: -1.0,
        drag: NoDrag,
        drag_from: 0.0,
        drag_to: 0.0,
        drag_dy: 0.0,
        last: (0.0, 0.0),
        pinch: (0.0, 0.0, 0.0),
        pinched: false,
        caught: false,
        ended_off: "",
        file: "",
        placed: None,
        taken_down: false,
      }
      player_views[key] = v
      v
    }
  }
}

///|
/// Where the player keyed `key` last drew its picture in its stage (x, y, w, h: as a finger left it, zoomed in or taken
/// down), while its view is open: what a viewer closing it flies back from.
pub fn player_picture_at(key : String) -> (Double, Double, Double, Double)? {
  match player_views.get(key) {
    Some(v) => v.placed
    None => None
  }
}

///|
/// What a player's view held of its own, by its player's key, let go (the player closed).
pub fn player_view_let_go(key : String) -> Unit {
  player_views.remove(key)
}

///|
/// Every player let go of (the app begun again).
fn players_reset() -> Unit {
  playings.clear()
  player_views.clear()
}

// ── its frames ───────────────────────────────────────────────────────────

///|
/// Where it is among its frames: the file's own (when each starts, read by the host), else a 60th of a second each;
/// how many, which one shows (the last to start by now), when that one starts, its rate (0: not known), whether they
/// were read (or there are none to read).
priv struct Frames {
  starts : Array[Double]?
  count : Int
  at : Int
  now : Double
  fps : Double
  read : Bool
  dur : Double
}

///|
/// The frames of what `p` plays, at `pos` (ms).
fn frames_of(p : @kit.Media, s : @kit.MediaStatus, pos : Double) -> Frames {
  let dur = s.duration
  let (starts, read) = match p.native() {
    Some(n) =>
      match n.frames() {
        Some(list) if list.length() > 0 => (Some(list), true)
        Some(_) => (None, true)
        None => (None, !n.here())
      }
    None => (None, false)
  }
  let step = player_guess_step
  match starts {
    Some(list) => {
      let k = list.length()
      let span = list[k - 1] - list[0]
      let at = frame_at(list, pos)
      { starts, count: k, at, now: list[at], fps: if span > 0.0 { (k - 1).to_double() * 1000.0 / span } else { 0.0 }, read, dur }
    }
    None => {
      let count = if dur > 0.0 && read { (dur / step).round().to_int() } else { 0 }
      { starts, count, at: if dur > 0.0 { ((pos + player_frame_slack) / step).floor().to_int() } else { 0 }, now: pos, fps: 0.0, read, dur }
    }
  }
}

///|
/// A film's own facts as its bar says them (the web player's bar): its size in pixels, how long, its rate. What its
/// message says, there from the first frame (FileFacts: the station read them from its header), else what the host
/// has read of it (its head, and its end where its header is kept there).
fn film_facts(said : FileFacts, s : @kit.MediaStatus, fr : Frames) -> String {
  let (w, h) = if said.width > 0.0 && said.height > 0.0 { (said.width, said.height) } else { (s.width, s.height) }
  guard w > 0.0 && h > 0.0 else { "" }
  let dur = if said.duration > 0.0 { said.duration } else { s.duration }
  let fps = if said.frames > 0 && said.duration > 0.0 {
    said.frames.to_double() * 1000.0 / said.duration
  } else {
    fr.fps
  }
  joined(
    ["\{w.to_int()}×\{h.to_int()}", if dur > 0.0 { clock(dur) } else { "" }, if fps > 0.0 { "\{fps.round().to_int()} fps" } else { "" }],
    " · ",
  )
}

///|
/// When frame `i` starts (the first or the last past either end).
fn Frames::start_of(self : Frames, i : Int) -> Double {
  match self.starts {
    Some(list) => list[if i < 0 { 0 } else if i >= list.length() { list.length() - 1 } else { i }]
    None => dmax(0.0, dmin(dmax(self.dur, 0.0), i.to_double() * player_guess_step))
  }
}

///|
/// The frame showing at `ms` among frames starting at `starts` (in order): the last to start by then (up to
/// player_frame_slack over taken as by then).
fn frame_at(starts : Array[Double], ms : Double) -> Int {
  let mut lo = 0
  let mut hi = starts.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if starts[mid] <= ms + player_frame_slack {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// What a finger on its time goes to at `ms`: the start of the frame showing then (the file's frames read), else `ms`.
fn Frames::snap(self : Frames, ms : Double) -> Double {
  match self.starts {
    Some(list) => list[frame_at(list, ms)]
    None => ms
  }
}

///|
/// Whether it plays (or waits for more to play on), or will once a finger moving it through the time lets go.
fn plays(p : @kit.Media, f : @kit.MediaFrame) -> Bool {
  f.phase == Playing || f.phase == Buffering || p.scrub_resumes()
}

///|
/// Paused at the frame `d` from the one shown (-1 the one before), told the player once the frame's builds are over
/// (Ctx::tell: a key or a tap one build alone sees).
fn step_frame(c : @ui.Ctx, p : @kit.Media, fr : Frames, d : Int) -> Unit {
  c.tell(p.key() + "/frame", fn() {
    p.pause()
    p.seek(fr.start_of(fr.at + d))
    @ui.log("player: frame \{fr.at + d + 1} of \{fr.count}")
    p.wake()
  })
}

///|
/// What is said of where it is: while it plays (and of a song, and of a film not ready) the time of how long; paused
/// or moved through by a finger, the time to the millisecond, and with the file's frames read which frame of how many at what rate (not
/// guessed: without them a step is a 60th of a second, which says nothing of the file).
fn where_runs(p : @kit.Media, fr : Frames, s : @kit.MediaStatus, playing : Bool, picture : Bool, ink : MediaInk) -> Array[@ui.Run] {
  let at = p.scrubbing().unwrap_or(s.position)
  let long = if s.duration > 0.0 { clock(s.duration) } else { "--:--" }
  match fr.starts {
    _ if !picture || s.duration <= 0.0 || (playing && p.scrubbing() is None) =>
      [
        @ui.span(clock(at), color=ink.text, weight=media_strong, mono=true),
        @ui.span(" / " + long, color=ink.muted, mono=true),
      ]
    Some(_) => {
      let frames = t("android-chat.video.frames", args=[("at", "\{fr.at + 1}"), ("n", "\{fr.count}")])
      let rate = if fr.fps > 0.0 { " · \{fr.fps.round().to_int()} fps" } else { "" }
      [
        @ui.span(clock_ms(fr.now), color=ink.text, weight=media_strong, mono=true),
        @ui.span(" · " + frames + rate, color=ink.muted, mono=true),
      ]
    }
    None =>
      [
        @ui.span(clock_ms(at), color=ink.text, weight=media_strong, mono=true),
        @ui.span(" / " + long, color=ink.muted, mono=true),
      ]
  }
}

///|
/// The frame shown saved as a picture once the host has it (`<name>-<frame>.png`, to the device: the host's keep).
fn take_grab(v : PlayerView, p : @kit.Media, name : String) -> Unit {
  if !v.grabbing {
    return
  }
  match p.native() {
    Some(n) =>
      match n.grabbed() {
        Some(png) => {
          v.grabbing = false
          let base = match name.rev_find(".") {
            Some(i) if i > 0 => name.view(end_offset=i).to_owned()
            _ => name
          }
          if png.length() > 0 {
            (viewer_host().keep)(base + "-\{v.grab_at + 1}.png", "image/png", png)
          } else {
            (viewer_host().say)(t("android-chat.video.saveFrame.failed"))
          }
        }
        None => ()
      }
    None => v.grabbing = false
  }
}

///|
/// The frame shown asked to be saved (paused, ready, none asked already).
fn grab(v : PlayerView, p : @kit.Media, fr : Frames) -> Unit {
  match p.native() {
    Some(n) if !v.grabbing && !n.grabbing() => {
      v.grabbing = true
      v.grab_at = fr.at
      n.grab_frame(fr.start_of(fr.at))
    }
    _ => ()
  }
}

///|
/// Where the picture shows in the stage `w` × `h`: zoomed as the view's zoom has it (fitted until zoomed in), or
/// filling the screen turned sideways (cropped); its size not known yet, a point in the middle.
fn picture_place(
  v : PlayerView,
  p : @kit.Media,
  s : @kit.MediaStatus,
  w : Double,
  h : Double,
  still : String,
  top? : Double = 0.0,
  foot? : Double = 0.0,
) -> (Double, Double, Double, Double) {
  let z = v.zoom
  z.boxed(w, h - top - foot)
  if s.width > 0.0 && s.height > 0.0 {
    z.natural(s.width, s.height)
  } else {
    // (its size not said yet: its still's, which is of it)
    match @ui.image_natural(still) {
      Some((sw, sh)) if still != "" && sw > 0.0 && sh > 0.0 => z.natural(sw, sh)
      _ => ()
    }
  }
  z.step()
  if p.fills() && p.is_sideways() {
    return p.picture_rect(s, w, h)
  }
  match z.rect() {
    Some((x, y, pw, ph)) => (x, y + top, pw, ph)
    None => p.picture_rect(s, w, h)
  }
}

///|
/// How far in from the stage's top and foot a film's picture is fitted (`top`, `foot`): laid out wider than Small,
/// clear of the bar along the top and of the controls over the foot (and of the system's bars where they are over the
/// window), so neither ever hides an edge of it (a screen's recording looked at closely, its time dragged along); it
/// stays where it is as they come and go. Laid out Small (a phone's) edge to edge, its controls over it.
pub fn player_room(width : Double) -> (Double, Double) {
  if layout(width) is Small {
    return (0.0, 0.0)
  }
  let (top, foot) = (viewer_host().room)()
  let said = if desk_narrow(width) { desk_time_over - media_bar_top + desk_time_h } else { 0.0 }
  (viewer_bar_h + top, media_bar_h() + said + media_bar_in + foot)
}

///|
/// Its still (a chat's film: the frame it was left at, else the station's poster) where its picture is, until the
/// player shows its first frame; under the controls, as the picture is.
fn player_still(c : @ui.Ctx, n : @ui.NativeView, still : String, x : Double, y : Double, w : Double, h : Double) -> Unit {
  if still != "" && !n.shown() {
    c.layer(fn() { c.picture(still, x~, y~, w~, h~) |> ignore }) |> ignore
  }
}

///|
/// What the speed shows as and the speeds to pick (the menu under it: each a choice, the one it plays at checked).
fn speed_menu(c : @ui.Ctx, v : PlayerView, p : @kit.Media, trigger : Int) -> Unit {
  let entries = player_speeds.map(fn(sp) { @kit.menu_radio(sp.to_string(), sp == p.speed(), label=speed_label(sp)) })
  let m = dropdown(c, p.key() + "/speeds", v.rates, trigger, entries, {}, player_speeds_w, side=Top)
  if !m.open {
    v.rates = false
  }
  match m.chosen {
    Some(chosen) =>
      match player_speeds.iter().find_first(fn(sp) { sp.to_string() == chosen }) {
        Some(sp) => {
          p.set_speed(sp)
          v.rates = false
          p.wake()
        }
        None => ()
      }
    None => ()
  }
}

///|
/// At its end, the next one in a moment (player_next_ms, the seconds left said as they pass: a frame a second while
/// it shows, none once it is gone), or now, or not (let go). Gone to, the card is done with.
fn ended_card(c : @ui.Ctx, v : PlayerView, p : @kit.Media, f : @kit.MediaFrame, next : String?, go : (String) -> Unit, ink : MediaInk) -> Unit {
  let other = match next {
    Some(o) if f.phase == Ended && v.ended_off != o => o
    _ => return
  }
  let key = p.key() + "/next/" + other
  let go_now = fn() {
    v.ended_off = other
    go(other)
  }
  // (what is shown does not wait for these: the card at any moment is whole, its next second and the next one to
  // come by time, as a toast's going)
  if @kit.after(c, key, true, player_next_ms, later=true) {
    c.after_build(key + "/go", go_now)
  }
  // the seconds gone since it showed: a timer each, declared from then
  let seconds = (player_next_ms / player_second_ms).round().to_int()
  let mut gone = 0
  for k in 1..<seconds {
    if @kit.after(c, key + "/\{k}", true, k.to_double() * player_second_ms, later=true) {
      gone = k
    }
  }
  let left = seconds - gone
  c.layer(fn() {
    c.box(style=player_middle, fn() {
      c.box(style=player_next_box.then(@ui.style(bg=Data(ink.ground))), fn() {
        c.text(t("android-misc.drive.player.ended"), style=player_next_note.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        let id = c.id(key + "/now")
        if c.clicked(id) {
          go_now()
        }
        let b = c.box(style=player_next_now.then(@ui.style(bg=Data(alpha(ink.text, media_rate_share)))), id~, fn() {
          c.text(t("android-misc.drive.player.nextOne", args=[("name", other)]), style=player_next_words.then(@ui.text_style(color=Data(ink.text))))
          |> ignore
        })
        c.semantics(b, Button, id~, label=t("android-misc.drive.player.nextOne", args=[("name", other)]))
        let after = t("web-pages.drive.player.nextIn", args=[("n", left.to_string())])
        c.text(after, style=player_next_note.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        let cancel = c.id(key + "/off")
        if c.clicked(cancel) {
          v.ended_off = other
        }
        let x = c.box(style=player_next_off, id=cancel, fn() {
          c.text(t("common.cancel"), style=player_next_note.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        })
        c.semantics(x, Button, id=cancel, label=t("common.cancel"))
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A subtitle's lines over the picture's middle: `over` off the foot while the controls show (`up`: clear of them),
/// lower once they go; `right` kept clear (a list docked there).
fn player_cue(c : @ui.Ctx, words : String, up : Bool, right : Double, over~ : Double) -> Unit {
  if words == "" {
    return
  }
  c.layer(fn() {
    c.box(style=if up { desk_cue_look.then(@ui.style(pb=room(over))) } else { desk_cue_down }, fn() {
      c.box(style=desk_cue_row, fn() {
        c.box(style=desk_grow_middle, fn() {
          c.box(style=desk_cue_box, fn() { c.text(words, style=desk_cue_words) |> ignore }) |> ignore
        })
        |> ignore
        c.box(style=@ui.style(w=Fixed(right)), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What it waits on (with how fast its bytes come meanwhile, once a second of it has gone: moving, or not at all), why
/// it failed, in the stage's middle.
fn player_waits(c : @ui.Ctx, p : @kit.Media, f : @kit.MediaFrame, ink : MediaInk) -> Unit {
  c.layer(fn() {
    c.box(style=player_middle, fn() {
      match f.phase {
        Opening | Buffering =>
          if f.waited {
            c.box(style=player_pill.then(@ui.style(bg=Data(ink.ground))), fn() {
              spinner(c, size=player_pill_spinner) |> ignore
              let what = t(if f.phase == Opening { "common.opening" } else { "web-pages.drive.player.buffering" })
              c.text(
                if f.rate >= 0.0 { what + " · " + file_size(f.rate) + "/s" } else { what },
                style=player_pill_words.then(@ui.text_style(color=Data(ink.text))),
              )
              |> ignore
            })
            |> ignore
          }
        Failed =>
          c.box(style=player_failed_box, fn() {
            c.text(t("web-pages.drive.player.failed", args=[("error", "")]), style=player_pill_words.then(@ui.text_style(color=Data(ink.text))))
            |> ignore
            let id = c.id(p.key() + "/retry")
            if c.clicked(id) {
              p.retry()
            }
            let b = c.box(style=player_next_now.then(@ui.style(bg=Data(alpha(ink.text, media_rate_share)))), id~, fn() {
              c.text(t("android-misc.drive.player.retry"), style=player_next_words.then(@ui.text_style(color=Data(ink.text))))
              |> ignore
            })
            c.semantics(b, Button, id~, label=t("android-misc.drive.player.retry"))
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A song has no picture: its mark and its name in the middle.
fn player_cover(c : @ui.Ctx, name : String, ink : MediaInk) -> Unit {
  c.layer(fn() {
    c.box(style=desk_play_cover, fn() {
      icon(c, "file-audio", size=desk_cover_icon, color=ink.muted) |> ignore
      c.text(name, style=desk_cover_name.then(@ui.text_style(color=Data(ink.text)))) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The player `p` of `file` over its page (see the file's head): `list` the folder's others it steps through (in order,
/// the one playing among them), `on_go` another of them opened, back to `back_label`; `still` (an image's key) shown
/// where its picture will be until its first frame is. A phone's or a desktop's, as the page is.
pub fn player_view(
  c : @ui.Ctx,
  p : @kit.Media,
  file : ViewerFile,
  list : Array[String],
  back_label~ : String,
  on_back~ : () -> Unit,
  on_go~ : (String) -> Unit,
  still? : String = "",
) -> Unit {
  // what the view holds of the file it shows (zoomed in, its end's card, a frame being saved) not held of the next one
  // played in its place; what it holds of the player (选集 open, its speeds' menu) stays
  let v = view_for(p.key())
  if v.file != file.key {
    v.file = file.key
    v.zoom.fit_now()
    v.grabbing = false
    v.ended_off = ""
    v.taken_down = false
    v.drag_dy = 0.0
  }
  // laid out Small: a phone's player, as the viewer's frame
  if layout(c.width) is Small {
    phone_player(c, p, file, list, back_label, on_back, on_go, still)
  } else {
    desk_player(c, p, file, list, back_label, on_back, on_go, still)
  }
}

// ── a desktop's ─────────────────────────────────────────────────────────

///|
/// The player over the window, a desktop's layout (see the file's head).
fn desk_player(
  c : @ui.Ctx,
  p : @kit.Media,
  file : ViewerFile,
  list : Array[String],
  back_label : String,
  on_back : () -> Unit,
  on_go : (String) -> Unit,
  still : String,
) -> Unit {
  let f = p.frame(c)
  let s = f.status
  let key = p.key()
  let v = view_for(key)
  let picture = !f.audio
  let ink = media_ink(picture)
  // the bar over a film on its black, in its words, its buttons lit as the controls' are; a song's on the page
  let bar_ink : ViewerInk = if picture {
    {
      ground: ink.stage,
      ink: ink.text,
      muted: ink.muted,
      line: alpha(ink.text, player_dark_line),
      hover: alpha(ink.text, media_hot_share),
      chosen: alpha(ink.text, player_dark_chosen),
    }
  } else {
    page_viewer_ink()
  }
  let name = file.name
  let index = list.search(name).unwrap_or(-1)
  let next = next_in(name, list)
  let prev = if index > 0 { list.get(index - 1) } else { None }
  let many = list.length() > 1
  let listing = many && v.listing
  let panel = if listing { desk_panel_w } else { desk_none }
  let playing = plays(p, f)
  let fr = frames_of(p, s, p.scrubbing().unwrap_or(s.position))
  let mac = @ui.platform() == 0
  take_grab(v, p, name)
  // a click (a finger's tap, on a tablet's screen too) shows or hides the controls; a mouse's pointer over the bar or
  // the controls shows them while it is there
  let finger = @ui.pointing() is Finger
  let (px, py, _) = c.pointer()
  let go = fn(other : String) {
    p.pause()
    on_go(other)
  }
  let full = fn() {
    let on = @ui.full_screen()
    c.set_full_screen(!on)
    v.fulled = !on
    p.wake()
  }
  let z = v.zoom
  let (room_top, room_foot) = player_room(c.width)
  p.near(!finger && py >= 0.0 && (py < room_top || py >= c.height - room_foot))
  // the keys (see the file's head)
  let char = fn(ch : Char) { c.key_pressed(@ui.key_of_char(ch)) }
  let shifted = fn(ch : Char) {
    c.key_pressed(@ui.key_of_char(ch), mods=@ui.mod_shift_key) || c.key_pressed(@ui.key_of_char(ch.to_ascii_uppercase()))
  }
  if c.key_pressed(@ui.key_space) || char('k') {
    p.play_pause()
    p.wake()
  }
  if char(',') {
    step_frame(c, p, fr, -1)
  }
  if char('.') {
    step_frame(c, p, fr, 1)
  }
  if c.key_pressed(@ui.key_code_left) {
    if playing {
      p.seek_by(-p.nudge_ms())
      p.wake()
    } else {
      step_frame(c, p, fr, -1)
    }
  }
  if c.key_pressed(@ui.key_code_right) {
    if playing {
      p.seek_by(p.nudge_ms())
      p.wake()
    } else {
      step_frame(c, p, fr, 1)
    }
  }
  if char('j') {
    p.seek_by(-p.nudge_ms())
    p.wake()
  }
  if char('l') {
    p.seek_by(p.nudge_ms())
    p.wake()
  }
  if c.key_pressed(@ui.key_code_up) || c.key_pressed(@ui.key_code_down) {
    let (volume, _) = p.volume()
    p.set_volume(volume + (if c.key_pressed(@ui.key_code_up) { player_volume_key } else { -player_volume_key }))
    p.wake()
  }
  if char('m') {
    p.toggle_mute()
    p.wake()
  }
  if char('f') && picture && mac {
    full()
  }
  if char('c') && p.subtitle().0 {
    p.toggle_subtitle()
    p.wake()
  }
  if shifted('n') {
    match next {
      Some(other) => go(other)
      None => ()
    }
  }
  if shifted('p') {
    match prev {
      Some(other) => go(other)
      None => ()
    }
  }
  if picture && z.nw > 0.0 {
    let zoom_key = fn(ch : Char) {
      c.key_pressed(@ui.key_of_char(ch)) || c.key_pressed(@ui.key_of_char(ch), mods=@ui.mod_shift_key)
    }
    if zoom_key('+') || zoom_key('=') {
      z.zoom_to(z.scale * player_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
    } else if zoom_key('-') || zoom_key('_') {
      z.zoom_to(z.scale / player_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
    } else if char('0') {
      z.reset()
    } else if char('1') {
      z.zoom_to(player_whole, z.bw / 2.0, z.bh / 2.0, true)
    }
  }
  if c.key_pressed(@ui.key_escape) {
    if v.rates {
      v.rates = false
    } else if listing {
      v.listing = false
    } else {
      desk_leave(c, v, on_back)
    }
  }
  c.box(style=desk_play_ground.then(@ui.style(bg=Data(ink.stage))), fn() {
    // the picture, in the window less the list beside it, as a phone's (Media::stage): a click or a finger's tap shows
    // or hides the controls, a double one in the middle plays or pauses, on the left third back, on the right on (the
    // user, 2026-10-28); the screen filled by F or its key
    let stage = c.id(key + "/desk-stage")
    @ui.capture(c, stage)
    p.stage(c, stage, c.width - panel)
    // the wheel: with ⌃ or ⌘ held (or a trackpad's pinch) it zooms round the pointer, alone it moves what is zoomed in
    let (wx, wy, mods) = @ui.wheel_of(c, stage)
    if picture && z.nw > 0.0 && (wx != 0.0 || wy != 0.0) {
      if (mods & (@ui.wheel_mod_ctrl | @ui.wheel_mod_cmd)) != 0 {
        let fine = (mods & @ui.wheel_mod_ctrl) != 0 && wy.abs() < player_pinch_step
        z.zoom_to(z.scale * @dmath.exp(-wy * (if fine { player_pinch_rate } else { player_wheel_rate })), px, py - room_top, false)
      } else if z.zoomed() {
        if (mods & @ui.wheel_mod_shift) != 0 && wx == 0.0 {
          z.pan(-wy, 0.0)
        } else {
          z.pan(-wx, -wy)
        }
      }
    }
    c.box(style=desk_play_row, fn() {
      c.box(style=desk_grow_full, id=stage, fn() {
        let w = dmax(desk_none, c.width - panel)
        match p.native() {
          Some(n) if n.here() => {
            let (x, y, pw, ph) = picture_place(v, p, s, w, c.height, still, top=room_top, foot=room_foot)
            v.placed = Some((x, y, pw, ph))
            c.native(n, content=Some((x, y, pw, ph))) |> ignore
            player_still(c, n, still, x, y, pw, ph)
          }
          _ => ()
        }
        if f.audio {
          player_cover(c, name, ink)
        }
        player_waits(c, p, f, ink)
      })
      |> ignore
      c.box(style=@ui.style(w=Fixed(panel), h=Full), fn() {  }) |> ignore
    })
    |> ignore
    player_cue(c, if p.subtitle().1 { f.said } else { "" }, f.shown > desk_half, panel, over=desk_cue_over(c.width))
    // the bar along the top
    c.layer(fn() {
      // which of the folder's, its size; a film's own facts after them
      let facts = if picture { film_facts(file.facts, s, fr) } else { "" }
      let meta = joined([if many && index >= 0 { "\{index + 1} / \{list.length()}" } else { "" }, file_size(file.size), facts], " · ")
      if viewer_bar(c, key + "/bar", back_label, name, meta, !f.on && !listing, bar_ink, title=file.title, fn() {
          if many && viewer_tool(c, key + "/list", "list", t("web-pages.drive.player.list"), bar_ink, on=listing) {
            v.listing = !listing
          }
          if viewer_download(c, key + "/download", bar_ink) {
            (file.save)()
          }
        }) {
        desk_leave(c, v, on_back)
      }
    })
    |> ignore
    // 选集, docked at the right under the bar
    if listing {
      c.layer(fn() { desk_play_list(c, v, p, list, index, f.phase == Playing, go, picture) }) |> ignore
    }
    // the controls over the foot
    c.layer(fn() {
      c.box(style=desk_controls_place, fn() {
        c.box(style=desk_play_row_end, fn() {
          c.box(style=desk_grow_middle, fn() {
            let most = dmin(media_bar_most, dmax(desk_none, c.width - panel - 2.0 * media_bar_in))
            let over = if desk_narrow(c.width) { desk_time_over } else { media_bar_top }
            let n = c.box(style=media_bar_box().then(@ui.style(w=Fixed(most), pt=room(over), bg=Data(ink.ground))), id=c.id(key + "/desk-controls"), fn() {
              desk_play_controls(c, v, p, s, f, fr, many, prev, next, go, full, picture, ink)
            })
            c.look(n, @ui.look(alpha=f.shown))
          })
          |> ignore
          c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
        })
        |> ignore
        // (over the navigation bar where the system's bars are over the window: a tablet's)
        let foot = (viewer_host().room)().1
        if foot > 0.0 {
          c.box(style=@ui.style(h=Fixed(foot)), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    ended_card(c, v, p, f, next, go, ink)
  })
  |> ignore
}

///|
/// Back from a player (`go_back`), the window as it was if the player made it fill the screen.
fn desk_leave(c : @ui.Ctx, v : PlayerView, go_back : () -> Unit) -> Unit {
  if v.fulled {
    v.fulled = false
    if @ui.full_screen() {
      c.set_full_screen(false)
    }
  }
  go_back()
}

///|
/// The controls: the timeline; then the one before, 15 s back, a frame back, play, a frame on, 15 s on, the one after;
/// where it is (the time, or paused its frame to the millisecond); the sound, the speed, the subtitle, the frame saved,
/// full screen.
fn desk_play_controls(
  c : @ui.Ctx,
  v : PlayerView,
  p : @kit.Media,
  s : @kit.MediaStatus,
  f : @kit.MediaFrame,
  fr : Frames,
  many : Bool,
  prev : String?,
  next : String?,
  go : (String) -> Unit,
  full : () -> Unit,
  picture : Bool,
  ink : MediaInk,
) -> Unit {
  let key = p.key()
  let on = f.on
  let playing = plays(p, f)
  let ready = s.duration > 0.0
  // (under 640 where it is said a line of its own over the timeline, as a phone's: the row is the keys')
  let said = where_runs(p, fr, s, playing, picture, ink)
  let narrow = desk_narrow(c.width)
  if narrow {
    c.box(style=desk_time_line, fn() { c.rich(said, style=desk_time_words) |> ignore }) |> ignore
  }
  desk_play_timeline(c, p, s, fr, on, ink)
  c.box(style=media_row(), fn() {
    c.box(style=media_group(), fn() {
      if many && media_key(c, key + "/prev", "skip-back", t("web-pages.drive.player.prev"), on && prev is Some(_), small=true, ink~) {
        match prev {
          Some(other) => go(other)
          None => ()
        }
      }
      if media_key(c, key + "/back15", "back-15", t("web-pages.drive.player.back15"), on, ink~) {
        p.seek_by(-p.nudge_ms())
        p.wake()
      }
      if picture && media_key(c, key + "/frame-back", "chevron-left", t("android-chat.video.prev"), on && ready, small=true, ink~) {
        step_frame(c, p, fr, -1)
      }
      if media_key(c, key + "/play", if playing { "pause" } else { "play" }, t(if playing { "web-main.video.pauseKey" } else { "web-main.video.playKey" }), on, bright=true, ink~) {
        p.play_pause()
        p.wake()
      }
      if picture && media_key(c, key + "/frame-on", "chevron-right", t("android-chat.video.next"), on && ready, small=true, ink~) {
        step_frame(c, p, fr, 1)
      }
      if media_key(c, key + "/forward15", "forward-15", t("web-pages.drive.player.forward15"), on, ink~) {
        p.seek_by(p.nudge_ms())
        p.wake()
      }
      if many && media_key(c, key + "/next", "skip-forward", t("web-pages.drive.player.next"), on && next is Some(_), small=true, ink~) {
        match next {
          Some(other) => go(other)
          None => ()
        }
      }
    })
    |> ignore
    c.box(style=desk_grow_clip, fn() {
      if !narrow {
        c.rich(said, style=media_time_words) |> ignore
      }
    })
    |> ignore
    c.box(style=media_group(), fn() {
      desk_volume(c, p, on, ink)
      // short of room (a narrow page, a finger's keys far apart), what is used least leaves the row for its ⋯, the
      // least first: 保存此帧, the subtitle, the speed (player_drop_grab)
      let gone : Array[MenuItem?] = []
      // the speed, as a figure: its menu of speeds
      let sid = c.id(key + "/speed")
      let speed_slot = c.id(key + "/speed-slot")
      c.box(id=speed_slot, taps=false, drop=player_drop_speed, fn() {
        if media_rate(c, key + "/speed", speed_label(p.speed()), t("web-pages.drive.player.rate"), on, ink~) {
          v.rates = !v.rates
          p.wake()
        }
      })
      |> ignore
      speed_menu(c, v, p, sid)
      let (subtitle, subs_on) = p.subtitle()
      let subs_label = t(if subs_on { "web-pages.drive.player.captionsOff" } else { "web-pages.drive.player.captionsOn" })
      let subs_flip = fn() {
        p.toggle_subtitle()
        p.wake()
      }
      if subtitle {
        let slot = c.id(key + "/captions-slot")
        c.box(id=slot, taps=false, drop=player_drop_subtitle, fn() {
          if media_key(c, key + "/captions", "captions", subs_label, on, small=true, lit=subs_on, ink~) {
            subs_flip()
          }
        })
        |> ignore
        if c.left_out(slot) {
          gone.push(Some(more_line(subs_label, "captions", disabled=!on, on_press=subs_flip)))
        }
      }
      // 保存此帧: paused, the frame shown at its own size
      let grabs = on && !playing && ready && !v.grabbing
      if picture {
        let slot = c.id(key + "/save-frame-slot")
        c.box(id=slot, taps=false, drop=player_drop_grab, fn() {
          if media_key(c, key + "/save-frame", "camera", t("android-chat.video.saveFrame"), grabs, small=true, ink~) {
            grab(v, p, fr)
            p.wake()
          }
        })
        |> ignore
        if c.left_out(slot) {
          gone.push(
            Some(
              more_line(t("android-chat.video.saveFrame"), "camera", disabled=!grabs, on_press=fn() {
                grab(v, p, fr)
                p.wake()
              }),
            ),
          )
        }
      }
      // (the speeds in it under their name, the one it plays at chosen)
      if c.left_out(speed_slot) {
        if !gone.is_empty() {
          gone.push(None)
        }
        gone.push(Some(menu_item_of(t("web-pages.drive.player.rate"), fn() {  }, heading=true)))
        for sp in player_speeds {
          gone.push(
            Some(
              menu_item_of(speed_label(sp), fn() {
                  p.set_speed(sp)
                  p.wake()
                }, chosen=sp == p.speed(), disabled=!on),
            ),
          )
        }
      }
      // 全屏: the window filling the screen (macOS's), back as it was (and as the player is left)
      if picture && @ui.platform() == 0 {
        let is_full = @ui.full_screen()
        if media_key(c, key + "/full", if is_full { "shrink" } else { "expand" }, t(if is_full { "web-pages.drive.player.unfull" } else { "web-pages.drive.player.full" }), on, small=true, ink~) {
          full()
        }
      }
      // what left the row, in its ⋯ (there only while something did), opened over it as the speeds are
      let more = key + "/more"
      let open = menu_open.val == more
      c.box(more=true, fn() {
        if media_key(c, more, "more", t("web-main.menu.more"), on, small=true, lit=open, ink~) {
          menu_open.val = if open { "" } else { more }
          p.wake()
        }
      })
      |> ignore
      menu_items(c, more, c.id(more), gone, side=Top, along=End) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The sound: a button that mutes, and beside it a line 72 wide to press or drag along (in twentieths), how loud on it
/// in the words, a 10 head.
fn desk_volume(c : @ui.Ctx, p : @kit.Media, on : Bool, ink : MediaInk) -> Unit {
  let key = p.key()
  let (volume, muted) = p.volume()
  let silent = muted || volume == 0.0
  c.box(style=desk_volume_row(), fn() {
    if media_key(c, key + "/mute", if silent { "volume-x" } else { "volume" }, t(if silent { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }), on, small=true, ink~) {
      p.toggle_mute()
      p.wake()
    }
    let id = c.id(key + "/volume")
    // (pressed along it, not clicked: it takes presses all the same)
    if on {
      c.takes_presses(id)
    }
    // pressed along it: as loud as where (told the player once the frame's builds are over)
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && c.pressed(id) => {
        let (px, _, _) = c.pointer()
        let to = (dmin(desk_whole, dmax(desk_none, (px - x) / dmax(desk_whole, w))) * desk_volume_steps).round() / desk_volume_steps
        c.after_build(key + "/volume", fn() {
          p.set_volume(to)
          p.wake()
        })
      }
      _ => ()
    }
    let shown = if muted { desk_none } else { volume }
    let b = c.box(style=desk_volume_line(), id=if on { id } else { 0 }, fn() {
      c.box(style=media_track.then(@ui.style(bg=Data(alpha(ink.text, media_track_share)))), fn() {
        c.layer(fn() { media_share_bar(c, shown, ink.text) }) |> ignore
      })
      |> ignore
      c.layer(fn() { media_head(c, shown, ink.text, small=true) }) |> ignore
    })
    c.semantics(b, Slider, id~, label=t("web-pages.drive.player.volume"), range=(desk_none, desk_whole, shown))
  })
  |> ignore
}

///|
/// Where it is, to click or drag to a place: the track on the words at 20%, what has come at 22% over it, what has
/// played in the words, the head; dragged, the picture goes with the pointer frame by frame (@kit.Media scrub_to);
/// with the pointer over it (or dragging), the time where it points over it.
fn desk_play_timeline(c : @ui.Ctx, p : @kit.Media, s : @kit.MediaStatus, fr : Frames, on : Bool, ink : MediaInk) -> Unit {
  let id = c.id(p.key() + "/desk-timeline")
  p.timeline(c, id, on, inset=player_track_inset, snap=fn(ms) { fr.snap(ms) })
  let dur = s.duration
  let part = fn(ms : Double) { if dur <= 0.0 { desk_none } else { dmin(desk_whole, dmax(desk_none, ms / dur)) } }
  let shown = part(p.scrubbing().unwrap_or(s.position))
  let came = part(s.buffered)
  c.box(style=media_timeline_box(), id=if on { id } else { 0 }, fn() {
    c.box(style=media_track.then(@ui.style(bg=Data(alpha(ink.text, media_track_share)))), fn() {
      c.layer(fn() { media_share_bar(c, came, alpha(ink.text, media_came_share)) }) |> ignore
      c.layer(fn() { media_share_bar(c, shown, ink.text) }) |> ignore
    })
    |> ignore
    // the head where it is
    c.layer(fn() { media_head(c, shown, ink.text, rail=true) }) |> ignore
    // with a mouse over it (or dragging), the time where it points, over it
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && dur > 0.0 && (c.lit(id) || c.pressed(id)) => {
        let (px, _, _) = c.pointer()
        let track = dmax(desk_whole, w - 2.0 * player_track_inset)
        let at = dmin(desk_whole, dmax(desk_none, (px - x - player_track_inset) / track))
        c.layer(fn() {
          c.box(style=desk_pointed, tx=px - x - desk_pointed_w / 2.0, ty=-desk_pointed_up, fn() {
            c.rich([@ui.span(clock(at * dur), mono=true)], style=desk_pointed_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// 选集: the folder's others docked at the right under the bar, a line before them (a film's on its dark, a song's on the
/// page): 选集 and which of how many, its close; each numbered, the one playing marked with ▶ (✓ paused).
fn desk_play_list(
  c : @ui.Ctx,
  v : PlayerView,
  p : @kit.Media,
  list : Array[String],
  index : Int,
  playing : Bool,
  go : (String) -> Unit,
  picture : Bool,
) -> Unit {
  let pal = theme().p
  let key = p.key()
  let (ground, line, words, quiet, chosen) = if picture {
    (player_list_dark, alpha(media_dark_text, player_dark_line), media_dark_text, media_dark_muted, alpha(media_dark_text, player_dark_chosen))
  } else {
    (pal.canvas, pal.line, pal.text, pal.muted, pal.selected)
  }
  let hover = if picture { alpha(words, media_hot_share) } else { pal.hover }
  let ink : ViewerInk = { ground, ink: words, muted: quiet, line, hover, chosen }
  c.box(style=desk_panel_place, fn() {
    c.box(style=desk_panel_top(), fn() {  }) |> ignore
    c.box(style=desk_panel_row, fn() {
      c.box(style=desk_panel_room, fn() {  }) |> ignore
      c.box(style=desk_panel_box.then(@ui.style(bg=Data(ground))), id=c.id(key + "/list-panel"), fn() {
        c.box(style=desk_list_head, fn() {
          c.text(t("web-pages.drive.player.list"), style=desk_panel_title.then(@ui.text_style(color=Data(words)))) |> ignore
          c.box(style=desk_grow, fn() {
            c.text("\{index + 1} / \{list.length()}", style=desk_panel_note.then(@ui.text_style(color=Data(quiet)))) |> ignore
          })
          |> ignore
          if viewer_tool(c, key + "/list-close", "close", t("common.close"), ink) {
            v.listing = false
          }
        })
        |> ignore
        c.box(style=desk_panel_list, fn() {
          c.list(key + "/list", list.length(), desk_row_h, fn(i) {
            let id = c.id(key + "/list/\{i}")
            let now = i == index
            if !now && c.clicked(id) {
              go(list[i])
            }
            let hot = c.lit(id) || c.pressed(id)
            c.box(style=desk_list_row.then(@ui.style(bg=Data(if now { chosen } else if hot { alpha(words, media_hot_share) } else { no_ground }))), id~, fn() {
              c.box(style=desk_chapter_number, fn() {
                c.text("\{i + 1}", style=desk_chapter_n_words.then(@ui.text_style(color=Data(quiet)))) |> ignore
              })
              |> ignore
              c.box(style=desk_grow_clip, fn() {
                c.text(list[i], style=(if now { desk_list_now } else { desk_list_words }).then(@ui.text_style(color=Data(words)))) |> ignore
              })
              |> ignore
              if now {
                icon(c, if playing { "play" } else { "check" }, size=desk_check_icon, color=words) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

// ── a phone's ───────────────────────────────────────────────────────────

///|
/// The player on a phone's page (see the file's head): its controls float over the picture and go when it is left
/// alone while it plays (a tap brings them back): the bar at the top (back, the name, which of the folder's, 选集), at
/// the foot where it is over its timeline, then the one before, 15 s back (paused: a frame back), play, 15 s on (a frame
/// on), the one after; the speed, the subtitle, the frame saved (paused), fit or fill, sideways.
fn phone_player(
  c : @ui.Ctx,
  p : @kit.Media,
  file : ViewerFile,
  list : Array[String],
  back_label : String,
  on_back : () -> Unit,
  on_go : (String) -> Unit,
  still : String,
) -> Unit {
  ignore(back_label)
  let f = p.frame(c)
  let s = f.status
  let key = p.key()
  let v = view_for(key)
  let picture = !f.audio
  let ink = media_ink(picture)
  let (room_top, room_foot) = (viewer_host().room)()
  let name = file.name
  let index = list.search(name).unwrap_or(-1)
  let next = next_in(name, list)
  let prev = if index > 0 { list.get(index - 1) } else { None }
  let many = list.length() > 1
  let fr = frames_of(p, s, p.scrubbing().unwrap_or(s.position))
  take_grab(v, p, name)
  let go = fn(other : String) {
    p.pause()
    on_go(other)
  }
  let back = fn() {
    if p.is_sideways() {
      p.upright()
    } else {
      on_back()
    }
  }
  let stage = c.id(key + "/stage")
  @ui.capture(c, stage)
  // (a ground: a tap shows or hides the controls)
  c.cursor(stage, Arrow)
  phone_gestures(c, v, p, s, fr, stage, picture, back)
  c.box(style=player_fill.then(@ui.style(bg=Data(ink.stage))), fn() {
    // the picture where its zoom puts it, a drag down taking it down with the finger
    c.box(style=player_fill, id=stage, fn() {
      match p.native() {
        Some(n) if n.here() => {
          let (x, y, w, h) = picture_place(v, p, s, c.width, c.height, still)
          v.placed = Some((x, y + v.drag_dy, w, h))
          c.native(n, content=Some((x, y + v.drag_dy, w, h))) |> ignore
          player_still(c, n, still, x, y + v.drag_dy, w, h)
        }
        _ => ()
      }
    })
    |> ignore
    if f.audio {
      player_cover(c, name, ink)
    }
    player_cue(c, if p.subtitle().1 { f.said } else { "" }, f.shown > desk_half, desk_none, over=phone_cue_over())
    player_waits(c, p, f, ink)
    // what a double tap did, a held finger's 2×, where a finger along it has gone: said a moment in the middle
    let said = match (f.note, v.held >= 0.0, v.drag) {
      (_, _, AlongTime) => clock(p.scrubbing().unwrap_or(v.drag_to)) + " / " + (if s.duration > 0.0 { clock(s.duration) } else { "--:--" })
      (_, true, _) => t("web-pages.drive.player.held")
      (Some(note), _, _) => phone_note_words(note)
      _ => ""
    }
    if said != "" {
      c.layer(fn() {
        c.box(style=player_middle, fn() {
          c.box(style=player_pill.then(@ui.style(bg=Data(ink.ground))), fn() {
            c.text(said, style=player_pill_words.then(@ui.text_style(color=Data(ink.text)))) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    let shown = if v.drag == DownClose || v.taken_down { desk_none } else { f.shown }
    let live = f.on && v.drag != DownClose && !v.taken_down
    // the bar at the top: back, the name, which of the folder's it is, 选集
    c.layer(fn() {
      c.box(style=@ui.style(h=Fixed(room_top)), fn() {  }) |> ignore
      let n = c.box(style=phone_head_place.then(sides_clear(@ui.Space::S2.px())), fn() {
        c.box(style=phone_head_box.then(@ui.style(bg=Data(ink.ground))), fn() {
          // (said 返回 to a screen reader, as a phone's way back is; where to is the name beside it)
          if phone_key(c, key + "/back", "chevron-left", live, t("common.back"), ink) {
            back()
          }
          c.box(style=phone_name_box, fn() {
            c.text(name, style=phone_name_words.then(@ui.text_style(color=Data(ink.text)))) |> ignore
          })
          |> ignore
          if many && index >= 0 {
            c.text("\{index + 1} / \{list.length()}", style=phone_index_words.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
          }
          if many && phone_key(c, key + "/list", "list", live, t("web-pages.drive.player.list"), ink, lit=v.listing) {
            v.listing = true
            p.wake()
          }
          // 下载, as every file opened has it
          if phone_key(c, key + "/download", "download", live, t("web-main.preview.download"), ink) {
            (file.save)()
          }
        })
        |> ignore
      })
      c.look(n, @ui.look(alpha=shown))
    })
    |> ignore
    // the controls at the foot
    c.layer(fn() {
      c.box(style=desk_grow_full_h, fn() {  }) |> ignore
      let n = c.box(style=phone_foot_place.then(sides_clear(@ui.Space::S2.px())), fn() {
        phone_controls(c, v, p, s, f, fr, picture, many, prev, next, go, live, ink)
      })
      c.look(n, @ui.look(alpha=shown))
      c.box(style=@ui.style(h=Fixed(room_foot)), fn() {  }) |> ignore
    })
    |> ignore
    ended_card(c, v, p, f, next, go, ink)
  })
  |> ignore
  phone_list_sheet(c, v, p, list, index, f.phase == Playing, go)
}

///|
/// What a finger does on the picture: two zoom it; one along it moves through the time (the picture going with it frame
/// by frame, paused meanwhile: @kit.Media scrub_to), down it takes the picture down and closes it past player_close_dy (sideways: upright first), held still
/// it plays at 2× until let go; zoomed in, one moves what is shown (let go moving, it goes on, slowing). A tap or a
/// double tap is the player's own (@kit.Media stage: the controls; a side's 15 s; play or pause), not when the finger
/// did any of these, nor when it came down on the picture flinging (stopping it).
fn phone_gestures(
  c : @ui.Ctx,
  v : PlayerView,
  p : @kit.Media,
  s : @kit.MediaStatus,
  fr : Frames,
  stage : Int,
  picture : Bool,
  back : () -> Unit,
) -> Unit {
  let z = v.zoom
  let (px, py, down) = c.pointer()
  let press = c.press()
  // two fingers: a pinch round the point between them, which moves the picture as it moves
  match c.second_pointer() {
    Some((x2, y2)) if picture && c.held_down(stage) && z.nw > 0.0 => {
      let cx = (px + x2) / 2.0
      let cy = (py + y2) / 2.0
      let d = ((px - x2) * (px - x2) + (py - y2) * (py - y2)).sqrt()
      let (was_d, was_x, was_y) = v.pinch
      if was_d > 0.0 && d > 0.0 {
        z.transform(cx, cy, d / was_d, cx - was_x, cy - was_y)
      }
      v.pinch = (d, cx, cy)
      v.pinched = true
      v.drag = MoveZoom
      return
    }
    _ => v.pinch = (0.0, 0.0, 0.0)
  }
  if press.fresh && (c.held_down(stage) || c.clicked(stage)) {
    v.caught = z.stop_fling()
  }
  // (held from the moment it went down: what it does follows the finger from there, whatever shows it pressed later
  // over what scrolls, Ctx::pressed)
  if down && c.held_down(stage) {
    let dx = px - press.x
    let dy = py - press.y
    if v.drag == NoDrag && press.moved && !v.pinched {
      v.drag = if z.zoomed() {
        MoveZoom
      } else if dx.abs() > dy.abs() && s.duration > 0.0 {
        AlongTime
      } else if dy > 0.0 {
        DownClose
      } else {
        MoveZoom
      }
      v.drag_from = s.position
      v.drag_to = s.position
      p.wake()
    }
    match v.drag {
      AlongTime => {
        // a screen's width is as much as player_drag_span of it (all of it, a short one)
        let span = dmin(s.duration, player_drag_span)
        v.drag_to = dmax(0.0, dmin(s.duration, v.drag_from + dx / dmax(1.0, c.width) * span))
        p.scrub_to(fr.snap(v.drag_to))
      }
      DownClose => v.drag_dy = dmax(0.0, dy)
      MoveZoom => {
        let (lx, ly) = v.last
        if press.moved && !v.pinched {
          z.pan(px - lx, py - ly)
        }
      }
      NoDrag => ()
    }
    // held still: 2× while it is held (playing)
    if press.long && !press.moved && v.held < 0.0 && s.playing {
      v.held = p.speed()
      p.set_speed(player_held_speed)
    }
    v.last = (px, py)
  } else {
    let was = v.drag
    let held = v.held >= 0.0
    match was {
      AlongTime => p.scrub_done()
      DownClose =>
        if v.drag_dy > player_close_dy {
          // going (not turned upright first): its picture stays where the finger left it, to go from there
          v.taken_down = !p.is_sideways()
          back()
        }
      // let go moving: on at the finger's speed, slowing, to a stop or its edge
      MoveZoom =>
        if !v.pinched {
          let (fx, fy) = c.pointer_velocity()
          z.fling(fx, fy)
        }
      _ => ()
    }
    if held {
      p.set_speed(v.held)
      v.held = -1.0
    }
    v.drag = NoDrag
    if !v.taken_down {
      v.drag_dy = 0.0
    }
    if !down {
      v.pinched = false
    }
    // a tap or a double tap (none of the above)
    if was == NoDrag && !held && !press.long && !v.caught {
      p.stage(c, stage, c.width)
    }
  }
}

///|
/// What a double tap did, said a moment: 快退 15 秒, 快进 15 秒, 已暂停, 继续播放.
fn phone_note_words(note : @kit.MediaNote) -> String {
  match note {
    Back(ms) => t("android-misc.drive.player.back", args=[("n", (ms / 1000.0).to_int().to_string())])
    Ahead(ms) => t("android-misc.drive.player.ahead", args=[("n", (ms / 1000.0).to_int().to_string())])
    Paused => t("android-misc.drive.player.paused")
    Played => t("android-misc.drive.player.playing")
  }
}

///|
/// The controls (the foot): where it is over the timeline; the one before, 15 s back or (paused) a frame back, play,
/// 15 s on or a frame on, the one after; the speed, the subtitle, the frame saved (paused), fit or fill (sideways),
/// sideways. A finger down anywhere on them keeps them a while.
fn phone_controls(
  c : @ui.Ctx,
  v : PlayerView,
  p : @kit.Media,
  s : @kit.MediaStatus,
  f : @kit.MediaFrame,
  fr : Frames,
  picture : Bool,
  many : Bool,
  prev : String?,
  next : String?,
  go : (String) -> Unit,
  on : Bool,
  ink : MediaInk,
) -> Unit {
  let key = p.key()
  let id = c.id(key + "/controls")
  p.keep_awake(c, id)
  let playing = plays(p, f)
  let inspect = picture && !playing && s.duration > 0.0
  c.box(style=phone_controls_box().then(@ui.style(bg=Data(ink.ground))), id~, fn() {
    c.box(style=phone_time_box, fn() {
      c.rich(where_runs(p, fr, s, playing, picture, ink), style=phone_time_words) |> ignore
    })
    |> ignore
    phone_timeline(c, v, p, s, fr, on, ink)
    c.box(style=phone_keys_row(), fn() {
      if many &&
        phone_key(c, key + "/prev", "skip-back", on && prev is Some(_), t("android-misc.drive.player.prev"), ink, drop=phone_drop_steps) {
        match prev {
          Some(other) => go(other)
          None => ()
        }
      }
      if inspect {
        if phone_key(c, key + "/frame-back", "chevron-left", on, t("android-chat.video.prev"), ink) {
          step_frame(c, p, fr, -1)
        }
      } else if phone_key(c, key + "/back15", "back-15", on, t("android-misc.drive.player.back15"), ink) {
        p.seek_by(-p.nudge_ms())
        p.wake()
      }
      if phone_key(c, key + "/play", if playing { "pause" } else { "play" }, on, t(if playing { "android-chat.video.pause" } else { "android-chat.video.play" }), ink) {
        p.play_pause()
        p.wake()
      }
      if inspect {
        if phone_key(c, key + "/frame-on", "chevron-right", on, t("android-chat.video.next"), ink) {
          step_frame(c, p, fr, 1)
        }
      } else if phone_key(c, key + "/forward15", "forward-15", on, t("android-misc.drive.player.forward15"), ink) {
        p.seek_by(p.nudge_ms())
        p.wake()
      }
      if many &&
        phone_key(c, key + "/next", "skip-forward", on && next is Some(_), t("android-misc.drive.player.next"), ink, drop=phone_drop_steps) {
        match next {
          Some(other) => go(other)
          None => ()
        }
      }
      c.box(style=desk_grow, fn() {  }) |> ignore
      // the speed, as a figure: its menu of speeds
      let sid = c.id(key + "/speed")
      if phone_speed(c, key + "/speed", speed_label(p.speed()), on, t("android-misc.drive.player.speed"), ink, lit=v.rates) {
        v.rates = !v.rates
        p.wake()
      }
      speed_menu(c, v, p, sid)
      let (subtitle, subs_on) = p.subtitle()
      if subtitle &&
        phone_key(c, key + "/captions", "captions", on, t(if subs_on { "android-misc.drive.player.subtitlesOff" } else { "android-misc.drive.player.subtitlesOn" }), ink, lit=subs_on) {
        p.toggle_subtitle()
        p.wake()
      }
      if inspect && phone_key(c, key + "/save-frame", "camera", on && !v.grabbing, t("android-chat.video.saveFrame"), ink, drop=phone_drop_grab) {
        grab(v, p, fr)
        p.wake()
      }
      // turned sideways the picture can fill the screen (cropped) or fit in it
      if picture &&
        p.is_sideways() &&
        phone_key(c, key + "/fill", if p.fills() { "shrink" } else { "expand" }, on, t(if p.fills() { "android-misc.drive.player.fit" } else { "android-misc.drive.player.fill" }), ink, lit=p.fills()) {
        p.toggle_fill()
        p.wake()
      }
      if picture &&
        phone_key(c, key + "/sideways", "landscape", on, t(if p.is_sideways() { "android-misc.drive.player.unfull" } else { "android-misc.drive.player.full" }), ink, lit=p.is_sideways()) {
        p.toggle_sideways()
        p.wake()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where it is, to tap or drag to a place: a thin track, what has come lighter on it, what has played, a round head.
/// Dragged, the picture goes with the finger frame by frame (@kit.Media scrub_to), the time with it.
fn phone_timeline(c : @ui.Ctx, v : PlayerView, p : @kit.Media, s : @kit.MediaStatus, fr : Frames, on : Bool, ink : MediaInk) -> Unit {
  let id = c.id(p.key() + "/timeline")
  let dur = s.duration
  p.timeline(c, id, on, inset=player_track_inset, snap=fn(ms) { fr.snap(ms) })
  let part = fn(ms : Double) { if dur <= 0.0 { desk_none } else { dmin(desk_whole, dmax(desk_none, ms / dur)) } }
  let scrub = match (p.scrubbing(), v.drag) {
    (Some(x), _) => Some(x)
    (None, AlongTime) => Some(v.drag_to)
    _ => None
  }
  let shown = part(scrub.unwrap_or(s.position))
  c.box(style=phone_timeline_box(), id=if on { id } else { 0 }, fn() {
    c.box(style=media_track.then(@ui.style(bg=Data(alpha(ink.text, media_track_share)))), fn() {
      c.layer(fn() { media_share_bar(c, part(s.buffered), alpha(ink.text, media_came_share)) }) |> ignore
      c.layer(fn() { media_share_bar(c, shown, ink.text) }) |> ignore
    })
    |> ignore
    c.layer(fn() { media_head(c, shown, ink.text, rail=true) }) |> ignore
  })
  |> ignore
}

///|
/// A round key on the controls: 40, a 20 icon in the words; `lit`, a soft light behind it while what it turns on is
/// on; `drop`, the k-th to leave the row short of room (Ctx::box drop, phone_drop_grab). True on the frame it was
/// tapped; `on` false, it takes no tap (what is under it does).
fn phone_key(
  c : @ui.Ctx,
  key : String,
  icon_name : String,
  on : Bool,
  said : String,
  ink : MediaInk,
  lit? : Bool = false,
  drop? : Int = 0,
) -> Bool {
  let id = c.id(key)
  let b = c.box(style=phone_key_box.then(@ui.style(bg=Data(if lit { alpha(ink.text, media_lit_share) } else { no_ground }))), aspect=1.0, id=if on { id } else { 0 }, drop~, fn() {
    icon(c, icon_name, size=viewer_back_icon, color=ink.text) |> ignore
    if on {
      @motion.ripple(c, id, phone_key_r)
    }
  })
  c.semantics(b, Button, id~, label=said, disabled=!on, pressed=lit)
  on && c.clicked(id)
}

///|
/// The speed on the controls, as their keys are (40 high, bare until pressed or while its menu is open): its figure.
fn phone_speed(c : @ui.Ctx, key : String, words : String, on : Bool, said : String, ink : MediaInk, lit? : Bool = false) -> Bool {
  let id = c.id(key)
  let b = c.box(style=phone_speed_box.then(@ui.style(bg=Data(if lit { alpha(ink.text, media_lit_share) } else { no_ground }))), id=if on { id } else { 0 }, fn() {
    c.rich([@ui.span(words, weight=media_strong, mono=true, color=ink.text)], style=media_rate_words) |> ignore
    if on {
      @motion.ripple(c, id, phone_key_r)
    }
  })
  c.semantics(b, Button, id~, label=said, disabled=!on, pressed=lit)
  on && c.clicked(id)
}

///|
/// 选集 as the page's sheet: each of the folder's numbered, the one playing marked; one picked plays.
fn phone_list_sheet(c : @ui.Ctx, v : PlayerView, p : @kit.Media, list : Array[String], index : Int, playing : Bool, go : (String) -> Unit) -> Unit {
  let sheet = match viewer_host().sheet {
    Some(f) => f
    None => return
  }
  if !v.listing && !v.list_closing {
    return
  }
  let close = fn() {
    v.listing = false
    v.list_closing = true
  }
  let pal = theme().p
  sheet(c, {
    title: t("web-pages.drive.player.list"),
    trailing: if index >= 0 { "\{index + 1} / \{list.length()}" } else { "" },
    height: player_list_sheet,
    draggable: true,
    closing: !v.listing,
    close,
    gone: fn() { v.list_closing = false },
    body: fn() {
      c.box(style=desk_panel_list, fn() {
        c.list(p.key() + "/sheet-list", list.length(), desk_row_h, fn(i) {
          let id = c.id(p.key() + "/sheet-list/\{i}")
          let now = i == index
          if c.clicked(id) {
            close()
            if !now {
              go(list[i])
            }
          }
          c.box(style=desk_list_row.then(@ui.style(bg=Data(if now { pal.selected } else { no_ground }))), id~, fn() {
            c.box(style=desk_chapter_number, fn() {
              c.text("\{i + 1}", style=desk_chapter_n_words.then(@ui.text_style(color=Data(pal.muted)))) |> ignore
            })
            |> ignore
            c.box(style=desk_grow_clip, fn() {
              c.text(list[i], style=(if now { desk_list_now } else { desk_list_words }).then(@ui.text_style(color=Data(pal.text))))
              |> ignore
            })
            |> ignore
            if now {
              icon(c, if playing { "play" } else { "check" }, size=desk_check_icon, color=pal.text) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
  })
}

///|
/// A film's dark: a line on it (its words at 12%), the one chosen in its list (16%), the list's own ground.
let player_dark_line : Double = 0.12

///|
let player_dark_chosen : Double = 0.16

///|
let player_list_dark : Int64 = 0x18181BFFL

///|
/// The sound a key's step (↑ ↓) changes; zoom: a key's step, as it is, the wheel's and a pinch's (a pinch's small steps
/// under 50 by a hundredth of each, a wheel's notches by a five-hundredth), its glides.
let player_volume_key : Double = 0.05

///|
let player_zoom_step : Double = 1.25

///|
let player_whole : Double = 1.0

///|
let player_pinch_step : Double = 50.0

///|
let player_pinch_rate : Double = 0.01

///|
let player_wheel_rate : Double = 0.002

///|
/// Without the file's own frames, a step is a 60th of a second; how far past a time a frame may start and still be the
/// one showing then (a player says where it is in whole ms).
let player_guess_step : Double = 1000.0 / 60.0

///|
let player_frame_slack : Double = 1.0

///|
/// The next one plays this long after the end, unless let go; its seconds counted down.
pub let player_next_ms : Double = 5000.0

///|
let player_second_ms : Double = 1000.0

///|
/// The speeds' menu at least this wide.
let player_speeds_w : Double = 120.0

///|
/// A finger held: this fast while it is; a drag down past this closes; a screen's width along it is this much of the
/// time at most (all of a shorter one).
let player_held_speed : Double = 2.0

///|
let player_close_dy : Double = 120.0

///|
let player_drag_span : Double = 120000.0

///|
/// 选集's sheet: its share of the page.
let player_list_sheet : Double = 0.62

///|
/// A phone's key: 40 round; the waiting pill's spinner 12.
let phone_key_r : Double = 20.0

///|
let player_pill_spinner : Double = 12.0

///|
/// The controls at most 720 wide; the timeline 26 high, as tall as a press's room where that is more (@ui.room_least).
let phone_controls_most : Double = 720.0

///|
fn phone_timeline_h() -> Double {
  dmax(phone_timeline_least, @ui.room_least())
}

///|
let phone_timeline_least : Double = 26.0

///|
let player_next_w : Double = 280.0

///|
// kept across runs: a value (no field of it changes)
let player_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let desk_grow_full_h : @ui.Style = @ui.style(w=Full, h=grow)

///|
// kept across runs: a value (no field of it changes)
let player_middle : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// A pill in the middle (what it waits on, what a tap did): 12 and 6 in, 8 apart, round.
// kept across runs: a value (no field of it changes)
let player_pill : @ui.Style = @ui.css("row px=S3 py=S1_5 gap=S2 radius=Xl1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let player_pill_words : @ui.TextStyle = @ui.text_style(size=Ui, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let player_failed_box : @ui.Style = @ui.css("p=S8 gap=S3 align=ACenter")

///|
/// The next one's card: 280 wide, 20 and 16 in, 12 between; its button 40 high.
// kept across runs: a value (no field of it changes)
let player_next_box : @ui.Style = @ui.style(w=Fixed(player_next_w), px=S5, py=S4, gap=S3, radius=Xl1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let player_next_note : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let player_next_now : @ui.Style = @ui.css("w=Full h=S10 px=S4 radius=Xl align=ACenter justify=JCenter clip")

///|
// kept across runs: a value (no field of it changes)
let player_next_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let player_next_off : @ui.Style = @ui.css("px=S3 py=S1")

///|
/// A phone's bar at the top: 8 and 6 in, 48 high, its corner 16; the name 15 in 600, which of how many 12.
// kept across runs: a value (no field of it changes)
let phone_head_place : @ui.Style = @ui.css("w=Full px=S2 py=S1_5")

///|
// kept across runs: a value (no field of it changes)
let phone_head_box : @ui.Style = @ui.css("row w=Full h=S12 px=S1 gap=S1 radius=Xl1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let phone_name_box : @ui.Style = @ui.style(w=grow, px=S1, clip=true)

///|
// kept across runs: a value (no field of it changes)
let phone_name_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let phone_index_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
/// A phone's controls: 8 round them, 720 wide at most, 8 over, their corner a card's (26), its 40 buttons in its foot
/// corners as far in at the sides and foot as makes them concentric with it (capsule_in: 4.87).
// kept across runs: a value (no field of it changes)
let phone_foot_place : @ui.Style = @ui.css("w=Full p=S2 align=ACenter")

///|
fn phone_controls_box() -> @ui.Style {
  @ui.style(
    w=Full,
    max_w=Fixed(phone_controls_most),
    px=room(phone_keys_in),
    pt=S2,
    pb=room(phone_controls_foot()),
    radius=Xl3,
  )
}

///|
let phone_keys_in : Double = capsule_in(card_corner, 40.0)

///|
/// Under the keys' row: as much less than phone_keys_in as the row is taller than its keys (phone_keys_row), the keys
/// in the foot corners concentric with them where they were.
fn phone_controls_foot() -> Double {
  phone_keys_in - (phone_row_h() - phone_key_side) / 2.0
}

///|
// kept across runs: a value (no field of it changes)
let phone_time_box : @ui.Style = @ui.css("pl=S2_5")

///|
// kept across runs: a value (no field of it changes)
let phone_time_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
/// The timelines' track in from either side of what takes the pointer (their boxes' px).
pub let player_track_inset : Double = @ui.Space::S2_5.px()

///|
fn phone_timeline_box() -> @ui.Style {
  @ui.style(w=Full, h=Fixed(phone_timeline_h()), px=S2_5, justify=JCenter)
}

///|
/// The keys' row: 2 apart at least (media.css.ts vvGroup), so the one kept on (the subtitle, sideways) never meets the
/// one pressed, as far as makes each a press's room across (keys_gap); 40 high, as tall as a press's room where that is
/// more (its keys in its middle).
fn phone_keys_row() -> @ui.Style {
  phone_keys_look.then(@ui.style(h=Fixed(phone_row_h()), gap=keys_gap(size=phone_key_side)))
}

///|
fn phone_row_h() -> Double {
  dmax(phone_key_side, @ui.room_least())
}

///|
// kept across runs: a value (no field of it changes)
let phone_keys_look : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// A key: 40 across, round; where the row has not the room for them all, some leave it (phone_drop_grab), none
/// squeezed narrower (its press's room is its side and the room beside it: keys_gap).
// kept across runs: a value (no field of it changes)
let phone_key_box : @ui.Style = @ui.css("w=S10 radius=Full align=ACenter justify=JCenter")

///|
/// A key's side (phone_key_box's S10).
let phone_key_side : Double = 40.0

///|
/// Where the row has not the room for all its keys (a phone's narrowest with a paused picture's: its frames' steps, its
/// captions, 保存此帧), what leaves it first: 保存此帧, then the files before and after; the last key at its end stays
/// in the controls' foot corner, concentric with it, never past it.
let phone_drop_grab : Int = 1

///|
let phone_drop_steps : Int = 2

///|
/// Where the controls' row on a wider page has not the room for its keys (a finger's far apart on a narrow one), what
/// leaves it for its ⋯ first: 保存此帧, then the subtitle, then the speed (its speeds in the ⋯ under its name).
let player_drop_grab : Int = 1

///|
let player_drop_subtitle : Int = 2

///|
let player_drop_speed : Int = 3

///|
/// The speed: a capsule at least as wide as it is high (its ends 20 round: at the row's end in the controls' foot corner,
/// 6 in, concentric with it, as a key there is), never a pill standing on its end.
// kept across runs: a value (no field of it changes)
let phone_speed_box : @ui.Style = @ui.css("min_w=S10 h=S10 px=S2 radius=Full align=ACenter justify=JCenter")

///|
/// A song's mark (72) in the middle; the cue's words (16 on 1.6) on black at 60%; above the controls while they show
/// (112 off the foot), else 28.
let desk_cover_icon : Double = 72.0

///|
let desk_half : Double = 0.5

///|
/// The time where the pointer is (Player.css.ts pointed): over the timeline, 4 above it, on black at 75%, 11 in white.
let desk_pointed_w : Double = 56.0

///|
let desk_pointed_up : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let desk_pointed : @ui.Style = @ui.style(w=Fixed(desk_pointed_w), h=S5, radius=Md, bg=VeilDeep, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_pointed_words : @ui.TextStyle = @ui.text_style(size=Caption, color=OnVeil, wrap=false)

///|
/// The sound's line: in twentieths, 72 wide.
let desk_volume_steps : Double = 20.0

///|
/// Its mute and its line as far apart as keys are (keys_gap), so the mute is pressed in a press's room.
fn desk_volume_row() -> @ui.Style {
  desk_volume_look.then(@ui.style(gap=keys_gap(size=media_key_d)))
}

///|
// kept across runs: a value (no field of it changes)
let desk_volume_look : @ui.Style = @ui.css("row pr=S1_5 align=ACenter")

///|
/// The line: as tall as a press's room, as the timeline is (media_timeline_h).
fn desk_volume_line() -> @ui.Style {
  @ui.style(w=Fixed(desk_volume_w), h=Fixed(media_timeline_h()), justify=JCenter)
}

///|
let desk_volume_w : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let desk_play_ground : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let desk_play_row : @ui.Style = @ui.css("row w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let desk_grow_full : @ui.Style = @ui.style(w=grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_play_cover : @ui.Style = @ui.css("w=Full h=Full px=S8 gap=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let desk_cover_name : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_play_middle : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

// kept across runs: a value (no field of it changes)
let desk_play_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
/// A cue over a desktop's controls: as far off the foot as they reach (player_room), and 16 more (with keyboard and
/// mouse on a wide page, the 112 it stood at before).
fn desk_cue_over(width : Double) -> Double {
  player_room(width).1 + desk_cue_apart
}

///|
let desk_cue_apart : Double = 16.0

///|
/// Over a phone's controls: 112 off the foot (Player.kt), and as much more as the controls are taller where their
/// timeline and keys' row are a press's room (phone_timeline_h, phone_row_h, phone_controls_foot).
fn phone_cue_over() -> Double {
  phone_cue_least + (phone_timeline_h() - phone_timeline_least) + (phone_row_h() - phone_key_side) / 2.0
}

///|
let phone_cue_least : Double = 112.0

///|
// kept across runs: a value (no field of it changes)
let desk_cue_look : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let desk_cue_down : @ui.Style = @ui.css("w=Full h=Full pb=S7 justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let desk_cue_row : @ui.Style = @ui.css("row w=Full px=S4")

///|
// kept across runs: a value (no field of it changes)
let desk_cue_box : @ui.Style = @ui.css("px=S2 py=S0_5 radius=Md bg=Veil")

///|
// kept across runs: a value (no field of it changes)
let desk_cue_words : @ui.TextStyle = @ui.text_style(size=Title, color=OnVeil, center=true, leading=L7)

///|
/// The controls: 16 off the window's foot, in the middle of what the list leaves.
// kept across runs: a value (no field of it changes)
let desk_controls_place : @ui.Style = @ui.css("w=Full h=Full justify=JEnd").then(@ui.style(pb=room(media_bar_in)))

///|
// kept across runs: a value (no field of it changes)
let desk_play_row_end : @ui.Style = @ui.css("row w=Full")

///|
/// 选集's head (listHead: 12 over, 10 right, 6 under, 18 at its start) and rows (listRow: 40 at least, 8 and 10 in, the
/// page's corner; the one playing on the chosen ground, in 500).
// kept across runs: a value (no field of it changes)
let desk_list_head : @ui.Style = @ui.css("row w=Full pl=S4_5 pr=S2_5 pt=S3 pb=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @ui.css("row w=Full min_h=S10 px=S2_5 py=S2 gap=S1 align=ACenter radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let desk_list_words : @ui.TextStyle = @ui.text_style(size=Ui, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
// kept across runs: a value (no field of it changes)
let desk_list_now : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
/// Whether a desktop's controls are laid out as the web's phone sizes are (under 640: viewer_small_w): where it is said
/// on a line of its own over the timeline (as a phone's), the row under it the keys' alone.
fn desk_narrow(width : Double) -> Bool {
  width <= viewer_small_w
}

///|
/// That line: the bar 8 over it (a phone's, clear of its corner), 16 high, in from its side as the timeline's track is.
let desk_time_over : Double = 8.0

///|
let desk_time_h : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let desk_time_line : @ui.Style = @ui.style(h=Fixed(desk_time_h), pl=S2_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_time_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, wrap=false)

///|
/// A line of the controls' ⋯ (desk_play_controls): what a key that left their row does, `on_press` once it is chosen.
fn more_line(label : String, icon : String, disabled~ : Bool, on_press~ : () -> Unit) -> MenuItem {
  menu_item_of(label, on_press, icon~, disabled~)
}
