// A run as data (PocketJS has it so: docs/DETERMINISM.md there): what each frame drew as one number, so two runs of
// the same steps are compared frame by frame (the same, or the first frame they part at) rather than by their last
// screen alone, and a test that gives the same steps another order of what comes from outside (a seed, a replay's
// pace) can say the frames that should not change did not.

///|
fn hash_mix(h : Int64, v : Int64) -> Int64 {
  (h ^ v) * 1099511628211L
}

///|
/// What the last frame drew, as one number (FNV-1a): every instance drawn (where, how large, its kind and colour, in
/// 1/64 px and 1/255 steps) and the laid-out tree with its words and carets (`dump`). The same steps give the same
/// number on every run and every machine.
pub fn Tester::frame_hash(self : Tester) -> Int64 {
  ignore(self)
  drawn_hash()
}

///|
/// What the last frame drew as text: the laid-out tree (`dump`), then each instance drawn, one a line (its 24
/// numbers, positions and sizes in 1/64 px, colours in 1/255): what two frames' hashes part on, line by line.
pub fn Tester::drawn_text(self : Tester) -> String {
  ignore(self)
  drawn_text()
}

///|
fn drawn_text() -> String {
  let c = g()
  let sb = StringBuilder()
  dump_node(sb, 0, 0)
  let named = image_numbers(c)
  for k in 0..<c.ninst {
    sb.write_string("inst")
    for j in 0..<inst_size {
      sb.write_string(" \{(inst_named(c, named, k, j) * 64.0).round().to_int64()}")
    }
    if c.inst[k * inst_size + 5] == 4.0 {
      let s = stream_drawn(c.inst[k * inst_size + 20].to_int())
      if s != "" {
        sb.write_string(" " + s)
      }
    }
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// The pictures the last frame drew, numbered as first drawn (their host's ids, which depend on what was decoded
/// before, are not what was drawn).
fn image_numbers(c : Ctx) -> Map[Int, Int] {
  let named : Map[Int, Int] = {}
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      let id = c.inst[b + 20].to_int()
      if !named.contains(id) {
        named[id] = named.length()
      }
    }
  }
  named
}

///|
/// Instance `k`'s number `j` as compared: a picture's id its number as first drawn.
fn inst_named(c : Ctx, named : Map[Int, Int], k : Int, j : Int) -> Double {
  let b = k * inst_size
  if j == 20 && c.inst[b + 5] == 4.0 {
    named.get(c.inst[b + 20].to_int()).unwrap_or(-1).to_double()
  } else {
    c.inst[b + j]
  }
}

///|
fn drawn_hash() -> Int64 {
  let c = g()
  let mut h = -3750763034362895579L
  let named = image_numbers(c)
  for k in 0..<c.ninst {
    for j in 0..<inst_size {
      let x = inst_named(c, named, k, j)
      // (a clip's corners' radii only where it has them: a picture with no rounded clip hashed as before they were kept)
      if j >= 24 && x == 0.0 {
        continue
      }
      h = hash_mix(h, (x * 64.0).round().to_int64())
    }
    // a stream's picture: its frame's size and time (stream.mbt)
    if c.inst[k * inst_size + 5] == 4.0 {
      for ch in stream_drawn(c.inst[k * inst_size + 20].to_int()) {
        h = hash_mix(h, ch.to_int().to_int64())
      }
    }
  }
  let sb = StringBuilder()
  dump_node(sb, 0, 0)
  for ch in sb.to_string() {
    h = hash_mix(h, ch.to_int().to_int64())
  }
  h
}

///|
/// MBUI_DRAW_LOG=1 on a real host: each frame's `frame_hash` on the log, the inputs between them with it (INPUT,
/// inputrec.mbt) (DRAWHASH frame time width height scale hash
/// stable: 1 when the host asked for output the same on every run, MBUI_BENCH=-1),
/// for a Tester over the host's kept text (textrec.mbt) given the same frames (`replay_frames`) to be checked against:
/// -1 not asked yet, 0 no, 1 yes.
let draw_log : Ref[Int] = Ref::new(-1)

///|
let draw_frames : Ref[Int] = Ref::new(0)

///|
fn log_drawn(w : Double, h : Double, scale : Double, t : Double) -> Unit {
  if taping() {
    draw_frames.val += 1
    let stable = if bench.mode < 0 { 1 } else { 0 }
    tape_line("DRAWHASH \{draw_frames.val} \{t} \{w} \{h} \{scale} \{drawn_hash()} \{stable}")
    // MBUI_DRAW_DUMP=N: frame N drawn as text (drawn_text), a line each
    if draw_logging() && @host.env("MBUI_DRAW_DUMP") == draw_frames.val.to_string() {
      for line in drawn_text().split("\n") {
        @host.log("DRAWDUMP " + line.to_owned())
      }
    }
  }
}

///|
/// `n` frames, `ms` apart: each one's hash (`frame_hash`) as it was drawn.
pub fn Tester::frames(self : Tester, n : Int, ms? : Double = 16.0) -> Array[Int64] {
  let out : Array[Int64] = []
  for _ in 0..<n {
    self.frame(ms~)
    out.push(self.frame_hash())
  }
  out
}

///|
/// When a real host's run drew its first frame (its log's first DRAWHASH line's time), if it says.
fn run_first_frame(run : String) -> Double? {
  for line in run.split("\n") {
    match line.find("DRAWHASH ") {
      Some(i) => {
        let parts = line.view(start_offset=i + 9).split(" ").map(fn(p) { p.to_owned() }).to_array()
        if parts.length() >= 2 {
          match (try Some(@json.parse(parts[1])) catch { _ => None }) {
            Some(Number(d, ..)) => return Some(d)
            _ => ()
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
/// A real host's frames as its log said them (MBUI_DRAW_LOG: DRAWHASH lines) drawn again, each at its time, the
/// window's size, scale and stability (Ctx::stable) as it had them: for each, its number, the host's hash and this
/// one's (as text). A frame at the time this Tester drew its last is that one (Tester::new at the host's first frame:
/// `time` 16 ms before it, and `run` this log, so that frame is drawn by the settings the run began with).
pub fn Tester::replay_frames(self : Tester, log : String) -> Array[(Int, String, String)] {
  let out = []
  let mut framed = false
  // an input handed on since the last frame: the next frame is its, drawn though at the Tester's own first frame's
  // time (an input at a frame's moment is taken in a frame at that moment)
  let mut fed = false
  // the scripts the run sent its pages (VIEWSCRIPT), and how many of this one's are compared with them: one that is
  // not the run's parts there, as a frame whose hash is not
  let scripts : Array[String] = []
  let sent_before = self.fake.scripts_sent.length()
  let num = fn(s : String) -> Double? {
    match (try Some(@json.parse(s)) catch { _ => None }) {
      Some(Number(d, ..)) => Some(d)
      _ => None
    }
  }
  for v in log.split("\n") {
    let line = v.to_owned()
    // what the host gave between two frames, handed on at its place (inputrec.mbt)
    if line.find("ENV ") is Some(_) {
      replay_env(self.fake, line)
      continue
    }
    if line.find("INPUT ") is Some(_) {
      replay_input(self.fake, line)
      fed = true
      continue
    }
    match line.find("VIEWSCRIPT ") {
      Some(i) => {
        scripts.push(line.view(start_offset=i + 11).to_owned())
        continue
      }
      None => ()
    }
    // what the host said of its views, said again at its place (hostcall.mbt: view_say); before its first frame, said
    // already (Tester::new's `run`)
    match line.find("VIEWSAID ") {
      Some(i) => {
        if framed {
          self.view_said(line.view(start_offset=i + 9).to_owned()) |> ignore
        }
        continue
      }
      None => ()
    }
    // the clipboard as the app took it, given again at its place: the frame after it takes it (device.mbt)
    match clip_of_line(line) {
      Some(clip) => {
        fake_clip_give(self.fake, clip)
        continue
      }
      None => ()
    }
    // what came from outside, posted again at its place: the frame after it takes it (messages.mbt)
    if is_message_line(line) {
      replay_message(self.fake, line)
      continue
    }
    guard line.find("DRAWHASH ") is Some(i) else { continue }
    framed = true
    let parts = line.view(start_offset=i + 9).split(" ").map(fn(p) { p.to_owned() }).to_array()
    guard parts.length() >= 6 else { continue }
    guard (num(parts[0]), num(parts[1]), num(parts[2]), num(parts[3]), num(parts[4]))
      is (Some(n), Some(t), Some(w), Some(h), Some(scale)) else {
      continue
    }
    self.w = w
    self.h = h
    self.fake.scale = scale
    if parts.length() >= 7 {
      bench.mode = if parts[6] == "1" { -1 } else { 0 }
    }
    // (the frame a Tester made at this time already, as it was made: its first, Tester::new's `time`, unless an input
    // came before it; any later one at the same time is drawn, as a Tester's tape has them: Tester::draw)
    if t != self.fake.time || out.length() > 0 || fed {
      self.frame_at(t)
    }
    fed = false
    out.push((n.to_int(), parts[5], drawn_hash().to_string()))
    // the scripts sent by now: the run's and this one's, the same in the same order
    let ours = self.fake.scripts_sent
    let k = ours.length() - sent_before
    if k != scripts.length() || (0).until(k).iter().any(fn(j) { ours[sent_before + j] != scripts[j] }) {
      out.push((
        n.to_int(),
        "VIEWSCRIPT " + scripts.join(", "),
        "VIEWSCRIPT " + ours[sent_before:].iter().collect().join(", "),
      ))
    }
  }
  out
}

///|
/// The first frame at which two runs' hashes part (None: the same, frame for frame; one longer than the other parts
/// where the shorter ends).
pub fn first_difference(a : Array[Int64], b : Array[Int64]) -> Int? {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return Some(i)
    }
  }
  if a.length() != b.length() {
    Some(n)
  } else {
    None
  }
}

