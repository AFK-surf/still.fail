// A picture the host decodes frame by frame, drawn by the app as an image (still.fail's remote screens: its Android
// app's remote/Decoders.kt and ScreenSession.kt): the app hands it a sender's frames, H.264 (`h264`, a config, then
// `frame`s) or JPEG (`jpeg`), and draws it where it likes (`Ctx::stream`), under and over what it paints, faded,
// frosted, zoomed and panned as any picture. Not a native view: nothing of it is the system's but the decoding.
//
// The sender sends a few frames ahead of the last one the app acknowledged, so each frame comes back through `shown`
// once its fate is known: drawn, or let go. Which frame shows is said by events, never by what the host happens to
// have decoded: the host says "decoded, W × H" or "let go" of each frame (or that its decoder broke) as it comes, the
// framework takes those as a frame begins (frame_body, before the view builds) and the stream shows from that frame
// on the last one said decoded (the host told to latch it: @host.stream_show). So what frame N draws depends only on
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
// after a config or a broken decoder, frames are let go unseen; where nothing decodes H.264 (@host.h264_here false,
// or no config yet) they are let go too. Those it lets go itself are said at the next frame's start, as a host's are.
//
// Under a Tester the host is the test's (Tester::new's `h264`; Tester::stream_fed, stream_shows, stream_drops,
// stream_broken), its picture a placeholder in the draw list: `image N PX "stream WxH ts=TS"`.

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
}

///|
/// The streams open, their events taken as each frame begins.
let open_streams : Array[Stream] = []

///|
/// Where streams are drawn this frame, by node: the stream, and the rect it is drawn at (Ctx::stream's `at`).
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
}

///|
/// A stream: `shown(ts)` once frame `ts` is drawn or let go (the sender's acknowledgement), `broken()` once its
/// decoder lost its state (the sender asked for a key frame). Nothing shows until a frame decodes. The host is not
/// asked for anything until the first config or frame (made where a view builds, it does nothing outside it).
pub fn Stream::new(shown~ : (Double) -> Unit, broken~ : () -> Unit) -> Stream {
  let s = {
    id: 0,
    opened: false,
    shown,
    broken,
    h264: false,
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
  self.cw = w
  self.ch = h
  self.need_key = true
  if self.id != 0 {
    h_stream_h264(self.id, avcc, w, h)
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
  if self.id == 0 || !self.h264 || !h_h264_here() || (self.need_key && !key) {
    self.let_go(ts)
    return
  }
  self.need_key = false
  h_stream_frame(self.id, data, key, ts)
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
  let c = g()
  if in_frame.val && self.taken == c.frame_no {
    c.owe_next()
  } else if !in_frame.val {
    c.read_changed("stream \{self.id}'s frame \{ts} let go")
  }
}

///|
/// The frames up to `ts` are no longer the host's.
fn Stream::settled_to(self : Stream, ts : Double) -> Unit {
  let left = []
  for o in self.out {
    if o.0 <= ts {
      outside_end(outside_stream, o.1)
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
/// As the frame begins (frame_body, before the view builds): each stream's events since the last, its own then the
/// host's, in the order said; the last frame said decoded is the one it shows from now (the host told to latch it).
fn streams_frame_start() -> Unit {
  let c = g()
  for s in open_streams.copy() {
    if s.closed {
      continue
    }
    s.taken = c.frame_no
    let events = s.own.copy()
    s.own.clear()
    if s.id != 0 {
      // (a bound, so a host that says without end cannot hold the frame)
      for _ in 0..<256 {
        let e = h_stream_next(s.id)
        if e == "" {
          break
        }
        events.push(e)
      }
    }
    let mut latch : Double? = None
    for e in events {
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
              latch = Some(ts)
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
        _ => ()
      }
    }
    match latch {
      Some(ts) if s.id != 0 && !s.closed => h_stream_show(s.id, ts)
      _ => ()
    }
  }
}

///|
/// Once the frame is painted: the frames taken in it said shown, drawn or not; where streams were drawn forgotten.
fn streams_after_paint() -> Unit {
  stream_nodes.clear()
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
/// after it; nothing until a frame shows.
pub fn Ctx::stream(
  self : Ctx,
  s : Stream,
  w? : Size = Fill(1.0),
  h? : Size = Fill(1.0),
  fit? : Fit = FitFill,
  radius? : Double = 0.0,
  at? : (Double, Double, Double, Double)? = None,
) -> Int {
  let i = self.image("", w~, h~, fit~, radius~, bg=0L, fade=false)
  stream_nodes[i] = (s, at)
  i
}

///|
/// Node `i`'s stream drawn (paint_image): an instance of kind 4 whose image is the stream's (@host.stream_tex_base +
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
    FitCover => {
      let k = dmax(bw / pw, bh / ph)
      let du = bw / k / pw
      let dv = bh / k / ph
      (bx, by, bw, bh, (1.0 - du) / 2.0, (1.0 - dv) / 2.0, du, dv)
    }
    FitContain => {
      let k = dmin(bw / pw, bh / ph)
      let w = pw * k
      let h = ph * k
      (bx + (bw - w) / 2.0, by + (bh - h) / 2.0, w, h, 0.0, 0.0, 1.0, 1.0)
    }
  }
  self.push_inst(x, y, w, h, n.radius, 4.0, 0.0, 0.0, 0xFFFFFFFFL, alpha, u0, v0, du, dv)
  self.inst[(self.ninst - 1) * inst_size + 20] = (@host.stream_tex_base + s.id).to_double()
  true
}

///|
/// The stream an instance's image is, if it is one's.
fn stream_of_image(image : Int) -> Stream? {
  if image <= @host.stream_tex_base {
    return None
  }
  let id = image - @host.stream_tex_base
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
    None => @host.stream_open()
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
    None => @host.stream_h264(id, avcc, w, h)
  }
}

///|
fn h_stream_frame(id : Int, data : Bytes, key : Bool, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "frame key=\{key} ts=\{ts} bytes=\{data.length()}")
    None => @host.stream_frame(id, data, key, ts)
  }
}

///|
fn h_stream_jpeg(id : Int, data : Bytes, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "jpeg ts=\{ts} bytes=\{data.length()}")
    None => @host.stream_jpeg(id, data, ts)
  }
}

///|
fn h_stream_show(id : Int, ts : Double) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "show ts=\{ts}")
    None => @host.stream_show(id, ts)
  }
}

///|
fn h_stream_close(id : Int) -> Unit {
  match fake.val {
    Some(f) => fake_fed(f, id, "close")
    None => @host.stream_close(id)
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
      let e = @host.stream_next(id)
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
        h264_known.val = if @host.h264_here() { 1 } else { 0 }
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
