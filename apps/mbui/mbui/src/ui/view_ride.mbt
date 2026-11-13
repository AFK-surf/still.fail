// What a list's row of the window's tree drew (Tree::rides_scroll), kept as the frame's instances it came to: drawn
// again moved, its nodes not gone through, where nothing of it changed since (Tree::drawn_rev) and it is only moved
// by whole pixels within the clip it is drawn in, as Android's RenderNode is drawn again offset, Chrome's layer
// scrolled. Where it was drawn otherwise than its instances moved say (its picture, decoded or fading in since; one
// not seen asked for), that part drawn anew in its place among them. So too what else holds others (a top bar, a
// card, a row's parts), in a row or in none: kept once it is gone through again and again with nothing of it changed
// (ride_holder), drawn again as kept from then on while nothing of it changes; what is gone through, so, is what
// changed and what holds it, down to it and no further, the rest drawn again as kept (a row whose icon turns: the
// icon and what holds it).

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
  /// its pieces as packed among the frame's (Ctx::segs_put)
  pack : SegPack
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
  /// whether its instances hold headers (a list's rows kept: ListRiding), each in one place of them, drawn out in its
  /// turn (ride_put_out); how many it draws out to
  heads : Bool
  out : Int
  /// a list drawn whole as one (ListRiding) with what is drawn anew each time it is drawn in it (a picture, one not seen
  /// asked for): drawn again only by going through it
  anew : Bool
  /// how many scrims the old frame had as it was drawn (ride_scrims): what of it is said to be drawn over a scrim
  /// (View::over_scrim) is moved after one as it is gone through (raising), never as it is drawn again, so it is drawn
  /// again only under as many (a scrim come or gone: gone through once, kept again after)
  scrims : Int
}

///|
/// How many scrims the old frame has as the window's tree is painted (dr.scrims: its layers' with a scrim, built before
/// the tree's paint): what is kept is kept under them (RideKept's `scrims`).
fn ride_scrims() -> Int {
  dr.scrims.length()
}

///|
/// What a column scrolls by its offset alone (a page's list's held, its bar's thumb: @view.Tree::scroll_off_of) being
/// drawn as the tree is painted: all of it drawn where it is placed in the column, not where the column has scrolled
/// it, in no clip of the window's (one open, push_unclipped), each row of it kept as drawn there (Riding, the inner of
/// the two); as it closes, kept whole as one group of the host's (@hostapi.group_set), drawn by one header moved as far
/// as the column has it and cut to the column's clip (ListHead), what moves it as it scrolls; else (one of its
/// instances worked on as the frame ends, an old view, bones: ride_groupable's) drawn out moved and cut so in its place
/// (list_put).
priv struct ListRiding {
  id : @view.NodeId
  /// the node of the column that scrolls it
  by : Int
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
  /// how big the window draws it: what the column's offset is multiplied by
  s : Double
  /// how far the window has it drawn off where it is placed, as it is drawn (its header's 0, 1), and the column's clip
  /// there (x0, y0, x1, y1: its header's 16-19)
  dx : Double
  dy : Double
  hc : FixedArray[Double]
  /// the clip it is drawn in (the open one), its 24 numbers
  clip : FixedArray[Double]
  mut spoiled : Bool
  mut anew : Bool
  mut nodes : Int
  kept : Array[Array[(Int, Double, Double)]]
}

///|
/// A header among the frame's instances of what a column scrolls by its offset alone (ListRiding): where it is, its
/// numbers as written, whose, how far it is moved besides (where it was kept from elsewhere: its header's 0, 1 less the
/// column's offset) and how big the window draws it; its header's 0, 1 written anew at each frame's moment by the
/// column's offset then (list_looks), nothing painted for it.
priv struct ListHead {
  mut at : Int
  head : FixedArray[Double]
  id : @view.NodeId
  bx : Double
  by : Double
  s : Double
}

///|
/// The headers of what columns scroll by their offsets alone among the frame's instances, in order (ListHead).
// kept across runs: emptied as a frame's instances are (Ctx::spans_cut)
let list_heads : Array[ListHead] = []

///|
/// The columns whose offset moves what was drawn out in the window's terms in the last paint (ListRiding: one of its
/// instances worked on as the frame ends, an old view, bones), by their nodes: moved, painted anew (view_offset_moved).
// kept across runs: emptied as each frame is painted
let offsets_flat : Array[Int] = []

///|
/// What each node drawing what it holds stretched (View::stretches) was last painted stretched by: one stretched
/// otherwise in a paint is told drawn anew where it shows (damage_known), one stretched as it was is not. Written only
/// as one is painted stretched, so a paint with none stretched does nothing more for it; let go whole as it comes to
/// stretch_painted_most (a node gone, or no longer stretched, kept till then: one stretched again as it was is compared,
/// as anything is), and as a run begins (view_forget), so a run's first stretch is told whatever ran before it.
// kept across runs: emptied as each begins (view_forget), written by a paint as it draws one stretched otherwise,
// emptied as it holds stretch_painted_most
let stretch_painted : Map[@view.NodeId, Double] = Map([])

///|
/// How many stretch_painted holds at most.
let stretch_painted_most = 16

///|
/// What a column scrolls by its offset alone being drawn now, as the tree is painted (none between paints): the outer
/// of the two rides there are (Riding the inner).
// kept across runs: none between paints
let list_riding : Ref[ListRiding?] = Ref(None)

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
  /// not a list's row nor an old view: what holds others (ride_holder), kept whether it is wholly within its clip or
  /// not
  holder : Bool
}

///|
/// What each row drew last, by its root (kept while it is drawn so: let go with the node, view_forget).
// kept across runs: emptied as a run begins (view_forget), each let go with its node (view_changes_taken)
let ride_kept : ByNode[RideKept] = ByNode::new()

///|
/// Each node as it was last gone through to paint it, by its index (ride_holder).
// kept across runs: emptied as a run begins (view_forget); one let go is another's at its index made again (RideWalk's
// `gen`)
let ride_walked : Array[RideWalk] = []

///|
/// A node as it was last gone through to paint it (ride_walked): which made at its index, the count of changes then,
/// where it was drawn and how opaque, and how many times running it was gone through so with nothing of it changed.
priv struct RideWalk {
  mut gen : Int
  mut rev : Int
  mut x : Double
  mut y : Double
  mut a : Double
  mut same : Int
}

///|
/// Node `id` gone through to paint it as of the count of changes `rev`, drawn at (x, y) as opaque as `a`, its count of
/// changes `now`: how many times running it was so with nothing of it changed, this one counted (0: it changed, or is
/// drawn otherwise than it was).
fn ride_walked_by(id : @view.NodeId, rev : Int, now : Int, x : Double, y : Double, a : Double) -> Int {
  let at = id.at
  while ride_walked.length() <= at {
    ride_walked.push({ gen: -1, rev: -1, x: 0.0, y: 0.0, a: 0.0, same: 0 })
  }
  let w = ride_walked.unsafe_get(at)
  w.same = if w.gen == id.gen && now <= w.rev && x == w.x && y == w.y && a == w.a { w.same + 1 } else { 0 }
  w.gen = id.gen
  w.rev = rev
  w.x = x
  w.y = y
  w.a = a
  w.same
}

///|
/// What holds others found holding a row, an old view or what a column scrolls by its offset alone as it was being drawn
/// to be kept (ride_holder_out), by its node: never begun again.
// kept across runs: emptied as a run begins (view_forget), each let go with its node (view_changes_taken)
let ride_unkept : ByNode[Bool] = ByNode::new()

///|
/// The rows kept whose instances the host keeps (RideKept's `group`), by their group: what a header among the frame's
/// stands for (Ctx::flat_from), drawn by the host itself where it keeps them.
// kept across runs: let go with what kept them (ride_let_go), told to the host as the frame they were last in is
// presented (ride_groups_told)
let ride_groups : Map[Int, RideKept] = Map([])

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
  ride_walked.clear()
  ride_unkept.clear()
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
    ride_draw_out(self.inst, at)
  }
}

///|
/// The header at instance `at` of `s` drawn out in its place, its group's instances there, as the host draws them
/// (groups.h's mb_group_out).
fn ride_draw_out(s : FixedArray[Double], at : Int) -> Unit {
  let b = at * inst_size
  let id = s[b + 12].to_int()
  guard ride_groups.get(id) is Some(k) else { @halt.saying("flat_from: group \{id} let go") }
  if k.heads {
    ride_put_out(k, s, at, s[b], s[b + 1], s[b + 15], s[b + 16], s[b + 17], s[b + 18], s[b + 19]) |> ignore
  } else {
    let first = s[b + 13].to_int()
    let n = s[b + 14].to_int()
    ride_put(k, first, n, s, at, s[b], s[b + 1], s[b + 15], s[b + 16], s[b + 17], s[b + 18], s[b + 19])
  }
}

///|
/// List kept `k`, whose instances hold headers (its rows kept, each in one place of it), written out whole into `s`
/// from instance `at`, moved by (dx, dy), its shapes' pieces `seg_by` on, cut to (h0, h1, h2, h3) as well: each header
/// drawn out where it comes, moved with it and cut so, as many as it says (groups.h's mb_group_out). How many it wrote.
fn ride_put_out(
  k : RideKept,
  s : FixedArray[Double],
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
  h0 : Double,
  h1 : Double,
  h2 : Double,
  h3 : Double,
) -> Int {
  let a = k.inst
  let m = a.length() / inst_size
  let mut q = at
  let mut i = 0
  while i < m {
    let b = i * inst_size
    if a[b + 5] != 13.0 {
      // (those up to the next header written at once)
      let mut j = i + 1
      while j < m && a[j * inst_size + 5] != 13.0 {
        j = j + 1
      }
      ride_put(k, i, j - i, s, q, dx, dy, seg_by, h0, h1, h2, h3)
      q = q + j - i
      i = j
      continue
    }
    guard ride_groups.get(a[b + 12].to_int()) is Some(r) else { @halt.saying("ride_put_out: group let go") }
    // (its clip this one's where it says none, else as much of both)
    let none = a[b + 16] == 0.0 && a[b + 17] == 0.0 && a[b + 18] == 0.0 && a[b + 19] == 0.0
    let cut = !(h0 == 0.0 && h1 == 0.0 && h2 == 0.0 && h3 == 0.0)
    let (c0, c1, c2, c3) = if !cut {
      (a[b + 16], a[b + 17], a[b + 18], a[b + 19])
    } else if none {
      (h0, h1, h2, h3)
    } else {
      (dmax(a[b + 16], h0), dmax(a[b + 17], h1), dmin(a[b + 18], h2), dmin(a[b + 19], h3))
    }
    let n = a[b + 14].to_int()
    ride_put(r, a[b + 13].to_int(), n, s, q, a[b] + dx, a[b + 1] + dy, a[b + 15] + seg_by, c0, c1, c2, c3)
    q = q + n
    i = i + 1
  }
  q - at
}

///|
/// Instance `b` of `s` cut to (h0, h1, h2, h3) as well, as a header's clip cuts its group's (its 16-19; none, all 0):
/// where its own clip is square or it has no outer, its own clip cut to it as a square clip cuts a round one it holds
/// (push_box_clip, clamp_inst_clip: a corner the cut moves square); else its outer. Never the header's as its outer
/// where it has none: an outer with no corner's radius is none (scene.mbt 40-51), what it cut drawn whole (a row's
/// words in a round box scrolled past the list's top, over what is above it). As the host draws a header out
/// (groups.h's mb_groups_draw_out), the same.
fn inst_cut_to(s : FixedArray[Double], b : Int, h0 : Double, h1 : Double, h2 : Double, h3 : Double) -> Unit {
  if h0 == 0.0 && h1 == 0.0 && h2 == 0.0 && h3 == 0.0 {
    return
  }
  if (s[b + 24] == 0.0 && s[b + 25] == 0.0 && s[b + 26] == 0.0 && s[b + 27] == 0.0) ||
    (s[b + 40] == 0.0 && s[b + 41] == 0.0 && s[b + 42] == 0.0 && s[b + 43] == 0.0) {
    let m0 = s[b + 16]
    let m1 = s[b + 17]
    let m2 = s[b + 18]
    let m3 = s[b + 19]
    s[b + 16] = dmax(m0, h0)
    s[b + 17] = dmax(m1, h1)
    s[b + 18] = dmin(m2, h2)
    s[b + 19] = dmin(m3, h3)
    if s[b + 16] != m0 || s[b + 17] != m1 {
      s[b + 24] = 0.0
      s[b + 28] = 0.0
    }
    if s[b + 18] != m2 || s[b + 17] != m1 {
      s[b + 25] = 0.0
      s[b + 29] = 0.0
    }
    if s[b + 18] != m2 || s[b + 19] != m3 {
      s[b + 26] = 0.0
      s[b + 30] = 0.0
    }
    if s[b + 16] != m0 || s[b + 19] != m3 {
      s[b + 27] = 0.0
      s[b + 31] = 0.0
    }
  } else {
    s[b + 40] = dmax(s[b + 40], h0)
    s[b + 41] = dmax(s[b + 41], h1)
    s[b + 42] = dmin(s[b + 42], h2)
    s[b + 43] = dmin(s[b + 43], h3)
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
  while list_heads.length() > 0 && list_heads[list_heads.length() - 1].at >= self.ninst {
    list_heads.pop() |> ignore
  }
}

///|
/// What is being drawn to be kept now, as the tree is painted, the innermost last (none between paints): a row or an old
/// view (none inside another), what holds others in it or in none, each holding what is drawn.
// kept across runs: none between paints
let ridings : Array[Riding] = []

///|
/// How many of ridings are a list's row or an old view hosted (not Riding's `holder`): 0 or 1.
// kept across runs: none between paints
let ridings_rows : Ref[Int] = Ref(0)

///|
/// The innermost of what is being drawn to be kept.
fn riding_now() -> Riding? {
  ridings.last()
}

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
/// place 33-34 says; bits 9-12, where it fades out towards a cut (52, 54, 56, 58), each that it says: all of it what
/// holds it inside the row or list said, none faded round them (a row or a list is kept only where nothing round it
/// fades), so it moves with them (a field's words fading at its edges, in a list scrolled: drawn where the field was
/// laid out, faded out wholly where it is drawn, till 2026-11-13).
fn ride_moves(a : FixedArray[Double], b : Int, e : FixedArray[Double]) -> Int {
  let mut m = 0
  for j in 0..<4 {
    if a[b + 16 + j] != e[j] {
      m = m | (1 << j)
    }
  }
  let none = a[b + 40] == 0.0 && a[b + 41] == 0.0 && a[b + 42] == 0.0 && a[b + 43] == 0.0
  // (`e`'s own outer, where it has one: none, every edge of the instance's its own)
  let e_none = e[12] == 0.0 && e[13] == 0.0 && e[14] == 0.0 && e[15] == 0.0
  if !none {
    for j in 0..<4 {
      let v = a[b + 40 + j]
      if v != e[j] && (e_none || v != e[12 + j]) {
        m = m | (1 << (4 + j))
      }
    }
  }
  if a[b + 32] != 0.0 {
    m = m | 256
  }
  for j in 0..<4 {
    if a[b + 53 + 2 * j] > 0.0 {
      m = m | (512 << j)
    }
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
  holder? : Bool = false,
) -> Unit {
  if !holder {
    ridings_rows.val = ridings_rows.val + 1
  }
  ridings.push({
    id: c.id,
    rev,
    k0: self.ninst,
    seg0: self.segs_whole_at(),
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
    holder,
  })
}

///|
/// What holds what was being drawn to be kept (`r`, ended now) kept with all it drew, as were it drawn there: what
/// spoiled it spoils that (an old view is never kept but as its own); as many nodes, as far as it reaches, what of it
/// is drawn anew each time, the glyphs it draws from.
fn ride_into_outer(r : Riding) -> Unit {
  guard riding_now() is Some(p) && !p.spoiled else { return }
  if r.spoiled || r.island {
    p.spoiled = true
    return
  }
  p.nodes = p.nodes + r.nodes
  p.x0 = dmin(p.x0, r.x0)
  p.y0 = dmin(p.y0, r.y0)
  p.x1 = dmax(p.x1, r.x1)
  p.y1 = dmax(p.y1, r.y1)
  p.spots.push_iter(r.spots.iter())
  p.kept.push_iter(r.kept.iter())
}

///|
/// The innermost being drawn to be kept ended, all of it drawn: kept where nothing of it is drawn otherwise than
/// moving it would draw it, a row wholly within its clip one way at least; else what was kept of it let go. Kept inside
/// another, never the host's group (drawn again there, it is copied: Ctx::ride_copy).
fn Ctx::ride_end(self : Ctx) -> Unit {
  guard ridings.pop() is Some(r) else { return }
  if !r.holder {
    ridings_rows.val = ridings_rows.val - 1
  }
  ride_into_outer(r)
  let k = r.clip_at
  let side_x = ride_side(r.x0, r.x1, clip_stack[k], clip_stack[k + 2])
  let side_y = ride_side(r.y0, r.y1, clip_stack[k + 1], clip_stack[k + 3])
  let n = self.ninst - r.k0
  if r.spoiled || (!r.island && !r.holder && side_x != 0 && side_y != 0) {
    ride_let_go(r.id)
    return
  }
  let e = ride_clip_at(k)
  // (what holds others in a clip not square kept to be drawn again only where it was: Ctx::ride_kept_for)
  let square = ride_clip_square(e)
  if !square && !r.holder {
    ride_let_go(r.id)
    return
  }
  let inst = inst_copy(self.inst, r.k0 * inst_size, n * inst_size)
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
  let segs = self.segs_from(r.seg0)
  // (kept by the host where it keeps groups and nothing of them is worked on as the frame ends; in a list drawn whole
  // as one as well, its header in that list's group where it is drawn again: ListRiding)
  let group = if ridings.is_empty() && groups_on() && ride_groupable(inst, n) {
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
    pack: SegPack::new(),
    spots: r.spots.map(fn(s) { { ..s, at: s.at - r.k0, end: s.end - r.k0 } }),
    owners,
    reach: (r.x0, r.y0, r.x1, r.y1),
    inside_x: square && side_x == 0,
    inside_y: square && side_y == 0,
    nodes: r.nodes,
    kept: r.kept,
    group,
    heads: false,
    out: n,
    anew: false,
    scrims: ride_scrims(),
  }
  ride_keep(r.id, kept)
  if group >= 0 {
    ride_groups[group] = kept
    presented.group_set(group, inst, n)
    @hostapi.group_set(group, inst, FixedArray::makei(n, fn(i) { moves[i].to_double() }), n)
  }
}

///|
/// Node `c` of the row being drawn, drawn at (x, y) `s` times as big: how far the row reaches, and whether it draws
/// what moving it would not draw again (`moved_not`: turned, grown, faded or stretched, in a layer, glass, bones, an
/// old view, a field).
fn ride_node(c : @view.Content, x : Double, y : Double, s : Double, moved_not : Bool) -> Unit {
  // (of a list drawn whole as one: an old view, or bones, drawn otherwise than as its instances say, ListRiding)
  match list_riding.val {
    Some(l) => {
      l.nodes = l.nodes + 1
      if c.hosted || c.bones != 0L {
        l.spoiled = true
      }
    }
    None => ()
  }
  // (the innermost alone: what holds it takes what it holds as it ends, ride_into_outer)
  guard riding_now() is Some(r) && !r.spoiled else { return }
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
  list_drawn_anew()
  match riding_now() {
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
    ride_scrims() == k.scrims &&
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
  if !k.spots.is_empty() {
    list_drawn_anew()
  }
  ride_caps.clear()
  self.segs_whole()
  let seg_by = (self.segs.length() / 4 - k.seg0).to_double()
  self.segs_put(k.segs, k.pack)
  // (in what is being drawn to be kept, all of it that one's as well, as were it drawn anew: ride_into_outer)
  let outer = match riding_now() {
    Some(r) if !r.spoiled => Some(r)
    _ => None
  }
  let mut from = 0
  for sp in k.spots {
    self.ride_copy(k, from, sp.at, dx, dy, seg_by)
    let at = self.ninst
    match sp.clip {
      None => {
        self.view_unseen(sp.c, sp.s)
        match outer {
          Some(r) => r.spots.push({ ..sp, at, end: self.ninst, x: sp.x + dx, y: sp.y + dy })
          None => ()
        }
      }
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
        match outer {
          Some(r) =>
            r.spots.push({
              ..sp,
              at,
              end: self.ninst,
              x: sp.x + dx,
              y: sp.y + dy,
              clip: Some(ride_clip_at(clip_top())),
            })
          None => ()
        }
        pop_clip()
      }
    }
    from = sp.end
  }
  self.ride_copy(k, from, k.inst.length() / inst_size, dx, dy, seg_by)
  match outer {
    Some(r) => {
      let (x0, y0, x1, y1) = k.reach
      r.nodes = r.nodes + k.nodes
      r.x0 = dmin(r.x0, x0 + dx)
      r.y0 = dmin(r.y0, y0 + dy)
      r.x1 = dmax(r.x1, x1 + dx)
      r.y1 = dmax(r.y1, y1 + dy)
      r.kept.push_iter(k.kept.iter())
    }
    None => ()
  }
}

///|
/// The captures the glass of the row drawn again (Ctx::ride_again) took as it was painted, each the one it takes in
/// this frame.
// kept across runs: emptied as each row is drawn again
let ride_caps : Map[Int, Int] = Map([])

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
  if k.group >= 0 && dr.mode == 0 && !shooting.val && ridings.is_empty() {
    self.ride_head(k.group, i0, n, at, dx, dy, seg_by)
  } else if k.heads {
    ride_put_out(k, self.inst, at, dx, dy, seg_by, 0.0, 0.0, 0.0, 0.0) |> ignore
  } else {
    ride_put(k, i0, n, self.inst, at, dx, dy, seg_by, 0.0, 0.0, 0.0, 0.0)
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
/// shapes' pieces `seg_by` on, cut to (h0, h1, h2, h3) as well (none: all 0; inst_cut_to): what a header of its group
/// stands for (the host's mb_groups_draw_out, groups.h).
fn ride_put(
  k : RideKept,
  i0 : Int,
  n : Int,
  s : FixedArray[Double],
  at : Int,
  dx : Double,
  dy : Double,
  seg_by : Double,
  h0 : Double,
  h1 : Double,
  h2 : Double,
  h3 : Double,
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
      for j in 0..<4 {
        if (m & (512 << j)) != 0 {
          let d = if j < 2 { dy } else { dx }
          s.unsafe_set(b + 52 + 2 * j, s.unsafe_get(b + 52 + 2 * j) + d)
        }
      }
    }
    inst_cut_to(s, b, h0, h1, h2, h3)
  }
}

///|
/// What is drawn now draws what moving it would not draw again: the innermost being drawn to be kept not kept, nor what
/// holds it (ride_into_outer).
fn ride_spoil() -> Unit {
  match riding_now() {
    Some(r) => r.spoiled = true
    None => ()
  }
}

///|
/// Whether node `c`, not a list's row, is begun to be kept with what it holds as it is drawn (Riding's `holder`), at
/// (x, y) as opaque as `a`, as of the count of changes `rev` it is drawn at: gone through to paint it ride_holder_after
/// times running with nothing of it changed, where it was and as opaque (it would be drawn as it was; what changes or
/// moves each time it is drawn never kept, its recording never drawn again), holding others; not an old view, in its
/// bones, glass, what a column scrolls by its offset alone, nor what was found holding such (ride_unkept). Each node
/// gone through is marked so; one that changed lets go of what it kept.
fn ride_holder(
  tree : @view.Tree,
  c : @view.Content,
  rev : Int,
  x : Double,
  y : Double,
  a : Double,
) -> Bool {
  let id = c.id
  let now = tree.drawn_rev(id)
  let same = ride_walked_by(id, rev, now, x, y, a)
  if same < ride_holder_after {
    if same == 0 && ride_kept.contains(id) {
      ride_let_go(id)
    }
    return false
  }
  !ride_unkept.contains(id) &&
  !c.hosted &&
  c.bones == 0L &&
  c.glass is None &&
  tree.held_count(id) >= 2 &&
  tree.scroll_off_by(id) < 0
}

///|
/// How many times running what holds others is gone through with nothing of it changed, drawn where it was as opaque,
/// before it is kept as it is drawn (ride_holder): what changed once (a row come in, its text set) not kept for a frame
/// it is drawn as kept in whole.
let ride_holder_after : Int = 2

///|
/// What holds others `id` kept, not drawn as kept though nothing of it changed (in another clip, its glyphs let go): let
/// go, begun again only once it is gone through so ride_holder_after times running again.
fn ride_holder_moved(id : @view.NodeId) -> Unit {
  ride_let_go(id)
  ride_walked.unsafe_get(id.at).same = 0
}

///|
/// What holds others being drawn to be kept (Riding's `holder`), the innermost up to a row, let be as a row, an old view
/// or what a column scrolls by its offset alone is come to in it (each kept as its own: in nothing else kept, or as
/// ListRiding draws it whole as one), never begun again.
fn ride_holder_out() -> Unit {
  while riding_now() is Some(r) && r.holder {
    ridings.pop() |> ignore
    ride_let_go(r.id)
    ride_unkept[r.id] = true
  }
}

///|
/// Whether row `c` drawn at (x, y) may be kept or drawn as kept: in a square clip (ride_clip_square), its box wholly
/// within it one way at least, as all it holds must be (Ctx::ride_end); one in a clip not square (none kept there),
/// across its edges each way, or wholly past it (a row kept for what comes, drawing nothing: no more gone through than
/// drawn again), drawn as it comes.
fn ride_may(c : @view.Content, x : Double, y : Double) -> Bool {
  let k = clip_top()
  for j in 4..<8 {
    if clip_stack[k + j] != 0.0 || clip_stack[k + 12 + j] != 0.0 {
      return false
    }
  }
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
  // (its pieces from an instance's first on, whether it is kept or drawn anew: Ctx::segs_whole)
  self.segs_whole()
  guard riding_now() is Some(r) && r.island && r.id == c.id else { return paint() }
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

///|
/// What is drawn now draws something anew each time it is drawn (a picture, one not seen asked for): the list drawn
/// whole as one it is in (ListRiding) drawn again only by going through it.
fn list_drawn_anew() -> Unit {
  match list_riding.val {
    Some(l) => l.anew = true
    None => ()
  }
}

///|
/// The glyphs a block drawn now draws from (ViewBlock's `kept`), held for the row and the list being drawn (view_glyphs_held).
fn ride_glyphs_kept(kept : Array[(Int, Double, Double)]) -> Unit {
  match riding_now() {
    Some(r) => r.kept.push(kept)
    None => ()
  }
  match list_riding.val {
    Some(l) => l.kept.push(kept)
    None => ()
  }
}

///|
/// What column `by` scrolls by its offset alone (node `c`: a page's list's held, its bar's thumb) begun being drawn
/// whole as one (ListRiding), at (x, y) where it is placed in the column, as opaque as `a`, laid out at (ux, uy), the
/// window drawing it `s` times as big, (dx, dy) off that as the column has it scrolled now, the column's clip `hc` (the
/// clip it is in now, square): what it holds drawn in a clip open from here (popped as it ends, with what it opened
/// since there were `clips` clips and `rings` edges open: view_paint's).
fn Ctx::list_ride_begin(
  self : Ctx,
  c : @view.Content,
  by : Int,
  rev : Int,
  x : Double,
  y : Double,
  a : Double,
  ux : Double,
  uy : Double,
  s : Double,
  dx : Double,
  dy : Double,
  clips : Int,
  rings : Int,
) -> Unit {
  let k = clip_top()
  let hc = FixedArray::makei(4, fn(j) { clip_stack[k + j] })
  push_unclipped()
  list_riding.val = Some({
    id: c.id,
    by,
    rev,
    k0: self.ninst,
    seg0: self.segs_whole_at(),
    clips0: clips,
    rings0: rings,
    x,
    y,
    a,
    off_x: ux - x,
    off_y: uy - y,
    s,
    dx,
    dy,
    hc,
    clip: ride_clip_at(clip_top()),
    spoiled: false,
    anew: false,
    nodes: 0,
    kept: [],
  })
}

///|
/// The list being drawn whole as one ended (ListRiding), all of it drawn and what it opened closed: kept as one group of
/// the host's, a header in its place moved as far as the column has it and cut to its clip (the group it was kept as
/// before where it drew the same); where the host keeps none, or one of its instances is worked on as the frame ends (a
/// look's tag, a native view's hole, a stream's picture: ride_groupable), or it holds an old view or bones, drawn out
/// moved and cut so in its place, its column's offset moving it painted anew (offsets_flat).
fn Ctx::list_ride_end(self : Ctx) -> Unit {
  guard list_riding.val is Some(l) else { return }
  list_riding.val = None
  let n = self.ninst - l.k0
  if n <= 0 {
    ride_let_go(l.id)
    return
  }
  let e = l.clip
  // (its instances, each of its rows kept among them by a header (Ctx::ride_head) in one place, the room after it
  // passed over: kept so by the host, drawn out whole by a header of it, n of them)
  let src = self.inst
  let mut m = 0
  let mut heads = false
  let mut q = 0
  while q < n {
    let b = (l.k0 + q) * inst_size
    let c = if src[b + 5] == 13.0 {
      heads = true
      src[b + 14].to_int()
    } else {
      1
    }
    q = q + (if c < 1 { 1 } else { c })
    m = m + 1
  }
  let inst = FixedArray::make(m * inst_size, 0.0)
  let moves = FixedArray::make(m, 0)
  let mut q = 0
  let mut i = 0
  while q < n {
    let b = (l.k0 + q) * inst_size
    if src[b + 5] == 13.0 {
      src.blit_to(inst, len=inst_size, src_offset=b, dst_offset=i * inst_size)
      let c = src[b + 14].to_int()
      q = q + (if c < 1 { 1 } else { c })
      i = i + 1
    } else {
      let mut r = q + 1
      while r < n && src[(l.k0 + r) * inst_size + 5] != 13.0 {
        r = r + 1
      }
      src.blit_to(inst, len=(r - q) * inst_size, src_offset=b, dst_offset=i * inst_size)
      for j in i..<(i + r - q) {
        moves[j] = ride_moves(inst, j * inst_size, e)
      }
      i = i + r - q
      q = r
    }
  }
  let (h0, h1, h2, h3) = (l.hc[0], l.hc[1], l.hc[2], l.hc[3])
  if l.spoiled || !groups_on() || dr.mode != 0 || shooting.val || !ride_groupable(inst, m) {
    ride_let_go(l.id)
    // (its rows' headers drawn out first, each instance then moved and cut in its place)
    self.flat_from(l.k0)
    let s = self.inst
    for i in 0..<n {
      let b = (l.k0 + i) * inst_size
      list_put(s, b, ride_moves(s, b, e), l.dx, l.dy, h0, h1, h2, h3)
    }
    offsets_flat.push(l.by)
    // (its column going on by itself (a fling, a wheel's notches easing in, what shows past an end going back): painted
    // anew each frame till that ends, as it is drawn moved so, nothing else telling the paint)
    match view_app.val {
      Some(tree) =>
        match tree.glide_end_of(l.by) {
          Some(end) => self.now_before(end) |> ignore
          None => ()
        }
      None => ()
    }
    return
  }
  let owned = inst_owners_kept()
  let owners : Array[(Int, (Double, Double), @view.NodeId?, Int)] = []
  if owned {
    let o = inst_owners.owner
    let cl = inst_owners.cell
    let tr = inst_owners.tree
    let mk = inst_owners.mark
    for k in l.k0..<self.ninst {
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
  let segs = self.segs_from(l.seg0)
  // (the group it was kept as before, where it drew the same: the host's kept, nothing told it again)
  let was = match ride_kept.get(l.id) {
    Some(k) if k.group >= 0 && k.moves == moves && k.inst == inst => Some(k.group)
    _ => None
  }
  let group = match was {
    Some(g) => g
    None => {
      ride_groups_made.val = ride_groups_made.val + 1
      ride_groups_made.val
    }
  }
  let kept : RideKept = {
    rev: l.rev,
    x: l.x,
    y: l.y,
    a: l.a,
    off_x: l.off_x,
    off_y: l.off_y,
    // (the frame's pixels a point of the list's own: as big as it was drawn, list_kept_for)
    scale: self.scale * l.s,
    zoom: words_zoom.val,
    glyphs: ride_glyphs_gone.val,
    owned,
    clip: e,
    inst,
    moves,
    segs,
    seg0: l.seg0,
    pack: SegPack::new(),
    spots: [],
    owners,
    reach: (0.0, 0.0, 0.0, 0.0),
    inside_x: true,
    inside_y: true,
    nodes: l.nodes,
    kept: l.kept,
    group,
    heads,
    out: n,
    anew: l.anew,
    scrims: ride_scrims(),
  }
  if was is Some(_) {
    ride_kept[l.id] = kept
  } else {
    ride_keep(l.id, kept)
    presented.group_set(group, inst, m)
    @hostapi.group_set(group, inst, FixedArray::makei(m, fn(i) { moves[i].to_double() }), m)
  }
  ride_groups[group] = kept
  let s = self.inst
  ride_head_blank.blit_to(s, len=inst_size, dst_offset=l.k0 * inst_size)
  // (its rows' headers in it stood for by its own now)
  while ride_spans.length() > 0 && ride_spans[ride_spans.length() - 1] >= l.k0 {
    ride_spans.pop() |> ignore
  }
  ride_spans.push(l.k0)
  ride_heads.val = ride_heads.val + 1
  self.list_head_put(l.k0, group, 0, n, 0.0, 0.0, 0.0, l.id, l.s, l.dx, l.dy, l.hc)
}

///|
/// The header at instance `at` of a list drawn whole as one (ListHead): group `group`'s instances from `first`, `n` of
/// them, their shapes' pieces `seg_by` on, moved by (bx, by) besides (dx, dy) as column's offset has it now, `s` the
/// window's scale of it, cut to `hc`; said among the frame's list headers.
fn Ctx::list_head_put(
  self : Ctx,
  at : Int,
  group : Int,
  first : Int,
  n : Int,
  seg_by : Double,
  bx : Double,
  by : Double,
  id : @view.NodeId,
  s : Double,
  dx : Double,
  dy : Double,
  hc : FixedArray[Double],
) -> Unit {
  let a = self.inst
  let b = at * inst_size
  a[b] = bx + dx
  a[b + 1] = by + dy
  a[b + 5] = 13.0
  a[b + 12] = group.to_double()
  a[b + 13] = first.to_double()
  a[b + 14] = n.to_double()
  a[b + 15] = seg_by
  for j in 0..<4 {
    a[b + 16 + j] = hc[j]
  }
  let head = FixedArray::make(inst_size, 0.0)
  a.blit_to(head, len=inst_size, src_offset=b)
  list_heads.push({ at, head, id, bx, by, s })
}

///|
/// Instance `b` of `s`, of a list drawn whole as one, where its header would draw it out (ride_put's, by its `moves`
/// bits): moved by (dx, dy), cut to (h0, h1, h2, h3).
fn list_put(
  s : FixedArray[Double],
  b : Int,
  m : Int,
  dx : Double,
  dy : Double,
  h0 : Double,
  h1 : Double,
  h2 : Double,
  h3 : Double,
) -> Unit {
  list_move(s, b, m, dx, dy)
  inst_cut_to(s, b, h0, h1, h2, h3)
}

///|
/// Instance `b` of `s` moved by (dx, dy), what of its clip and outer `m` says (ride_moves) with it.
fn list_move(s : FixedArray[Double], b : Int, m : Int, dx : Double, dy : Double) -> Unit {
  s[b] = s[b] + dx
  s[b + 1] = s[b + 1] + dy
  if m != 0 {
    for j in 0..<4 {
      let d = if j % 2 == 0 { dx } else { dy }
      if (m & (1 << j)) != 0 {
        s[b + 16 + j] = s[b + 16 + j] + d
      }
      if (m & (1 << (4 + j))) != 0 {
        s[b + 40 + j] = s[b + 40 + j] + d
      }
    }
    if (m & 256) != 0 {
      s[b + 33] = s[b + 33] + dx
      s[b + 34] = s[b + 34] + dy
    }
    for j in 0..<4 {
      if (m & (512 << j)) != 0 {
        s[b + 52 + 2 * j] = s[b + 52 + 2 * j] + (if j < 2 { dy } else { dx })
      }
    }
  }
}

///|
/// An old view hosted in a list drawn whole as one (ListRiding) drew itself from instance `k0` on where the window has
/// it, the column's offset in it (its old frame built where Tree::drawn_one finds it, which takes that offset in); the
/// list as it ends moves all it holds by that offset (list_put): taken back by it first, so the old view moves with
/// the rows round it, once (Home's list on a phone drew what was left up long under it twice as fast as its rows).
fn Ctx::island_in_list(self : Ctx, k0 : Int) -> Unit {
  guard list_riding.val is Some(l) && (l.dx != 0.0 || l.dy != 0.0) else { return }
  for k in k0..<self.ninst {
    let b = k * inst_size
    list_move(self.inst, b, ride_moves(self.inst, b, l.clip), -l.dx, -l.dy)
  }
}

///|
/// What list `c` (ListRiding's) kept as one, where it may be drawn again by its header alone, moved by where it is
/// placed now (x, y) from where it was, `s` the window's scale of it: nothing of it changed since (its count of changes no
/// more than what was kept's), nothing in it drawn anew each time, as opaque, laid out, as big, set on the pixels and its
/// words as big as then, moved by whole pixels; the host keeping its group.
fn Ctx::list_kept_for(
  self : Ctx,
  tree : @view.Tree,
  c : @view.Content,
  x : Double,
  y : Double,
  a : Double,
  ux : Double,
  uy : Double,
  s : Double,
) -> RideKept? {
  guard ride_kept.get(c.id) is Some(k) else { return None }
  let fits = k.group >= 0 &&
    !k.anew &&
    a == k.a &&
    ux - x == k.off_x &&
    uy - y == k.off_y &&
    self.scale * s == k.scale &&
    words_zoom.val == k.zoom &&
    ride_glyphs_gone.val == k.glyphs &&
    inst_owners_kept() == k.owned &&
    tree.drawn_rev(c.id) <= k.rev &&
    ride_scrims() == k.scrims &&
    ride_whole(x - k.x, self.scale) &&
    ride_whole(y - k.y, self.scale)
  if fits {
    Some(k)
  } else {
    None
  }
}

///|
/// List kept `k` (ListRiding's) drawn again by its header alone, moved by (bx, by) from where it was kept and (dx, dy)
/// as its column has it now, `s` the window's scale of it, cut to `hc`: its shapes' pieces put among the frame's, who
/// drew what as kept.
fn Ctx::list_again(
  self : Ctx,
  k : RideKept,
  id : @view.NodeId,
  bx : Double,
  by : Double,
  s : Double,
  dx : Double,
  dy : Double,
  hc : FixedArray[Double],
) -> Unit {
  self.segs_whole()
  let seg_by = (self.segs.length() / 4 - k.seg0).to_double()
  self.segs_put(k.segs, k.pack)
  let n = k.out
  let at = self.ninst
  self.ride_copy(k, 0, n, 0.0, 0.0, seg_by)
  self.list_head_put(at, k.group, 0, n, seg_by, bx, by, id, s, dx, dy, hc)
}
