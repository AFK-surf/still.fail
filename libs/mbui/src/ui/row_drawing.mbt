// A keyed, fully visible row with no effects that depend on where it is painted can retain its drawing. The
// recording belongs to the row's nodes and follows what its paint read; when it is no longer safe to reuse, paint it
// normally. The host still receives the same flat instances in their original order.

///|
priv struct RowDrawing {
  watch : @signals.Watch
  mut valid : Bool
  mut x : Double
  mut y : Double
  mut alpha : Double
  mut words_alpha : Double
  mut surface_alpha : Double
  mut targets_said : Bool
  mut text_runs : Bool
  mut tracks_owners : Bool
  mut tree_owner : @view.NodeId?
  mut inst : FixedArray[Double]
  /// how each instance is cut: 0 by the list's clip (`clip`) itself, 1 by one of the row's own wholly inside it
  klass : Array[Int]
  /// the pieces of the row's shapes (kind 11's, from piece `seg_from` of the frame's as it drew them)
  segs : Array[Double]
  mut seg_from : Int
  clip : Array[Double]
  /// painted whole, past the list's clip (rec_whole): what a paint where it is drawn again leaves out is left out
  mut whole : Bool
  /// not kept painted whole where it was last (something of it left out, or cut otherwise): painted as it is until it
  /// is wholly inside the list's clip
  mut held_off : Bool
  /// the clip's rect it was painted in (what it said is put in the list's as it is said again)
  band : Array[Double]
  /// how far it was painted, its rect: the band, short of a line of words past the list's clip whose glyphs were not
  /// asked for (rec_reach); drawn again only while the list's clip is inside it
  reach : Array[Double]
  /// how many nodes it is
  mut n : Int
  /// each instance's node (from the row's first; -1, the row's paint around its nodes) and line of words (top,
  /// height; a height below 0, none), where it is painted whole
  node_of : Array[Int]
  line_top : Array[Double]
  line_h : Array[Double]
  glyphs : Array[(Int, Double, Double)]
  /// its targets as the frame's are found alone (Ctx::targets: dr's mode_hits), kept as what it drew is, while that
  /// is: where it was, how faint, the clip's rect they were found in
  mut hits_valid : Bool
  mut hits_x : Double
  mut hits_y : Double
  mut hits_alpha : Double
  hits_band : Array[Double]
  hits_said : Array[&SaidAgain]
  owners : Array[(Int, (Double, Double), @view.NodeId?, Int)]
  said : Array[&SaidAgain]
}

///|
fn row_drawing_new() -> RowDrawing {
  let watch = @signals.watch(fn() {
    // A nested watch reads in place of the frame's paint watch. Tell that watch too, so a paint-only change can never
    // be mistaken for a frame of the looks alone.
    match paint_watch.val {
      Some(w) => w.touch()
      None => ()
    }
    if frame_running.val {
      if paint_phase.val > 0 {
        paint_said.val = "a retained row's paint changed"
      }
    } else {
      h_frame_owed()
    }
  })
  {
    watch,
    valid: false,
    x: 0.0,
    y: 0.0,
    alpha: 1.0,
    words_alpha: 1.0,
    surface_alpha: 1.0,
    targets_said: false,
    text_runs: false,
    tracks_owners: false,
    tree_owner: None,
    inst: FixedArray::make(0, 0.0),
    klass: [],
    segs: [],
    seg_from: 0,
    clip: [],
    whole: false,
    held_off: false,
    band: [],
    reach: [],
    n: 0,
    node_of: [],
    line_top: [],
    line_h: [],
    glyphs: [],
    hits_valid: false,
    hits_x: 0.0,
    hits_y: 0.0,
    hits_alpha: 1.0,
    hits_band: [],
    hits_said: [],
    owners: [],
    said: [],
  }
}

///|
fn row_drawing_forget(rn : RowNodes) -> Unit {
  match rn.drawing {
    Some(d) => d.watch.stop()
    None => ()
  }
  rn.drawing = None
}

///|
/// Whether the row's nodes can be translated together without observing a different layout, cut, look or owner.
/// The first implementation deliberately falls back for complex rows; the ordinary paint remains their source of truth.
fn Ctx::row_drawing_safe(self : Ctx, rn : RowNodes, i : Int) -> String {
  if !nodes_run.on || !rn.ok || !rn.in_pool || rn.base != i || rn.row_key is None || rn.n <= 0 {
    return "row"
  }
  if dr.mode != 0 || !dr.moves.is_empty() || self.passing != 0 {
    return "frame"
  }
  // (a surface a look is said on over the row: how faint it is is kept with what the row drew, and compared)
  if inst_owners.on {
    return "owners"
  }
  if words_zoom.val != 1.0 {
    return "zoom"
  }
  // (what a package keeps by the row's nodes, rn.again, is said of them where they are: the row's nodes are not moved
  // among the frame's as it is drawn again; how each is drawn is its look, asked below)
  if !rn.laid.is_empty() {
    return "row laid"
  }
  for j in i..<(i + rn.n) {
    let n = self.nodes[j]
    if n.kind != kind_box && n.kind != kind_text && n.kind != kind_rich && n.kind != kind_image {
      return "kind \{n.kind}"
    }
    if n.kind == kind_rich && !words_sel.is_empty() { return "selection" }
    if n.glass is Some(_) { return "glass" }
    // (a box scrolled across: cut by a clip of its own, where it is scrolled to read by the drawing's watch)
    if n.passes || n.portal || n.shot || n.floats || n.mark != 0 {
      return "passes/portal/shot/floats/mark"
    }
    if n.moved_by is Some(_) || n.place is Some(_) || n.ticks is Some(_) || n.stick == n.stick {
      return "moved/place/ticks/stick"
    }
    if n.corner_by != 0 { return "corner_by" }
    // (what comes and goes in its row's room: drawn by its look while it does, asked below)
    if n.paints is Some(_) { return "paints" }
    match self.drawn_entry(j) {
      Some(e) => {
        if !e.look.is_still() { return "look" }
        if e.z != 0 || e.only || e.keep is Some(_) { return "z/only/keep" }
        // (a fade towards its own cut, or towards the edges of a node of the row, moves with the row: drawn again moved,
        // as its 52-59 are; one towards something outside the row, the list's edges, stays where that is)
        if e.fade_of >= 0 && (e.fade_of < i || e.fade_of >= i + rn.n) { return "fade" }
        if e.ground is Some(_) || e.ground_bg is Some(_) { return "ground" }
        if e.cycle is Some(_) { return "cycle" }
        // (worked out as it is painted: kept only where it is still now, what it read followed by the drawing's watch;
        // a row come in, its look still once it is in, ListRows::enter)
        if e.look_by is Some(_) && !e.look_now().is_still() { return "look_by" }
        if e.glyphs_by is Some(_) || e.notch_by is Some(_) || e.cut_by is Some(_) { return "glyphs/notch/cut_by" }
        if e.ink_by is Some(_) { return "ink_by" }
      }
      None => ()
    }
  }
  ""
}

///|
/// How the instances the row drew from `from` are cut, into `klass` (0: by the list's clip `clip` itself; 1: by a clip
/// of the row's own wholly inside it, moved with the row), false where one is cut otherwise (a clip of its own that the
/// list's cuts, glass, a native view's hole, the frame's shape pieces): those are drawn as they are painted.
fn Ctx::row_drawing_cuts(
  self : Ctx,
  from : Int,
  clip : Array[Double],
  klass : Array[Int],
  whole? : Bool = false,
) -> Bool {
  klass.clear()
  self.flat_from(from)
  let a = self.inst
  for j in from..<self.ninst {
    let b = j * inst_size
    let kind = a[b + 5]
    if kind == 5.0 || kind == 6.0 || kind == 7.0 || kind == 9.0 || kind == 12.0 {
      return false
    }
    let mut band = true
    for q in 0..<4 {
      if a[b + 16 + q] != clip[q] || a[b + 24 + q] != clip[4 + q] || a[b + 28 + q] != clip[8 + q] {
        band = false
      }
    }
    for q in 0..<12 {
      if a[b + 40 + q] != clip[12 + q] {
        band = false
      }
    }
    if band {
      klass.push(0)
    } else if (if whole {
        // (painted whole: one the far clip cuts is cut by the list's, which that is past while it is drawn again)
        a[b + 16] >= clip[0] && a[b + 17] >= clip[1] && a[b + 18] <= clip[2] && a[b + 19] <= clip[3]
      } else {
        a[b + 16] > clip[0] && a[b + 17] > clip[1] && a[b + 18] < clip[2] && a[b + 19] < clip[3]
      }) &&
      a[b + 44] == 0.0 && a[b + 45] == 0.0 && a[b + 46] == 0.0 && a[b + 47] == 0.0 {
      klass.push(1)
    } else {
      return false
    }
  }
  true
}

///|
/// Whether the row's own clips, moved by `dy`, are still wholly inside the list's (`clip`): drawn again as they are.
fn row_cuts_inside(d : RowDrawing, dx : Double, dy : Double) -> Bool {
  let c = d.clip
  for j, kl in d.klass {
    if kl == 1 {
      let b = j * inst_size
      let a = d.inst
      if a[b + 16] + dx <= c[0] || a[b + 17] + dy <= c[1] || a[b + 18] + dx >= c[2] || a[b + 19] + dy >= c[3] {
        return false
      }
    }
  }
  true
}

///|
/// Whether the row, moved by `dx, dy` (`n` where it is now), and all it drew lie wholly inside the list's clip: one
/// that reaches past it has what a paint of it there would leave out (Ctx::paint's cull), so is painted again.
fn row_inside_band(d : RowDrawing, n : Node, dx : Double, dy : Double) -> Bool {
  let c = d.clip
  if n.x < c[0] || n.y < c[1] || n.x + n.fw > c[2] || n.y + n.fh > c[3] {
    return false
  }
  let a = d.inst
  let mut b = 0
  while b < a.length() {
    let x = a[b] + dx
    let y = a[b + 1] + dy
    if x < c[0] || y < c[1] || x + a[b + 2] > c[2] || y + a[b + 3] > c[3] {
      return false
    }
    b += inst_size
  }
  true
}

///|
/// Whether the list's clip at `k` lies inside how far the row painted whole (`d`) was painted, moved with it by `dx`,
/// `dy`: all of it that can show there was painted.
fn row_reach(d : RowDrawing, dx : Double, dy : Double, k : Int) -> Bool {
  d.reach.length() == 4 &&
  clip_stack[k] >= d.reach[0] + dx &&
  clip_stack[k + 1] >= d.reach[1] + dy &&
  clip_stack[k + 2] <= d.reach[2] + dx &&
  clip_stack[k + 3] <= d.reach[3] + dy
}

///|
/// Whether the list's clip at `k` (in clip_stack) is a plain rect: no corners, no outer. A row in one is painted whole
/// to be kept (rec_whole), what of it is past the clip left out as it is drawn again.
fn band_plain(k : Int) -> Bool {
  for q in 4..<clip_n {
    if clip_stack[k + q] != 0.0 {
      return false
    }
  }
  true
}

///|
/// How far past the list's clip a row is painted whole (rec_whole), half as much again as the clip is tall and wide: what
/// lies further is not painted (a row it leaves something of is not kept), nor its words' glyphs made, nor its
/// pictures asked for before they come near.
fn row_whole_rect(k : Int) -> Array[Double] {
  let w = (clip_stack[k + 2] - clip_stack[k]) / 2.0
  let h = (clip_stack[k + 3] - clip_stack[k + 1]) / 2.0
  [clip_stack[k] - w, clip_stack[k + 1] - h, clip_stack[k + 2] + w, clip_stack[k + 3] + h]
}

///|
/// Whether a rect (x0 y0 x1 y1) shows none of it in clip `k` (as Ctx::paint_node culls: one touching it shows).
fn out_of_clip(k : Int, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Bool {
  x0 > clip_stack[k + 2] || y0 > clip_stack[k + 3] || x1 < clip_stack[k] || y1 < clip_stack[k + 1]
}

///|
/// What the row kept (`d`) drawn again, moved by `dx`, `dy`, in the list's clip at `k`: what a paint of it there leaves
/// out (a node outside what cuts it, a line of words), left out, and a clip of its own the list's cuts cut so; false,
/// nothing drawn, where that is not known (such a clip with an outer, a node left out that paints what it holds otherwise
/// faint), for it to be painted.
fn Ctx::row_replay(self : Ctx, d : RowDrawing, i : Int, dx : Double, dy : Double, k : Int) -> Bool {
  let a0 = d.inst
  let count = a0.length() / inst_size
  let (bx0, by0, bx1, by1) = (clip_stack[k], clip_stack[k + 1], clip_stack[k + 2], clip_stack[k + 3])
  // each instance: 0 left out; 1 in the list's clip; 2 in a clip of its own wholly inside it, moved; 3 in one the
  // list's cuts, cut so (row_keep)
  let keep = row_keep
  keep.clear()
  for q in 0..<count {
    let b = q * inst_size
    // (what cuts it as it is drawn again, and whether the list's clip is in that)
    let mut how = 1
    let mut cx0 = bx0
    let mut cy0 = by0
    let mut cx1 = bx1
    let mut cy1 = by1
    if d.klass[q] == 1 {
      let (x0, y0, x1, y1) = (a0[b + 16] + dx, a0[b + 17] + dy, a0[b + 18] + dx, a0[b + 19] + dy)
      if x0 > bx0 && y0 > by0 && x1 < bx1 && y1 < by1 {
        how = 2
      } else if out_of_clip(k, x0, y0, x1, y1) {
        how = 0
      } else {
        for m in 40..<52 {
          if a0[b + m] != 0.0 {
            return false
          }
        }
        how = 3
        cx0 = dmax(x0, bx0)
        cy0 = dmax(y0, by0)
        cx1 = dmin(x1, bx1)
        cy1 = dmin(y1, by1)
      }
    }
    if (how == 1 || how == 3) && d.whole {
      let r = d.node_of[q]
      if r >= 0 {
        let nn = self.nodes[i + r]
        if (nn.x > cx1 || nn.y > cy1 || nn.x + nn.fw < cx0 || nn.y + nn.fh < cy0) &&
          !(dr.any && dr.mode != mode_hits && self.draw_carries(i + r)) {
          // (one left out paints what it holds as faint as it is in, Ctx::paint_node: its own surface, or a look's,
          // not)
          if nn.surface || nn.look_scope {
            return false
          }
          how = 0
        }
      }
      let h = d.line_h[q]
      if how != 0 && h >= 0.0 {
        let top = d.line_top[q] + dy
        if top > cy1 || top + h < cy0 {
          how = 0
        }
      }
    }
    keep.push(how)
  }
  while (self.ninst + count + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let a = self.inst
  for q in 0..<count {
    let how = keep[q]
    if how == 0 {
      continue
    }
    let b0 = q * inst_size
    let j = self.ninst
    let b = j * inst_size
    a0.blit_to(a, len=inst_size, src_offset=b0, dst_offset=b)
    self.ninst += 1
    a[b] += dx
    a[b + 1] += dy
    // (cut by a clip of its own: moved with it, and cut by the list's where that cuts it, its corners square where
    // cut, as push_box_clip makes them; by the list's: in it as it is now; turned about a point: that point too;
    // faded towards a cut: where)
    if how == 1 {
      for c in 0..<4 {
        a[b + 16 + c] = clip_stack[k + c]
      }
    } else {
      let (x0, y0, x1, y1) = (a[b + 16] + dx, a[b + 17] + dy, a[b + 18] + dx, a[b + 19] + dy)
      if how == 3 {
        let (cx0, cy0, cx1, cy1) = (dmax(x0, bx0), dmax(y0, by0), dmin(x1, bx1), dmin(y1, by1))
        let cut_l = cx0 != x0
        let cut_t = cy0 != y0
        let cut_r = cx1 != x1
        let cut_b = cy1 != y1
        for c in 0..<4 {
          let cut = if c == 0 {
            cut_l || cut_t
          } else if c == 1 {
            cut_r || cut_t
          } else if c == 2 {
            cut_r || cut_b
          } else {
            cut_l || cut_b
          }
          if cut {
            a[b + 24 + c] = 0.0
            a[b + 28 + c] = 0.0
          }
        }
        a[b + 16] = cx0
        a[b + 17] = cy0
        a[b + 18] = cx1
        a[b + 19] = cy1
      } else {
        a[b + 16] = x0
        a[b + 17] = y0
        a[b + 18] = x1
        a[b + 19] = y1
        if a[b + 48] != 0.0 || a[b + 49] != 0.0 || a[b + 50] != 0.0 || a[b + 51] != 0.0 ||
          a[b + 40] != 0.0 || a[b + 41] != 0.0 || a[b + 42] != 0.0 || a[b + 43] != 0.0 {
          a[b + 40] += dx
          a[b + 41] += dy
          a[b + 42] += dx
          a[b + 43] += dy
        }
      }
    }
    if a[b + 32] != 0.0 {
      a[b + 33] += dx
      a[b + 34] += dy
    }
    if a[b + 53] != 0.0 { a[b + 52] += dy }
    if a[b + 55] != 0.0 { a[b + 54] += dy }
    if a[b + 57] != 0.0 { a[b + 56] += dx }
    if a[b + 59] != 0.0 { a[b + 58] += dx }
    // (a band of a shape: its pieces put now among the frame's)
    if a[b + 5] == 11.0 {
      let first = (a[b + 12].to_int() - d.seg_from) * 4
      a[b + 12] = (self.segs.length() / 4).to_double()
      for v in first..<(first + a[b + 13].to_int() * 4) {
        self.segs.push(d.segs[v])
      }
    }
    if d.tracks_owners {
      let (owner, cell, tree, mark) = d.owners[q]
      inst_owned(j)
      inst_owners.owner[j] = if owner >= 0 { i + owner } else { -1 }
      inst_owners.cell[j] = cell
      inst_owners.tree[j] = tree
      inst_owners.mark[j] = mark
    }
  }
  self.say_again(d.said, {
    ..unmoved,
    dx,
    dy,
    cut: k,
    band_l: d.band[0],
    band_t: d.band[1],
    band_r: d.band[2],
    band_b: d.band[3],
  })
  true
}

///|
// kept across runs: worked on in place, a row at a time (Ctx::row_replay)
let row_keep : Array[Int] = []

///|
fn Ctx::paint_list_row(self : Ctx, i : Int, alpha : Double) -> Unit {
  // The window's target-finding pass is independent of the following paint; it must not discard a drawing merely by
  // walking the row's targets: what it kept of them is said again (Ctx::row_targets). (A row in a row painted whole:
  // painted as it is, with it.)
  if dr.mode == mode_hits && !rec_whole.val {
    self.row_targets(i, alpha)
    return
  }
  if dr.mode != 0 || rec_whole.val {
    self.paint(i, alpha)
    return
  }
  let n = self.nodes[i]
  if n.parent < 0 || n.item < 0 {
    self.paint(i, alpha)
    return
  }
  let rn = match kept_nodes.get((self.nodes[n.parent].id, n.item)) {
    Some(rn) => rn
    None => {
      self.paint(i, alpha)
      return
    }
  }
  let k = clip_top()
  // (where the list's clip is a plain rect, a row is painted whole and what is outside it left out as it is drawn
  // again; in another, only a row wholly inside it is kept, painted as it is where it is cut)
  let cut = n.x < clip_stack[k] || n.y < clip_stack[k + 1] || n.x + n.fw > clip_stack[k + 2] ||
    n.y + n.fh > clip_stack[k + 3]
  if cut && !band_plain(k) {
    self.paint(i, alpha)
    return
  }
  let refusal = self.row_drawing_safe(rn, i)
  if refusal != "" {
    row_drawing_forget(rn)
    self.paint(i, alpha)
    return
  }
  let d = match rn.drawing {
    Some(d) if !d.watch.gone() => d
    _ => {
      let d = row_drawing_new()
      rn.drawing = Some(d)
      d
    }
  }
  let dx = n.x - d.x
  let dy = n.y - d.y
  // (painted whole: drawn again in the list's clip wherever that is now, so long as it is a plain one and inside how far
  // the row was painted, row_reach: a page coming in moves both)
  let mut same_clip = d.clip.length() == clip_n
  if d.whole {
    same_clip = same_clip && band_plain(k)
  } else if same_clip {
    for q in 0..<clip_n {
      if d.clip[q] != clip_stack[k + q] {
        same_clip = false
        break
      }
    }
  }
  let again = d.valid &&
    !d.watch.is_stale() &&
    same_clip &&
    d.n == rn.n &&
    d.alpha == alpha &&
    d.words_alpha == words_alpha.val &&
    d.surface_alpha == look_surface.val.0 &&
    d.targets_said == dr.targets_said &&
    d.text_runs == text_runs.on &&
    d.tracks_owners == inst_owners_kept() &&
    d.tree_owner == inst_owners.tree_painting &&
    (if d.whole { row_reach(d, dx, dy, k) } else { row_cuts_inside(d, dx, dy) && row_inside_band(d, n, dx, dy) }) &&
    (dx * self.scale - (dx * self.scale).round()).abs() < 0.000001 &&
    (dy * self.scale - (dy * self.scale).round()).abs() < 0.000001 &&
    glyphs_still(d.glyphs, self.scale)
  if again && self.row_replay(d, i, dx, dy, k) {
    return
  }
  // (cut by the list's clip and not kept so where it was last, or not drawn again from what it kept here: painted as it
  // is, not painted to be kept again until it is wholly inside; what it kept is still tried, each frame, which costs
  // only what row_replay asks before it draws)
  if cut && (d.held_off || again) {
    if again {
      d.held_off = true
    }
    self.paint(i, alpha)
    return
  }
  d.held_off = false
  // Capture only the paint itself under the row's watch. The surrounding frame's paint still follows its own reads.
  // (its targets kept with what it drew: found again with it)
  d.hits_valid = false
  let start = self.ninst
  let segs = self.segs.length()
  // (what of it lay outside what cuts it and was not painted: shown once moved, so not kept as drawn)
  let culled = paint_culled.val
  // (and what read the clock as it was painted, or waits for a moment: drawn as the clock goes)
  let clocked = clock_reads.val
  let wake = paint_base.wake
  let marks : Array[Int] = []
  self.paint_marks(marks)
  d.clip.clear()
  for q in 0..<clip_n {
    d.clip.push(clip_stack[k + q])
  }
  // (cut by the list's plain clip: painted whole, in a clip that far out, each instance's node and line marked)
  let plain = cut
  d.whole = plain
  d.band.clear()
  if !plain {
    for q in 0..<4 {
      d.band.push(d.clip[q])
    }
  }
  if plain {
    d.band.append(row_whole_rect(k))
    rec_real.val = (d.clip[0], d.clip[1], d.clip[2], d.clip[3])
    rec_reach.val = (d.band[1], d.band[3])
    for q in 0..<4 {
      clip_stack[k + q] = d.band[q]
    }
    rec_node_at.clear()
    rec_line_at.clear()
    rec_node_now.val = -1
    rec_whole.val = true
  }
  d.glyphs.clear()
  let was_glyphs = glyphs_kept.val
  glyphs_kept.val = Some(d.glyphs)
  let was_band = row_band.val
  // (what is left out where it is painted past the list's clip; painted whole, what is past how far it is painted is
  // not counted: it is drawn again only while the list's clip is inside that, row_reach)
  row_band.val = if plain { None } else { Some(d.clip) }
  d.watch.read(fn() { self.paint(i, alpha) })
  row_band.val = was_band
  rec_whole.val = false
  for q in 0..<4 {
    clip_stack[k + q] = d.clip[q]
  }
  glyphs_kept.val = was_glyphs
  match was_glyphs {
    Some(glyphs) => glyphs.append(d.glyphs)
    None => ()
  }
  self.paint_take(marks, d.said)
  d.x = n.x
  d.y = n.y
  d.n = rn.n
  d.alpha = alpha
  d.words_alpha = words_alpha.val
  d.surface_alpha = look_surface.val.0
  d.targets_said = dr.targets_said
  d.text_runs = text_runs.on
  d.tracks_owners = inst_owners_kept()
  d.tree_owner = inst_owners.tree_painting
  // (painted as it is, only a row wholly inside what cuts it: one past it has what is outside left out a glyph at a
  // time, Ctx::emit_text, which shows once it is moved in)
  let whole = plain ||
    (n.x >= d.clip[0] && n.y >= d.clip[1] && n.x + n.fw <= d.clip[2] && n.y + n.fh <= d.clip[3])
  let band = d.band
  d.reach.clear()
  d.reach.append(band)
  if plain {
    d.reach[1] = rec_reach.val.0
    d.reach[3] = rec_reach.val.1
  }
  d.valid = whole && !d.watch.is_stale() && paint_culled.val == culled && clock_reads.val == clocked &&
    paint_base.wake == wake &&
    self.row_drawing_cuts(start, if plain { row_whole_clip(d.clip, band) } else { d.clip }, d.klass, whole=plain)
  d.owners.clear()
  if d.valid && d.tracks_owners {
    for j in start..<self.ninst {
      let owner = inst_owners.owner[j]
      if owner >= 0 && (owner < i || owner >= i + rn.n) {
        d.valid = false
        break
      }
      d.owners.push((if owner >= 0 { owner - i } else { -1 }, inst_owners.cell[j], inst_owners.tree[j], inst_owners.mark[j]))
    }
  }
  if d.valid {
    let floats = (self.ninst - start) * inst_size
    d.inst = FixedArray::make(floats, 0.0)
    self.inst.blit_to(d.inst, len=floats, src_offset=start * inst_size)
    d.seg_from = segs / 4
    d.segs.clear()
    for q in segs..<self.segs.length() {
      d.segs.push(self.segs[q])
    }
    if plain {
      row_marks_of(d, start, self.ninst, i)
    }
  }
  if plain {
    // (what it painted whole taken back: drawn again where it is, in the list's clip; a row it could not keep, painted
    // as it is)
    self.ninst = start
    self.spans_cut()
    self.segs_cut(segs)
    self.paint_cut(marks)
    if !(d.valid && self.row_replay(d, i, 0.0, 0.0, k)) {
      d.valid = false
      d.held_off = true
      self.paint(i, alpha)
    }
  }
}

///|
/// The items whose targets were said again from what their rows kept (Ctx::row_targets), in order: kept only while a
/// test asks, by setting it to Some([]).
// kept across runs: None but while a test asks, which puts it back
let row_targets_again : Ref[Array[Int]?] = Ref(None)

///|
/// Row `i`'s targets as the frame's are found alone (dr's mode_hits): where what it drew is kept, what it said of them
/// kept with that and said again moved, cut by the list's clip; found again, painted whole where the list's clip cuts
/// it (rec_whole: the same far clip, what is past the list's left out as it is said), where it is not kept or the clip
/// went past how far they were found. A row kept as drawn moved its nodes alike, so its targets are where they were,
/// moved.
fn Ctx::row_targets(self : Ctx, i : Int, alpha : Double) -> Unit {
  // (in what passes a finger on, its targets marked so as they are found: not said again, Ctx::push_hit)
  if self.passing != 0 {
    self.paint(i, alpha)
    return
  }
  let n = self.nodes[i]
  let rn = if n.parent >= 0 && n.item >= 0 { kept_nodes.get((self.nodes[n.parent].id, n.item)) } else { None }
  let d = match rn {
    Some(rn) =>
      match rn.drawing {
        Some(d) if d.valid && !d.watch.is_stale() && d.n == rn.n && rn.base == i && nodes_run.on => Some(d)
        _ => None
      }
    None => None
  }
  let d = match d {
    Some(d) => d
    None => {
      self.paint(i, alpha)
      return
    }
  }
  // (a node of it that passes a finger on, however it came to: its targets marked so as they are found, Ctx::push_hit)
  for j in i..<(i + d.n) {
    if self.nodes[j].passes {
      d.hits_valid = false
      self.paint(i, alpha)
      return
    }
  }
  let k = clip_top()
  let plain = band_plain(k)
  let dx = n.x - d.hits_x
  let dy = n.y - d.hits_y
  if d.hits_valid && plain && d.hits_alpha == alpha &&
    clip_stack[k] >= d.hits_band[0] + dx &&
    clip_stack[k + 1] >= d.hits_band[1] + dy &&
    clip_stack[k + 2] <= d.hits_band[2] + dx &&
    clip_stack[k + 3] <= d.hits_band[3] + dy {
    if row_targets_again.val is Some(said) {
      said.push(n.item)
    }
    self.say_again(d.hits_said, {
      ..unmoved,
      dx,
      dy,
      cut: k,
      band_l: d.hits_band[0],
      band_t: d.hits_band[1],
      band_r: d.hits_band[2],
      band_b: d.hits_band[3],
    })
    return
  }
  d.hits_valid = false
  if !plain {
    self.paint(i, alpha)
    return
  }
  // (found whole, in the far clip, then said again in the list's)
  let marks : Array[Int] = []
  self.paint_marks(marks)
  let across = self.across_seen.length()
  let real = (clip_stack[k], clip_stack[k + 1], clip_stack[k + 2], clip_stack[k + 3])
  d.hits_band.clear()
  d.hits_band.append(row_whole_rect(k))
  for q in 0..<4 {
    clip_stack[k + q] = d.hits_band[q]
  }
  self.paint(i, alpha)
  clip_stack[k] = real.0
  clip_stack[k + 1] = real.1
  clip_stack[k + 2] = real.2
  clip_stack[k + 3] = real.3
  self.paint_take(marks, d.hits_said)
  self.paint_cut(marks)
  // (what is found across a list's rows of its own: not said again, so not kept)
  d.hits_valid = self.across_seen.length() == across
  d.hits_x = n.x
  d.hits_y = n.y
  d.hits_alpha = alpha
  self.say_again(d.hits_said, {
    ..unmoved,
    dx: 0.0,
    dy: 0.0,
    cut: k,
    band_l: d.hits_band[0],
    band_t: d.hits_band[1],
    band_r: d.hits_band[2],
    band_b: d.hits_band[3],
  })
}

///|
/// The list's clip `clip` with its rect `band`'s (what a row is painted whole in: Ctx::paint_list_row).
fn row_whole_clip(clip : Array[Double], band : Array[Double]) -> Array[Double] {
  let c = clip.copy()
  for q in 0..<4 {
    c[q] = band[q]
  }
  c
}

///|
/// Each instance `start` to `end` of what row `i` painted whole: its node (from the row's first; -1, none of the row's)
/// and the line of words it is of, from the marks made as it was painted (rec_node_at, rec_line_at).
fn row_marks_of(d : RowDrawing, start : Int, end : Int, i : Int) -> Unit {
  d.node_of.clear()
  d.line_top.clear()
  d.line_h.clear()
  let mut np = 0
  let mut lp = 0
  let mut node = -1
  let mut top = 0.0
  let mut h = -1.0
  for j in start..<end {
    while np < rec_node_at.length() && rec_node_at[np] <= j {
      node = rec_node_at[np + 1]
      np += 2
    }
    while lp < rec_line_at.length() && rec_line_at[lp].to_int() <= j {
      top = rec_line_at[lp + 1]
      h = rec_line_at[lp + 2]
      lp += 3
    }
    d.node_of.push(if node >= i && node < i + d.n { node - i } else { -1 })
    d.line_top.push(top)
    d.line_h.push(h)
  }
}
