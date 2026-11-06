// A picture the host decodes frame by frame, drawn by the app as an image (still.fail's remote screens: its Android
// app's remote/Decoders.kt and ScreenSession.kt): the app hands it a sender's frames, H.264 (`h264`, a config, then
// `frame`s) or JPEG (`jpeg`), and draws it where it likes (`Ctx::stream`), under and over what it paints, faded,
// frosted, zoomed and panned as any picture. Not a native view: nothing of it is the system's but the decoding.
//
// The sender sends a few frames ahead of the last one the app acknowledged, so each frame comes back through `shown`
// once its fate is known: drawn, or let go. Which frame shows is said by events, never by what the host happens to
// have decoded: the host says "decoded, W × H" or "let go" of each frame (or that its decoder broke) as it comes, the
// framework takes those as a frame begins (frame_body, before the view builds) and the stream shows from that frame
// on the last one said decoded (the host told to latch it: @hostapi.stream_show). So what frame N draws depends only on
// the events taken by then, and a run's tape (VIEWSAID {"stream":…} lines, the host's words as they were taken)
// replays it exactly. `shown(ts)` is called once that frame is painted, for each frame taken in it, drawn or not (a
// page not showing the stream that frame let its frame go all the same); `broken()` as the event is taken, the app
// asking the sender for a key frame.
//
// Each frame handed over is the host's work until its event comes: a ticket of the window's runtime (effect.mb's
// outside, hostcall.mbt's outside_stream), "stream N frame TS", so a run is not at rest while a frame is out (a
// Tester's until the test says what became of it: Tester::stream_shows, stream_drops). A stream open between frames
// is at rest: nothing of it moves by the clock.
//
// The rules of Android's decoder (Decoders.kt), kept here where the host would only repeat them: until a key frame
// after a config or a broken decoder, frames are let go unseen; where nothing decodes H.264 (@hostapi.h264_here false,
// or no config yet) they are let go too. Those it lets go itself are said at the next frame's start, as a host's are.
//
// Under a Tester the host is the test's (Tester::new's `h264`; Tester::stream_fed, stream_shows, stream_drops,
// stream_broken), its picture a placeholder in the draw list: `image N PX "stream WxH ts=TS"`.
//
// Shown by the system (`layer`, where the host has a layer of its own for it: @hostapi.stream_layers, macOS's and
// iOS's, whose contents are the decoded frame's IOSurface; Windows', a composition swap chain the GPU puts the frame
// in): an H.264 stream drawn whole and as it is (`Ctx::stream`'s
// `layer`, stretched to its rect, not faded) is a native view of kind 4 under the canvas, its hole painted where the
// picture would be (native.mbt), each frame shown put on that layer by the host as well. While that view shows, a frame
// decoded of the picture's size (and one its app says may: Stream::new's `quiet`) changes nothing the app draws: its
// event is taken as it comes (streams_arrive; between frames, streams_said), the frame shown and said shown at once,
// nothing built or painted for it, no frame asked, as a video plays under the app's canvas. Its first frame, another
// size, what the app let go of itself and whatever else comes, as before.
//
// Routed (`route`, where the host has routes: @hostapi.stream_direct, macOS's, iOS's, Windows' and Android's): while it
// shows itself so, the app may have the host take a route's frames and sound straight from the app's engine
// (still.fail's shell reading a remote screen), not by way of the app's queue: the host decodes, shows and acknowledges
// each, nothing of the app's run. What came so is said in one event as the stream's are next taken ("D TS N BYTES":
// the frame it shows, how many came and their bytes), on the run's tape as any; no ticket is the app's for them. A
// config of the route stops it (the host's), and a stream that no longer shows itself stops it as the frame begins.
//
// A stream on its system video layer is decoded by the host itself even where the host's decoder is otherwise driven
// from here (Android's: @hostapi.stream_feeds; its layered streams' own MediaCodec decodes onto the layer, as Apple's
// VideoToolbox does): no feed for it.

///|
/// A picture decoded frame by frame.
pub struct Stream {
  /// the host's number for it, once opened (as the first frame or config is handed over: made in a view, a stream
  /// touches no host as the frame builds); 0 before, or where the host has none
  priv mut id : Int
  priv mut opened : Bool
  priv shown : (Double) -> Unit
  priv broken : () -> Unit
  /// H.264 (a config came), else JPEG; the config's picture size
  priv mut h264 : Bool
  /// (its config H.265's: `hevc`)
  priv mut hevc : Bool
  priv mut cw : Int
  priv mut ch : Int
  /// frames let go until a key frame
  priv mut need_key : Bool
  /// the picture shown: its size in pixels and its frame's time, from the event that said it decoded
  priv mut size : (Int, Int)?
  priv mut at : Double?
  /// frames handed over, their fate not said yet: their time and their ticket's number
  priv out : Array[(Double, Int)]
  /// what it let go of itself, said as the next frame begins ("d TS")
  priv own : Array[String]
  /// the frames to say shown once this frame is painted
  priv acks : Array[Double]
  /// the frame its events were last taken in
  priv mut taken : Int
  priv mut closed : Bool
  /// its H.264 decoder, driven from here where the host's is (@hostapi.stream_feeds: stream_feed.mbt)
  priv mut feed : Feed?
  /// shown by a system video layer where the host has one (Stream::new's `layer`): the native view it is in, once
  /// opened
  priv layer : Bool
  priv mut view : NativeView?
  /// whether a frame of `ts` decoded may be shown as it comes, nothing of the app's built for it (Stream::new's
  /// `quiet`: the app's say, where what it draws around the picture follows the frame shown); None: any of its size
  priv quiet : ((Double) -> Bool)?
  /// the route last asked of the host (Stream::route): its key, and whether its frames and its sound
  priv mut routed : (Int, Bool, Bool)
  /// the frames that came by a route (its "D" events), and their bytes
  priv mut direct_frames : Int
  priv mut direct_bytes : Int
}

///|
/// The streams open, their events taken as each frame begins.
let open_streams : Array[Stream] = []

///|
/// Where streams are drawn, by node, as the last build said: the stream, and the rect it is drawn at (Ctx::stream's
/// `at`).
let stream_nodes : Map[Int, (Stream, (Double, Double, Double, Double)?)] = Map([])

///|
/// The frames handed over so far (their tickets' numbers).
let stream_tickets : Ref[Int] = Ref::new(0)

///|
/// Whether the real host decodes H.264, asked once (-1 not yet).
// kept across runs: the real host's (asked once): a Tester never reads it (h_h264_here answers its fake's)
let h264_known : Ref[Int] = Ref::new(-1)

///|
fn streams_reset() -> Unit {
  open_streams.clear()
  stream_nodes.clear()
  stream_tickets.val = 0
  pointers_told.clear()
}

///|
/// A stream: `shown(ts)` once frame `ts` is drawn or let go (the sender's acknowledgement), `broken()` once its
/// decoder lost its state (the sender asked for a key frame). Nothing shows until a frame decodes. The host is not
/// asked for anything until the first config or frame (made where a view builds, it does nothing outside it).
/// `layer`: shown by the host's own video layer where it has one (@hostapi.stream_layers), drawn as it is
/// (Ctx::stream's `layer`); `quiet(ts)`: whether its frame of `ts` may then be shown as it comes, nothing built for it
/// (false: what the app draws around it changes with it, as a part of a screen over the whole: the frame built).
pub fn Stream::new(
  shown~ : (Double) -> Unit,
  broken~ : () -> Unit,
  layer? : Bool = false,
  quiet? : ((Double) -> Bool)? = None,
) -> Stream {
  let s = {
    id: 0,
    opened: false,
    shown,
    broken,
    h264: false,
    hevc: false,
    cw: 0,
    ch: 0,
    need_key: true,
    size: None,
    at: None,
    out: [],
    own: [],
    acks: [],
    taken: -1,
    closed: false,
    feed: None,
    layer,
    view: None,
    quiet,
    routed: (0, false, false),
    direct_frames: 0,
    direct_bytes: 0,
  }
  open_streams.push(s)
  s
}

///|
/// Whether this host decodes H.264 (else the sender is asked for JPEG only). Under a Tester, Tester::new's `h264`; a
/// run's tape keeps the host's (its ENV line), and a replay gives it again.
pub fn h264_here() -> Bool {
  h_h264_here()
}

///|
/// A config for H.264 (`avcc`: its AVCDecoderConfigurationRecord; the picture `w` × `h` pixels): the decoder starts
/// anew, the frames inside it let go, and takes nothing until a key frame.
pub fn Stream::h264(self : Stream, avcc : Bytes, w : Int, h : Int) -> Unit {
  if self.closed {
    return
  }
  self.open()
  self.h264 = true
  self.hevc = false
  self.cw = w
  self.ch = h
  self.need_key = true
  if self.id != 0 {
    h_stream_h264(self.id, avcc, w, h)
    // (one on its system video layer is decoded by the host itself, onto that layer: no feed, whatever the host's)
    if h_stream_feeds() && self.view is None {
      let f = match self.feed {
        Some(f) => f
        None => {
          // (the host's first surface made as its first config came: @hostapi.stream_h264)
          let f = Feed::new()
          f.surface = 1
          self.feed = Some(f)
          f
        }
      }
      f.configure(avcc, w, h)
      self.fed()
    }
  }
}

///|
/// What its feed said and asks of the host since: its words for the app said as the next frame begins (as the frames
/// it lets go itself are), its commands given the host now.
fn Stream::fed(self : Stream) -> Unit {
  guard self.feed is Some(f) else { return }
  let said = f.said.copy()
  f.said.clear()
  for e in said {
    self.own.push(e)
  }
  if said.length() > 0 {
    self.owe()
  }
  self.feed_host(f)
}

///|
/// Its feed's commands given the host, oldest first.
fn Stream::feed_host(self : Stream, f : Feed) -> Unit {
  let todo = f.todo.copy()
  f.todo.clear()
  for d in todo {
    h_stream_codec(self.id, d.cmd, d.data)
  }
}

///|
/// An H.264 access unit (AVCC: each NAL after its length), a key frame or not, of time `ts` (a whole number: the
/// decoders carry it as a frame's presentation time, as the sender's are).
pub fn Stream::frame(self : Stream, data : Bytes, key : Bool, ts : Double) -> Unit {
  if self.closed {
    return
  }
  self.open()
  self.hand_over(ts)
  let decodes = if self.hevc { h265_here() } else { h_h264_here() }
  if self.id == 0 || !self.h264 || !decodes || (self.need_key && !key) {
    self.let_go(ts)
    return
  }
  self.need_key = false
  match self.feed {
    Some(f) => {
      f.frame(data, key, ts)
      self.fed()
    }
    None => h_stream_frame(self.id, data, key, ts)
  }
}

///|
/// Whether this host decodes H.265 (the sender is then asked for it first: `hevc`). Under a Tester, false unless
/// Tester::set_h265; a run's tape keeps the host's (its ENV line says it only when it does).
pub fn h265_here() -> Bool {
  match fake.val {
    Some(f) => f.h265_here
    None => {
      if h265_known.val < 0 {
        h265_known.val = if @hostapi.h265_here() { 1 } else { 0 }
      }
      h265_known.val == 1
    }
  }
}

///|
// kept across runs: the real host's (asked once)
let h265_known : Ref[Int] = Ref::new(-1)

///|
/// A config for H.265 (`hvcc`: its HEVCDecoderConfigurationRecord; the picture `w` × `h` pixels), as `h264`'s: its
/// access units after it go to `frame` (each NAL after its length). Only where `h265_here`: elsewhere its frames are
/// let go.
pub fn Stream::hevc(self : Stream, hvcc : Bytes, w : Int, h : Int) -> Unit {
  if self.closed {
    return
  }
  self.open()
  self.h264 = true
  self.hevc = true
  self.cw = w
  self.ch = h
  self.need_key = true
  if self.id != 0 && h265_here() {
    match fake.val {
      Some(f) => fake_fed(f, self.id, "hevc \{w}x\{h} hvcc=\{hvcc.length()}")
      None => @hostapi.stream_hevc(self.id, hvcc, w, h)
    }
  }
}

///|
/// A JPEG frame of time `ts`.
pub fn Stream::jpeg(self : Stream, data : Bytes, ts : Double) -> Unit {
  if self.closed {
    return
  }
  self.open()
  self.h264 = false
  self.hand_over(ts)
  if self.id == 0 {
    self.let_go(ts)
    return
  }
  h_stream_jpeg(self.id, data, ts)
}

///|
/// The picture's size in pixels, once a frame of it shows (H.264's: its config's; JPEG's: the frame's).
pub fn Stream::size(self : Stream) -> (Int, Int)? {
  self.size
}

///|
/// Whether a frame has shown since it opened (one is kept on screen through a reconnect or an end).
pub fn Stream::shown_any(self : Stream) -> Bool {
  self.at is Some(_)
}

///|
/// The time of the frame it shows, once one does.
pub fn Stream::shown_at(self : Stream) -> Double? {
  self.at
}

///|
/// Its host's number for it (what a Tester's stream_fed, stream_shows… take): from the first config or frame handed
/// over; 0 before, or where the host has none.
pub fn Stream::id(self : Stream) -> Int {
  self.id
}

///|
/// Gone: its decoder stopped, its frames let go and not said (nothing more is), nothing of it drawn.
pub fn Stream::close(self : Stream) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  for o in self.out {
    outside_end(outside_stream, o.1)
  }
  self.out.clear()
  self.own.clear()
  self.acks.clear()
  self.feed = None
  match self.view {
    Some(v) => v.close()
    None => ()
  }
  self.view = None
  if self.id != 0 {
    h_stream_close(self.id)
  }
  open_streams.retain(fn(s) { !physical_equal(s, self) })
}

///|
/// Its host's stream, opened as the first config or frame is handed over.
fn Stream::open(self : Stream) -> Unit {
  if !self.opened {
    self.opened = true
    self.id = h_stream_open()
    // its system video layer, where the host has one: a native view of its own (kind 4, the stream's id)
    if self.layer && self.id != 0 && h_stream_layers() {
      let v = NativeView::make(4, self.id.to_string(), None)
      if v.here() {
        self.view = Some(v)
      }
    }
  }
}

///|
/// Whether its frames are shown by its system video layer now, nothing of the app's drawn for them: its view shown
/// in the last frame painted, its decoder the host's own.
fn Stream::shows_itself(self : Stream) -> Bool {
  match self.view {
    Some(v) => !v.closed && v.told_shown && self.feed is None
    None => false
  }
}

///|
/// Route `route`'s frames (`video`) and sound (`audio`) taken by the host straight from the app's engine
/// (@hostapi.stream_direct), from the record after the `after`th, the last the app took of it: its frames only while it
/// shows itself (its system video layer, its decoder the host's, a frame shown, past a key frame). Asked again as each
/// is taken while it is wanted (the host takes it only when nothing of the route is left in the app's queue); said once
/// when it is not. Nothing of the app's changes by it: what came so is said by the stream's events ("D").
pub fn Stream::route(self : Stream, route : Int, after : Double, video~ : Bool, audio~ : Bool) -> Unit {
  if self.closed || self.id == 0 {
    return
  }
  let video = video && self.routable()
  let want = (if video || audio { route } else { 0 }, video, audio)
  if !video && !audio && !self.routed.1 && !self.routed.2 {
    return
  }
  self.routed = want
  match fake.val {
    Some(f) => fake_fed(f, self.id, "route \{want.0} after=\{after} video=\{video} audio=\{audio}")
    None => @hostapi.stream_direct(self.id, route.to_double(), after, video~, audio~)
  }
}

///|
/// Whether a route's frames may be shown by the host as they come: it shows itself, a frame of it shown, its H.264 or
/// H.265 past a key frame.
fn Stream::routable(self : Stream) -> Bool {
  self.shows_itself() && self.h264 && self.at is Some(_) && !self.need_key
}

///|
/// The frames that came by a route (Stream::route) as its events said, and their bytes.
pub fn Stream::direct_count(self : Stream) -> (Int, Int) {
  (self.direct_frames, self.direct_bytes)
}

///|
/// A route's "D TS N BYTES": the frames counted; the one shown, if any (`ts` ≥ 0), shown from now, as far as the app is
/// concerned (the host showed it and said it shown to its sender).
fn Stream::take_direct(self : Stream, w : Array[String]) -> Unit {
  guard w is [_, t, n, b, ..] else { return }
  match (stream_num(t), stream_num(n), stream_num(b)) {
    (Some(ts), Some(n), Some(b)) => {
      self.direct_frames += n.to_int()
      self.direct_bytes += b.to_int()
      if ts >= 0.0 {
        self.at = Some(ts)
      }
    }
    _ => ()
  }
}

///|
/// A host's event taken as it comes, while the stream shows itself (streams_arrive): a frame decoded of the size it
/// shows (shown on its layer and said shown at once), one let go (said), its decoder broken. False for one that
/// changes what the app draws (the first frame, another size): taken as the frame is built, as before.
fn Stream::take_quietly(self : Stream, e : String) -> Bool {
  let w = e.split(" ").map(fn(x) { x.to_string() }).to_array()
  match w {
    ["f", t, pw, ph, ..] =>
      match (stream_num(t), stream_num(pw), stream_num(ph)) {
        (Some(ts), Some(fw), Some(fh)) => {
          let size = if self.h264 && self.cw > 0 && self.ch > 0 {
            Some((self.cw, self.ch))
          } else {
            Some((fw.to_int(), fh.to_int()))
          }
          if self.at is None || size != self.size {
            return false
          }
          match self.quiet {
            Some(f) if !f(ts) => return false
            _ => ()
          }
          self.at = Some(ts)
          self.settled_to(ts, wake=false)
          h_stream_show(self.id, ts)
          (self.shown)(ts)
          true
        }
        _ => false
      }
    ["d", t, ..] =>
      match stream_num(t) {
        Some(ts) => {
          self.settled_to(ts, wake=false)
          (self.shown)(ts)
          true
        }
        None => false
      }
    ["b", ..] => {
      self.need_key = true
      (self.broken)()
      true
    }
    ["D", t, ..] =>
      match (stream_num(t), self.quiet) {
        (Some(ts), Some(f)) if ts >= 0.0 && !f(ts) => false
        (Some(_), _) => {
          self.take_direct(w)
          true
        }
        _ => false
      }
    _ => false
  }
}

///|
/// Frame `ts` handed over: the host's (or its own) until its fate is said.
fn Stream::hand_over(self : Stream, ts : Double) -> Unit {
  stream_tickets.val += 1
  let n = stream_tickets.val
  outside_start(outside_stream, n, "stream \{self.id} frame \{ts}")
  self.out.push((ts, n))
}

///|
/// Frame `ts` let go here (before a key frame, nothing to decode it): said as the next frame begins, the frame that
/// takes it asked for unless this one is still to take it. One let go in a frame that took its events already waits
/// for the next frame's start (streams_frame_start): that frame is owed now (Ctx::owe_next).
fn Stream::let_go(self : Stream, ts : Double) -> Unit {
  self.own.push("d \{ts}")
  self.owe()
}

///|
/// What it said itself is taken as the next frame begins: that frame asked for (owed, when this one took its events).
fn Stream::owe(self : Stream) -> Unit {
  let c = g()
  if in_frame.val && self.taken == c.frame_no {
    c.owe_next()
  } else if !in_frame.val {
    c.read_changed("stream \{self.id} said")
  }
}

///|
/// The frames up to `ts` are no longer the host's (`wake` false: nothing shown changes for it, no frame asked).
fn Stream::settled_to(self : Stream, ts : Double, wake? : Bool = true) -> Unit {
  let left = []
  for o in self.out {
    if o.0 <= ts {
      outside_end(outside_stream, o.1, wake~)
    } else {
      left.push(o)
    }
  }
  self.out.clear()
  self.out.append(left)
}

///|
/// A number of an event's.
fn stream_num(s : String) -> Double? {
  match (try Some(@json.parse(s)) catch { _ => None }) {
    Some(Number(d, ..)) => Some(d)
    _ => None
  }
}

///|
/// As a frame begins, before it is decided what it does again (frame_watch.mbt): what the host said of each stream
/// since the last, taken after what it said itself; where any came, said come from outside (the frame is built and
/// takes it: streams_frame_start).
fn streams_arrive() -> Unit {
  let mut came = false
  for s in open_streams {
    if s.take_said() {
      came = true
    }
  }
  if came {
    outside_counted()
  }
}

///|
/// What its host said since, taken: while it shows itself (its system video layer), what changes nothing drawn taken
/// now, in order, till one does; the rest kept for the frame that takes it (streams_frame_start). Whether any was.
fn Stream::take_said(self : Stream) -> Bool {
  if self.closed || self.id == 0 {
    return false
  }
  let s = self
  let quiet = s.shows_itself()
  let mut came = false
  // (a bound, so a host that says without end cannot hold the frame)
  for _ in 0..<256 {
    let e = h_stream_next(s.id)
    if e == "" {
      break
    }
    if quiet && s.own.is_empty() && s.take_quietly(e) {
      continue
    }
    s.own.push(e)
    came = true
  }
  came
}

///|
/// Between frames, stream `id`'s host said something (hostcall.mbt's outside_streamed: a host whose streams show
/// themselves): taken now; a frame asked for only where something is left for it, none for a frame its layer shows.
fn streams_said(id : Int) -> Unit {
  if in_frame.val {
    // (the frame being drawn takes it, or the next: streams_arrive)
    outside_counted()
    return
  }
  for s in open_streams {
    if s.id == id {
      // (what is left: a frame, which takes it)
      if s.take_said() {
        outside_left()
      }
      return
    }
  }
}

///|
/// As the frame is built (frame_body, before the view builds): each stream's events since the last, its own then the
/// host's (streams_arrive), in the order said; the last frame said decoded is the one it shows from now (the host told
/// to latch it).
fn streams_frame_start() -> Unit {
  let c = g()
  for s in open_streams.copy() {
    if s.closed {
      continue
    }
    // (its frames routed to the host while it showed itself: no longer, now it does not; its sound goes on)
    if s.routed.1 && !s.routable() {
      s.route(s.routed.0, -1.0, video=false, audio=s.routed.2)
    }
    s.taken = c.frame_no
    // (what the host said of it, taken as the frame began: streams_arrive)
    let events = s.own.copy()
    s.own.clear()
    let latch : Ref[Double?] = Ref::new(None)
    let take = fn(e : String) {
      let w = e.split(" ").map(fn(x) { x.to_string() }).to_array()
      match w {
        ["f", t, pw, ph, ..] =>
          match (stream_num(t), stream_num(pw), stream_num(ph)) {
            (Some(ts), Some(fw), Some(fh)) => {
              s.at = Some(ts)
              s.size = if s.h264 && s.cw > 0 && s.ch > 0 {
                Some((s.cw, s.ch))
              } else {
                Some((fw.to_int(), fh.to_int()))
              }
              latch.val = Some(ts)
              s.acks.push(ts)
              s.settled_to(ts)
            }
            _ => ()
          }
        ["d", t, ..] =>
          match stream_num(t) {
            Some(ts) => {
              s.acks.push(ts)
              s.settled_to(ts)
            }
            None => ()
          }
        ["b", ..] => {
          s.need_key = true
          (s.broken)()
        }
        ["D", ..] => s.take_direct(w)
        _ => ()
      }
    }
    for e in events {
      match (e.has_prefix("c "), s.feed) {
        (true, Some(f)) => {
          // the host's decoder or surface said something: what the feed makes of it taken now, in its place
          f.event(e.split(" ").map(fn(x) { x.to_string() }).to_array()[1:].to_array())
          let said = f.said.copy()
          f.said.clear()
          for x in said {
            take(x)
          }
          s.feed_host(f)
        }
        (true, None) => ()
        _ => take(e)
      }
    }
    match latch.val {
      Some(ts) if s.id != 0 && !s.closed =>
        match s.feed {
          Some(f) => {
            f.latch(ts)
            // (what it said meanwhile, the next frame's)
            s.fed()
          }
          None => h_stream_show(s.id, ts)
        }
      _ => ()
    }
  }
}

///|
/// Once the frame is painted: the frames taken in it said shown, drawn or not.
fn streams_after_paint() -> Unit {
  for s in open_streams.copy() {
    if s.acks.length() == 0 {
      continue
    }
    let acks = s.acks.copy()
    s.acks.clear()
    for ts in acks {
      (s.shown)(ts)
    }
  }
}

///|
/// Where `s` is drawn: a node of `w` × `h` (filling its parent by default), its picture stretched to it (`fit`: as an
/// image's), or drawn at `at` (x, y, w, h from the node's top left: zoomed, panned; only what is inside the clip it is
/// painted in shows). Drawn as an image is, at the box's opacity, in its clip and transforms, under what is painted
/// after it; nothing until a frame shows. `layer`: a stream shown by its system video layer (Stream::new's `layer`)
/// shown there, under the canvas, once an H.264 frame of it shows (JPEG's are drawn here; stretched to its rect: `fit` FitFill; whole, not faded:
/// what is painted over it draws over it, a glass over it frosts the canvas alone); else drawn by the app.
pub fn Ctx::stream(
  self : Ctx,
  s : Stream,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  fit? : Fit = FitFill,
  radius? : Double = 0.0,
  at? : (Double, Double, Double, Double)? = None,
  layer? : Bool = true,
) -> Int {
  match s.view {
    Some(v) if layer && s.h264 && fit is FitFill && radius == 0.0 && !s.closed && s.at is Some(_) =>
      return self.native(v, w~, h~, content=at)
    _ => ()
  }
  let i = self.image("", w~, h~, fit~, radius~, bg=0L, fade=false)
  stream_nodes[i] = (s, at)
  // (its frames come as they are decoded: a part kept builds it each frame, kept_part.mbt)
  part_live()
  i
}

///|
/// Node `i`'s stream drawn (paint_image): an instance of kind 4 whose image is the stream's (@hostapi.stream_tex_base +
/// its id), as an image's is placed.
fn Ctx::paint_stream(self : Ctx, i : Int, n : Node, alpha : Double) -> Bool {
  let (s, at) = match stream_nodes.get(i) {
    Some(x) => x
    None => return false
  }
  let (pw, ph) = match s.size {
    Some((pw, ph)) if !s.closed && s.id != 0 && pw > 0 && ph > 0 => (pw.to_double(), ph.to_double())
    _ => return true
  }
  let (bx, by, bw, bh, fit) = match at {
    Some((x, y, w, h)) => (n.x + x, n.y + y, w, h, FitFill)
    None => (n.x, n.y, n.fw, n.fh, n.fit)
  }
  if bw <= 0.0 || bh <= 0.0 {
    return true
  }
  let (x, y, w, h, u0, v0, du, dv) = match fit {
    FitFill => (bx, by, bw, bh, 0.0, 0.0, 1.0, 1.0)
    FitCover | FitCoverAt(_) => {
      let k = dmax(bw / pw, bh / ph)
      let du = bw / k / pw
      let dv = bh / k / ph
      let vertical = match fit { FitCoverAt(y) => dclamp(y, 0.0, 1.0); _ => 0.5 }
      (bx, by, bw, bh, (1.0 - du) / 2.0, (1.0 - dv) * vertical, du, dv)
    }
    FitContain => {
      let k = dmin(bw / pw, bh / ph)
      let w = pw * k
      let h = ph * k
      (bx + (bw - w) / 2.0, by + (bh - h) / 2.0, w, h, 0.0, 0.0, 1.0, 1.0)
    }
  }
  self.push_inst(x, y, w, h, n.radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha, u0, v0, du, dv)
  self.corners_last(n)
  self.inst[(self.ninst - 1) * inst_size + 20] = (@hostapi.stream_tex_base + s.id).to_double()
  true
}

///|
/// The stream an instance's image is, if it is one's.
fn stream_of_image(image : Int) -> Stream? {
  if image <= @hostapi.stream_tex_base {
    return None
  }
  let id = image - @hostapi.stream_tex_base
  for s in open_streams {
    if s.id == id {
      return Some(s)
    }
  }
  None
}

///|
/// What a frame's stream picture is, for its hash and its text (frames.mbt): its size and its frame's time; "" for an
/// image that is no stream's.
fn stream_drawn(image : Int) -> String {
  match stream_of_image(image) {
    Some(s) =>
      match (s.size, s.at) {
        (Some((w, h)), Some(ts)) => "stream \{w}x\{h} ts=\{ts}"
        _ => "stream"
      }
    None => ""
  }
}

// ── the host, or a Tester's ────────────────────────────────────────────

///|
fn h_stream_open() -> Int {
  match fake.val {
    Some(f) => {
      f.stream_ids += 1
      f.streams_fed[f.stream_ids] = []
      f.stream_said[f.stream_ids] = []
      f.stream_ids
    }
    None => @hostapi.stream_open()
  }
}

///|
fn fake_fed(f : FakeHost, id : Int, line : String) -> Unit {
  match f.streams_fed.get(id) {
    Some(a) => a.push(line)
    None => f.streams_fed[id] = [line]
  }
}

///|
fn h_stream_h264(id : Int, avcc : Bytes, w : Int, h : Int) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "h264 \{w}x\{h} avcc=\{avcc.length()}")
    None => @hostapi.stream_h264(id, avcc, w, h)
  }
}

///|
fn h_stream_frame(id : Int, data : Bytes, key : Bool, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "frame key=\{key} ts=\{ts} bytes=\{data.length()}")
    None => @hostapi.stream_frame(id, data, key, ts)
  }
}

///|
fn h_stream_jpeg(id : Int, data : Bytes, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "jpeg ts=\{ts} bytes=\{data.length()}")
    None => @hostapi.stream_jpeg(id, data, ts)
  }
}

///|
fn h_stream_show(id : Int, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "show ts=\{ts}")
    None => @hostapi.stream_show(id, ts)
  }
}

///|
fn h_stream_codec(id : Int, cmd : String, data : Bytes) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, if data.length() > 0 { "do \{cmd} bytes=\{data.length()}" } else { "do \{cmd}" })
    None => @hostapi.stream_codec(id, cmd, data)
  }
}

///|
/// Whether the host's H.264 decoder is driven from here (stream_feed.mbt): Tester::set_stream_feeds, a run's ENV line.
fn h_stream_feeds() -> Bool {
  match fake.val {
    Some(f) => f.stream_feeds
    None => {
      if feeds_known.val < 0 {
        feeds_known.val = if @hostapi.stream_feeds() { 1 } else { 0 }
      }
      feeds_known.val == 1
    }
  }
}

///|
// kept across runs: the real host's (asked once)
let feeds_known : Ref[Int] = Ref::new(-1)

///|
/// Whether a stream may be shown by the host's own video layer (@hostapi.stream_layers): Tester::set_stream_layers, a
/// run's ENV line.
fn h_stream_layers() -> Bool {
  match fake.val {
    Some(f) => f.stream_layers
    None => layers_kind() != 0
  }
}

///|
/// Whether that layer shows the stream's tagged colours (@hostapi.stream_layers_tagged): a Tester's unless it said its
/// host's are sRGB (Tester::set_stream_layers_srgb), a run's ENV line.
fn h_stream_layers_tagged() -> Bool {
  match fake.val {
    Some(f) => f.stream_layers && !f.stream_layers_srgb
    None => layers_kind() == 1
  }
}

///|
/// The real host's layers (asked once): 0 none, 1 in the stream's tagged colours, 2 in sRGB.
fn layers_kind() -> Int {
  if layers_known.val < 0 {
    layers_known.val = if !@hostapi.stream_layers() {
      0
    } else if @hostapi.stream_layers_tagged() {
      1
    } else {
      2
    }
  }
  layers_known.val
}

///|
// kept across runs: the real host's (asked once)
let layers_known : Ref[Int] = Ref::new(-1)

///|
fn h_stream_close(id : Int) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "close")
    None => @hostapi.stream_close(id)
  }
}

///|
/// The stream's next event: the test's (or the run's, said again), else the host's, on the run's tape as it is taken
/// (`{"stream":{"id":N,"e":E}}`, what Tester::view_said says again).
fn h_stream_next(id : Int) -> String {
  match fake.val {
    Some(f) =>
      match f.stream_said.get(id) {
        Some(q) if q.length() > 0 => q.remove(0)
        _ => ""
      }
    None => {
      let e = @hostapi.stream_next(id)
      if e != "" && (views_tracer.val is Some(_) || taping()) {
        view_say({ "stream": Json::object({ "id": Json::number(id.to_double()), "e": Json::string(e) }) })
      }
      e
    }
  }
}

///|
fn h_h264_here() -> Bool {
  match fake.val {
    Some(f) => f.h264
    None => {
      if h264_known.val < 0 {
        h264_known.val = if @hostapi.h264_here() { 1 } else { 0 }
      }
      h264_known.val == 1
    }
  }
}

///|
/// A run's `{"stream":{"id":N,"e":E}}` (Tester::view_said): the event said again, taken at the next frame.
fn fake_stream_said(f : FakeHost, v : Map[String, Json]) -> Bool {
  match (v.get("id"), v.get("e")) {
    (Some(Number(id, ..)), Some(String(e))) => {
      fake_said(f, id.to_int(), e)
      true
    }
    _ => false
  }
}

///|
fn fake_said(f : FakeHost, id : Int, e : String) -> Unit {
  match f.stream_said.get(id) {
    Some(q) => q.push(e)
    None => f.stream_said[id] = [e]
  }
  f.wants = true
}

///|
/// What the app handed stream `id`'s host, oldest first, a line each: "h264 WxH avcc=N" a config, "frame key=K ts=T
/// bytes=N", "jpeg ts=T bytes=N", "show ts=T" the frame it shows from then, "close". Frames let go before reaching it
/// (before a key frame, nothing to decode them) are not among them.
pub fn Tester::stream_fed(self : Tester, id : Int) -> Array[String] {
  self.fake.streams_fed.get(id).unwrap_or([]).copy()
}

///|
/// Stream `id`'s host decoded frame `ts`, `w` × `h` pixels: taken at the next frame, which shows it.
pub fn Tester::stream_shows(self : Tester, id : Int, ts : Double, w : Int, h : Int) -> Unit {
  fake_said(self.fake, id, "f \{ts} \{w} \{h}")
}

///|
/// Stream `id`'s host let its frames up to `ts` go undecoded: taken at the next frame.
pub fn Tester::stream_drops(self : Tester, id : Int, ts : Double) -> Unit {
  fake_said(self.fake, id, "d \{ts}")
}

///|
/// Stream `id`'s decoder lost its state: taken at the next frame (`broken`; frames let go until a key frame).
pub fn Tester::stream_broken(self : Tester, id : Int) -> Unit {
  fake_said(self.fake, id, "b")
}

///|
/// Whether its host's H.264 decoder is driven from here, as Android's (stream_feed.mbt): what it is told shows in
/// stream_fed ("do CMD", "do queue … bytes=N"), what it says is the test's to give (stream_codec_said).
pub fn Tester::set_stream_feeds(self : Tester, on : Bool) -> Unit {
  self.fake.stream_feeds = on
}

///|
/// Whether a stream asking for one is shown by a system video layer (@hostapi.stream_layers): a native view of kind 4
/// opened with it (Tester's views), its frames taken as they come while it shows.
pub fn Tester::set_stream_layers(self : Tester, on : Bool) -> Unit {
  self.fake.stream_layers = on
}

///|
/// Whether its layers (set_stream_layers) show a frame as sRGB whatever colours it is tagged with (Windows'), not as
/// tagged (Apple's, the default).
pub fn Tester::set_stream_layers_srgb(self : Tester, on : Bool) -> Unit {
  self.fake.stream_layers_srgb = on
}

///|
/// Stream `id`'s host's decoder or surface said `e` (stream_feed.mbt's words, without "c "): taken at the next frame.
pub fn Tester::stream_codec_said(self : Tester, id : Int, e : String) -> Unit {
  fake_said(self.fake, id, "c " + e)
}

///|
/// Whether a stream asking for it is shown by the host's own video layer (@hostapi.stream_layers) that shows a
/// video in the colours it is tagged with (Display P3's wider than sRGB's), not the app's sRGB canvas: false where the
/// host has none, or one that shows it as sRGB (@hostapi.stream_layers_tagged: Windows').
pub fn stream_layers_here() -> Bool {
  h_stream_layers_tagged()
}

///|
/// This host plays system audio carried alongside a remote screen; recorded with the run's environment.
pub fn stream_audio_here() -> Bool {
  match fake.val { Some(f) => f.audio_here; None => @hostapi.stream_audio_here() }
}

///|
/// PCM16 stereo at 48 kHz, 20 ms per packet; empty stops queued audio immediately.
pub fn Stream::audio(self : Stream, data : Bytes) -> Unit {
  if self.closed || (data.length() != 0 && data.length() != 3840) { return }
  if data.length() == 0 && !self.opened { return }
  self.open()
  match fake.val {
    Some(f) => fake_fed(f, self.id, "audio bytes=\{data.length()}")
    None => @hostapi.stream_audio(self.id, data)
  }
}

///|
pub fn Tester::set_stream_audio(self : Tester, on : Bool) -> Unit { self.fake.audio_here = on }

///|
/// Whether its host decodes H.265 (h265_here; false until set).
pub fn Tester::set_h265(self : Tester, on : Bool) -> Unit {
  self.fake.h265_here = on
}
