// A video or a song played as it streams, how a player behaves (still.fail's Android drive/Player.kt, its media app's
// videos): the system's player in a native view under the canvas (@ui.NativeView::video), its bytes asked a part at a
// time of the `read` it is given, never fetched whole first; opened at a place, tried again where it failed; its
// controls left alone while it plays fading away and a tap bringing them back (a song's stay); a tap or a double tap on
// the picture (a double one on its left or right third jumping back or on, in its middle playing or pausing, said a
// moment); its timeline tapped or dragged (the time following the finger, the player sent there once let go); its speed
// stepped, its subtitle's words at their time and turned off, the picture fitted or filling the screen turned sideways.
// How it looks and what it says are the view's (still.fail's src/player): this is what the fingers and the clock do.

///|
/// What is played: its name, its media type, whether it is known to be a song, and how its bytes are read
/// (`read(offset, length, answer)`: `answer(bytes, total, more)` as they come, what it gives back stopping it, as
/// `@ui.NativeView::video` reads).
pub(all) struct MediaTrack {
  name : String
  mime : String
  audio : Bool
  read : (Double, Int, (Bytes, Double, Bool) -> Unit) -> () -> Unit
}

///|
/// How a player stands, as its view says (or pinned, for a fixture's shot).
pub(all) struct MediaStatus {
  /// -1 failed, -2 unsupported format, -3 damaged file, -4 unsupported or damaged, 0 opening, 1 ready
  state : Int
  duration : Double
  position : Double
  buffered : Double
  playing : Bool
  buffering : Bool
  ended : Bool
  /// the picture's own size (0 × 0: none, or not known yet)
  width : Double
  height : Double
} derive(Eq, Show, Debug)

///|
/// How `n` stands now (nothing open: opening, of no length).
pub fn media_status(n : @ui.NativeView?) -> MediaStatus {
  match n {
    Some(n) => {
      let (w, h) = n.natural()
      {
        state: n.state(),
        duration: n.duration(),
        position: n.position(),
        buffered: n.buffered(),
        playing: n.playing(),
        buffering: n.buffering(),
        ended: n.ended(),
        width: w,
        height: h,
      }
    }
    None =>
      {
        state: 0,
        duration: -1.0,
        position: 0.0,
        buffered: 0.0,
        playing: false,
        buffering: false,
        ended: false,
        width: 0.0,
        height: 0.0,
      }
  }
}

///|
/// What is playing, in the terms a person cares about.
pub(all) enum MediaPhase {
  Opening
  Buffering
  Playing
  Paused
  Ended
  Failed
} derive(Eq, Show, Debug)

///|
/// What a double tap did, said a moment (the view's words for it): `nudge_ms` back, on, paused, played.
pub(all) enum MediaNote {
  Back(Double)
  Ahead(Double)
  Paused
  Played
} derive(Eq, Show, Debug)

///|
/// A frame of the player: how it stands, what is playing, whether it is a song, whether what it waits on has been
/// waited on long enough to say and how fast its bytes come meanwhile (bytes a second over the wait's last whole
/// second; -1 not waiting, or not a second yet), how far its controls show (0 … 1, coming or going) and whether they
/// take taps, the note a double tap said (while it is said), the subtitle's words now ("" none).
pub(all) struct MediaFrame {
  status : MediaStatus
  phase : MediaPhase
  audio : Bool
  waited : Bool
  rate : Double
  shown : Double
  on : Bool
  note : MediaNote?
  said : String
}

///|
/// A player: what it plays and how its controls stand. One per page that plays; `key` keeps its widgets and its clocks
/// apart from another's.
pub struct Media {
  priv key : String
  priv speeds : Array[Double]
  priv nudge_ms : Double
  priv rest_ms : Double
  priv double_tap_ms : Double
  priv note_ms : Double
  priv wake_ms : Double
  priv sleep_ms : Double
  priv wait_ms : Double
  priv mut track : MediaTrack?
  priv mut view : @ui.NativeView?
  priv mut start_at : Double
  priv mut started : Bool
  /// the place it opens at, owed to the player once the frame's builds are over (Media::frame)
  priv mut seek_owed : Bool
  priv mut speed : Double
  priv mut subs_on : Bool
  priv mut subtitle : Bool
  priv mut cues : Array[@codec.Cue]
  priv mut fill : Bool
  priv mut sideways : Bool
  priv mut awake : Bool
  /// a mouse's pointer over where its controls or its bar are (Media::near): they show while it is
  priv mut near : Bool
  priv mut poke : Int
  priv mut rest_key : String
  priv mut note : MediaNote?
  /// a tap waiting to be a single one (for double_tap_ms)
  priv mut tap_waiting : Bool
  /// where the timeline is dragged to (ms); -1: it is not
  priv mut scrub : Double
  /// where the player was last sent while it is dragged (ms; -1: not yet), whether it played when the finger came
  priv mut scrub_sent : Double
  priv mut scrub_played : Bool
  priv mut pinned : MediaStatus?
  /// how loud (0 … 1), and its sound off, kept for what it plays next
  priv mut volume : Double
  priv mut muted : Bool
  /// while it waits (opening, buffering): whether it does, the last whole second measured and the bytes it had been
  /// given by then (-1: none yet), how fast they came (Media::rate_now)
  priv mut waiting : Bool
  priv mut rate_tick : Int
  priv mut rate_bytes : Double
  priv mut rate : Double
}

///|
/// How long a player's controls stay left alone while it plays (Player.kt's 2.5 s), a note a double tap said is said
/// (0.8 s), its controls take to come as they are woken (0.12 s) and to fade as they rest (0.32 s, both on the
/// ease-out: still.fail's, viewer/media.css.ts): Media::new's, unless said otherwise.
pub let media_rest_ms : Double = 2500.0

///|
pub let media_note_ms : Double = 800.0

///|
pub let media_wake_ms : Double = 120.0

///|
pub let media_sleep_ms : Double = 320.0

///|
/// A player with nothing in it yet. Its ways, as Player.kt's: the speeds a tap steps through, what a double tap on a
/// side jumps, how long its controls stay left alone while it plays (0: they stay), a double tap's second tap's time,
/// how long a note is said, how long its controls take to come and to go, how long it waits before it says it is
/// waiting.
pub fn Media::new(
  key? : String = "media",
  speeds? : Array[Double] = [1.0, 1.25, 1.5, 2.0, 0.5, 0.75],
  nudge_ms? : Double = 15000.0,
  rest_ms? : Double = media_rest_ms,
  double_tap_ms? : Double = @ui.double_tap_ms,
  note_ms? : Double = media_note_ms,
  wake_ms? : Double = media_wake_ms,
  sleep_ms? : Double = media_sleep_ms,
  wait_ms? : Double = 400.0,
) -> Media {
  {
    key,
    speeds,
    nudge_ms,
    rest_ms,
    double_tap_ms,
    note_ms,
    wake_ms,
    sleep_ms,
    wait_ms,
    track: None,
    view: None,
    start_at: 0.0,
    started: false,
    seek_owed: false,
    speed: 1.0,
    subs_on: true,
    subtitle: false,
    cues: [],
    fill: false,
    sideways: false,
    awake: true,
    near: false,
    poke: 0,
    rest_key: "",
    note: None,
    tap_waiting: false,
    scrub: -1.0,
    scrub_sent: -1.0,
    scrub_played: false,
    pinned: None,
    volume: 1.0,
    muted: false,
    waiting: false,
    rate_tick: 0,
    rate_bytes: 0.0,
    rate: -1.0,
  }
}

///|
/// `track` played from `start` ms in (0: its start), at the speed chosen; what played before stops.
pub fn Media::open(self : Media, track : MediaTrack, start? : Double = 0.0) -> Unit {
  self.close_view()
  let n = @ui.NativeView::video(track.mime, track.read)
  if self.speed != 1.0 {
    n.rate(self.speed)
  }
  if self.muted || self.volume < 1.0 {
    n.volume(if self.muted { 0.0 } else { self.volume })
  }
  if start > 0.0 {
    n.seek(start)
  }
  n.play()
  self.view = Some(n)
  self.track = Some(track)
  self.start_at = start
  self.started = false
  self.awake = true
  self.scrub = -1.0
  self.scrub_sent = -1.0
  self.waiting = false
  @ui.log("player: open \{track.name} (\{track.mime}) from \{start.to_int()} ms")
}

///|
/// Opened again where it was (after it failed).
pub fn Media::retry(self : Media) -> Unit {
  match self.track {
    Some(t) => {
      let at = self.position()
      self.open(t, start=if at > 0.0 { at } else { self.start_at })
    }
    None => ()
  }
}

///|
fn Media::close_view(self : Media) -> Unit {
  match self.view {
    Some(n) => n.close()
    None => ()
  }
  self.view = None
}

///|
/// Stopped and let go of (its view closed); upright again if it was sideways.
pub fn Media::close(self : Media) -> Unit {
  self.close_view()
  self.upright()
}

///|
/// The subtitle beside it: there is one (its key shows), and its lines once read.
pub fn Media::set_subtitle(self : Media, there : Bool, cues : Array[@codec.Cue]) -> Unit {
  self.subtitle = there
  self.cues = cues
}

///|
/// How it stands shown as `s` whatever the view says (a fixture's shots, the same on every run).
pub fn Media::pin(self : Media, s : MediaStatus) -> Unit {
  self.pinned = Some(s)
}

///|
/// How it stands now.
pub fn Media::status(self : Media) -> MediaStatus {
  match self.pinned {
    Some(s) => s
    None => media_status(self.view)
  }
}

///|
/// Its key: what keeps its widgets apart from another's (the view's names its own after it).
pub fn Media::key(self : Media) -> String {
  self.key
}

///|
/// What it plays (None before it opens anything).
pub fn Media::track(self : Media) -> MediaTrack? {
  self.track
}

///|
/// Its native view, while one is open.
pub fn Media::native(self : Media) -> @ui.NativeView? {
  self.view
}

///|
/// Where it is (ms).
pub fn Media::position(self : Media) -> Double {
  self.status().position
}

///|
/// Its length (ms; -1 not known).
pub fn Media::duration(self : Media) -> Double {
  self.status().duration
}

///|
/// Whether it has been ready to play (its length known, where it is worth keeping).
pub fn Media::started(self : Media) -> Bool {
  self.started
}

///|
/// Whether it is sideways (back turns it upright first).
pub fn Media::is_sideways(self : Media) -> Bool {
  self.sideways
}

///|
/// Upright again (back while sideways).
pub fn Media::upright(self : Media) -> Unit {
  if self.sideways {
    self.sideways = false
    @hostapi.set_sideways(false)
  }
}

///|
/// The speed it plays at.
pub fn Media::speed(self : Media) -> Double {
  self.speed
}

///|
/// Whether there is a subtitle beside it, and whether its words are shown.
pub fn Media::subtitle(self : Media) -> (Bool, Bool) {
  (self.subtitle, self.subs_on)
}

///|
/// Whether the picture fills the screen (turned sideways), cropped.
pub fn Media::fills(self : Media) -> Bool {
  self.fill
}

///|
/// Where the timeline is being dragged to (ms), while it is.
pub fn Media::scrubbing(self : Media) -> Double? {
  if self.scrub >= 0.0 {
    Some(self.scrub)
  } else {
    None
  }
}

///|
fn Media::phase(self : Media, s : MediaStatus) -> MediaPhase {
  if s.state < 0 {
    Failed
  } else if !self.started {
    Opening
  } else if s.ended {
    Ended
  } else if s.buffering {
    Buffering
  } else if s.playing {
    Playing
  } else {
    Paused
  }
}

///|
fn phase_code(p : MediaPhase) -> Int {
  match p {
    Opening => 0
    Buffering => 1
    Playing => 2
    Paused => 3
    Ended => 4
    Failed => 5
  }
}

///|
/// Its controls brought back (and kept a while again).
pub fn Media::wake(self : Media) -> Unit {
  self.awake = true
  self.poke += 1
}

///|
/// Its controls hidden while shown, shown while hidden (a click on its picture).
pub fn Media::toggle(self : Media) -> Unit {
  if self.awake {
    self.awake = false
  } else {
    self.wake()
  }
}

///|
/// A mouse's pointer over where its controls or its bar are (`on`): they show while it is, hidden or not.
pub fn Media::near(self : Media, on : Bool) -> Unit {
  self.near = on
}

///|
/// Played, or paused (at its end: from its start again).
pub fn Media::play_pause(self : Media) -> Unit {
  let s = self.status()
  match self.view {
    Some(n) =>
      if s.playing {
        n.pause()
      } else {
        if s.ended {
          n.seek(0.0)
        }
        n.play()
      }
    None => ()
  }
}

///|
/// Paused (another is opened in its place).
pub fn Media::pause(self : Media) -> Unit {
  match self.view {
    Some(n) => n.pause()
    None => ()
  }
}

///|
/// To `ms` in.
pub fn Media::seek(self : Media, ms : Double) -> Unit {
  match self.view {
    Some(n) => n.seek(ms)
    None => ()
  }
}

///|
/// To about `ms` in, at once (NativeView::seek_near: a jump, the very frame not waited for).
pub fn Media::seek_near(self : Media, ms : Double) -> Unit {
  match self.view {
    Some(n) => n.seek_near(ms)
    None => ()
  }
}

///|
/// About `delta` ms on (back, below 0), within its length, at once (Media::seek_near).
pub fn Media::seek_by(self : Media, delta : Double) -> Unit {
  let s = self.status()
  let mut to = s.position + delta
  if to < 0.0 {
    to = 0.0
  }
  if s.duration > 0.0 && to > s.duration {
    to = s.duration
  }
  self.seek_near(to)
}

///|
/// What a double tap on a side jumps (ms).
pub fn Media::nudge_ms(self : Media) -> Double {
  self.nudge_ms
}

///|
/// The speed after this one.
pub fn Media::step_speed(self : Media) -> Unit {
  let i = self.speeds.search(self.speed).unwrap_or(0)
  self.speed = self.speeds[(i + 1) % self.speeds.length()]
  match self.view {
    Some(n) => n.rate(self.speed)
    None => ()
  }
}

///|
/// The speeds it steps through, in order.
pub fn Media::speeds(self : Media) -> Array[Double] {
  self.speeds
}

///|
/// At `speed` from now on (one of its speeds, or another: a speed held a while, then let go).
pub fn Media::set_speed(self : Media, speed : Double) -> Unit {
  self.speed = speed
  match self.view {
    Some(n) => n.rate(speed)
    None => ()
  }
}

///|
/// How loud it plays (0 … 1), whether its sound is off.
pub fn Media::volume(self : Media) -> (Double, Bool) {
  (self.volume, self.muted)
}

///|
/// As loud as `volume` (0 … 1), its sound on again (none at 0).
pub fn Media::set_volume(self : Media, volume : Double) -> Unit {
  self.volume = if volume < 0.0 { 0.0 } else if volume > 1.0 { 1.0 } else { volume }
  self.muted = self.volume == 0.0
  match self.view {
    Some(n) => n.volume(self.volume)
    None => ()
  }
}

///|
/// Its sound off, or on again as loud as it was.
pub fn Media::toggle_mute(self : Media) -> Unit {
  self.muted = !self.muted
  match self.view {
    Some(n) => n.volume(if self.muted { 0.0 } else { self.volume })
    None => ()
  }
}

///|
/// The subtitle's words shown, or not.
pub fn Media::toggle_subtitle(self : Media) -> Unit {
  self.subs_on = !self.subs_on
}

///|
/// The picture filling the screen, or fitted in it.
pub fn Media::toggle_fill(self : Media) -> Unit {
  self.fill = !self.fill
}

///|
/// Turned sideways, or upright again.
pub fn Media::toggle_sideways(self : Media) -> Unit {
  self.sideways = !self.sideways
  @hostapi.set_sideways(self.sideways)
}

///|
/// The player this frame (asked once a frame, before what shows it is built): ready once it is (the place it opens at
/// owed to it where it took none before), its controls going once left alone `rest_ms` while it plays (a song's stay),
/// a tap left single after `double_tap_ms` bringing them or taking them away, a note said `note_ms`.
pub fn Media::frame(self : Media, c : @ui.Ctx) -> MediaFrame {
  let p = self
  let s = p.status()
  let name = match p.track {
    Some(t) => t.name
    None => ""
  }
  if s.state == 1 && !p.started {
    p.started = true
    let read = match p.view {
      Some(n) => n.bytes().to_int()
      None => 0
    }
    @ui.log("player: \{name} ready, \{s.duration.to_int()} ms long, \{read} bytes read")
    // the place it opens at, once more where the player took no seek before it was ready
    if p.start_at > 0.0 && s.position < p.start_at - 1000.0 {
      p.seek_owed = true
    }
  }
  // (told the player once the frame's builds are over: by the host's say of it, once)
  if p.seek_owed {
    c.after_build(p.key + "/seek", fn() {
      p.seek_owed = false
      p.seek(p.start_at)
    })
  }
  let phase = p.phase(s)
  let known_audio = match p.track {
    Some(t) => t.audio
    None => false
  }
  // no picture: none once its host is done opening it (a video's done at its first frame shown, its size known by
  // then); ready alone, a video's size may not be known yet (Android's ExoPlayer tells its size after it is ready)
  let host_done = match (p.pinned, p.view) {
    (Some(_), _) => true
    (None, Some(n)) => n.host_done()
    (None, None) => false
  }
  let audio = known_audio || (p.started && host_done && s.width <= 0.0)
  // left alone while it plays, the controls go (a song's stay): rest_ms from when that last changed
  let rest = "\{p.awake}|\{phase_code(phase)}|\{p.poke}|\{audio}"
  if rest != p.rest_key {
    p.rest_key = rest
    after(c, p.key + "/rest", false, p.rest_ms) |> ignore
  }
  if after(c, p.key + "/rest", p.awake && phase == Playing && !audio && p.rest_ms > 0.0, p.rest_ms) {
    p.awake = false
  }
  if p.note is Some(_) && after(c, p.key + "/note", true, p.note_ms) {
    p.note = None
  }
  // what it waits on said only once it has waited wait_ms, with how fast its bytes come meanwhile
  let waited = after(c, p.key + "/wait", phase is (Opening | Buffering), p.wait_ms)
  let rate = p.rate_now(c, phase is (Opening | Buffering))
  // a tap left single: the controls shown or hidden
  if p.tap_waiting && after(c, p.key + "/tap", true, p.double_tap_ms) {
    p.tap_waiting = false
    if p.awake && phase == Playing {
      p.awake = false
    } else {
      p.wake()
    }
  }
  let target = if p.awake || p.near || phase != Playing || audio { 1.0 } else { 0.0 }
  let shown = @motion.animate(c, p.key + "/shown", target, spec=@motion.tween(
      if target > 0.0 {
        p.wake_ms
      } else {
        p.sleep_ms
      },
      ease=Out,
    ))
  let said = if p.subs_on { @codec.cues_at(p.cues, s.position) } else { "" }
  { status: s, phase, audio, waited, rate, shown, on: shown > 0.0, note: p.note, said }
}

///|
/// How fast its bytes come while it waits (`waiting`: opening or buffering): those its player was given (the host's
/// count, NativeView::bytes) over each whole second of the clock (Ctx::every) from the first that began after the wait
/// did, as the last one ended; -1 when it does not wait, or before such a second is over.
fn Media::rate_now(self : Media, c : @ui.Ctx, waiting : Bool) -> Double {
  let bytes = match self.view {
    Some(n) => n.bytes()
    None => 0.0
  }
  if !waiting {
    self.waiting = false
    return -1.0
  }
  let k = c.every(1000.0)
  if !self.waiting {
    // (the second it began in counts for nothing: part of it was not waited)
    self.waiting = true
    self.rate_tick = k + 1
    self.rate_bytes = -1.0
    self.rate = -1.0
  }
  if k >= self.rate_tick {
    if self.rate_bytes >= 0.0 && k > self.rate_tick {
      let came = bytes - self.rate_bytes
      self.rate = (if came > 0.0 { came } else { 0.0 }) / (k - self.rate_tick).to_double()
    }
    if self.rate_bytes < 0.0 || k > self.rate_tick {
      self.rate_tick = k
      self.rate_bytes = bytes
    }
  }
  self.rate
}

///|
/// The picture's stage `id`, `w` wide, tapped: a tap waits to be a single one (the controls shown or hidden, Media::frame);
/// a second within double_tap_ms a double one: on the left third back nudge_ms, on the right on, in the middle played
/// or paused, said a moment (MediaFrame's note).
pub fn Media::stage(self : Media, c : @ui.Ctx, id : Int, w : Double) -> Unit {
  // (a ground, not a control: Ctx::cursor)
  c.cursor(id, Arrow)
  if !c.clicked(id) {
    return
  }
  let (x, _, _) = c.pointer()
  if !self.tap_waiting {
    self.tap_waiting = true
    restart(c, self.key + "/tap", self.double_tap_ms)
    return
  }
  self.tap_waiting = false
  let third = w / 3.0
  if x < third {
    self.seek_by(-self.nudge_ms)
    self.note = Some(Back(self.nudge_ms))
  } else if x > third * 2.0 {
    self.seek_by(self.nudge_ms)
    self.note = Some(Ahead(self.nudge_ms))
  } else {
    let was = self.status().playing
    self.play_pause()
    self.note = Some(if was { Paused } else { Played })
  }
  restart(c, self.key + "/note", self.note_ms)
}

///|
/// A finger down anywhere on the controls (`id`) keeps them a while.
pub fn Media::keep_awake(self : Media, c : @ui.Ctx, id : Int) -> Unit {
  let (px, py, down) = c.pointer()
  match c.rect_of(id) {
    Some((x, y, w, h)) if down && px >= x && px < x + w && py >= y && py < y + h => self.wake()
    _ => ()
  }
}

///|
/// The timeline `id` (taking taps while `on`; its track `inset` in from either side), tapped or dragged along to a time
/// (`snap`: what is gone to for a time, e.g. the start of the frame showing then): dragged, it goes with the finger
/// (Media::scrub_to) until let go (Media::scrub_done); tapped, there at once, played or paused as it was.
pub fn Media::timeline(
  self : Media,
  c : @ui.Ctx,
  id : Int,
  on : Bool,
  inset? : Double = 0.0,
  snap? : (Double) -> Double = fn(ms) { ms },
) -> Unit {
  let dur = self.status().duration
  let under = fn() -> Double? {
    match c.rect_of(id) {
      Some((x, _, w, _)) if dur > 0.0 => {
        let (px, _, _) = c.pointer()
        let track = w - 2.0 * inset
        let k = (px - x - inset) / (if track < 1.0 { 1.0 } else { track })
        Some(snap((if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }) * dur))
      }
      _ => None
    }
  }
  if on && c.pressed(id) {
    match under() {
      Some(ms) => self.scrub_to(ms)
      None => ()
    }
  } else if self.scrub >= 0.0 {
    // let go: where it was let go (its last move and its lifting can be one frame)
    match under() {
      Some(ms) if on => self.scrub = ms
      _ => ()
    }
    self.scrub_done()
  } else if on && c.clicked(id) {
    match under() {
      Some(ms) => {
        self.seek_near(ms)
        self.wake()
      }
      None => ()
    }
  }
}

///|
/// A finger moving it through the time, at `ms` now: paused while the finger is on it, the player told its seeks come
/// one after another (NativeView::scrub: each frame gone to shown before the next is taken up), sent there when that
/// is not where it was last sent; Media::scrubbing says where, until Media::scrub_done.
pub fn Media::scrub_to(self : Media, ms : Double) -> Unit {
  if self.scrub < 0.0 {
    self.scrub_played = self.status().playing
    self.scrub_sent = -1.0
    match self.view {
      Some(n) => {
        n.pause()
        n.scrub(true)
      }
      None => ()
    }
  }
  self.scrub = ms
  if ms != self.scrub_sent {
    self.scrub_sent = ms
    self.seek(ms)
  }
  self.wake()
}

///|
/// Whether it plays again once the finger moving it through the time lets go (paused meanwhile).
pub fn Media::scrub_resumes(self : Media) -> Bool {
  self.scrub >= 0.0 && self.scrub_played
}

///|
/// The finger let go: sent where it was last moved to (when the last seek was not there), its seeks as before, played
/// again if it played when the finger came.
pub fn Media::scrub_done(self : Media) -> Unit {
  if self.scrub < 0.0 {
    return
  }
  if self.scrub != self.scrub_sent {
    self.seek(self.scrub)
  }
  match self.view {
    Some(n) => {
      n.scrub(false)
      if self.scrub_played {
        n.play()
      }
    }
    None => ()
  }
  self.scrub = -1.0
  self.scrub_sent = -1.0
  self.wake()
}

///|
/// Where the picture shows in a stage `bw` × `bh` (x, y, w, h): fitted in it, or filling it turned sideways (cropped),
/// in its middle, on whole pixels (as the hole it shows through is); its size not known yet, a point in the middle (so
/// the player has somewhere to draw, and tells its size).
pub fn Media::picture_rect(self : Media, s : MediaStatus, bw : Double, bh : Double) -> (Double, Double, Double, Double) {
  if s.width > 0.0 && s.height > 0.0 {
    let kx = bw / s.width
    let ky = bh / s.height
    let k = if self.fill && self.sideways {
      if kx > ky {
        kx
      } else {
        ky
      }
    } else if kx < ky {
      kx
    } else {
      ky
    }
    let w = (s.width * k).round()
    let h = (s.height * k).round()
    (((bw - w) / 2.0).round(), ((bh - h) / 2.0).round(), w, h)
  } else {
    (bw / 2.0, bh / 2.0, 1.0, 1.0)
  }
}

///|
/// `key`'s wait (after) started now, from nothing (a note said, a tap waiting to be a double one).
fn restart(c : @ui.Ctx, key : String, ms : Double) -> Unit {
  after(c, key, false, ms) |> ignore
  after(c, key, true, ms) |> ignore
}
