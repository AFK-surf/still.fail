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
  spots : Array[RideSpot]
  /// who drew each, as kept (inst_owners)
  owners : Array[(Int, (Double, Double), @view.NodeId?, Int)]
  /// how far all it holds reaches (x0, y0, x1, y1); whether that was wholly within its clip across and up and down
  reach : (Double, Double, Double, Double)
  inside_x : Bool
  inside_y : Bool
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
/// Whether the host keeps groups of instances (@hostapi.groups_here), a Tester's frames drawing them out as one would
/// (Ctx::flat_from): asked once.
// kept across runs: the host's, the same for the program's life
let groups_host : Ref[Int] = Ref(-1)

///|
fn groups_on() -> Bool {
  if fake.val is Some(_) {
    return true
  }
  if groups_host.val < 0 {
    groups_host.val = if @hostapi.groups_here() { 1 } else { 0 }
  }
  groups_host.val == 1
}

///|
/// Row `id` kept as `k`, what it kept before let go.
fn ride_keep(id : @view.NodeId, k : RideKept) -> Unit {
  ride_let_go(id)
  ride_kept[id] = k
}

///|
/// What row `id` kept let go, its group with it.
fn ride_let_go(id : @view.NodeId) -> Unit {
  match ride_kept.get(id) {
    Some(k) => {
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
  for g, _ in ride_groups {
    ride_groups_gone.push(g)
  }
  ride_groups.clear()
  ride_kept.clear()
}

///|
/// The frame presented: the groups let go before it told to the host, and to what compares frames.
fn ride_groups_told() -> Unit {
  if ride_groups_gone.is_empty() {
    return
  }
  let real = fake.val is None
  for g in ride_groups_gone {
    presented.group_drop(g)
    if real {
      @hostapi.group_drop(g)
    }
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
    ride_put(k, first, n, s, at, s[b], s[b + 1], s[b + 15])
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
) -> Unit {
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
  })
}

///|
/// The row being drawn ended, all of it drawn: kept where nothing of it is drawn otherwise than moving it would draw
/// it, wholly within its clip one way at least; else what was kept of it let go.
fn Ctx::ride_end(self : Ctx) -> Unit {
  guard riding.val is Some(r) else { return }
  riding.val = None
  let k = r.clip_at
  let side_x = ride_side(r.x0, r.x1, clip_stack[k], clip_stack[k + 2])
  let side_y = ride_side(r.y0, r.y1, clip_stack[k + 1], clip_stack[k + 3])
  let n = self.ninst - r.k0
  if r.spoiled || (side_x != 0 && side_y != 0) {
    ride_let_go(r.id)
    return
  }
  let e = ride_clip_at(k)
  if !ride_clip_square(e) {
    ride_let_go(r.id)
    return
  }
  let inst = FixedArray::make(n * inst_size, 0.0)
  self.inst.blit_to(inst, len=n * inst_size, src_offset=r.k0 * inst_size)
  let moves = FixedArray::make(n, 0)
  for i in 0..<n {
    moves[i] = ride_moves(inst, i * inst_size, e)
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
  let group = if groups_on() && ride_groupable(inst, n) {
    ride_groups_made.val = ride_groups_made.val + 1
    ride_groups_made.val
  } else {
    -1
  }
  let kept : RideKept = {
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
    spots: r.spots.map(fn(s) { { ..s, at: s.at - r.k0, end: s.end - r.k0 } }),
    owners,
    reach: (r.x0, r.y0, r.x1, r.y1),
    inside_x: side_x == 0,
    inside_y: side_y == 0,
    nodes: r.nodes,
    kept: r.kept,
    group,
  }
  ride_keep(r.id, kept)
  if group >= 0 {
    ride_groups[group] = kept
    if fake.val is None {
      presented.group_set(group, inst, n)
      @hostapi.group_set(group, inst, FixedArray::makei(n, fn(i) { moves[i].to_double() }), n)
    }
  }
}

///|
/// Node `c` of the row being drawn, drawn at (x, y) `s` times as big: how far the row reaches, and whether it draws
/// what moving it would not draw again (`moved_not`: turned, grown, faded or stretched, in a layer, glass, bones, an
/// old view, a field).
fn ride_node(c : @view.Content, x : Double, y : Double, s : Double, moved_not : Bool) -> Unit {
  guard riding.val is Some(r) else { return }
  r.nodes = r.nodes + 1
  if moved_not || s != 1.0 || c.hosted || c.bones != 0L || c.glass is Some(_) {
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
      self.ride_draw(c, x, y, s, a, seen)
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
  guard dx == 0.0 || (k.inside_x && ride_side(x0 + dx, x1 + dx, e[0], e[2]) == 0) else { return None }
  guard dy == 0.0 || (k.inside_y && ride_side(y0 + dy, y1 + dy, e[1], e[3]) == 0) else { return None }
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
/// so in its place among them.
fn Ctx::ride_again(self : Ctx, k : RideKept, dx : Double, dy : Double) -> Unit {
  ride_drawn.val = ride_drawn.val + 1
  let seg_by = (self.segs.length() / 4 - k.seg0).to_double()
  self.segs.append(k.segs)
  let mut from = 0
  for sp in k.spots {
    self.ride_copy(k, from, sp.at, dx, dy, seg_by)
    match sp.clip {
      None => self.view_unseen(sp.c, sp.s)
      Some(cl) => {
        // (the clip it was drawn in, moved where it is the row's own)
        let e = k.clip
        for j in 0..<clip_n {
          let v = cl[j]
          let moved = j < 4 && v != e[j]
          clip_stack.push(if moved { v + (if j % 2 == 0 { dx } else { dy }) } else { v })
        }
        for j in 12..<16 {
          let v = clip_stack[clip_stack.length() - clip_n + j]
          let none = cl[12] == 0.0 && cl[13] == 0.0 && cl[14] == 0.0 && cl[15] == 0.0
          if !none && v != e[j - 12] && v != e[j] {
            clip_stack[clip_stack.length() - clip_n + j] = v + (if j % 2 == 0 { dx } else { dy })
          }
        }
        clip_say_apart(sp.apart)
        clip_say_window(sp.window)
        self.view_picture(sp.c, sp.x + dx, sp.y + dy, sp.s, sp.a)
        pop_clip()
      }
    }
    from = sp.end
  }
  self.ride_copy(k, from, k.inst.length() / inst_size, dx, dy, seg_by)
}

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
  if k.group >= 0 && dr.mode == 0 && !shooting.val {
    self.ride_head(k.group, i0, n, at, dx, dy, seg_by)
  } else {
    ride_put(k, i0, n, self.inst, at, dx, dy, seg_by)
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
/// (dx, dy), their shapes' pieces `seg_by` on, drawn in its place and the room after it, as ride_put would write them.
fn Ctx::ride_head(
  self : Ctx,
  group : Int,
  first : Int,
  n : Int,
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
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
/// shapes' pieces `seg_by` on: what a header of its group stands for (the host's mb_groups_draw_out, groups.h).
fn ride_put(
  k : RideKept,
  i0 : Int,
  n : Int,
  s : FixedArray[Double],
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
) -> Unit {
  k.inst.blit_to(s, len=n * inst_size, src_offset=i0 * inst_size, dst_offset=at * inst_size)
  for i in 0..<n {
    let b = (at + i) * inst_size
    s.unsafe_set(b, s.unsafe_get(b) + dx)
    s.unsafe_set(b + 1, s.unsafe_get(b + 1) + dy)
    if s.unsafe_get(b + 5) == 11.0 {
      s.unsafe_set(b + 12, s.unsafe_get(b + 12) + seg_by)
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
/// Whether row `c` drawn at (x, y) may be kept or drawn as kept: its box wholly within the clip it is drawn in one way
/// at least, as all it holds must be (Ctx::ride_end); one across its edges each way, or wholly past it (a row kept
/// for what comes, drawing nothing: no more gone through than drawn again), drawn as it comes.
fn ride_may(c : @view.Content, x : Double, y : Double) -> Bool {
  let k = clip_top()
  ride_side(x, x + c.w, clip_stack[k], clip_stack[k + 2]) == 0 ||
  ride_side(y, y + c.h, clip_stack[k + 1], clip_stack[k + 3]) == 0
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
