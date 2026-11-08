// What a list's row of the window's tree drew (Tree::rides_scroll), kept as the frame's instances it came to: drawn
// again moved, its nodes not gone through, where nothing of it changed since (Tree::drawn_rev) and it is only moved
// by whole pixels within the clip it is drawn in, as Android's RenderNode is drawn again offset, Chrome's layer
// scrolled. Where it was drawn otherwise than its instances moved say (its picture, decoded or fading in since; one
// not seen asked for), that part drawn anew in its place among them.

///|
/// A part of a row drawn anew each time it is drawn again (a picture, or one not seen yet asked for): where among its
/// instances it was (`at` until `end`), whose, where it was drawn and as big and opaque, in which clip.
priv struct RideSpot {
  at : Int
  end : Int
  c : @view.Content
  x : Double
  y : Double
  s : Double
  a : Double
  /// none: one not seen (Ctx::view_unseen), nothing drawn
  clip : FixedArray[Double]?
  apart : Bool
  window : Bool
}

///|
/// What a row drew, kept to draw it again (Ctx::ride_again).
priv struct RideKept {
  /// the row kept
  id : @view.NodeId
  /// the tree's count of changes as it was drawn (Tree::drawn_rev_taken): kept while its own is no more
  rev : Int
  /// where its root was drawn, how opaque, and where it is laid out off that (where its glyphs are set)
  x : Double
  y : Double
  a : Double
  off_x : Double
  off_y : Double
  /// the frame's pixels a point, words' zoom, the glyphs let go before it (ride_glyphs_gone), whether who drew what
  /// was kept: drawn again only as they were
  scale : Double
  zoom : Double
  glyphs : Int
  owned : Bool
  /// the clip it was drawn in (a clip_stack level)
  clip : FixedArray[Double]
  /// its instances, and which of their numbers are moved with it (ride_moves' bits)
  inst : FixedArray[Double]
  moves : FixedArray[Int]
  /// its shapes' pieces, and where among the frame's they began
  segs : Array[Double]
  seg0 : Int
  /// its pieces as packed among the frame's (Ctx::segs_put)
  pack : SegPack
  spots : Array[RideSpot]
  /// who drew each, as kept (inst_owners)
  owners : Array[(Int, (Double, Double), @view.NodeId?, Int)]
  /// how far all it holds reaches (x0, y0, x1, y1); whether that was wholly within its clip across and up and down
  reach : (Double, Double, Double, Double)
  inside_x : Bool
  inside_y : Bool
  /// drawn all of it, cut by its clip as it is drawn each time (inst_cut): drawn again wherever it is moved in it, what
  /// of its nodes is wholly outside the clip there left out (`edges`, Riding's)
  cut : Bool
  edges : Array[Double]
  /// how many of the tree's nodes it drew
  nodes : Int
  /// the glyphs each of its nodes' blocks draws from (ViewBlock's `kept`): held in the atlas for it as a frame begins
  /// without its nodes gone through (view_glyphs_held)
  kept : Array[Array[(Int, Double, Double)]]
  /// its instances as the host keeps them (@hostapi.group_set), drawn again by a header in their place (ride_head);
  /// -1, copied each time
  group : Int
}

///|
/// A row being drawn as the tree is painted, kept as it closes (Ctx::ride_end).
priv struct Riding {
  id : @view.NodeId
  rev : Int
  k0 : Int
  seg0 : Int
  clips0 : Int
  rings0 : Int
  x : Double
  y : Double
  a : Double
  off_x : Double
  off_y : Double
  /// where in clip_stack the clip it is drawn in is
  clip_at : Int
  spots : Array[RideSpot]
  mut spoiled : Bool
  mut x0 : Double
  mut y0 : Double
  mut x1 : Double
  mut y1 : Double
  mut nodes : Int
  kept : Array[Array[(Int, Double, Double)]]
  /// an old view hosted (island_rides): drawn again only where it was
  island : Bool
  /// drawn all of it under no clip of the window's (one pushed over its clip at `clip_at`), its own clips whole, cut by
  /// its clip once drawn (inst_cut)
  cut : Bool
  /// of such a one, each of its nodes that draws only in its box (in_box) and is inside its own clips: where it is (x0,
  /// y0, x1, y1, off its root's place), and what it drew, from and to: its instances, shape pieces and pictures, off
  /// the row's, and the clip of the row's own it is drawn in (Ctx::ride_cut_node), fourteen numbers each
  edges : Array[Double]
}

///|
/// What each row drew last, by its root (kept while it is drawn so: let go with the node, view_forget).
// kept across runs: emptied as a run begins (view_forget), each let go with its node (view_changes_taken)
let ride_kept : ByNode[RideKept] = ByNode::new()

///|
/// The rows kept whose instances the host keeps (RideKept's `group`), by their group: what a header among the frame's
/// stands for (Ctx::flat_from), drawn by the host itself where it keeps them.
// kept across runs: let go with what kept them (ride_let_go), told to the host as the frame they were last in is
// presented (ride_groups_told)
let ride_groups : Map[Int, RideKept] = {}

///|
/// The groups made so far: a group's number is never another's, so the same header is never another's instances
/// (frame_watch.mbt's insts_said, @damage's frames compared).
// kept across runs: a group's number is never one a run before had
let ride_groups_made : Ref[Int] = Ref(0)

///|
/// The groups let go since the last frame presented, told to the host after the next is (what that frame was compared
/// with may hold them).
// kept across runs: emptied as each frame is presented (ride_groups_told)
let ride_groups_gone : Array[Int] = []

///|
/// Where the frame's instances hold a header (Ctx::ride_head), in order: the instance it is at, its group's after it
/// up to its count in its room, unwritten.
// kept across runs: emptied as a frame's instances are (Ctx::spans_cut), each drawn out where they are worked on
let ride_spans : Array[Int] = []

///|
/// Whether the host keeps groups of instances (@hostapi.groups_here): asked once.
// kept across runs: the host's, the same for the program's life (each Tester's asked anew: reset_globals)
let groups_host : Ref[Int] = Ref(-1)

///|
fn groups_on() -> Bool {
  if groups_host.val < 0 {
    groups_host.val = if @hostapi.groups_here() { 1 } else { 0 }
  }
  groups_host.val == 1
}

///|
/// How many times what the rows keep changed (ride_keep, ride_let_go): what a frame drawn again as the last one painted
/// draws by is what it was drawn by while it is the same (scroll_patch.mbt).
// kept across runs: only counts
let ride_gen : Ref[Int] = Ref(0)

///|
/// Row `id` kept as `k`, what it kept before let go.
fn ride_keep(id : @view.NodeId, k : RideKept) -> Unit {
  ride_let_go(id)
  ride_gen.val = ride_gen.val + 1
  ride_kept[id] = k
}

///|
/// What row `id` kept let go, its group with it.
fn ride_let_go(id : @view.NodeId) -> Unit {
  match ride_kept.get(id) {
    Some(k) => {
      ride_gen.val = ride_gen.val + 1
      if k.group >= 0 {
        ride_groups.remove(k.group)
        ride_groups_gone.push(k.group)
      }
      ride_kept.remove(id)
    }
    None => ()
  }
}

///|
/// All the rows kept let go (view_forget).
fn ride_let_go_all() -> Unit {
  patch_forget()
  ride_gen.val = ride_gen.val + 1
  for g, _ in ride_groups {
    ride_groups_gone.push(g)
  }
  ride_groups.clear()
  ride_kept.clear()
  ride_cut_not.clear()
}

///|
/// The frame presented: the groups let go before it told to the host, and to what compares frames.
fn ride_groups_told() -> Unit {
  if ride_groups_gone.is_empty() {
    return
  }
  for g in ride_groups_gone {
    presented.group_drop(g)
    @hostapi.group_drop(g)
  }
  ride_groups_gone.clear()
}

///|
/// Whether a row's instances (`n` in `inst`) can be kept by the host and drawn by a header: none worked on as the
/// frame ends (a look's tag, slot 20 below 0; a native view's hole; a stream's picture, changing under the same
/// numbers).
fn ride_groupable(inst : FixedArray[Double], n : Int) -> Bool {
  for i in 0..<n {
    let b = i * inst_size
    let t = inst[b + 20]
    if t < 0.0 || inst[b + 5] == 9.0 || t >= @damage.stream_tex_base {
      return false
    }
  }
  true
}

///|
/// The frame's instances from `i0` on drawn out where a header stands for a group's (Ctx::ride_head), as the host
/// draws them: what works on them as they are finds them there.
fn Ctx::flat_from(self : Ctx, i0 : Int) -> Unit {
  while ride_spans.length() > 0 {
    let at = ride_spans[ride_spans.length() - 1]
    if at < i0 {
      break
    }
    ride_spans.pop() |> ignore
    let s = self.inst
    let b = at * inst_size
    let id = s[b + 12].to_int()
    let first = s[b + 13].to_int()
    let n = s[b + 14].to_int()
    guard ride_groups.get(id) is Some(k) else { abort("flat_from: group \{id} let go") }
    let clip = if s[b + 21] == 1.0 { Some(FixedArray::makei(4, fn(j) { s[b + 16 + j] })) } else { None }
    ride_put(k, first, n, s, at, s[b], s[b + 1], s[b + 15], clip)
  }
}

///|
/// The instance after instance `q` of `a` (one where an instance begins, as the frame's from its first): past the room
/// a header there stands for (Ctx::ride_head).
fn inst_after(a : FixedArray[Double], q : Int) -> Int {
  let b = q * inst_size
  if a[b + 5] == 13.0 {
    q + a[b + 14].to_int()
  } else {
    q + 1
  }
}

///|
/// The headers among the frame's instances past where they end now let go (what was drawn after `ninst` dropped).
fn Ctx::spans_cut(self : Ctx) -> Unit {
  while ride_spans.length() > 0 && ride_spans[ride_spans.length() - 1] >= self.ninst {
    ride_spans.pop() |> ignore
  }
}

///|
/// The rows drawn all of them (Riding's `cut`) that drew what moving them would not draw
/// again: drawn as they come from then on, only what of them is inside the clip.
// kept across runs: emptied as a run begins (ride_let_go_all), each another node's once its index is made again
let ride_cut_not : ByNode[Bool] = ByNode::new()

///|
/// The row being drawn now, as the tree is painted (none between paints).
// kept across runs: none between paints
let riding : Ref[Riding?] = Ref(None)

///|
/// How many rows were drawn as kept, moved (Ctx::ride_again): for a test.
// kept across runs: only counts
let ride_drawn : Ref[Int] = Ref(0)

///|
/// How many times glyphs kept by what nodes drew were let go of in the atlas (view_glyphs_held): a row kept before
/// draws them from where they are no more.
// kept across runs: only counts
let ride_glyphs_gone : Ref[Int] = Ref(0)

///|
/// The clip at `k` of `clip_stack`, its 24 numbers.
fn ride_clip_at(k : Int) -> FixedArray[Double] {
  let c = FixedArray::make(clip_n, 0.0)
  for j in 0..<clip_n {
    c[j] = clip_stack[k + j]
  }
  c
}

///|
/// Whether a clip is one a row's own clips are measured against the same wherever the row is in it: square, and its
/// outer square (push_clip_r's choice of an outer: none cuts a box inside it).
fn ride_clip_square(c : FixedArray[Double]) -> Bool {
  for j in 4..<8 {
    if c[j] != 0.0 || c[12 + j] != 0.0 {
      return false
    }
  }
  true
}

///|
/// Which of instance `b`'s numbers (in `a`) move with the row drawn in clip `e`: its clip's edges and its outer's
/// that are not `e`'s own (its own clips' within it, as far inside it as the row is), as bits 0-3 and 4-7; bit 8, the
/// place 33-34 says.
fn ride_moves(a : FixedArray[Double], b : Int, e : FixedArray[Double]) -> Int {
  let mut m = 0
  for j in 0..<4 {
    if a[b + 16 + j] != e[j] {
      m = m | (1 << j)
    }
  }
  let none = a[b + 40] == 0.0 && a[b + 41] == 0.0 && a[b + 42] == 0.0 && a[b + 43] == 0.0
  if !none {
    for j in 0..<4 {
      let v = a[b + 40 + j]
      if v != e[j] && v != e[12 + j] {
        m = m | (1 << (4 + j))
      }
    }
  }
  if a[b + 32] != 0.0 {
    m = m | 256
  }
  m
}

///|
/// ride_moves' bits of instance `b` (in `a`) of a row drawn under no clip of the window's (Riding's `cut`): every edge of
/// its clip and its outer that is one (a clip of the row's own: none is its clip's, cut by that only as it is drawn),
/// not the unbounded's.
fn ride_moves_cut(a : FixedArray[Double], b : Int) -> Int {
  let mut m = 0
  for j in 0..<4 {
    if a[b + 16 + j].abs() < 1.0e8 {
      m = m | (1 << j)
    }
  }
  let none = a[b + 40] == 0.0 && a[b + 41] == 0.0 && a[b + 42] == 0.0 && a[b + 43] == 0.0
  if !none {
    for j in 0..<4 {
      if a[b + 40 + j].abs() < 1.0e8 {
        m = m | (1 << (4 + j))
      }
    }
  }
  if a[b + 32] != 0.0 {
    m = m | 256
  }
  m
}

///|
/// Whether `v` points are whole pixels, `sc` of them a point.
fn ride_whole(v : Double, sc : Double) -> Bool {
  let p = v * sc
  (p - p.round()).abs() < 1.0e-6
}

///|
/// A row being drawn begun (`c` at (x, y), as opaque as `a`, laid out at (ux, uy)), its instances from here on its.
fn Ctx::ride_begin(
  self : Ctx,
  c : @view.Content,
  rev : Int,
  x : Double,
  y : Double,
  a : Double,
  ux : Double,
  uy : Double,
  clips : Int,
  rings : Int,
  island? : Bool = false,
) -> Unit {
  let k = clip_top()
  // (drawn all of it, none of it left out where it lies outside the clip, its own clips whole, cut by the clip once
  // drawn: kept so, drawn again wherever it is moved in it, across its edges too)
  // (not one taller or wider than the clip, nor one that drew what moving it would not draw again as it was drawn so
  // before: all of it drawn each time for nothing, ride_cut_not)
  let cut = !island &&
    c.w <= clip_stack[k + 2] - clip_stack[k] &&
    c.h <= clip_stack[k + 3] - clip_stack[k + 1] &&
    !ride_cut_not.contains(c.id)
  riding.val = Some({
    id: c.id,
    rev,
    k0: self.ninst,
    seg0: self.segs.length() / 4,
    clips0: clips,
    rings0: rings,
    x,
    y,
    a,
    off_x: ux - x,
    off_y: uy - y,
    clip_at: clip_top(),
    spots: [],
    spoiled: false,
    x0: x,
    y0: y,
    x1: x + c.w,
    y1: y + c.h,
    nodes: 0,
    kept: [],
    island,
    cut,
    edges: [],
  })
  if cut {
    push_unclipped()
  }
}

///|
/// Whether what node `c` draws lies in its box, where nothing moves it after it is drawn (in what is drawn stretched
/// `stretching` deep, turned by `turn`, its ground drawn in a box of its own, shadowed): one wholly outside the clip it
/// is drawn in draws nothing there (Ctx::view_paint).
fn in_box(c : @view.Content, stretching : Int, turn : Double, ground : (Double, Double, Double, Double)) -> Bool {
  stretching == 0 &&
  turn == 0.0 &&
  ground.0 == 0.0 &&
  ground.1 == 0.0 &&
  ground.2 == 0.0 &&
  ground.3 == 0.0 &&
  (c.shadow.2 & 0xFFL) == 0L
}

///|
/// Whether the row being drawn is drawn all of it (Riding's `cut`).
fn ride_cutting() -> Bool {
  riding.val is Some(r) && r.cut
}

///|
/// How many pictures the row being drawn has drawn anew (Riding's `spots`).
fn ride_spots_n() -> Int {
  match riding.val {
    Some(r) => r.spots.length()
    None => 0
  }
}

///|
/// A node of the row being drawn all of it, reaching from (x0, y0) to (x1, y1), drawn from instance `k0`, shape piece
/// `seg0` and picture `spot0` on, to where the frame's are now (`ring`: where its edge was, drawn after what it holds,
/// taken out of them), and the clip of the row's own it is drawn in: told of the row (`edges`), fourteen numbers each,
/// left out where it is drawn again wholly outside its clip (Ctx::ride_emit).
fn Ctx::ride_cut_node(
  self : Ctx,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  k0 : Int,
  seg0 : Int,
  spot0 : Int,
  ring : Int,
) -> Unit {
  guard riding.val is Some(r) && r.cut else { return }
  // (its edge taken out as it is drawn, held till what it holds is drawn (view_paint's rings): told of the row as it is
  // put, Ctx::ride_ring_put; the pictures it drew after it one back with the rest)
  let held = if ring >= 0 { 1 } else { 0 }
  if ring >= 0 {
    for j in spot0..<r.spots.length() {
      let sp = r.spots[j]
      if sp.at > ring {
        r.spots[j] = { ..sp, at: sp.at - 1, end: sp.end - 1 }
      }
    }
  }
  ride_edge(
    r,
    x0,
    y0,
    x1,
    y1,
    k0 - r.k0,
    self.ninst - held - r.k0,
    seg0 - r.seg0,
    self.segs.length() / 4 - r.seg0,
    spot0,
    r.spots.length(),
  )
}

///|
/// The edge of a node reaching from (x0, y0) to (x1, y1) put as the frame's last instance (view_paint's rings): of a row
/// being drawn all of it, told of it as a node of its own (`edges`).
fn Ctx::ride_ring_put(self : Ctx, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  guard riding.val is Some(r) && r.cut else { return }
  let s = self.segs.length() / 4 - r.seg0
  let p = r.spots.length()
  ride_edge(r, x0, y0, x1, y1, self.ninst - 1 - r.k0, self.ninst - r.k0, s, s, p, p)
}

///|
/// Node of row `r` reaching from (x0, y0) to (x1, y1) told of it (`edges`): what it drew, from and to, and the clip of
/// the row's own it is drawn in.
fn ride_edge(
  r : Riding,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  i0 : Int,
  i1 : Int,
  s0 : Int,
  s1 : Int,
  p0 : Int,
  p1 : Int,
) -> Unit {
  let k = clip_top()
  let ed = r.edges
  ed.push(x0 - r.x)
  ed.push(y0 - r.y)
  ed.push(x1 - r.x)
  ed.push(y1 - r.y)
  ed.push(i0.to_double())
  ed.push(i1.to_double())
  ed.push(s0.to_double())
  ed.push(s1.to_double())
  ed.push(p0.to_double())
  ed.push(p1.to_double())
  ed.push(clip_stack[k] - r.x)
  ed.push(clip_stack[k + 1] - r.y)
  ed.push(clip_stack[k + 2] - r.x)
  ed.push(clip_stack[k + 3] - r.y)
}

///|
/// Instances `i0` until `i1` of `a`, drawn under no clip of the window's, cut by clip `e` (a clip_stack
/// level's numbers, square: ride_clip_square) as push_box_clip cuts what is drawn in it: each one's rect within it, its
/// corners square where cut, its outer kept.
fn inst_cut(a : FixedArray[Double], i0 : Int, i1 : Int, e : FixedArray[Double]) -> Unit {
  let (e0, e1, e2, e3) = (e[0], e[1], e[2], e[3])
  guard i1 * inst_size <= a.length() else { abort("inst_cut: \{i1} instances, room for fewer") }
  for q in i0..<i1 {
    let b = q * inst_size
    let x0 = a.unsafe_get(b + 16)
    let y0 = a.unsafe_get(b + 17)
    let x1 = a.unsafe_get(b + 18)
    let y1 = a.unsafe_get(b + 19)
    let cut_l = x0 < e0
    let cut_t = y0 < e1
    let cut_r = x1 > e2
    let cut_b = y1 > e3
    if !(cut_l || cut_t || cut_r || cut_b) {
      continue
    }
    if cut_l || cut_t {
      a.unsafe_set(b + 24, 0.0)
      a.unsafe_set(b + 28, 0.0)
    }
    if cut_r || cut_t {
      a.unsafe_set(b + 25, 0.0)
      a.unsafe_set(b + 29, 0.0)
    }
    if cut_r || cut_b {
      a.unsafe_set(b + 26, 0.0)
      a.unsafe_set(b + 30, 0.0)
    }
    if cut_l || cut_b {
      a.unsafe_set(b + 27, 0.0)
      a.unsafe_set(b + 31, 0.0)
    }
    if cut_l {
      a.unsafe_set(b + 16, e0)
    }
    if cut_t {
      a.unsafe_set(b + 17, e1)
    }
    if cut_r {
      a.unsafe_set(b + 18, e2)
    }
    if cut_b {
      a.unsafe_set(b + 19, e3)
    }
  }
}

///|
/// The row being drawn ended, all of it drawn: kept where nothing of it is drawn otherwise than moving it would draw
/// it, wholly within its clip one way at least; else what was kept of it let go.
fn Ctx::ride_end(self : Ctx) -> Unit {
  guard riding.val is Some(r) else { return }
  riding.val = None
  let k = r.clip_at
  // (drawn all of it: the clip over its own taken off; kept as drawn, then cut by its clip)
  if r.cut {
    pop_clip()
  }
  let side_x = ride_side(r.x0, r.x1, clip_stack[k], clip_stack[k + 2])
  let side_y = ride_side(r.y0, r.y1, clip_stack[k + 1], clip_stack[k + 3])
  let n = self.ninst - r.k0
  let e = ride_clip_at(k)
  if r.cut && r.spoiled {
    ride_cut_not[r.id] = true
  }
  let keep = !(r.spoiled || (!r.island && !r.cut && side_x != 0 && side_y != 0) || !ride_clip_square(e))
  // (one not kept drawn as it is, not by a header: no frame of its list moving alone drawn again so, scroll_patch.mbt)
  if !keep {
    patch_spoil("a row not kept")
  }
  if !keep && !r.cut {
    ride_let_go(r.id)
    return
  }
  let inst = FixedArray::make(n * inst_size, 0.0)
  self.inst.blit_to(inst, len=n * inst_size, src_offset=r.k0 * inst_size)
  let moves = FixedArray::make(n, 0)
  for i in 0..<n {
    moves[i] = if r.cut { ride_moves_cut(inst, i * inst_size) } else { ride_moves(inst, i * inst_size, e) }
  }
  let owned = inst_owners_kept()
  let owners : Array[(Int, (Double, Double), @view.NodeId?, Int)] = []
  if owned {
    let o = inst_owners.owner
    let cl = inst_owners.cell
    let tr = inst_owners.tree
    let mk = inst_owners.mark
    for k in r.k0..<self.ninst {
      owners.push(
        (
          if k < o.length() { o[k] } else { -1 },
          if k < cl.length() { cl[k] } else { (0.0, 1.0) },
          if k < tr.length() { tr[k] } else { None },
          if k < mk.length() { mk[k] } else { 0 },
        ),
      )
    }
  }
  let segs = []
  for j in (r.seg0 * 4)..<self.segs.length() {
    segs.push(self.segs[j])
  }
  // (kept by the host where it keeps groups and nothing of them is worked on as the frame ends)
  let group = if keep && groups_on() && ride_groupable(inst, n) {
    ride_groups_made.val = ride_groups_made.val + 1
    ride_groups_made.val
  } else {
    -1
  }
  let kept : RideKept = {
    id: r.id,
    rev: r.rev,
    x: r.x,
    y: r.y,
    a: r.a,
    off_x: r.off_x,
    off_y: r.off_y,
    scale: self.scale,
    zoom: words_zoom.val,
    glyphs: ride_glyphs_gone.val,
    owned,
    clip: e,
    inst,
    moves,
    segs,
    seg0: r.seg0,
    pack: SegPack::new(),
    spots: r.spots.map(fn(s) { { ..s, at: s.at - r.k0, end: s.end - r.k0 } }),
    owners,
    reach: (r.x0, r.y0, r.x1, r.y1),
    inside_x: side_x == 0,
    inside_y: side_y == 0,
    cut: r.cut,
    edges: r.edges,
    nodes: r.nodes,
    kept: r.kept,
    group,
  }
  if keep {
    ride_keep(r.id, kept)
  } else {
    ride_let_go(r.id)
  }
  if group >= 0 {
    ride_groups[group] = kept
    presented.group_set(group, inst, n)
    @hostapi.group_set(group, inst, FixedArray::makei(n, fn(i) { moves[i].to_double() }), n)
  }
  // (drawn all of it: what the frame drew of it taken back, drawn as it is drawn again, what is wholly outside its
  // clip left out, cut by it; so the same whether drawn anew or again)
  // (its glass taking the captures it took as it was drawn)
  if r.cut {
    ride_caps.clear()
    for i in 0..<n {
      let b = i * inst_size
      let kind = inst[b + 5]
      if (kind == 5.0 || kind == 6.0) && inst[b + 20] < 0.0 {
        let was = (-inst[b + 20]).to_int()
        ride_caps[was] = was
      }
    }
    self.ninst = r.k0
    self.spans_cut()
    self.segs_cut(r.seg0 * 4)
    self.ride_emit(kept, 0.0, 0.0, caps=true, outside=!keep)
  }
}

///|
/// Node `c` of the row being drawn, drawn at (x, y) `s` times as big: how far the row reaches, and whether it draws
/// what moving it would not draw again (`moved_not`: turned, grown, faded or stretched, in a layer, glass, bones, an
/// old view, a field).
fn ride_node(c : @view.Content, x : Double, y : Double, s : Double, moved_not : Bool) -> Unit {
  guard riding.val is Some(r) else { return }
  r.nodes = r.nodes + 1
  if moved_not ||
    s != 1.0 ||
    (c.hosted && !(r.island && r.id == c.id)) ||
    c.bones != 0L ||
    c.glass is Some(_) {
    r.spoiled = true
  }
  r.x0 = dmin(r.x0, x)
  r.y0 = dmin(r.y0, y)
  r.x1 = dmax(r.x1, x + c.w * s)
  r.y1 = dmax(r.y1, y + c.h * s)
}

///|
/// Content `c`'s picture drawn here (`seen`), or, one not seen, asked for (Ctx::view_unseen); of the row being drawn,
/// what it draws anew each time, where it was among its instances kept (no closure made for it: one a node).
fn Ctx::ride_spot(
  self : Ctx,
  c : @view.Content,
  x : Double,
  y : Double,
  s : Double,
  a : Double,
  seen : Bool,
) -> Unit {
  match riding.val {
    Some(r) => {
      let at = self.ninst
      let k = clip_top()
      // (of a row drawn all of it, drawn as the row is drawn as kept: Ctx::ride_end)
      if !r.cut {
        self.ride_draw(c, x, y, s, a, seen)
      }
      r.spots.push({
        at,
        end: self.ninst,
        c,
        x,
        y,
        s,
        a,
        clip: if seen { Some(ride_clip_at(k)) } else { None },
        apart: clip_is_apart(k),
        window: clip_is_window(k),
      })
    }
    None => self.ride_draw(c, x, y, s, a, seen)
  }
}

///|
/// Content `c`'s picture drawn (`seen`), or asked for where it is not seen.
fn Ctx::ride_draw(self : Ctx, c : @view.Content, x : Double, y : Double, s : Double, a : Double, seen : Bool) -> Unit {
  if seen {
    self.view_picture(c, x, y, s, a)
  } else {
    self.view_unseen(c, s)
  }
}

///|
/// Whether row `c`, drawn at (x, y) as opaque as `a`, `s` times as big, laid out at (ux, uy), may be drawn as kept,
/// moved (Ctx::ride_again): nothing of it changed since (its count of changes no more than what was kept's), as big,
/// opaque and set on the pixels as then, moved by whole pixels only and that within the same clip, at both ends
/// wholly within it whichever way it moved.
fn Ctx::ride_kept_for(
  self : Ctx,
  tree : @view.Tree,
  c : @view.Content,
  x : Double,
  y : Double,
  a : Double,
  s : Double,
  ux : Double,
  uy : Double,
) -> RideKept? {
  guard ride_kept.get(c.id) is Some(k) else { return None }
  let dx = x - k.x
  let dy = y - k.y
  // (an old view hosted: only where it was, nothing it read as it was painted changed since, nor built anew, nothing
  // said to move)
  if c.hosted && !(dx == 0.0 && dy == 0.0 && island_still(c.id, self.build_no) && !self.moves_now()) {
    return None
  }
  let fits = s == 1.0 &&
    a == k.a &&
    ux - x == k.off_x &&
    uy - y == k.off_y &&
    self.scale == k.scale &&
    words_zoom.val == k.zoom &&
    ride_glyphs_gone.val == k.glyphs &&
    inst_owners_kept() == k.owned &&
    tree.drawn_rev(c.id) <= k.rev &&
    ride_whole(dx, self.scale) &&
    ride_whole(dy, self.scale)
  guard fits else { return None }
  let e = k.clip
  let (x0, y0, x1, y1) = k.reach
  if k.cut {
    // (one drawn all of it, cut by its clip each time: wherever it meets it; wholly past it, drawn as nothing)
    guard x1 + dx > e[0] && x0 + dx < e[2] && y1 + dy > e[1] && y0 + dy < e[3] else { return None }
  } else {
    guard dx == 0.0 || (k.inside_x && ride_side(x0 + dx, x1 + dx, e[0], e[2]) == 0) else { return None }
    guard dy == 0.0 || (k.inside_y && ride_side(y0 + dy, y1 + dy, e[1], e[3]) == 0) else { return None }
  }
  let at = clip_top()
  for j in 0..<clip_n {
    if clip_stack[at + j] != e[j] {
      return None
    }
  }
  Some(k)
}

///|
/// Row kept `k` drawn again, moved by (dx, dy): its instances where they were moved, what of it is drawn anew drawn
/// so in its place among them; of one drawn all of it, what of its nodes is wholly outside the
/// clip where they are now left out (its instances, shape pieces and pictures), as drawing it there would leave them.
fn Ctx::ride_again(self : Ctx, k : RideKept, dx : Double, dy : Double) -> Unit {
  ride_drawn.val = ride_drawn.val + 1
  self.ride_emit(k, dx, dy)
}

///|
/// Row kept `k`'s drawing put after the frame's, moved by (dx, dy), as Ctx::ride_again draws it (`caps`: the captures
/// its glass takes as ride_caps says already, Ctx::ride_end's).
fn Ctx::ride_emit(
  self : Ctx,
  k : RideKept,
  dx : Double,
  dy : Double,
  caps? : Bool = false,
  outside? : Bool = false,
) -> Unit {
  if !caps {
    ride_caps.clear()
  }
  let seg_by = (self.segs.length() / 4 - k.seg0).to_double()
  // (one drawn so once, not kept (Ctx::ride_end): what of it is wholly outside its clip left out, as it is drawn from
  // then on, ride_cut_not)
  let out = if k.cut && outside { ride_out_now(k, dx, dy).unwrap_or(ride_none_out) } else { ride_none_out }
  if out.is_empty() {
    self.segs_put(k.segs, k.pack)
  } else {
    // (its pieces but those of what is left out)
    let mut p = 0
    for o in out {
      for v in (4 * p)..<(4 * k.edges[o + 6].to_int()) {
        self.segs.push(k.segs[v])
      }
      p = k.edges[o + 7].to_int()
    }
    for v in (4 * p)..<k.segs.length() {
      self.segs.push(k.segs[v])
    }
  }
  let n = k.inst.length() / inst_size
  let mut from = 0
  let mut si = 0
  let mut removed = 0
  let mut q = 0
  while true {
    // (the pictures before the next left out drawn as before; those it drew not seen)
    let sp0 = if q < out.length() { k.edges[out[q] + 8].to_int() } else { k.spots.length() }
    while si < sp0 {
      let sp = k.spots[si]
      self.ride_copy(k, from, sp.at, dx, dy, seg_by - removed.to_double())
      self.ride_spot_again(k, sp, dx, dy)
      from = sp.end
      si = si + 1
    }
    guard q < out.length() else { break }
    let o = out[q]
    self.ride_copy(k, from, k.edges[o + 4].to_int(), dx, dy, seg_by - removed.to_double())
    while si < k.edges[o + 9].to_int() {
      self.view_unseen(k.spots[si].c, k.spots[si].s)
      si = si + 1
    }
    from = k.edges[o + 5].to_int()
    removed = removed + k.edges[o + 7].to_int() - k.edges[o + 6].to_int()
    q = q + 1
  }
  self.ride_copy(k, from, n, dx, dy, seg_by - removed.to_double())
}

///|
/// Where in row kept `k`'s `edges` each node it drew is that is wholly outside its clip moved by (dx, dy), in order;
/// none where one it left out as outside would be drawn there (drawn anew).
fn ride_out_now(k : RideKept, dx : Double, dy : Double) -> Array[Int]? {
  let e = k.clip
  // (all of it within the clip, none left out: none of it outside)
  if ride_within(k, dx, dy) {
    return Some(ride_none_out)
  }
  let ox = k.x + dx
  let oy = k.y + dy
  let ed = k.edges
  let out = []
  let mut i = 0
  while i < ed.length() {
    // (as the row is drawn there: outside the clip of its own it is drawn in, or the row's)
    let x0 = ed[i] + ox
    let y0 = ed[i + 1] + oy
    let x1 = ed[i + 2] + ox
    let y1 = ed[i + 3] + oy
    let gone = x0 > ed[i + 12] + ox ||
      y0 > ed[i + 13] + oy ||
      x1 < ed[i + 10] + ox ||
      y1 < ed[i + 11] + oy ||
      x0 > e[2] ||
      y0 > e[3] ||
      x1 < e[0] ||
      y1 < e[1]
    if ed[i + 4] < 0.0 {
      if !gone {
        return None
      }
    } else if gone {
      out.push(i)
    }
    i = i + 14
  }
  Some(out)
}

///|
/// Whether all row kept `k` reaches, moved by (dx, dy), is within its clip.
fn ride_within(k : RideKept, dx : Double, dy : Double) -> Bool {
  let e = k.clip
  let (x0, y0, x1, y1) = k.reach
  x0 + dx >= e[0] && x1 + dx <= e[2] && y0 + dy >= e[1] && y1 + dy <= e[3]
}

///|
/// No node of a row outside its clip (ride_out_now).
// kept across runs: never written
let ride_none_out : Array[Int] = []

///|
/// Picture `sp` of row kept `k` drawn again, moved by (dx, dy), as it was drawn: in the clip it was drawn in, moved
/// where it is the row's own; one not seen, not seen again.
fn Ctx::ride_spot_again(self : Ctx, k : RideKept, sp : RideSpot, dx : Double, dy : Double) -> Unit {
  match sp.clip {
    None => self.view_unseen(sp.c, sp.s)
    Some(cl) => {
      // (a picture drawn anew each time: no frame of its list moving alone drawn again so, scroll_patch.mbt)
      patch_spoil("a picture of a row drawn anew")
      // (the clip it was drawn in, moved where it is the row's own)
      let e = k.clip
      for j in 0..<clip_n {
        let v = cl[j]
        let moved = j < 4 && (if k.cut { v.abs() < 1.0e8 } else { v != e[j] })
        clip_stack.push(if moved { v + (if j % 2 == 0 { dx } else { dy }) } else { v })
      }
      for j in 12..<16 {
        let v = clip_stack[clip_stack.length() - clip_n + j]
        let none = cl[12] == 0.0 && cl[13] == 0.0 && cl[14] == 0.0 && cl[15] == 0.0
        if !none && (if k.cut { v.abs() < 1.0e8 } else { v != e[j - 12] && v != e[j] }) {
          clip_stack[clip_stack.length() - clip_n + j] = v + (if j % 2 == 0 { dx } else { dy })
        }
      }
      clip_say_apart(sp.apart)
      clip_say_window(sp.window)
      self.view_picture(sp.c, sp.x + dx, sp.y + dy, sp.s, sp.a)
      pop_clip()
    }
  }
}

///|
/// The captures the glass of the row drawn again (Ctx::ride_again) took as it was painted, each the one it takes in
/// this frame.
// kept across runs: emptied as each row is drawn again
let ride_caps : Map[Int, Int] = {}

///|
/// Row kept `k`'s instances `i0` until `i1` put after the frame's, moved by (dx, dy), their shapes' pieces where they
/// are among the frame's now (`seg_by` on): where the host keeps its group, a header in their place (Ctx::ride_head),
/// their room after it unwritten.
fn Ctx::ride_copy(self : Ctx, k : RideKept, i0 : Int, i1 : Int, dx : Double, dy : Double, seg_by : Double) -> Unit {
  let n = i1 - i0
  guard n > 0 else { return }
  while (self.ninst + n) * inst_size > self.inst.length() {
    self.grow()
  }
  let at = self.ninst
  // (drawn all of it: cut by its clip where it is now, as the header says where the host draws it out)
  let clip = if k.cut { Some(k.clip) } else { None }
  if k.group >= 0 && dr.mode == 0 && !shooting.val {
    self.ride_head(k.group, i0, n, at, dx, dy, seg_by, clip)
  } else {
    ride_put(k, i0, n, self.inst, at, dx, dy, seg_by, clip)
    // (one of no list's, an old view hosted, drawn where it was: drawn so again while it reads as it did; one of a
    // list's, moved with it, no frame of the list moving alone drawn again so, scroll_patch.mbt)
    patch_put(k.id)
  }
  if k.owned {
    for i in 0..<n {
      let q = at + i
      inst_owned(q)
      let (ow, cel, tre, mar) = k.owners[i0 + i]
      inst_owners.owner[q] = ow
      inst_owners.cell[q] = cel
      inst_owners.tree[q] = tre
      inst_owners.mark[q] = mar
    }
  }
  self.ninst = at + n
}

///|
/// A header at instance `at` (kind 13, scene.mbt): group `group`'s instances from `first`, `n` of them, moved by
/// (dx, dy), their shapes' pieces `seg_by` on, cut by `clip` (16-19, 21 one: one drawn all of it across its clip's
/// edges), drawn in its place and the room after it, as ride_put would write them.
fn Ctx::ride_head(
  self : Ctx,
  group : Int,
  first : Int,
  n : Int,
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
  clip : FixedArray[Double]?,
) -> Unit {
  let s = self.inst
  let b = at * inst_size
  ride_head_blank.blit_to(s, len=inst_size, dst_offset=b)
  s[b] = dx
  s[b + 1] = dy
  s[b + 5] = 13.0
  s[b + 12] = group.to_double()
  s[b + 13] = first.to_double()
  s[b + 14] = n.to_double()
  s[b + 15] = seg_by
  if clip is Some(e) {
    for j in 0..<4 {
      s[b + 16 + j] = e[j]
    }
    s[b + 21] = 1.0
  }
  ride_spans.push(at)
  ride_heads.val = ride_heads.val + 1
}

///|
/// How many headers were written (Ctx::ride_head): for a test.
// kept across runs: only counts
let ride_heads : Ref[Int] = Ref(0)

///|
// kept across runs: never written
let ride_head_blank : FixedArray[Double] = FixedArray::make(inst_size, 0.0)

///|
/// Row kept `k`'s instances from `i0`, `n` of them, written into `s` from instance `at`, moved by (dx, dy), their
/// shapes' pieces `seg_by` on, cut by `clip` where one is given (inst_cut): what a header of its group stands for (the
/// host's mb_groups_draw_out, groups.h).
fn ride_put(
  k : RideKept,
  i0 : Int,
  n : Int,
  s : FixedArray[Double],
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
  clip : FixedArray[Double]?,
) -> Unit {
  k.inst.blit_to(s, len=n * inst_size, src_offset=i0 * inst_size, dst_offset=at * inst_size)
  for i in 0..<n {
    let b = (at + i) * inst_size
    s.unsafe_set(b, s.unsafe_get(b) + dx)
    s.unsafe_set(b + 1, s.unsafe_get(b + 1) + dy)
    let kind = s.unsafe_get(b + 5)
    if kind == 11.0 {
      s.unsafe_set(b + 12, s.unsafe_get(b + 12) + seg_by)
    } else if (kind == 5.0 || kind == 6.0) && s.unsafe_get(b + 20) < 0.0 {
      // (glass, an old view's: a capture of this frame's, as one kept and drawn again takes, Ctx::insts_replay)
      let was = (-s.unsafe_get(b + 20)).to_int()
      let now = match ride_caps.get(was) {
        Some(c) => c
        None => {
          glass_paint.run = glass_paint.run + 1
          ride_caps[was] = glass_paint.run
          glass_paint.run
        }
      }
      s.unsafe_set(b + 20, -now.to_double())
      if kind == 5.0 {
        glass_paint.frost_run = now
      }
      glass_paint.run_start = -1
      glass_paint.run_len = 0
    }
    let m = k.moves.unsafe_get(i0 + i)
    if m != 0 {
      for j in 0..<4 {
        let d = if j % 2 == 0 { dx } else { dy }
        if (m & (1 << j)) != 0 {
          s.unsafe_set(b + 16 + j, s.unsafe_get(b + 16 + j) + d)
        }
        if (m & (1 << (4 + j))) != 0 {
          s.unsafe_set(b + 40 + j, s.unsafe_get(b + 40 + j) + d)
        }
      }
      if (m & 256) != 0 {
        s.unsafe_set(b + 33, s.unsafe_get(b + 33) + dx)
        s.unsafe_set(b + 34, s.unsafe_get(b + 34) + dy)
      }
    }
  }
  if clip is Some(e) {
    inst_cut(s, at, at + n, e)
  }
}

///|
/// The row being drawn draws what moving it would not draw again: not kept.
fn ride_spoil() -> Unit {
  match riding.val {
    Some(r) => r.spoiled = true
    None => ()
  }
}

///|
/// Whether row `c` drawn at (x, y) may be kept or drawn as kept: in a square clip (ride_clip_square), some of it inside
/// it; one wholly past it, or only touching its edge (a row kept for what comes, drawing nothing: no more gone through
/// than drawn again), drawn as it comes.
fn ride_may(c : @view.Content, x : Double, y : Double) -> Bool {
  let k = clip_top()
  // (in a clip not square none is kept, Ctx::ride_end: none gone through to be)
  for j in 4..<8 {
    if clip_stack[k + j] != 0.0 || clip_stack[k + 12 + j] != 0.0 {
      return false
    }
  }
  ride_meets(x, y, x + c.w, y + c.h, k)
}

///|
/// Whether what reaches from (x0, y0) to (x1, y1) has any of it inside the clip at `k` of `clip_stack`: not only
/// touching its edge (one that does draws nothing there, as one wholly past it).
fn ride_meets(x0 : Double, y0 : Double, x1 : Double, y1 : Double, k : Int) -> Bool {
  x1 > clip_stack[k] && x0 < clip_stack[k + 2] && y1 > clip_stack[k + 1] && y0 < clip_stack[k + 3]
}

///|
/// Where what reaches from `a0` to `a1` one way is against a clip from `c0` to `c1` that way: 0 wholly within it, 1 wholly
/// before it, 2 wholly past it, -1 across an edge of it (or on one).
fn ride_side(a0 : Double, a1 : Double, c0 : Double, c1 : Double) -> Int {
  if a0 > c0 && a1 < c1 {
    0
  } else if a1 < c0 {
    1
  } else if a0 > c1 {
    2
  } else {
    -1
  }
}

///|
/// What an old view hosted read as it was painted last (Ctx::island_painted), and the old frame's build it was painted
/// of: drawn again as kept (Ctx::ride_again) only while none of it changed.
priv struct IslandWatch {
  watch : @signals.Watch
  mut built : Int
}

///|
/// Whether an old view's list the hand moved this frame (frame_watch.mbt's frame_drawn): no old view drawn as kept.
// kept across runs: written as each frame begins
let old_lists_moved : Ref[Bool] = Ref(false)

///|
/// Each old view hosted's, by its node.
// kept across runs: emptied as a run begins (view_forget), each let go with its node (view_changes_taken)
let island_watches : ByNode[IslandWatch] = ByNode::new()

///|
/// Whether node `c`, an old view hosted, is drawn as kept where nothing of it changed: not the old frame's whole, not in
/// its bones, laid out in a box of the old frame's; not while the hand moves an old view's list (what it draws moves
/// each frame then: not kept to be drawn again).
fn island_rides(c : @view.Content) -> Bool {
  c.hosted && !old_whole.val && c.bones == 0L && !old_lists_moved.val && old_box_of.get(c.id) is Some(_)
}

///|
/// Whether the old view hosted in `id` reads as it did when it was painted last, of build `built`.
fn island_still(id : @view.NodeId, built : Int) -> Bool {
  match island_watches.get(id) {
    Some(w) => !w.watch.is_stale() && w.built == built
    None => false
  }
}

///|
/// The old view hosted in `c` painted by `paint`: where it is the row being drawn (island_rides), what it reads followed
/// (as the frame's paint follows what it reads: a frame asked for as it changes, that paint read anew), and the glyphs
/// it draws from kept for it (held in the atlas while it is drawn again: view_glyphs_held).
fn Ctx::island_painted(self : Ctx, c : @view.Content, paint : () -> Unit) -> Unit {
  guard riding.val is Some(r) && r.island && r.id == c.id else { return paint() }
  let w = match island_watches.get(c.id) {
    Some(w) => w
    None => {
      let w : IslandWatch = {
        watch: @signals.watch(fn() {
          // (as the frame's paint watch is told: paint_watch_of)
          paint_watch_of().touch()
          if frame_running.val && paint_phase.val == 0 {
            ()
          } else if frame_running.val {
            paint_said.val = "a value an old view's paint read changed as it was painted"
          } else {
            h_frame_owed()
          }
        }),
        built: -1,
      }
      island_watches[c.id] = w
      w
    }
  }
  let kept : Array[(Int, Double, Double)] = []
  let was = glyphs_kept.val
  glyphs_kept.val = Some(kept)
  // (what it asks of the frames as it is painted: a frame, a moment, a cycle, apart from what the rest of the frame asks;
  // a look by the clock it draws, cycle_look.mbt's tag, worked out as the frame's paint ends)
  let (wants, wake, cycling) = (self.wants_frame, self.wake_at, self.cycling)
  let tagged = cycle_tagged.val
  self.wants_frame = false
  self.wake_at = -1.0
  self.cycling = false
  w.watch.read(paint)
  let asked = self.wants_frame ||
    self.wake_at >= 0.0 ||
    self.cycling ||
    cycle_tagged.val != tagged ||
    self.moves_now()
  self.wants_frame = self.wants_frame || wants
  if wake >= 0.0 && (self.wake_at < 0.0 || wake < self.wake_at) {
    self.wake_at = wake
  }
  self.cycling = self.cycling || cycling
  glyphs_kept.val = was
  // (what goes on by the clock as it is painted (a motion, a fling, a caret's blink, a waiting band's breath), and what
  // is said to move while it is painted, drawn anew in the frames after, never as kept)
  w.built = if asked { -1 } else { self.build_no }
  r.kept.push(kept)
}

///|
/// No old view hosted drawn again as it was kept (an old view's list the hand moves: what they draw moved, nothing they
/// read told): each painted anew the next frame it is drawn.
fn islands_unkept() -> Unit {
  for id in island_watches.keys() {
    match island_watches.get(id) {
      Some(w) => w.built = -1
      None => ()
    }
  }
}

///|
/// What the old view hosted in `id` read let go of, with its node.
fn island_watch_gone(id : @view.NodeId) -> Unit {
  match island_watches.get(id) {
    Some(w) => {
      w.watch.stop()
      island_watches.remove(id)
    }
    None => ()
  }
}

///|
/// All of it let go, as a run begins.
fn island_watches_clear() -> Unit {
  for id in island_watches.keys() {
    island_watch_gone(id)
  }
}
