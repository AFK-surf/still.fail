// A shot: what a view builds drawn whole as one picture, however long, and never shown (a chat's messages shared as
// one long picture, the card to share). While it is being taken (Ctx::take_shot) the view builds it (Ctx::shot) in a
// layer of its own that is not drawn on the screen, pressed or read out, laid out as wide as it is said (whatever the
// window's) and as tall as it is. It is painted apart from the frame (Ctx::paint passes a node said `shot` by), all of
// it, into instances of its own, at as many pixels a point as it is taken at (the window's, or its own: a picture as
// sharp on any screen, its words' glyphs made that much larger, its pictures decoded so: text.mbt words_zoom); once the
// frame is presented, those are drawn by the host's renderer as frames are, shot_band_most rows of it at a time into a
// picture of their own, each time moved up by the rows already taken (whole device pixels: its words as crisp), and
// read back (@hostapi.drawn_pixels_of) into its PNG (@pixels.PngRows), then told: all in that one frame, so what is
// taken is what the view built in it, however many frames come. While a picture in it is still coming (its bytes, its
// decode), it is built and painted again at each frame till none is (shot_wait_most at most). Never more of its pixels
// held than its PNG so far and a band's.

///|
/// A shot being taken: what is told once it is, the frame it was asked in, since when it has waited for its pictures;
/// as the frame built and painted it, its layer and its root, its instances, whether a picture in it is still coming.
/// A picture made as nodes (take_picture): its tree; its layer and root then say it was laid out this frame.
struct Shot {
  done : (Bytes?) -> Unit
  asked : Int
  since : Double
  /// its pixels a point (0: the window's)
  scale : Double
  mut layer : Int
  mut node : Int
  mut inst : FixedArray[Double]
  mut ninst : Int
  mut waits : Bool
  tree : ShotTree?
  /// where its root was painted and how big (x, y, w, h), as the frame painted it
  mut rect : (Double, Double, Double, Double)
}

///|
/// The longest a shot waits for a picture in it to come (its bytes, its decode): one that has not by then is taken as
/// it is drawn then (its ground, a thumbnail).
pub let shot_wait_most : Double = 10000.0

///|
/// How many rows of a shot the host draws at a time (a picture of their own: as big as every renderer's can be).
let shot_band_most : Int = 2048

///|
/// Whether what is painted now is a shot's (Ctx::paint_shots): its pictures drawn whole, not fading in, and one still
/// coming said (`shot_waits`); no native view (the window's own, where the page has it).
// kept across runs: set only while a shot is painted, within one frame's paint, and put back
let shooting : Ref[Bool] = Ref(false)

///|
// kept across runs: set only while a shot is painted, within one frame's paint
let shot_waits : Ref[Bool] = Ref(false)

///|
fn shot_id(key : String) -> Int {
  stable_hash("\u{2}shot/" + key).to_int()
}

///|
/// The shot `key` (shot.mbt) built by `body`: laid out `w` wide (whatever the window's) and as tall as it is, built only
/// while it is being taken (Ctx::take_shot), else nothing. Never seen, pressed or read out. Built where the view builds
/// what it shows, every frame it is, from what it reads.
pub fn Ctx::shot(self : Ctx, key : String, w : Double, body : () -> Unit) -> Unit {
  let s = match self.shots.get(shot_id(key)) {
    Some(s) => s
    None => return
  }
  let mut root = -1
  let was = self.shot_scale
  self.shot_scale = s.scale
  let o = self.overlay("\u{2}shot/" + key, inert=true, escape=false, outside=false, fn() {
    // (at the layer's corner, the window's, as tall as it is; its ids its own: what the view builds of the same on the
    // screen keeps its state apart)
    root = self.box(style=style(w=Fixed(w)), fn() { self.scope(shot_id(key), body) })
  })
  self.shot_scale = was
  self.nodes[o.node].shot = true
  s.layer = o.node
  s.node = root
}
///|
/// A picture made as nodes (take_picture): its tree, made apart from the window's (its nodes' indexes its own), and
/// the box its picture is of, as wide as it was asked.
priv struct ShotTree {
  tree : @view.Tree
  held : @view.View
  w : Double
}

///|
/// How tall a picture made as nodes may come to (take_picture): the room its tree is laid out in, its box as tall as
/// what it holds within it.
let shot_tree_room : Double = 1000000.0

///|
/// A picture of what `make` makes as nodes, `w` wide and as tall as it is, taken once from now as a shot is
/// (Ctx::take_shot: never seen, pressed or read out, at `scale` pixels a point, its bands and the pictures in it waited
/// for as a shot's), `done` told its PNG: asked at a cause (a press's handler). What `make` makes is a tree of its own,
/// made now, laid out at each frame till the picture is taken (its words and pictures as the window's tree's are, at
/// the shot's pixels a point), painted apart (Ctx::tree_shot_paint), let go as it is told. Taken again under the same
/// `key` while it is, it begins again (the one before let go untold).
pub fn take_picture(
  key : String,
  w : Double,
  make : (@view.View) -> Unit,
  done : (Bytes?) -> Unit,
  scale? : Double = 0.0,
) -> Unit {
  let c = g()
  let id = shot_id(key)
  match c.shots.get(id) {
    Some({ tree: Some(st), .. }) => st.tree.dispose()
    _ => ()
  }
  let held : Ref[@view.View?] = Ref(None)
  let tree = @signals.untracked(fn() {
    @view.Tree::new(
      fn(root) {
        root.tree.drawn_by(
          words_scale=fn() { font_scale() },
          pixel_scale=fn() { if scale > 0.0 { scale } else { g().scale } },
          glass_solid=fn() { true },
          image_ready=fn(src, _) { image_ready_asking_none(src) },
          image_ask=fn(src, px) { g().image_ready(src, px) |> ignore },
        )
        root.box(fn(b) {
          b.width(Is(Some(w))) |> ignore
          held.val = Some(b)
          make(b)
        })
        |> ignore
      },
      measure=view_words_measure,
      measure_runs=view_runs_measure,
      measure_kept=view_words_measure_kept,
      measure_runs_kept=view_runs_measure_kept,
      measure_shorter=view_shorter_measure,
      time=fn() { h_event_time() },
    )
  })
  let st = { tree, held: held.val.unwrap(), w }
  c.shots[id] = {
    done: fn(png) {
      tree.dispose()
      done(png)
    },
    asked: c.frame_no,
    since: c.clock,
    scale,
    layer: -1,
    node: -1,
    inst: FixedArray::make(0, 0.0),
    ninst: 0,
    waits: false,
    tree: Some(st),
    rect: (0.0, 0.0, 0.0, 0.0),
  }
  c.read_changed("a picture taken")
}

///|
/// The pictures made as nodes (take_picture) laid out in this frame, at its moment, while each is being taken: built
/// so, as a shot built in it is (Ctx::shot).
fn Ctx::pictures_built(self : Ctx) -> Unit {
  for _, s in self.shots {
    match s.tree {
      Some(st) => {
        @signals.untracked(fn() {
          st.tree.at(view_logic_at.val)
          st.tree.frame(st.w, shot_tree_room, now=view_logic_at.val) |> ignore
        })
        s.layer = 0
        s.node = 0
      }
      None => ()
    }
  }
}

///|
/// Every shot let go untold (a run's end): the trees of the pictures made as nodes with them.
fn Ctx::shots_let_go(self : Ctx) -> Unit {
  for _, s in self.shots {
    match s.tree {
      Some(st) => st.tree.dispose()
      None => ()
    }
  }
  self.shots.clear()
}

///|
/// Takes the shot `key` (Ctx::shot), built from now: `done` told its PNG once it is taken, None where this host cannot
/// read what it draws back. `scale`: its pixels a point, the same on any screen (a picture to share as sharp from a
/// screen of one pixel a point as from one of three); the window's where not said. Taken again while it is being
/// taken, it begins again (only the later told).
pub fn Ctx::take_shot(self : Ctx, key : String, done : (Bytes?) -> Unit, scale? : Double = 0.0) -> Unit {
  match self.shots.get(shot_id(key)) {
    Some({ tree: Some(st), .. }) => st.tree.dispose()
    _ => ()
  }
  self.shots[shot_id(key)] = {
    done,
    asked: self.frame_no,
    since: self.clock,
    scale,
    layer: -1,
    node: -1,
    inst: FixedArray::make(0, 0.0),
    ninst: 0,
    waits: false,
    tree: None,
    rect: (0.0, 0.0, 0.0, 0.0),
  }
  self.read_changed("a shot taken")
}

///|
/// How many pixels a point what is built now is drawn at: a shot's own where one taken at its own is built (Ctx::shot,
/// take_shot `scale`), else the window's. What is made for its pixels as it is built (a picture's curves cut as fine as
/// they show) is made for these.
pub fn Ctx::drawn_scale(self : Ctx) -> Double {
  if self.shot_scale > 0.0 {
    self.shot_scale
  } else {
    self.scale
  }
}

///|
/// Whether the shot `key` is being taken.
pub fn Ctx::taking_shot(self : Ctx, key : String) -> Bool {
  self.shots.contains(shot_id(key))
}

///|
/// The shots built this frame painted, each into instances of its own (the frame's put back after), all of it: cut to
/// its root, what flies over everything in it over the rest of it, its shapes' pieces after all (Ctx::emit_segs), as a
/// frame's are; at its own pixels a point where it says (Ctx::take_shot `scale`), its words' glyphs made so.
fn Ctx::paint_shots(self : Ctx) -> Unit {
  if self.shots.is_empty() {
    return
  }
  let inst = self.inst
  let ninst = self.ninst
  // (the frame's headers where they are in its instances, none in a shot's: Ctx::ride_copy)
  let spans = ride_spans.copy()
  ride_spans.clear()
  let segs = self.segs.copy()
  let runs = seg_runs.copy()
  let tops = dr.tops.copy()
  let window_scale = self.scale
  for _, s in self.shots {
    if s.layer < 0 || s.node < 0 {
      continue
    }
    let (x, y, w, h) = match s.tree {
      Some(st) => st.held.rect()
      None => {
        let n = self.nodes[s.node]
        (n.x, n.y, n.fw, n.fh)
      }
    }
    s.rect = (x, y, w, h)
    self.inst = if s.inst.length() >= inst_size * 64 { s.inst } else { FixedArray::make(inst_size * 1024, 0.0) }
    self.ninst = 0
    self.segs_cut(0)
    dr.tops.clear()
    shooting.val = true
    shot_waits.val = false
    if s.scale > 0.0 {
      self.scale = s.scale
      words_zoom.val = s.scale / window_scale
    }
    push_clip(x, y, x + w, y + h)
    match s.tree {
      Some(st) => self.tree_shot_paint(st.tree)
      None => self.paint(s.layer, 1.0)
    }
    self.land_flying()
    pop_clip()
    self.raise_tops()
    self.cycle_looks()
    self.emit_segs()
    self.scale = window_scale
    words_zoom.val = 1.0
    shooting.val = false
    s.inst = self.inst
    s.ninst = self.ninst
    s.waits = shot_waits.val
  }
  self.inst = inst
  self.ninst = ninst
  ride_spans.clear()
  ride_spans.append(spans)
  self.segs_cut(0)
  self.segs.append(segs)
  seg_runs.append(runs)
  dr.tops.clear()
  dr.tops.append(tops)
}

///|
/// Once the frame drawn at `at` (its moment) is presented, each shot built and painted in it with nothing in it still
/// coming (or waited for long enough by then) taken whole and told: drawn by the host a window's height at a time,
/// moved up by what is taken, its rows read back into its PNG. One with a picture still coming waits for the frame that
/// brings it (the host's), or its time's end. One not built in this frame (what built it is gone) is let go untold.
fn Ctx::shots_after_present(self : Ctx, at : Double) -> Unit {
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
    if s.waits && at < end {
      // (the host's frame as a picture comes; its time's end at the latest)
      if self.wake_at < 0.0 || end < self.wake_at {
        self.wake_at = end
      }
      continue
    }
    // (told what watches the shots taken: a Tester's, Tester::shot_drawn)
    match shot_watch.val {
      Some(w) => {
        let words = match s.tree {
          Some(st) => tree_shot_words(st.tree)
          None => self.shot_words(node)
        }
        w(words, s)
      }
      None => ()
    }
    ended.push((id, self.shot_png(s)))
  }
  for id in gone {
    match self.shots.get(id) {
      Some({ tree: Some(st), .. }) => st.tree.dispose()
      _ => ()
    }
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
/// Shot `s` as painted (its root where `rect` says), drawn by the host shot_band_most rows at a time at its pixels a point and read
/// back into a PNG of them; None where the host cannot.
fn Ctx::shot_png(self : Ctx, s : Shot) -> Bytes? {
  let (nx, ny, nw, nh) = s.rect
  let sc = if s.scale > 0.0 { s.scale } else { self.scale }
  let rows = (nh * sc).round().to_int()
  let cols = (nw * sc).round().to_int()
  let win = shot_band_most
  if rows <= 0 || cols <= 0 {
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
    // what reaches into the band, moved up so its first row is the picture's top (its root's corner at its own)
    let dx = -nx
    let dy = -ny - taken.to_double() / sc
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
    if !h_drawn_pixels_of(band_inst, k + np, sc, cols, band, out) {
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
  inst_fade_moved(a, b, 0.0, 1.0, dy)
  inst_fade_moved_across(a, b, 0.0, 1.0, dx)
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
  let walk : Ref[(Int) -> Unit] = Ref(fn(_) {  })
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

///|
/// Each instance a shot drew (`inst`, `n` of them), from its root's corner (`x`, `y`), as a test compares them: its
/// numbers to a hundredth, a glyph's place in its atlas left out; in one order.
fn shot_drawn_of(inst : FixedArray[Double], n : Int, x : Double, y : Double) -> Array[String] {
  let out = Array::makei(n, fn(k) {
    let b = k * inst_size
    Array::makei(inst_size, fn(j) {
      let v = inst[b + j]
      if inst[b + 5] == 1.0 && (j == 12 || j == 13) {
        "-"
      } else if j == 0 {
        ((v - x) * 100.0).round().to_string()
      } else if j == 1 {
        ((v - y) * 100.0).round().to_string()
      } else {
        (v * 100.0).round().to_string()
      }
    }).join(",")
  })
  out.sort()
  out
}

///|
/// Each shot taken (Ctx::take_shot), oldest first: its picture's size in pixels and each instance it drew, from its
/// root's corner (shot_drawn_of).
pub fn Tester::shot_drawn(self : Tester) -> Array[((Int, Int), Array[String])] {
  Array::makei(self.fake.shot_sizes.length(), fn(i) { (self.fake.shot_sizes[i], self.fake.shot_drawn[i]) })
}

///|
/// Who is told of each shot taken, as it is taken (the words it shows in the order they are painted, the shot): a Tester's, which keeps what it
/// says and drew (Tester::shot_drawn).
// kept across runs: set by each Tester as it is made, let go as its run ends
let shot_watch : Ref[((Array[String], Shot) -> Unit)?] = Ref(None)

///|
/// A picture's tree (take_picture's) painted into the instances being painted now (a shot's: Ctx::paint_shots), in
/// the order the scene draws it, as the window's tree is (Ctx::view_paint): each node's own drawing made (Ctx::view_drawn),
/// what it holds cut to it where it clips, its edge drawn after what it holds. Made apart from what the window's tree
/// keeps of its nodes (their indexes the window's), and let go after: nothing of it kept from one frame to the next.
/// Not here, as nothing a picture is made of has it: old views, lists drawn by their offset alone, what fades or
/// stretches at its edges, layers.
fn Ctx::tree_shot_paint(self : Ctx, tree : @view.Tree) -> Unit {
  // (what the window's tree keeps of its nodes, by their indexes, put aside while this one's are painted)
  let blocks : ByNode[ViewBlock] = ByNode::new()
  let pictures : ByNode[ViewPicture] = ByNode::new()
  let bands : ByNode[ShapeBands] = ByNode::new()
  view_blocks.swap(blocks)
  view_pictures.swap(pictures)
  view_shape_bands.swap(bands)
  let fields = tree_fields.copy()
  tree_fields.clear()
  // (the window's native views none of this one's: a picture shows none, NativeView::paint_in)
  let natives = tree_natives.copy()
  tree_natives.clear()
  let words = inst_owners.tree_words.copy()
  let work = { ..view_paint_work }
  tree.set_pixel_grid(self.scale)
  let clipping : Array[@view.NodeId] = []
  let rings : Array[(@view.NodeId, FixedArray[Double])] = []
  let close_to = fn(next : @view.NodeId?) {
    let open = fn(id : @view.NodeId) {
      match next {
        Some(n) => tree.holds_in_order(id, n)
        None => false
      }
    }
    while true {
      let clip_out = clipping.length() > 0 && !open(clipping[clipping.length() - 1])
      let ring_out = rings.length() > 0 && !open(rings[rings.length() - 1].0)
      if !clip_out && !ring_out {
        break
      }
      // (the inner of the two first, as the window's tree's are closed)
      let clip_first = clip_out &&
        (!ring_out || tree.holds_in_order(rings[rings.length() - 1].0, clipping[clipping.length() - 1]))
      if clip_first {
        clipping.pop() |> ignore
        pop_clip()
      } else {
        let (_, held) = rings.pop().unwrap()
        self.shot_ring_put(held)
      }
    }
  }
  tree.each_drawn_laid(fn(c, x, y, a, s, ux, uy) {
    close_to(Some(c.id))
    // (the root draws nothing of its own)
    if c.id.at == 0 {
      return
    }
    // (on its way: cut to itself before it draws its own, as the window's tree is painted, Content::clips_self)
    if c.clips_self {
      let r = c.radius * s
      match c.corners {
        Some((tl, tr, br, bl)) => push_box_clip(x, y, c.w * s, c.h * s, tl * s, tr * s, br * s, bl * s)
        None => push_box_clip(x, y, c.w * s, c.h * s, r, r, r, r)
      }
      clipping.push(c.id)
    }
    let ring_at = self.view_drawn(
      tree,
      c,
      x,
      y,
      a,
      s,
      ux,
      uy,
      tree.turn_angle_of(c.id),
      tree.ground_drawn_of(c.id),
    )
    if c.clips && !c.clips_self {
      let r = c.radius * s
      match c.corners {
        Some((tl, tr, br, bl)) => push_box_clip(x, y, c.w * s, c.h * s, tl * s, tr * s, br * s, bl * s)
        None => push_box_clip(x, y, c.w * s, c.h * s, r, r, r, r)
      }
      clipping.push(c.id)
    }
    if ring_at >= 0 && ring_at < self.ninst {
      rings.push((c.id, self.shot_ring_take(ring_at)))
    }
  })
  close_to(None)
  view_blocks.swap(blocks)
  view_pictures.swap(pictures)
  view_shape_bands.swap(bands)
  tree_fields.clear()
  for id, f in fields {
    tree_fields[id] = f
  }
  tree_natives.clear()
  for id, n in natives {
    tree_natives[id] = n
  }
  inst_owners.tree_words.clear()
  for id, w in words {
    inst_owners.tree_words[id] = w
  }
  view_paint_work.made = work.made
  view_paint_work.copied = work.copied
  view_paint_work.handed = work.handed
}

///|
/// Instance `k` of a shot's taken out (those after it one back): a node's edge, held till what it holds is drawn.
fn Ctx::shot_ring_take(self : Ctx, k : Int) -> FixedArray[Double] {
  let held = FixedArray::make(inst_size, 0.0)
  self.inst.blit_to(held, len=inst_size, src_offset=k * inst_size)
  let n = self.ninst
  if k + 1 < n {
    self.inst.blit_to(self.inst, len=(n - k - 1) * inst_size, src_offset=(k + 1) * inst_size, dst_offset=k * inst_size)
  }
  self.ninst = n - 1
  held
}

///|
/// A held instance (shot_ring_take's) put at the shot's end.
fn Ctx::shot_ring_put(self : Ctx, held : FixedArray[Double]) -> Unit {
  while (self.ninst + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  held.blit_to(self.inst, len=inst_size, dst_offset=self.ninst * inst_size)
  self.ninst = self.ninst + 1
}

///|
/// The words a picture's tree shows, in the order they are painted (a test's: Tester::shots).
fn tree_shot_words(tree : @view.Tree) -> Array[String] {
  let out = []
  tree.each_drawn(fn(c, _, _, _) {
    if c.words != "" {
      out.push(c.words)
    } else if !c.runs.is_empty() {
      out.push(c.runs.map(fn(r) { r.text }).join(""))
    }
  })
  out
}
