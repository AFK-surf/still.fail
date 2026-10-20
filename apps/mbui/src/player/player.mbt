// A video or a song played as it streams through whoever reads it (ember apps/android drive/Player.kt PlayerScreen):
// the system's player in a native view under the canvas (src/ui/native.mbt: Media3's ExoPlayer on Android, AVPlayer on
// Apple), its bytes asked a part at a time of the `read` it is given (still.fail: `drive.read` through the core; the
// media app: its own service), never fetched whole first. Dark, as a viewer of pictures; its controls float over the
// picture and fade when left alone while it plays (a tap brings them back): the bar at the top (back, the name, which
// of the folder's it is), at the foot the time over where it is and how much is buffered (tapped or dragged along: the
// player goes there once let go), the one before, 15 s back, play, 15 s on, the one after, the speed, the subtitle beside
// it, fit or fill, sideways. A double tap on the left or right third jumps 15 s, in the middle it pauses or plays. A
// song has no picture: its mark and its name in the middle, its controls staying. Where it is goes to whoever keeps it
// (`position`, `duration`), and it opens at a place given (`open(start=)`).
//
// Not here, against Player.kt: the frosted glass (a native view under the bars cannot be blurred: a deeper solid tint),
// the subtitle's shadow (a dark ground under its words only), what was played kept on the device to play again from it
// (DriveCache's played: every play reads through `read` again).

///|
/// Its words (client/i18n/catalog/zh android-misc.json, android-chat.json, common.json).
let words : Map[String, String] = {
  "android-misc.drive.player.buffering": "正在缓冲",
  "android-misc.drive.player.failed": "播放失败",
  "android-misc.drive.player.retry": "重试",
  "android-misc.drive.player.ended": "播放结束",
  "android-misc.drive.player.nextOne": "下一个：{name}",
  "android-misc.drive.player.back": "快退 {n} 秒",
  "android-misc.drive.player.ahead": "快进 {n} 秒",
  "android-misc.drive.player.paused": "已暂停",
  "android-misc.drive.player.playing": "继续播放",
  "android-chat.video.playFailed": "播放失败",
  "common.opening": "正在打开",
}

///|
/// The words for `key`, `{name}`s put in from `args`.
pub fn word(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = words.get(key).unwrap_or(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// Dark whatever the theme, as a viewer of pictures: its text, what is quieter.
let ink : Int64 = 0xF4F4F5FFL

///|
let muted : Int64 = 0xFFFFFF99L

///|
/// The speeds offered, as a tap steps through them.
let speeds : Array[Double] = [1.0, 1.25, 1.5, 2.0, 0.5, 0.75]

///|
/// What a double tap on a side jumps (ms).
let nudge_ms : Double = 15000.0

///|
/// The controls fade after this long left alone while it plays.
let rest_ms : Double = 2500.0

///|
/// A second tap within this long of the first is a double tap (Compose's doubleTapTimeout); a single tap waits it out.
let double_tap_ms : Double = 300.0

///|
/// How long a note in the middle (快进 15 秒) stays.
let note_ms : Double = 800.0

///|
/// The controls coming or going.
let shown_ms : Double = 200.0

///|
/// What is played: its name, its media type, whether it is known to be a song, and how its bytes are read
/// (`read(offset, length, answer)`: `answer(bytes, total)`, as `@ui.NativeView::video` reads).
pub(all) struct Track {
  name : String
  mime : String
  audio : Bool
  read : (Double, Int, (Bytes, Double) -> Unit) -> Unit
}

///|
/// How it stands, as its view says (or pinned, for a fixture's shot).
pub(all) struct Status {
  /// -1 failed, 0 opening, 1 ready
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
}

///|
/// What is playing, in the terms a person cares about.
priv enum Phase {
  Opening
  Buffering
  Playing
  Paused
  Ended
  Failed
} derive(Eq)

///|
/// A player: what it plays and how its controls stand. One per page that plays.
pub struct Player {
  priv key : String
  priv mut track : Track?
  priv mut view : @ui.NativeView?
  priv mut start_at : Double
  priv mut started : Bool
  priv mut speed : Double
  priv mut subs_on : Bool
  priv mut subtitle : Bool
  priv mut cues : Array[Cue]
  priv mut fill : Bool
  priv mut sideways : Bool
  priv mut awake : Bool
  priv mut poke : Int
  priv mut rest_key : String
  priv mut note : String
  /// a tap waiting to be a single one (for double_tap_ms)
  priv mut tap_waiting : Bool
  /// where the timeline is dragged to (ms); -1: it is not
  priv mut scrub : Double
  priv mut pinned : Status?
}

///|
/// A player with nothing in it yet; `key` keeps its widgets apart from another's.
pub fn Player::new(key? : String = "player") -> Player {
  {
    key,
    track: None,
    view: None,
    start_at: 0.0,
    started: false,
    speed: 1.0,
    subs_on: true,
    subtitle: false,
    cues: [],
    fill: false,
    sideways: false,
    awake: true,
    poke: 0,
    rest_key: "",
    note: "",
    tap_waiting: false,
    scrub: -1.0,
    pinned: None,
  }
}

///|
/// `track` played from `start` ms in (0: its start), at the speed chosen; what played before stops.
pub fn Player::open(self : Player, track : Track, start? : Double = 0.0) -> Unit {
  self.close_view()
  let n = @ui.NativeView::video(track.mime, track.read)
  if self.speed != 1.0 {
    n.rate(self.speed)
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
  @ui.log(
    "player: open \{track.name} (\{track.mime}) from \{start.to_int()} ms",
  )
}

///|
/// Opened again where it was (after it failed).
pub fn Player::retry(self : Player) -> Unit {
  match self.track {
    Some(t) => {
      let at = self.position()
      self.open(t, start=if at > 0.0 { at } else { self.start_at })
    }
    None => ()
  }
}

///|
fn Player::close_view(self : Player) -> Unit {
  match self.view {
    Some(n) => n.close()
    None => ()
  }
  self.view = None
}

///|
/// Stopped and let go of (its view closed); upright again if it was sideways.
pub fn Player::close(self : Player) -> Unit {
  self.close_view()
  if self.sideways {
    self.sideways = false
    @host.set_sideways(false)
  }
}

///|
/// The subtitle beside it: there is one (its key shows), and its lines once read.
pub fn Player::set_subtitle(self : Player, there : Bool, cues : Array[Cue]) -> Unit {
  self.subtitle = there
  self.cues = cues
}

///|
/// How it stands shown as `s` whatever the view says (a fixture's shots, the same on every run).
pub fn Player::pin(self : Player, s : Status) -> Unit {
  self.pinned = Some(s)
}

///|
pub fn Player::status(self : Player) -> Status {
  match self.pinned {
    Some(s) => return s
    None => ()
  }
  match self.view {
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
/// Where it is (ms).
pub fn Player::position(self : Player) -> Double {
  self.status().position
}

///|
/// Its length (ms; -1 not known).
pub fn Player::duration(self : Player) -> Double {
  self.status().duration
}

///|
/// Whether it has been ready to play (its length known, where it is worth keeping).
pub fn Player::started(self : Player) -> Bool {
  self.started
}

///|
/// Whether it is sideways (back turns it upright first).
pub fn Player::is_sideways(self : Player) -> Bool {
  self.sideways
}

///|
/// Upright again (back while sideways).
pub fn Player::upright(self : Player) -> Unit {
  if self.sideways {
    self.sideways = false
    @host.set_sideways(false)
  }
}

///|
fn Player::phase(self : Player, s : Status) -> Phase {
  if s.state == -1 {
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
fn phase_code(p : Phase) -> Int {
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
fn Player::wake(self : Player) -> Unit {
  self.awake = true
  self.poke += 1
}

///|
fn Player::play_pause(self : Player, s : Status) -> Unit {
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
fn Player::seek(self : Player, ms : Double) -> Unit {
  match self.view {
    Some(n) => n.seek(ms)
    None => ()
  }
}

///|
fn Player::seek_by(self : Player, s : Status, delta : Double) -> Unit {
  let mut to = s.position + delta
  if to < 0.0 {
    to = 0.0
  }
  if s.duration > 0.0 && to > s.duration {
    to = s.duration
  }
  self.seek(to)
}

///|
/// The player over the whole page: the picture (or a song's mark), what is said over it, its bars. `list`: the
/// folder's playable names in order (empty: it alone), the one playing among them; `on_back` leaves, `on_open(name)`
/// plays another of them.
pub fn Player::view(
  self : Player,
  c : @ui.Ctx,
  list? : Array[String] = [],
  on_back : () -> Unit,
  on_open : (String) -> Unit,
) -> Unit {
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
      p.seek(p.start_at)
    }
  }
  let phase = p.phase(s)
  let known_audio = match p.track {
    Some(t) => t.audio
    None => false
  }
  let audio = known_audio || (p.started && s.width <= 0.0)
  // left alone while it plays, the controls go (a song's stay): rest_ms from when that last changed
  let rest = "\{p.awake}|\{phase_code(phase)}|\{p.poke}|\{audio}"
  if rest != p.rest_key {
    p.rest_key = rest
    @kit.after(c, p.key + "/rest", false, rest_ms) |> ignore
  }
  if @kit.after(c, p.key + "/rest", p.awake && phase == Playing && !audio, rest_ms) {
    p.awake = false
  }
  if p.note != "" && @kit.after(c, p.key + "/note", true, note_ms) {
    p.note = ""
  }
  // what it waits on said only once it has waited @sf.later_ms
  let waited = @kit.after(c, p.key + "/wait", phase is (Opening | Buffering), @sf.later_ms)
  // a tap left single: the controls shown or hidden
  if p.tap_waiting && @kit.after(c, p.key + "/tap", true, double_tap_ms) {
    p.tap_waiting = false
    if p.awake && phase == Playing {
      p.awake = false
    } else {
      p.wake()
    }
  }
  let target = if p.awake || phase != Playing || audio { 1.0 } else { 0.0 }
  let shown = @motion.animate(c, p.key + "/shown", target, spec=@motion.tween(shown_ms))
  let on = shown > 0.0
  let index = list.search(name).unwrap_or(-1)
  let next = next_in(name, list)
  let prev = if index > 0 { list.get(index - 1) } else { None }
  let glass = if audio { 0x1212149EL } else { 0x121214D9L }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=0x000000FFL, fn() {
    // the picture, fitted in the page or filling it (cropped), in the middle; a stage taking the taps
    let stage = c.id(p.key + "/stage")
    if c.clicked(stage) {
      let (px, _, _) = c.pointer()
      if p.tap_waiting {
        p.tap_waiting = false
        p.double_tap(c, s, px)
      } else {
        p.tap_waiting = true
        start_after(c, p.key + "/tap", double_tap_ms)
      }
    }
    c.box(w=Fill(1.0), h=Fill(1.0), id=stage, fn() {
      match p.view {
        Some(n) if n.here() => {
          let bw = c.width
          let bh = c.height
          let rect = if s.width > 0.0 && s.height > 0.0 {
            let kx = bw / s.width
            let ky = bh / s.height
            let k = if p.fill && p.sideways {
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
            // on whole pixels, as the hole it shows through is (no hairline of the page between them)
            let w = (s.width * k).round()
            let h = (s.height * k).round()
            (((bw - w) / 2.0).round(), ((bh - h) / 2.0).round(), w, h)
          } else {
            // not known yet: a point in the middle, so the player has somewhere to draw (and tells its size)
            (bw / 2.0, bh / 2.0, 1.0, 1.0)
          }
          c.native(n, content=Some(rect)) |> ignore
        }
        _ => ()
      }
    })
    |> ignore
    if audio {
      c.layer(align=ACenter, fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), pad=32.0, gap=12.0, align=ACenter, justify=JCenter, fn() {
          @sf.icon(c, "file-audio", size=56.0, color=muted) |> ignore
          c.text(name, size=16.0, color=ink, center=true, w=Fill(1.0)) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // the subtitle's words, over the foot (higher while the controls show)
    let said = if p.subs_on { cues_at(p.cues, s.position) } else { "" }
    if said != "" {
      c.layer(fn() {
        c.box(
          w=Fill(1.0),
          h=Fill(1.0),
          padx=24.0,
          pb=if shown > 0.5 { 132.0 } else { 28.0 },
          align=ACenter,
          justify=JEnd,
          fn() {
            c.box(bg=0x00000059L, radius=6.0, padx=8.0, pady=2.0, fn() {
              c.text(
                said,
                size=if p.sideways { 20.0 } else { 16.0 },
                line=if p.sideways { 26.0 } else { 22.0 },
                color=0xFFFFFFFFL,
                center=true,
              )
              |> ignore
            })
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    }
    // what it waits on, why it failed, what comes next
    c.layer(fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
        match phase {
          Opening | Buffering =>
            if waited {
              c.box(dir=Row, padx=12.0, pady=6.0, gap=8.0, radius=15.0, bg=glass, align=ACenter, fn() {
                @sf.spinner(c, size=12.0) |> ignore
                c.text(
                  if phase == Opening {
                    word("common.opening")
                  } else {
                    word("android-misc.drive.player.buffering")
                  },
                  size=13.0,
                  line=18.0,
                  color=ink,
                  wrap=false,
                )
                |> ignore
              })
              |> ignore
            }
          Failed => {
            c.box(pad=32.0, gap=12.0, align=ACenter, fn() {
              c.text(word("android-misc.drive.player.failed"), size=15.0, weight=600, color=ink, wrap=false)
              |> ignore
              if chip(c, p.key + "/retry", word("android-misc.drive.player.retry")) {
                p.retry()
              }
            })
            |> ignore
          }
          Ended => {
            match next {
              Some(other) =>
                c.box(gap=12.0, align=ACenter, fn() {
                  c.text(word("android-misc.drive.player.ended"), size=14.0, color=muted, wrap=false)
                  |> ignore
                  if chip(c, p.key + "/next-one", word("android-misc.drive.player.nextOne", args=[("name", other)])) {
                    p.pause_view()
                    on_open(other)
                  }
                })
                |> ignore
              None => ()
            }
          }
          _ => ()
        }
      })
      |> ignore
    })
    |> ignore
    if p.note != "" {
      c.layer(fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), pb=120.0, align=ACenter, justify=JCenter, fn() {
          c.box(bg=0x0000008CL, radius=12.0, padx=16.0, pady=9.0, fn() {
            c.text(p.note, size=14.0, color=ink, wrap=false) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // the bar at the top: back, the name, which of the folder's it is
    c.layer(fn() {
      c.box(w=Fill(1.0), padx=8.0, pady=6.0, opacity=shown, fn() {
        c.box(dir=Row, w=Fill(1.0), h=Px(48.0), radius=16.0, bg=glass, pl=4.0, pr=14.0, align=ACenter, fn() {
          if key_button(c, p.key + "/back", "chevron-left", on) {
            if p.sideways {
              p.upright()
            } else {
              on_back()
            }
          }
          let room = c.width - 16.0 - 18.0 - 40.0 - (if list.length() > 1 { 56.0 } else { 0.0 })
          c.box(padx=4.0, max_w=if room > 40.0 { room } else { 40.0 }, clip=true, fn() {
            c.text(name, size=15.0, weight=600, color=ink, wrap=false) |> ignore
          })
          |> ignore
          if list.length() > 1 && index >= 0 {
            c.box(pl=4.0, fn() {
              c.text("\{index + 1} / \{list.length()}", size=12.0, color=muted, wrap=false) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the controls at the foot
    c.layer(fn() {
      c.spacer()
      c.box(w=Fill(1.0), padx=8.0, pady=8.0, align=ACenter, opacity=shown, fn() {
        p.controls(c, s, phase, audio, on, glass, list, prev, next, on_open)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
fn Player::pause_view(self : Player) -> Unit {
  match self.view {
    Some(n) => n.pause()
    None => ()
  }
}

///|
/// A double tap at `x`: on the left third 15 s back, on the right 15 s on, in the middle play or pause; said a moment.
fn Player::double_tap(self : Player, c : @ui.Ctx, s : Status, x : Double) -> Unit {
  let third = c.width / 3.0
  let n = (nudge_ms / 1000.0).to_int().to_string()
  if x < third {
    self.seek_by(s, -nudge_ms)
    self.note = word("android-misc.drive.player.back", args=[("n", n)])
  } else if x > third * 2.0 {
    self.seek_by(s, nudge_ms)
    self.note = word("android-misc.drive.player.ahead", args=[("n", n)])
  } else {
    let was = s.playing
    self.play_pause(s)
    self.note = if was {
      word("android-misc.drive.player.paused")
    } else {
      word("android-misc.drive.player.playing")
    }
  }
  start_after(c, self.key + "/note", note_ms)
}

///|
/// The controls (Player.kt's foot): the time over the timeline; the one before, 15 s back, play, 15 s on, the one
/// after; the speed, the subtitle, fit or fill, sideways. A finger down anywhere on them keeps them a while.
fn Player::controls(
  self : Player,
  c : @ui.Ctx,
  s : Status,
  phase : Phase,
  audio : Bool,
  on : Bool,
  glass : Int64,
  list : Array[String],
  prev : String?,
  next : String?,
  on_open : (String) -> Unit,
) -> Unit {
  let p = self
  let id = c.id(p.key + "/controls")
  let (px, py, down) = c.pointer()
  match c.rect_of(id) {
    Some((x, y, w, h)) if down && px >= x && px < x + w && py >= y && py < y + h => p.wake()
    _ => ()
  }
  c.box(w=Fill(1.0), max_w=720.0, radius=bar_radius, bg=glass, pl=bar_side, pr=bar_side, pt=8.0, pb=bar_foot, id~, fn() {
    let at = if p.scrub >= 0.0 { p.scrub } else { s.position }
    c.box(pl=10.0, fn() {
      c.rich(
        [
          @ui.span(clock(at), color=ink, weight=600),
          @ui.span(" / " + (if s.duration > 0.0 { clock(s.duration) } else { "--:--" })),
        ],
        size=12.0,
        color=muted,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
    p.timeline(c, s, on)
    c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
      if list.length() > 1 &&
        key_button(c, p.key + "/prev", "skip-back", on && prev is Some(_)) {
        match prev {
          Some(other) => {
            p.pause_view()
            on_open(other)
          }
          None => ()
        }
      }
      if key_button(c, p.key + "/back15", "back-15", on) {
        p.seek_by(s, -nudge_ms)
        p.wake()
      }
      let playing = phase == Playing || phase == Buffering
      if key_button(c, p.key + "/play", if playing { "pause" } else { "play" }, on) {
        p.play_pause(s)
        p.wake()
      }
      if key_button(c, p.key + "/forward15", "forward-15", on) {
        p.seek_by(s, nudge_ms)
        p.wake()
      }
      if list.length() > 1 &&
        key_button(c, p.key + "/next", "skip-forward", on && next is Some(_)) {
        match next {
          Some(other) => {
            p.pause_view()
            on_open(other)
          }
          None => ()
        }
      }
      c.spacer()
      // the speed, as a figure: a tap goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×)
      let sid = c.id(p.key + "/speed")
      if on && c.clicked(sid) {
        let i = speeds.search(p.speed).unwrap_or(0)
        p.speed = speeds[(i + 1) % speeds.length()]
        match p.view {
          Some(n) => n.rate(p.speed)
          None => ()
        }
        p.wake()
      }
      // in the bar's bottom right corner (the audio's): as far from its right edge as from its foot, concentric with it
      let speed_inset = bar_foot + (key_size - speed_h) / 2.0
      c.box(pr=speed_inset - bar_side, fn() {
        c.box(
          h=Px(speed_h),
          min_w=44.0,
          radius=@ui.concentric(bar_radius, speed_inset),
          padx=8.0,
          bg=if p.speed != 1.0 { 0xFFFFFF24L } else { 0xFFFFFF0FL },
          align=ACenter,
          justify=JCenter,
          id=if on { sid } else { 0 },
          fn() {
            c.text(speed_label(p.speed), size=12.0, weight=600, color=ink, wrap=false) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
      if p.subtitle &&
        key_button(c, p.key + "/captions", "captions", on, lit=p.subs_on) {
        p.subs_on = !p.subs_on
        p.wake()
      }
      // turned sideways the picture can fill the screen (cropped) or fit in it
      if !audio &&
        p.sideways &&
        key_button(c, p.key + "/fill", if p.fill { "shrink" } else { "expand" }, on, lit=p.fill) {
        p.fill = !p.fill
        p.wake()
      }
      if !audio &&
        key_button(c, p.key + "/sideways", "landscape", on, lit=p.sideways) {
        p.sideways = !p.sideways
        @host.set_sideways(p.sideways)
        p.wake()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Where it is, to tap or drag to a place: a thin track, what is buffered lighter on it, what has played, a round head.
/// The time follows the finger while it drags; the player is sent there once it is let go.
fn Player::timeline(self : Player, c : @ui.Ctx, s : Status, on : Bool) -> Unit {
  let p = self
  let id = c.id(p.key + "/timeline")
  let dur = s.duration
  match c.rect_of(id) {
    Some((x, _, w, _)) if on && dur > 0.0 && c.pressed(id) => {
      let (px, _, _) = c.pointer()
      let k = (px - x) / (if w < 1.0 { 1.0 } else { w })
      p.scrub = (if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }) * dur
    }
    _ =>
      if p.scrub >= 0.0 {
        p.seek(p.scrub)
        p.scrub = -1.0
        p.wake()
      }
  }
  let part = fn(ms : Double) {
    if dur <= 0.0 {
      0.0
    } else {
      let k = ms / dur
      if k < 0.0 {
        0.0
      } else if k > 1.0 {
        1.0
      } else {
        k
      }
    }
  }
  let dragging = p.scrub >= 0.0
  let th = if dragging { 4.0 } else { 3.0 }
  let r = if dragging { 8.0 } else { 6.0 }
  let shown = part(if dragging { p.scrub } else { s.position })
  c.box(w=Fill(1.0), padx=10.0, fn() {
    c.box(w=Fill(1.0), h=Px(26.0), justify=JCenter, id=if on { id } else { 0 }, fn() {
      c.box(w=Fill(1.0), h=Px(th), radius=th / 2.0, bg=0xFFFFFF33L, fn() {  }) |> ignore
      share_bar(c, part(s.buffered), th, 0xFFFFFF59L)
      share_bar(c, shown, th, ink)
      // the head
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
          if shown > 0.0 {
            c.box(w=Fill(shown), fn() {  }) |> ignore
          }
          // no room of its own: centred on where it is, at the end as at the start
          c.box(w=Px(0.0), h=Px(r * 2.0), fn() {
            c.box(w=Px(r * 2.0), h=Px(r * 2.0), radius=r, bg=ink, tx=-r, fn() {  }) |> ignore
          })
          |> ignore
          if shown < 1.0 {
            c.box(w=Fill(1.0 - shown), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// `part` of the track from its start, `h` high, in `color`, over what is under it.
fn share_bar(c : @ui.Ctx, part : Double, h : Double, color : Int64) -> Unit {
  if part <= 0.0 {
    return
  }
  c.layer(fn() {
    c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
      c.box(w=Fill(part), h=Px(h), radius=h / 2.0, bg=color, fn() {  }) |> ignore
      if part < 1.0 {
        c.box(w=Fill(1.0 - part), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The controls' bar: its corner, its sides' and its foot's room; a key's size, the speed's height.
let bar_radius : Double = 20.0

///|
let bar_side : Double = 6.0

///|
let bar_foot : Double = 4.0

///|
let key_size : Double = 40.0

///|
let speed_h : Double = 30.0

///|
/// A round key on the controls (Player.kt Key): 40, a 20 icon; `lit`, a soft light behind it while what it turns on is
/// on. True on the frame it was tapped; `on` false, it takes no tap (what is under it does).
fn key_button(c : @ui.Ctx, key : String, icon : String, on : Bool, lit? : Bool = false) -> Bool {
  let id = c.id(key)
  let pressing = if on { @motion.pressing(c, id) } else { 0.0 }
  c.box(
    w=Px(key_size),
    h=Px(key_size),
    radius=key_size / 2.0,
    align=ACenter,
    justify=JCenter,
    bg=if lit {
      0xFFFFFF24L
    } else {
      @sf.alpha(0xFFFFFFFFL, 0.12 * pressing)
    },
    id=if on { id } else { 0 },
    fn() { @sf.icon(c, icon, size=20.0, color=ink) |> ignore },
  )
  |> ignore
  on && c.clicked(id)
}

///|
/// A choice over the picture (Player.kt Chip): its words on white at 14%, round 12.
fn chip(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  c.box(
    max_w=280.0,
    radius=12.0,
    bg=@sf.alpha(0xFFFFFFFFL, 0.14 + 0.08 * @motion.pressing(c, id)),
    padx=16.0,
    pady=9.0,
    clip=true,
    id~,
    fn() { c.text(label, size=14.0, color=ink, wrap=false) |> ignore },
  )
  |> ignore
  c.clicked(id)
}

///|
/// `key`'s @kit.after started now, from nothing (a note said, a tap waiting to be a double one).
fn start_after(c : @ui.Ctx, key : String, ms : Double) -> Unit {
  @kit.after(c, key, false, ms) |> ignore
  @kit.after(c, key, true, ms) |> ignore
}
