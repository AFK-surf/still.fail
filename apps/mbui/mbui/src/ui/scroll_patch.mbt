// A frame where only a list moved (what its node that scrolls holds moved in it, nothing else of the tree changed how
// it is drawn: Tree::still_rev) drawn as the last one painted, its rows' headers moved: what painting it whole would
// draw, each row drawn again as kept, moved, all of it cut by the list's clip (view_ride.mbt), and nothing else of it
// otherwise. The frame painted whole tells what it may be drawn again so for (patch_rec): the rows by their headers
// alone, all of one list's, nothing else of the list drawn, and how far the list may move before a row comes into its
// clip or leaves it. A Tester draws each frame painted alone whole after it as well, and the two must be the same
// (tester_looks.mbt).

///|
priv struct PatchRec {
  /// told as the frame is painted whole (patch_rec_begin), till it ends (patch_rec_end)
  mut on : Bool
  /// whether the frame painted last may be drawn again so
  mut ok : Bool
  /// the node scrolled (its held), where it was placed as the frame was painted, and how far it may move from there
  mut held : @view.NodeId?
  mut top : Double
  mut lo : Double
  mut hi : Double
  /// the tree's count of changes but for what scrolls (Tree::still_rev), and what else the paint was drawn by
  mut still : Int
  mut scale : Double
  mut w : Double
  mut h : Double
  mut zoom : Double
  mut glyphs : Int
  mut atlas : Int
  /// the frame's instances and its headers among them (ride_spans), each as written
  mut n : Int
  spans : Array[Int]
  heads : Array[Double]
  /// whether each is of the list's (moved with it)
  moving : Array[Bool]
  /// the list's clip, as the damage is told it
  mut clip : (Double, Double, Double, Double)
  /// the old views hosted it drew: drawn so again while each reads as it did (island_still)
  islands : Array[@view.NodeId]
  mut built : Int
  /// what the rows kept as it was painted (ride_gen)
  mut kept : Int
}

///|
// kept across runs: told anew as each frame is painted whole, let go as a run begins (patch_forget)
let patch_rec : PatchRec = {
  on: false,
  ok: false,
  held: None,
  top: 0.0,
  lo: 0.0,
  hi: 0.0,
  still: -1,
  scale: 0.0,
  w: 0.0,
  h: 0.0,
  zoom: 0.0,
  glyphs: 0,
  atlas: 0,
  n: 0,
  spans: [],
  heads: [],
  moving: [],
  clip: (0.0, 0.0, 0.0, 0.0),
  islands: [],
  built: 0,
  kept: 0,
}

///|
/// How many frames were drawn so (a bench's count).
// kept across runs: only counts
let patch_frames : Ref[Int] = Ref(0)

///|
/// How many frames were drawn as the last one painted, its list's rows moved (scroll_patch.mbt), and why the last one
/// was not, or the last painted whole may not be: for a test.
pub fn frames_patched() -> (Int, String) {
  (patch_frames.val, patch_why.val)
}

///|
/// Why the last frame was not drawn so, or the last painted whole may not be (a test's message).
// kept across runs: only said
let patch_why : Ref[String] = Ref("")

///|
/// Nothing painted before drawn again so.
fn patch_forget() -> Unit {
  patch_rec.on = false
  patch_rec.ok = false
}

///|
/// The frame being painted whole draws what a frame of the list's moving alone could not draw again so.
fn patch_spoil(why : String) -> Unit {
  if patch_rec.on && patch_rec.ok {
    patch_rec.ok = false
    patch_why.val = why
  }
}

///|
/// A frame painted whole begun: told as it goes what it may be drawn again for.
fn patch_rec_begin() -> Unit {
  patch_rec.on = !shooting.val && dr.mode == 0
  patch_rec.ok = patch_rec.on
  patch_rec.islands.clear()
}

///|
/// The old view hosted in `id` drawn in the frame being painted whole: drawn so again while it reads as it did.
fn patch_island(id : @view.NodeId) -> Unit {
  if patch_rec.on && !patch_rec.islands.contains(id) {
    patch_rec.islands.push(id)
  }
}

///|
/// Row `id` drawn again as kept not by a header (Ctx::ride_copy): one of a list's spoils the frame being painted whole,
/// one of none (an old view hosted) is drawn so again while it reads as it did.
fn patch_put(id : @view.NodeId) -> Unit {
  guard patch_rec.on && patch_rec.ok else { return }
  match view_app.val {
    Some(tree) if tree.row_held(id) is None => patch_island(id)
    _ => patch_spoil("a row of a list drawn not by its header")
  }
}

///|
/// The frame painted whole ended (`c`'s instances): what it may be drawn again for, where it may.
fn Ctx::patch_rec_end(self : Ctx) -> Unit {
  guard patch_rec.on else { return }
  patch_rec.on = false
  guard patch_rec.ok else { return }
  patch_rec.ok = false
  guard view_app.val is Some(tree) && ride_spans.length() > 0 else {
    patch_why.val = "no headers"
    return
  }
  guard cycle_frame.is_empty() && !inst_owners.on && paint_clock_at.val == "" && paint_base.wake < 0.0 else {
    patch_why.val = "clocked"
    return
  }
  // (each header one of a row kept of the same list, cut by its clip)
  let a = self.inst
  let mut held : @view.NodeId? = None
  let mut clip = (0.0, 0.0, 0.0, 0.0)
  let mut lo = -1.0e9
  let mut hi = 1.0e9
  for at in ride_spans {
    let b = at * inst_size
    guard ride_groups.get(a[b + 12].to_int()) is Some(k) else {
      patch_why.val = "a header of no group"
      return
    }
    // (one of no list's, an old view hosted: where it was, while it reads as it did)
    guard tree.row_held(k.id) is Some(h) else {
      patch_island(k.id)
      continue
    }
    guard k.cut && a[b + 21] == 1.0 else {
      patch_why.val = "a row not cut"
      return
    }
    match held {
      None => {
        held = Some(h)
        clip = (a[b + 16], a[b + 17], a[b + 18], a[b + 19])
      }
      Some(was) =>
        if !(was == h && clip == (a[b + 16], a[b + 17], a[b + 18], a[b + 19])) {
          patch_why.val = "rows of more than one list"
          return
        }
    }
  }
  guard held is Some(h) else {
    patch_why.val = "no list"
    return
  }
  // (each row of the list: one drawn stays across the clip, one not drawn stays outside it)
  guard tree.drawn_place(h) is Some((_, hy, _, hs)) && hs == 1.0 else {
    patch_why.val = "the list not placed"
    return
  }
  let (_, e1, _, e3) = clip
  let spans = tree.rows_spans(h)
  let mut j = 0
  while j < spans.length() {
    let y0 = hy + spans[j]
    let y1 = hy + spans[j + 1]
    if y1 < e1 {
      hi = dmin(hi, e1 - y1)
    } else if y0 > e3 {
      lo = dmax(lo, e3 - y0)
    } else {
      lo = dmax(lo, e1 - y1)
      hi = dmin(hi, e3 - y0)
    }
    j = j + 2
  }
  patch_rec.ok = true
  patch_rec.held = held
  patch_rec.top = tree.placed_top(h)
  patch_rec.lo = lo
  patch_rec.hi = hi
  patch_rec.still = tree.still_rev()
  tree.still_watch(held)
  patch_rec.scale = self.scale
  patch_rec.w = self.window_w
  patch_rec.h = self.window_h
  patch_rec.zoom = words_zoom.val
  patch_rec.glyphs = ride_glyphs_gone.val
  patch_rec.atlas = atlas_now()
  patch_rec.n = self.ninst
  patch_rec.clip = clip
  patch_rec.built = self.build_no
  patch_rec.kept = ride_gen.val
  patch_rec.spans.clear()
  patch_rec.heads.clear()
  patch_rec.moving.clear()
  for at in ride_spans {
    patch_rec.spans.push(at)
    patch_rec.moving.push(
      ride_groups.get(a[at * inst_size + 12].to_int()) is Some(k) && tree.row_held(k.id) is Some(_),
    )
    for q in 0..<inst_size {
      patch_rec.heads.push(a[at * inst_size + q])
    }
  }
}

///|
/// Whether the frame is drawn as the last one painted whole, its list's rows' headers moved as far as the list moved
/// since (patch_rec): where nothing else changed how it is drawn and the list moved by whole pixels no further than
/// it may.
fn Ctx::patch_draw(self : Ctx) -> Bool {
  guard patch_rec.ok && patch_rec.held is Some(h) && view_app.val is Some(tree) else {
    patch_why.val = if patch_rec.ok { "no tree" } else { patch_why.val }
    return false
  }
  guard tree.still_rev() == patch_rec.still &&
    self.scale == patch_rec.scale &&
    self.window_w == patch_rec.w &&
    self.window_h == patch_rec.h &&
    words_zoom.val == patch_rec.zoom &&
    ride_glyphs_gone.val == patch_rec.glyphs &&
    atlas_now() == patch_rec.atlas &&
    cycle_frame.is_empty() &&
    // (no look of what it drew asking to be applied again by now: Ctx::cycle_looks)
    !looks_own.cycling &&
    (looks_own.wake < 0.0 || self.clock < looks_own.wake) &&
    !shooting.val &&
    dr.mode == 0 &&
    !inst_owners.on else {
    patch_why.val = "changed"
    return false
  }
  guard self.build_no == patch_rec.built && ride_gen.val == patch_rec.kept && !self.moves_now() else {
    patch_why.val = "built, kept anew or moving"
    return false
  }
  for id in patch_rec.islands {
    guard island_still(id, patch_rec.built) else {
      patch_why.val = "an old view changed"
      return false
    }
  }
  let dy = tree.placed_top(h) - patch_rec.top
  // (no further than it may: strictly within, as a row's node on its clip's edge is either side of it)
  guard dy > patch_rec.lo && dy < patch_rec.hi && ride_whole(dy, self.scale) else {
    patch_why.val = "moved too far or by part of a pixel"
    return false
  }
  guard self.inst.length() >= patch_rec.n * inst_size else { return false }
  self.ninst = patch_rec.n
  ride_spans.clear()
  for i, at in patch_rec.spans {
    for q in 0..<inst_size {
      self.inst[at * inst_size + q] = patch_rec.heads[i * inst_size + q]
    }
    if patch_rec.moving[i] {
      self.inst[at * inst_size + 1] = patch_rec.heads[i * inst_size + 1] + dy
    }
    ride_spans.push(at)
  }
  damage_known.push(patch_rec.clip)
  patch_frames.val = patch_frames.val + 1
  true
}
