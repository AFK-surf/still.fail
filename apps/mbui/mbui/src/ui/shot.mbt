// A shot: what a view builds drawn whole as one picture, however long, and never shown (a chat's messages shared as
// one long picture). While it is being taken (Ctx::take_shot) the view builds it (Ctx::shot) in a layer of its own
// that is not drawn on the screen, pressed or read out, laid out as wide as it is said and as tall as it is. It is
// painted apart from the frame (Ctx::paint passes a node said `shot` by), all of it, into instances of its own; once
// the frame is presented, those are drawn by the host's renderer as frames of the window's size are, the window's
// height of it at a time, each time moved up by the rows already taken (whole device pixels: its words as crisp), and
// read back (@hostapi.drawn_pixels_of) into its PNG (@pixels.PngRows), then told: all in that one frame, so what is
// taken is what the view built in it, however many frames come. While a picture in it is still coming (its bytes, its
// decode), it is built and painted again at each frame till none is (shot_wait_most at most). Its pixels are the
// window's, as many to a point; never more of them held than its PNG so far and a window's.

///|
/// A shot being taken: what is told once it is, the frame it was asked in, since when it has waited for its pictures;
/// as the frame built and painted it, its layer and its root, its instances, whether a picture in it is still coming.
struct Shot {
  done : (Bytes?) -> Unit
  asked : Int
  since : Double
  mut layer : Int
  mut node : Int
  mut inst : FixedArray[Double]
  mut ninst : Int
  mut waits : Bool
}

///|
/// The longest a shot waits for a picture in it to come (its bytes, its decode): one that has not by then is taken as
/// it is drawn then (its ground, a thumbnail).
pub let shot_wait_most : Double = 10000.0

///|
/// Whether what is painted now is a shot's (Ctx::paint_shots): its pictures drawn whole, not fading in, and one still
/// coming said (`shot_waits`); no native view (the window's own, where the page has it).
// kept across runs: set only while a shot is painted, within one frame's paint, and put back
let shooting : Ref[Bool] = Ref::new(false)

///|
// kept across runs: set only while a shot is painted, within one frame's paint
let shot_waits : Ref[Bool] = Ref::new(false)

///|
fn shot_id(key : String) -> Int {
  stable_hash("\u{2}shot/" + key).to_int()
}

///|
/// The shot `key` (shot.mbt) built by `body`: laid out `w` wide (the window's at most) and as tall as it is, built only
/// while it is being taken (Ctx::take_shot), else nothing. Never seen, pressed or read out. Built where the view builds
/// what it shows, every frame it is, from what it reads.
pub fn Ctx::shot(self : Ctx, key : String, w : Double, body : () -> Unit) -> Unit {
  let s = match self.shots.get(shot_id(key)) {
    Some(s) => s
    None => return
  }
  let w = dmin(w, self.window_w)
  let mut root = -1
  let o = self.overlay("\u{2}shot/" + key, inert=true, escape=false, outside=false, fn() {
    // (its ids its own: what the view builds of the same on the screen keeps its state apart)
    root = self.box(left=0.0, top=0.0, w=Px(w), fn() { self.scope(shot_id(key), body) })
  })
  self.nodes[o.node].shot = true
  s.layer = o.node
  s.node = root
}

///|
/// Takes the shot `key` (Ctx::shot), built from now: `done` told its PNG once it is taken, None where this host cannot
/// read what it draws back. Taken again while it is being taken, it begins again (only the later told).
pub fn Ctx::take_shot(self : Ctx, key : String, done : (Bytes?) -> Unit) -> Unit {
  self.shots[shot_id(key)] = {
    done,
    asked: self.frame_no,
    since: self.now,
    layer: -1,
    node: -1,
    inst: FixedArray::make(0, 0.0),
    ninst: 0,
    waits: false,
  }
  self.read_changed("a shot taken")
}

///|
/// Whether the shot `key` is being taken.
pub fn Ctx::taking_shot(self : Ctx, key : String) -> Bool {
  self.shots.contains(shot_id(key))
}

///|
/// The shots built this frame painted, each into instances of its own (the frame's put back after), all of it: cut to
/// its root, what flies over everything in it over the rest of it, its shapes' pieces after all (Ctx::emit_segs), as a
/// frame's are.
fn Ctx::paint_shots(self : Ctx) -> Unit {
  if self.shots.is_empty() {
    return
  }
  let inst = self.inst
  let ninst = self.ninst
  let segs = self.segs.copy()
  let tops = dr.tops.copy()
  for _, s in self.shots {
    if s.layer < 0 || s.node < 0 {
      continue
    }
    let n = self.nodes[s.node]
    self.inst = if s.inst.length() >= inst_size * 64 { s.inst } else { FixedArray::make(inst_size * 1024, 0.0) }
    self.ninst = 0
    self.segs.clear()
    dr.tops.clear()
    shooting.val = true
    shot_waits.val = false
    push_clip(n.x, n.y, n.x + n.fw, n.y + n.fh)
    self.paint(s.layer, 1.0)
    self.paint_overlays()
    pop_clip()
    self.raise_tops()
    self.emit_segs()
    shooting.val = false
    s.inst = self.inst
    s.ninst = self.ninst
    s.waits = shot_waits.val
  }
  self.inst = inst
  self.ninst = ninst
  self.segs.clear()
  self.segs.append(segs)
  dr.tops.clear()
  dr.tops.append(tops)
}

///|
/// Once the frame is presented, each shot built and painted in it with nothing in it still coming (or waited for long
/// enough) taken whole and told: drawn by the host a window's height at a time, moved up by what is taken, its rows
/// read back into its PNG. One with a picture still coming waits for the frame that brings it (the host's), or its
/// time's end. One not built in this frame (what built it is gone) is let go untold.
fn Ctx::shots_after_present(self : Ctx) -> Unit {
  if self.shots.is_empty() {
    return
  }
  let ended : Array[(Int, Bytes?)] = []
  let gone : Array[Int] = []
  for id, s in self.shots {
    let (layer, node) = (s.layer, s.node)
    s.layer = -1
    s.node = -1
    if layer < 0 || node < 0 {
      // (asked for once this frame was built: built from the next)
      if s.asked == self.frame_no {
        self.wants_frame = true
      } else {
        gone.push(id)
      }
      continue
    }
    // (its layout read back still moving: taken once it is not)
    if self.read_back_moved {
      self.wants_frame = true
      continue
    }
    let end = s.since + shot_wait_most
    if s.waits && self.now < end {
      // (the host's frame as a picture comes; its time's end at the latest)
      if self.wake_at < 0.0 || end < self.wake_at {
        self.wake_at = end
      }
      continue
    }
    let n = self.nodes[node]
    match fake.val {
      Some(f) => f.shots.push(self.shot_words(node))
      None => ()
    }
    ended.push((id, self.shot_png(s, n)))
  }
  for id in gone {
    self.shots.remove(id)
  }
  for e in ended {
    match self.shots.get(e.0) {
      Some(s) => {
        self.shots.remove(e.0)
        (s.done)(e.1)
        // (built no more, and what the view does with it shown)
        self.wants_frame = true
      }
      None => ()
    }
  }
}

///|
/// Shot `s` as painted, its root `n`, drawn by the host a window's height at a time and read back into a PNG of its
/// device pixels; None where the host cannot.
fn Ctx::shot_png(self : Ctx, s : Shot, n : Node) -> Bytes? {
  let sc = self.scale
  let rows = (n.fh * sc).round().to_int()
  let cols = (n.fw * sc).round().to_int()
  let win = (self.window_h * sc).floor().to_int()
  if rows <= 0 || cols <= 0 || win <= 0 {
    return None
  }
  let png = @pixels.PngRows::new(cols, rows)
  let a = s.inst
  // the pieces of its shapes after everything drawn (kind 12): kept as they are, at the end, in every band
  let mut pieces = s.ninst
  while pieces > 0 && a[(pieces - 1) * inst_size + 5] == 12.0 {
    pieces = pieces - 1
  }
  let band_inst = FixedArray::make(s.ninst * inst_size + inst_size, 0.0)
  let mut taken = 0
  while taken < rows {
    let band = if rows - taken < win { rows - taken } else { win }
    // what reaches into the band, moved up so its first row is the window's top (n's corner at the window's)
    let dx = -n.x
    let dy = -n.y - taken.to_double() / sc
    let top = -dy
    let bottom = top + band.to_double() / sc
    let mut k = 0
    for i in 0..<pieces {
      let b = i * inst_size
      // (a shadow's blur reaches past its rect: the shaders' grow; what is turned, wherever it is)
      let grow = if a[b + 5] == 2.0 { a[b + 7] * 3.0 + 2.0 } else { 2.0 }
      if a[b + 32] == 0.0 && (a[b + 1] - grow > bottom || a[b + 1] + a[b + 3] + grow < top) {
        continue
      }
      let o = k * inst_size
      a.blit_to(band_inst, len=inst_size, src_offset=b, dst_offset=o)
      shift_inst(band_inst, o, dx, dy)
      k = k + 1
    }
    let np = s.ninst - pieces
    if np > 0 {
      a.blit_to(band_inst, len=np * inst_size, src_offset=pieces * inst_size, dst_offset=k * inst_size)
    }
    let out = FixedArray::make(cols * band * 4, b'\x00')
    if !h_drawn_pixels_of(band_inst, k + np, 0, 0, cols, band, out) {
      return None
    }
    png.add(out, band)
    taken = taken + band
  }
  Some(png.end())
}

///|
/// Instance `b` of `a` moved by `dx`, `dy`: its rect, what cuts it and its outer clip, the point it turns about (the
/// rest of it is its own: a line's ends, a shape's pieces and a notch are where its rect is).
fn shift_inst(a : FixedArray[Double], b : Int, dx : Double, dy : Double) -> Unit {
  a[b] = a[b] + dx
  a[b + 1] = a[b + 1] + dy
  a[b + 16] = a[b + 16] + dx
  a[b + 17] = a[b + 17] + dy
  a[b + 18] = a[b + 18] + dx
  a[b + 19] = a[b + 19] + dy
  if inst_has_outer(a, b) {
    a[b + 40] = a[b + 40] + dx
    a[b + 41] = a[b + 41] + dy
    a[b + 42] = a[b + 42] + dx
    a[b + 43] = a[b + 43] + dy
  }
  if a[b + 32] != 0.0 {
    a[b + 33] = a[b + 33] + dx
    a[b + 34] = a[b + 34] + dy
  }
}

///|
/// The words node `i` and what it holds show, in the order they are painted (a test's: Tester::shots).
fn Ctx::shot_words(self : Ctx, i : Int) -> Array[String] {
  let out = []
  let walk : Ref[(Int) -> Unit] = Ref::new(fn(_) {  })
  walk.val = fn(k) {
    let n = self.nodes[k]
    if (n.kind == kind_text || n.kind == kind_rich) && n.text != "" {
      out.push(n.text)
    }
    let mut c = n.first
    while c >= 0 {
      (walk.val)(c)
      c = self.nodes[c].next
    }
  }
  (walk.val)(i)
  out
}

///|
/// The words of each shot taken (Ctx::take_shot), oldest first: what each drew, in the order it was painted.
pub fn Tester::shots(self : Tester) -> Array[Array[String]] {
  self.fake.shots
}
