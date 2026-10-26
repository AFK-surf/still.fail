// A list's rows kept as they were drawn (Ctx::list): a row that nothing it shows can have changed since it was built is
// not built, laid out nor painted again as the list scrolls; its last build's drawing is drawn again where the row now
// is, moved with it. (Zed's GPUI replays a cached view's paint with its hitboxes and what it said of the frame;
// Chromium keeps a layer's display list recorded past what shows, its interest rect, so that scrolling replays it.)
//
// What builds a row again is a part's (kept_part.mbt's head): what it read of signals, an event from outside, its key
// (the list's width, its rows' count, its scope), the layout's epoch, a motion, cycle or wake of its own; and
// a row's own: any motion round it but its list's scrolling (what moves may be read in what it shows), a press held but
// for the list's own drag, the mouse's pointer over it (it lights what it points at), what it holds held at the list's
// top as it scrolls past (Ctx::stick: a message's picture), and where it now shows more than its last build drew of it
// (row_reach past its list's clip, both ways: a row taller than that is built again every so often as it scrolls). A
// row that holds what must be built each frame (a field, a native view, a list of its own, a scroll bar its list's rows
// share, what is drawn over everything) is always built.
//
// Its list's rows are laid on the pixels as it scrolls (place_list's snap): a row is drawn again only moved by whole
// device pixels, as its laying out there would set its words and boxes.
//
// Drawn again, it says again what its build and its paint said of the frame: its targets (where presses, the wheel and
// the pointer go), what takes the focus, what asks for a menu, the pointer's shape, what tells outside, its words. Its
// instances are recorded in the band (its list's clip as built, row_reach past it) unclipped by its list, and put in
// its list's clip as it is drawn (row_clip_into), built or drawn again alike: a row drawn again is drawn as its build
// would draw it there.

///|
/// How far past its list's clip a row's build draws what is recorded of it (the band): what it may scroll by before
/// it is built again, where it is taller than its list.
let row_reach : Double = 480.0

///|
/// What a row kept holds besides its drawing (KeptPart's `row`): where it was built, what of it was drawn, and what its
/// build and its paint said of the frame, said again each frame it is drawn again.
priv struct RowKept {
  /// its list's id, its item
  list : Int
  item : Int
  /// where its node was laid out as it was built, and how tall
  mut x : Double
  mut y : Double
  mut h : Double
  /// what of it was recorded: from band0 to band1 down the window (its list's clip as it was built, row_reach past it),
  /// across from band_l to band_r (its list's clip's)
  mut band0 : Double
  mut band1 : Double
  mut band_l : Double
  mut band_r : Double
  /// whether it can be drawn again at all (kept_rows.mbt's head: nothing in it that must be built)
  mut keepable : Bool
  /// what it holds held near its list's top as it scrolls past (Ctx::stick): each one's place below the row's top as
  /// laid out, how far below the list's top it is held, how far it may go down; and whether its build's drawing has one
  /// held (moved from where it is laid out): drawn again, the row is built again where one would be
  sticks : Array[(Double, Double, Double)]
  mut held : Bool
  /// this pass: drawn again (not built), its node; how far below where it was built it is drawn
  mut kept : Bool
  mut node : Int
  mut dy : Double
  /// where its box was as it was last drawn (x, y, w, h: the pointer over it lights what it points at)
  mut last : (Double, Double, Double, Double)
  // what its build said of the frame
  focus : Array[Focusable]
  cursors : Array[(Int, Int)]
  takers : Array[Int]
  drags : Array[Int]
  keeps : Array[Int]
  askers : Array[Int]
  mut mouse_drags : Bool?
  /// what it said to tell outside: (0 after_build, 1 tell; its id; what)
  tells : Array[(Int, Int, () -> Unit)]
  /// the words it marked (Ctx::words), as laid out
  words : Array[(String, Words)]
  /// a Tester's: the lines of words it drew (Tester::text_runs); the bars of what scrolls sideways in it (where the
  /// pointer drags them); what else its paint said of the frame is its part's (KeptPart's hit_ids and on)
  runs : Array[TextRun]
  bars : Array[BarAt]
  /// how its list builds a row (Ctx::list's `row`, this build's): its part's build runs it
  mut build : (Int) -> Unit
}

///|
fn RowKept::new(list : Int, item : Int) -> RowKept {
  {
    list,
    item,
    x: 0.0,
    y: 0.0,
    h: 0.0,
    band0: 0.0,
    band1: 0.0,
    band_l: 0.0,
    band_r: 0.0,
    keepable: false,
    sticks: [],
    held: false,
    kept: false,
    node: -1,
    dy: 0.0,
    last: (0.0, 0.0, 0.0, 0.0),
    focus: [],
    cursors: [],
    takers: [],
    drags: [],
    keeps: [],
    askers: [],
    mouse_drags: None,
    tells: [],
    words: [],
    runs: [],
    bars: [],
    build: fn(_) {  },
  }
}

///|
/// What its build says of the frame, from none (its build runs again).
fn RowKept::build_starts(self : RowKept) -> Unit {
  self.focus.clear()
  self.cursors.clear()
  self.takers.clear()
  self.drags.clear()
  self.keeps.clear()
  self.askers.clear()
  self.mouse_drags = None
  self.tells.clear()
  self.words.clear()
  self.sticks.clear()
  self.held = false
}

///|
/// The rows kept, by their ids (their own: a part's is any Int), and their ids by list and item.
// kept across runs: let go of with the parts (parts_forget, rows_frame_end)
let kept_rows : Map[Int, KeptPart] = {}

///|
// kept across runs: let go of with the parts (parts_forget, rows_frame_end)
let row_ids : Map[(Int, Int), Int] = {}

///|
// kept across runs: it only counts on
let row_next_id : Ref[Int] = Ref(1)

///|
/// The frame is built: the rows that did not show in it let go (what they read no longer kept by them).
fn rows_frame_end(c : Ctx) -> Unit {
  if kept_rows.is_empty() {
    return
  }
  let gone = []
  for id, st in kept_rows {
    if st.shown != c.frame_no {
      gone.push(id)
    }
  }
  for id in gone {
    match kept_rows.get(id) {
      Some(st) => {
        st.tracker.dispose()
        match st.row {
          Some(rk) => row_ids.remove((rk.list, rk.item))
          None => ()
        }
      }
      None => ()
    }
    kept_rows.remove(id) |> ignore
  }
}

///|
/// What a list's rows are kept by in this build of the frame, worked out once for its rows (Ctx::rows_round): the list
/// (its id), the build, its rows' key, whether anything moves round them but the list's own scrolling, the rows with a
/// motion of their own.
priv struct RowsRound {
  mut list : Int
  mut build : Int
  mut key : String
  mut moving : Bool
  rows : Array[Int]
}

///|
// kept across runs: worked out anew for each list and build (Ctx::rows_round)
let rows_round : RowsRound = { list: 0, build: -1, key: "", moving: false, rows: [] }

///|
/// Whether a part kept and a list's row kept may be drawn again (a test's: false, each built every frame, its drawing
/// taken as when it is kept: what drawing it again must match).
// kept across runs: put back by each Tester (Tester::new)
let drawn_again_on : Ref[Bool] = Ref(true)

///|
/// Whether a list's rows may be kept this frame: as parts are (Tester::keep_parts), and not while anything reads what
/// each frame builds (a screen reader, a test's instance owners, a test lighting everything).
fn Ctx::rows_on(self : Ctx) -> Bool {
  parts_on.val && !inst_owners.on && !self.lit_every && !h_a11y_on()
}

///|
/// The kept part row `k` of list `list` is kept as.
fn row_part(list : Int, k : Int) -> KeptPart {
  let id = match row_ids.get((list, k)) {
    Some(id) => id
    None => {
      let id = row_next_id.val
      row_next_id.val = id + 1
      row_ids[(list, k)] = id
      id
    }
  }
  match kept_rows.get(id) {
    Some(st) => st
    None => {
      let st = kept_new(id)
      let rk = RowKept::new(list, k)
      st.row = Some(rk)
      // (its build: the row as its list builds it now)
      st.body.val = fn() {
        rk.build_starts()
        (rk.build)(rk.item)
      }
      kept_rows[id] = st
      st
    }
  }
}

///|
/// Row `k` of list node `li`: built, or (rows_on, nothing it shows changed) a box as tall as its last build drawn again
/// as that drew it (kept: Ctx::rows_placed builds it after all where it shows what that did not draw). `force`: built.
fn Ctx::row_of(self : Ctx, li : Int, st : ListState, k : Int, iw : Double, force? : Bool = false) -> Int {
  if !self.rows_on() {
    return self.build_row(li, st, k)
  }
  let list = self.nodes[li].id
  let kp = row_part(list, k)
  let rk = kp.row.unwrap()
  // (shown in the frame before, or in this one's pass before: else it comes now)
  if kp.shown < self.frame_no - 1 {
    kp.built = -1
  }
  kp.shown = self.frame_no
  let id = kp.id
  let round = self.rows_round(list, st, iw)
  // (while what moves round its rows goes, or a press is held but by the list's own drag, none of them is drawn again:
  // each built as where none is kept, nothing of its drawing taken)
  if round.moving || (self.down && !(self.dragging && st.held)) {
    kp.built = -1
    let r = self.build_row(li, st, k)
    // (what its list's clip leaves nothing of dropped, as of a row built to be kept)
    self.drawn_of(r).row = -1
    return r
  }
  let moving = round.rows.contains(id)
  let key = round.key
  let same = !force &&
    drawn_again_on.val &&
    rk.keepable &&
    kp.built >= 0 &&
    kp.built != self.frame_no &&
    kp.drawn == kp.built &&
    kp.key == key &&
    kp.outside == outside_events.val &&
    kp.epoch == self.epoch &&
    kp.scale == self.scale &&
    kp.pointing == pointing() &&
    !kp.live &&
    self.now < kp.due &&
    !moving
  rk.build = st.row
  if !same {
    kp.forced = kp.forced + 1
    kp.force.set(kp.forced)
  }
  // built as build_row builds a row, its build run by the part's tracker
  let saved_cur = self.cur
  let saved_seed = self.id_seed
  let saved_owner = self.owner
  let (saved_w, saved_h) = (self.width, self.height)
  let saved_sel = desk.selecting
  let (saved_theme, saved_dir, saved_layer) = (self.theme, self.direction, self.layer_cur)
  desk.selecting = st.sel
  self.theme = st.theme
  self.direction = st.direction
  self.layer_cur = st.layer
  self.cur = li
  self.id_seed = st.seed
  self.owner = st.owner
  if st.vw > 0.0 {
    self.width = st.vw
    self.height = st.vh
  }
  let r = self.alloc(kind_box)
  self.nodes[r].item = k
  // (in a part kept: what the row tells moves the part's too, kept_part.mbt)
  let (row_was, part_was) = (part_now.row, part_now.part)
  let (live, due, due_later) = (part_now.live, part_now.due, part_now.due_later)
  part_now.row = id
  part_now.part = st.part
  part_now.live = false
  part_now.due = @double.infinity
  part_now.due_later = true
  let layers = self.layers.length()
  let back = self.back_next
  let mut ran = false
  self.with_parent(r, fn() {
    self.scope(k, fn() {
      let stamp = kp.tracker.get()
      if stamp != kp.stamp {
        ran = true
        kp.stamp = stamp
        kp.live = part_now.live || self.layers.length() != layers || !physical_equal(self.back_next, back)
        kp.due = part_now.due
        kp.due_later = part_now.due_later
      }
    })
  })
  // (what holds it asks what it asked of time: a row it is in, being built, as a part's build tells what holds it; the
  // part its list is in, built before its rows are laid, told itself)
  let (rlive, rdue, rlater) = (kp.live, kp.due, kp.due_later)
  part_now.row = row_was
  part_now.part = part_was
  part_now.live = live || rlive
  if rdue < due {
    part_now.due = rdue
    part_now.due_later = rlater
  } else {
    part_now.due = due
    part_now.due_later = due_later
  }
  if st.part != 0 {
    match kept_parts.get(st.part) {
      Some(p) => {
        p.live = p.live || rlive
        if rdue < p.due {
          p.due = rdue
          p.due_later = rlater
        }
      }
      None => ()
    }
  }
  self.id_seed = saved_seed
  self.cur = saved_cur
  self.owner = saved_owner
  self.width = saved_w
  self.height = saved_h
  desk.selecting = saved_sel
  self.theme = saved_theme
  self.direction = saved_dir
  self.layer_cur = saved_layer
  let e = self.drawn_of(r)
  rk.node = r
  if ran {
    kp.built = self.frame_no
    kp.key = key
    kp.outside = outside_events.val
    kp.epoch = self.epoch
    kp.scale = self.scale
    kp.pointing = pointing()
    kp.again = false
    rk.kept = false
    rk.keepable = true
    // what its paint draws taken (row_paint_record)
    e.row = id
  } else {
    // drawn again, as tall as it was: what it said of the frame said again once where it shows is known
    // (Ctx::rows_placed)
    kp.again = true
    rk.kept = true
    self.nodes[r].h = Px(rk.h)
    e.again = Some(kp)
    // (what it draws from kept through this frame: the glyphs' plots, the pictures)
    for p in kp.plots {
      if p >= part_colour_plot {
        atlas_for(true).0.drawn(p - part_colour_plot)
      } else {
        atlas_for(false).0.drawn(p)
      }
    }
    for img in kp.images {
      img.used = self.frame_no
    }
    if kp.due < @double.infinity {
      self.wake_at_time(kp.due, later=kp.due_later)
    }
  }
  r
}

///|
/// What the rows of list `list` (`st`, `iw` wide) are kept by in this build (RowsRound), worked out at its first row:
/// their key (its width, its rows' count, its scope, picking, its layer, its direction, what the press is on: one taken
/// from it, as the list takes the drag, shows it pressed no more; the theme each build works out anew from what changes
/// only by what builds it again: a setting, the system, a motion); whether anything moves round them but the list's own
/// scrolling (another row's motion is that row's: what moves may be read in what a row shows, a message held till an
/// avatar lands); the rows with a motion of their own. Motions asked as the last frame left them, as a part asks.
fn Ctx::rows_round(self : Ctx, list : Int, st : ListState, iw : Double) -> RowsRound {
  let r = rows_round
  if r.list == list && r.build == self.build_no {
    return r
  }
  r.list = list
  r.build = self.build_no
  r.key = "\{iw} \{st.count} \{st.seed} \{st.owner} \{st.sel} \{st.layer} \{st.direction} \{self.active} \{self.down}"
  r.moving = false
  r.rows.clear()
  let last = self.frame_no - 1
  for e in self.movers {
    if e.m.rest_at(self.now, last) > self.now {
      if e.row != 0 {
        r.rows.push(e.row)
      } else if (e.part == 0 || e.part == st.part) && !physical_equal(e.who, st.ease_mover) {
        r.moving = true
      }
    }
  }
  r
}

///|
/// List node `li`'s rows placed (`order`, top to bottom, in its content box from `iy`, `ih` tall): each kept where its
/// last build drew all of what shows of it now, and the pointer is not over it (a row lights what the mouse points
/// at), what it said of the frame said again; any other built where it is, the rows under it moved by what its height
/// changed (none, as nothing it shows changed). Whether any was built (`order` holds its node now).
fn Ctx::rows_placed(
  self : Ctx,
  li : Int,
  st : ListState,
  order : Array[Int],
  ix : Double,
  iy : Double,
  iw : Double,
  ih : Double,
) -> Bool {
  if !self.rows_on() {
    return false
  }
  let nan = 0.0 / 0.0
  let mut moved = 0.0
  let mut built = false
  for j in 0..<order.length() {
    let r = order[j]
    if moved != 0.0 {
      self.shift(r, moved)
    }
    let kp = match self.drawn_entry(r) {
      Some({ again: Some(kp), .. }) => kp
      _ => continue
    }
    let rk = kp.row.unwrap()
    let n = self.nodes[r]
    let dy = n.y - rk.y
    // what shows of it now, and what its build drew of it, moved with it
    let top = dmax(iy, n.y)
    let bottom = dmin(iy + ih, n.y + n.fh)
    let (lx, ly, lw, lh) = rk.last
    // (what the pointer is over one of its targets, as it was built or now; or the pointer over it, where it was and
    // where it is: it lights what it points at, one frame late)
    let pointed = kp.lit ||
      self.part_lit(kp) ||
      (
        pointing() is Mouse &&
        self.px >= 0.0 &&
        (
          (self.px >= lx && self.px < lx + lw && self.py >= ly && self.py < ly + lh) ||
          (self.px >= n.x && self.px < n.x + n.fw && self.py >= n.y && self.py < n.y + n.fh)
        )
      )
    // (moved by whole device pixels, as scrolling moves rows: laid out there, its words and boxes would be set on the
    // pixels as they are)
    let whole = (dy * self.scale - (dy * self.scale).round()).abs() < 0.000001
    // (what it holds near the list's top: held now, or as it was drawn)
    let mut held = rk.held
    for t in rk.sticks {
      if dmin(iy + t.1 - (n.y + t.0), t.2) > 0.0 {
        held = true
      }
    }
    if whole && !held && n.x == rk.x && top >= rk.band0 + dy && bottom <= rk.band1 + dy && !pointed {
      rk.dy = dy
      self.row_said_again(rk)
      continue
    }
    // built where it is
    let k = n.item
    let r2 = self.row_of(li, st, k, iw, force=true)
    let h = self.layout(r2, ix, n.y, iw, nan)
    if h != n.fh {
      moved = moved + (h - n.fh)
      st.set_height(k, h)
    }
    self.nodes[r2].parent = li
    order[j] = r2
    built = true
  }
  built
}

///|
/// What row `rk`'s build said of the frame, said again as it is drawn again (its targets are said as it is painted).
fn Ctx::row_said_again(self : Ctx, rk : RowKept) -> Unit {
  for f in rk.focus {
    self.focusables.push({ ..f, node: rk.node })
  }
  for c in rk.cursors {
    desk.next_cursors[c.0] = c.1
  }
  for id in rk.takers {
    desk.next_takers.add(id)
  }
  for id in rk.drags {
    desk.next_drags.push(id)
  }
  for id in rk.keeps {
    desk.next_keeps.push(id)
  }
  for id in rk.askers {
    desk.next_askers.push(id)
  }
  match rk.mouse_drags {
    Some(on) => desk.next_mouse_drags = on
    None => ()
  }
  for t in rk.tells {
    let list = if t.0 == 0 { self.tells } else { self.told }
    match list.search_by(fn(x) { x.0 == t.1 }) {
      Some(i) => list[i] = (t.1, t.2)
      None => list.push((t.1, t.2))
    }
  }
}

///|
/// The row being built now.
fn row_building() -> RowKept? {
  if part_now.row == 0 {
    return None
  }
  match kept_rows.get(part_now.row) {
    Some(st) => st.row
    None => None
  }
}

///|
/// Row `id`'s build (node `i`) painted, as its list paints it: in the band (its list's clip, row_reach past it both
/// ways, nothing else of its list's), what it draws and what it says of the frame taken; then put in its list's clip,
/// as what drawing it again puts there.
fn Ctx::row_paint_record(self : Ctx, i : Int, id : Int, alpha : Double) -> Unit {
  let kp = match kept_rows.get(id) {
    Some(st) => st
    None => {
      dr.bypass = i
      self.paint(i, alpha)
      dr.bypass = -1
      return
    }
  }
  let rk = kp.row.unwrap()
  let k = clip_top()
  let s = clip_stack
  let (x0, y0, x1, y1) = (s[k], s[k + 1], s[k + 2], s[k + 3])
  let i0 = self.ninst
  let h0 = self.next_hit_ids.length()
  let s0 = self.next_scroll_ids.length()
  let sel0 = desk.next_sels.length()
  let r0 = text_runs.runs.length()
  let g0 = self.segs.length()
  let b0 = self.next_bars.length()
  let a0 = self.across_seen.length()
  let t0 = dr.tops.length()
  let o0 = dr.overlay.length()
  kp.points.clear()
  kp.plots.clear()
  kp.plot_seen.clear()
  kp.images.clear()
  kp.from = (h0, s0, sel0)
  // (the band: a clip of its own, nothing of its list's, nor any outer)
  for v in [x0, y0 - row_reach, x1, y1 + row_reach] {
    clip_stack.push(v)
  }
  for _ in 0..<20 {
    clip_stack.push(0.0)
  }
  let was = part_now.painting_row
  part_now.painting_row = id
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  part_now.painting_row = was
  pop_clip()
  let n = self.nodes[i]
  kp.take_insts(self, i0)
  kp.drawn = self.frame_no
  kp.words.clear()
  if fake.val is Some(_) {
    kp.words.append(self.part_words(i))
  }
  rk.x = n.x
  rk.y = n.y
  rk.h = n.fh
  rk.band0 = y0 - row_reach
  rk.band1 = y1 + row_reach
  rk.band_l = x0
  rk.band_r = x1
  rk.dy = 0.0
  self.take_said(kp)
  rk.runs.clear()
  for j in r0..<text_runs.runs.length() {
    rk.runs.push(text_runs.runs[j])
  }
  rk.bars.clear()
  for j in b0..<self.next_bars.length() {
    rk.bars.push(self.next_bars[j])
  }
  // (what must be built each frame: drawn over everything, a scroll bar of its rows', a native view's hole, a field, a
  // list of its own)
  rk.keepable = rk.keepable &&
    dr.tops.length() == t0 &&
    dr.overlay.length() == o0 &&
    self.across_seen.length() == a0 &&
    !kp.holds_native() &&
    !self.holds_built(i)
  // in its list's clip
  self.row_clip_into(k, i0, h0, s0, sel0, r0, g0, b0, drops=dr.tops.length() == t0 && dr.overlay.length() == o0)
  rk.last = (n.x, n.y, n.fw, n.fh)
  kp.lit = self.part_lit(kp)
}

///|
/// Row part `kp` drawn again (node `i`), as its build drew it, moved down by how far its node is below where it was
/// built: its instances, its targets and what scrolls in it, its paragraphs that can be picked; put in its list's clip.
fn Ctx::row_paint_again(self : Ctx, i : Int, kp : KeptPart) -> Unit {
  let rk = kp.row.unwrap()
  let dy = self.nodes[i].y - rk.y
  rk.dy = dy
  let k = clip_top()
  let i0 = self.ninst
  let h0 = self.next_hit_ids.length()
  let s0 = self.next_scroll_ids.length()
  let sel0 = desk.next_sels.length()
  let r0 = text_runs.runs.length()
  let g0 = self.segs.length()
  let b0 = self.next_bars.length()
  if dr.mode != mode_hits {
    self.part_paint_again(kp)
    let a = self.inst
    for q in i0..<self.ninst {
      let b = q * inst_size
      rk.unband(a, b + 16)
      a[b + 1] = a[b + 1] + dy
      a[b + 17] = a[b + 17] + dy
      a[b + 19] = a[b + 19] + dy
      // (its outer, where it has one)
      if a[b + 44] > 0.0 || a[b + 45] > 0.0 || a[b + 46] > 0.0 || a[b + 47] > 0.0 {
        a[b + 41] = a[b + 41] + dy
        a[b + 43] = a[b + 43] + dy
      }
      if a[b + 32] != 0.0 {
        a[b + 34] = a[b + 34] + dy
      }
    }
  }
  if dr.mode != mode_draw {
    for j in 0..<kp.hit_ids.length() {
      self.next_hit_ids.push(kp.hit_ids[j])
      self.next_hit_ends.push(kp.hit_ends[j] + h0)
      let v = j * 4
      self.next_hit_rects.push(kp.hit_rects[v])
      self.next_hit_rects.push(kp.hit_rects[v + 1] + dy)
      self.next_hit_rects.push(kp.hit_rects[v + 2])
      self.next_hit_rects.push(kp.hit_rects[v + 3] + dy)
      let c = j * clip_n
      let hc = kp.hit_clips
      let outer = hc[c + 16] > 0.0 || hc[c + 17] > 0.0 || hc[c + 18] > 0.0 || hc[c + 19] > 0.0
      let from = self.next_hit_clips.length()
      for m in 0..<clip_n {
        self.next_hit_clips.push(hc[c + m])
      }
      // (the y of its own rect's edges, and its outer's where it has one)
      let nc = self.next_hit_clips
      rk.unband_hit(nc, from)
      nc[from + 1] = nc[from + 1] + dy
      nc[from + 3] = nc[from + 3] + dy
      if outer {
        nc[from + 13] = nc[from + 13] + dy
        nc[from + 15] = nc[from + 15] + dy
      }
    }
    for id in kp.points {
      self.point_said(id)
    }
    for j in 0..<kp.scroll_ids.length() {
      self.next_scroll_ids.push(kp.scroll_ids[j])
      let v = j * 4
      self.next_scroll_rects.push(kp.scroll_rects[v])
      self.next_scroll_rects.push(kp.scroll_rects[v + 1] + dy)
      self.next_scroll_rects.push(kp.scroll_rects[v + 2])
      self.next_scroll_rects.push(kp.scroll_rects[v + 3] + dy)
    }
    for t in kp.sels {
      selectable_painted(t.base, t.at, t.lay, t.text, t.ox, t.oy + dy, t.x0, t.y0 + dy, t.x1, t.y1 + dy)
    }
    for b in rk.bars {
      self.next_bars.push({ ..b, y0: b.y0 + dy, y1: b.y1 + dy, ty: b.ty + dy })
    }
  }
  if dr.mode != mode_hits && text_runs.on {
    for t in rk.runs {
      text_runs.runs.push({ ..t, base: t.base + dy, top: t.top + dy, bottom: t.bottom + dy })
    }
  }
  self.row_clip_into(k, i0, h0, s0, sel0, r0, g0, b0, drops=true)
  let n = self.nodes[i]
  rk.last = (n.x, n.y, n.fw, n.fh)
}

///|
/// What a row painted from instance `i0`, target `h0`, scrolling target `s0`, paragraph `sel0`, line of words `r0`, its
/// shapes' pieces from `g0` (in the frame's `segs`), scroll bar `b0` on put in the clip at `k` (its list's): each cut by
/// it where they meet (clip_into), the rects of its targets, of what scrolls in it and of its bars cut to it, the lines
/// of words outside it left out; with `drops` (nothing of it put off to be drawn over everything), what it leaves
/// nothing of dropped (row_drop).
fn Ctx::row_clip_into(
  self : Ctx,
  k : Int,
  i0 : Int,
  h0 : Int,
  s0 : Int,
  sel0 : Int,
  r0 : Int,
  g0 : Int,
  b0 : Int,
  drops~ : Bool,
) -> Unit {
  let s = clip_stack
  let (x0, y0, x1, y1) = (s[k], s[k + 1], s[k + 2], s[k + 3])
  let c = clip_scratch
  let a = self.inst
  for q in i0..<self.ninst {
    let b = q * inst_size
    for m in 0..<4 {
      c[m] = a[b + 16 + m]
      c[4 + m] = a[b + 24 + m]
      c[8 + m] = a[b + 28 + m]
    }
    for m in 0..<12 {
      c[12 + m] = a[b + 40 + m]
    }
    clip_into(k, c)
    for m in 0..<4 {
      a[b + 16 + m] = c[m]
      a[b + 24 + m] = c[4 + m]
      a[b + 28 + m] = c[8 + m]
    }
    for m in 0..<12 {
      a[b + 40 + m] = c[12 + m]
    }
  }
  if drops {
    self.row_drop(i0, g0)
  }
  for h in h0..<self.next_hit_ids.length() {
    let v = h * 4
    let r = self.next_hit_rects
    r[v] = dmax(r[v], x0)
    r[v + 1] = dmax(r[v + 1], y0)
    r[v + 2] = dmin(r[v + 2], x1)
    r[v + 3] = dmin(r[v + 3], y1)
    let hc = self.next_hit_clips
    let base = h * clip_n
    for m in 0..<clip_n {
      c[m] = hc[base + m]
    }
    clip_into(k, c)
    for m in 0..<clip_n {
      hc[base + m] = c[m]
    }
  }
  for j in s0..<self.next_scroll_ids.length() {
    let v = j * 4
    let r = self.next_scroll_rects
    r[v] = dmax(r[v], x0)
    r[v + 1] = dmax(r[v + 1], y0)
    r[v + 2] = dmin(r[v + 2], x1)
    r[v + 3] = dmin(r[v + 3], y1)
  }
  for j in sel0..<desk.next_sels.length() {
    let t = desk.next_sels[j]
    desk.next_sels[j] = { ..t, x0: dmax(t.x0, x0), y0: dmax(t.y0, y0), x1: dmin(t.x1, x1), y1: dmin(t.y1, y1) }
  }
  for j in b0..<self.next_bars.length() {
    let b = self.next_bars[j]
    self.next_bars[j] = { ..b, y0: dmax(b.y0, y0), y1: dmin(b.y1, y1) }
  }
  // (as keep_text_runs keeps those inside the clip alone)
  let runs = text_runs.runs
  let mut w = r0
  for j in r0..<runs.length() {
    let t = runs[j]
    if t.top > y1 || t.bottom < y0 {
      continue
    }
    runs[w] = t
    w = w + 1
  }
  runs.truncate(w)
}

///|
/// A clip's 24 numbers, worked on in place (row_clip_into).
// kept across runs: scratch, written before it is read
let clip_scratch : FixedArray[Double] = FixedArray::make(24, 0.0)

///|
/// A clip `c` (a level's 24 numbers: its rect, its corners' radii, how smooth they are, its outer's 12) as what is in
/// the clip at `k` (in `clip_stack`) is cut where they meet, by the rule a clip pushed in it is (push_round_clip,
/// push_clip_r): their rects' intersection; each corner its own where it is still its own (the rounder where it is also
/// the outer clip's), else the outer clip's where it is that one's, else square; its outer that clip's outer, else that
/// clip where it cuts through a rounded corner of it, else its own. One that holds that clip's rect whole, square and
/// with no outer (what a row draws in nothing of its own that cuts) is that clip.
fn clip_into(k : Int, c : FixedArray[Double]) -> Unit {
  let s = clip_stack
  let (ox0, oy0, ox1, oy1) = (c[0], c[1], c[2], c[3])
  if ox0 <= s[k] &&
    oy0 <= s[k + 1] &&
    ox1 >= s[k + 2] &&
    oy1 >= s[k + 3] &&
    c[4] <= 0.0 &&
    c[5] <= 0.0 &&
    c[6] <= 0.0 &&
    c[7] <= 0.0 &&
    c[16] <= 0.0 &&
    c[17] <= 0.0 &&
    c[18] <= 0.0 &&
    c[19] <= 0.0 {
    for m in 0..<24 {
      c[m] = s[k + m]
    }
    return
  }
  let x0 = dmax(ox0, s[k])
  let y0 = dmax(oy0, s[k + 1])
  let x1 = dmin(ox1, s[k + 2])
  let y1 = dmin(oy1, s[k + 3])
  for j in 0..<4 {
    let left = j == 0 || j == 3
    let top = j < 2
    let px = if left { x0 } else { x1 }
    let py = if top { y0 } else { y1 }
    let own = px == (if left { ox0 } else { ox1 }) && py == (if top { oy0 } else { oy1 })
    let (lr, ls) = clip_corner_r(k, j, px, py)
    if !(own && c[4 + j] > 0.0 && c[4 + j] >= lr) {
      c[4 + j] = lr
      c[8 + j] = ls
    }
  }
  if clip_has_outer(k) {
    for m in 0..<12 {
      c[12 + m] = s[k + 12 + m]
    }
  } else if clip_cuts(k, x0, y0, x1, y1, (c[4], c[5], c[6], c[7])) {
    for m in 0..<12 {
      c[12 + m] = s[k + m]
    }
  }
  c[0] = x0
  c[1] = y0
  c[2] = x1
  c[3] = y1
}

///|
/// Whether node `i` holds what must be built each frame it shows (kept_rows.mbt's head): a field, a native view, a
/// book's page, a list of its own, a layer.
fn Ctx::holds_built(self : Ctx, i : Int) -> Bool {
  let n = self.nodes[i]
  if n.kind == kind_editor || n.kind == kind_native || n.kind == kind_page || n.portal {
    return true
  }
  let mut c = n.first
  while c >= 0 {
    let cn = self.nodes[c]
    if cn.kind == kind_list || self.holds_built(c) {
      return true
    }
    c = cn.next
  }
  false
}

///|
/// How many of the last frame's list rows were drawn again as their last build drew them, not built.
pub fn Tester::rows_kept(self : Tester) -> Int {
  ignore(self)
  let c = g()
  let mut n = 0
  for _, st in kept_rows {
    match st.row {
      Some(rk) if st.shown == c.frame_no && rk.kept => n = n + 1
      _ => ()
    }
  }
  n
}

///|
/// The words the rows drawn again marked (words_after_layout took them as their build laid them out), where they are
/// now: kept as their build would keep them, each seen; where a build read them and they moved, a layout read back that
/// moved, as their build's.
fn Ctx::rows_words_again(self : Ctx, seen : Map[String, Bool]) -> Unit {
  for _, st in kept_rows {
    match st.row {
      Some(rk) if st.shown == self.frame_no && rk.kept =>
        for w in rk.words {
          let pieces = w.1.pieces.map(fn(p) { { ..p, y: p.y + rk.dy } })
          match words_kept.get(w.0) {
            Some(was) if !same_place(was.pieces, pieces) && self.words_reads.contains(w.0) =>
              self.read_changed("words_of \"" + w.0 + "\"")
            _ => ()
          }
          words_kept[w.0] = { text: w.1.text, pieces }
          seen[w.0] = true
        }
      _ => ()
    }
  }
}

///|
/// The list row being built this frame that node `i` is in, if it is in one (its node's entry says so).
fn Ctx::row_holding(self : Ctx, i : Int) -> RowKept? {
  let mut p = i
  while p >= 0 {
    match self.drawn_entry(p) {
      Some(e) if e.row != 0 =>
        return match kept_rows.get(e.row) {
          Some(st) => st.row
          None => None
        }
      _ => ()
    }
    p = self.nodes[p].parent
  }
  None
}

///|
/// Whether (x, y) is on what scrolls in a row drawn again in the last frame (a table's words sideways): a wheel turned
/// there scrolls it, an event from outside for its row (it is built from where it is scrolled to).
fn row_scroller_under(x : Double, y : Double) -> Bool {
  let frame = g().frame_no
  for _, st in kept_rows {
    match st.row {
      Some(rk) if st.shown == frame && st.scroll_ids.length() > 0 =>
        for j in 0..<st.scroll_ids.length() {
          let v = j * 4
          let r = st.scroll_rects
          if x >= r[v] && x < r[v + 2] && y >= r[v + 1] + rk.dy && y < r[v + 3] + rk.dy {
            return true
          }
        }
      _ => ()
    }
  }
  false
}

///|
/// Whether parts kept and a list's rows kept are drawn again (true, as on a host) or built every frame, their drawing
/// taken as when they are kept (false): a test's, to hold what is drawn again to what building it draws.
pub fn Tester::drawn_again(self : Tester, on : Bool) -> Unit {
  ignore(self)
  drawn_again_on.val = on
}

///|
/// The edges of a clip (its rect from `at` in `a`: x0 y0 x1 y1) that are the band's, the row's recording's own and not
/// what cuts it: as far off as nothing cuts, so that its list's clip where it is drawn again cuts it there as it would
/// have cut its build there.
fn RowKept::unband(self : RowKept, a : FixedArray[Double], at : Int) -> Unit {
  if a[at] == self.band_l {
    a[at] = -1.0e9
  }
  if a[at + 1] == self.band0 {
    a[at + 1] = -1.0e9
  }
  if a[at + 2] == self.band_r {
    a[at + 2] = 1.0e9
  }
  if a[at + 3] == self.band1 {
    a[at + 3] = 1.0e9
  }
}

///|
/// The same of a target's clip (from `at` in the frame's targets' clips).
fn RowKept::unband_hit(self : RowKept, a : Array[Double], at : Int) -> Unit {
  if a[at] == self.band_l {
    a[at] = -1.0e9
  }
  if a[at + 1] == self.band0 {
    a[at + 1] = -1.0e9
  }
  if a[at + 2] == self.band_r {
    a[at + 2] = 1.0e9
  }
  if a[at + 3] == self.band1 {
    a[at + 3] = 1.0e9
  }
}

///|
/// Node `s`, held near its list's top (Ctx::stick_in), laid out at `y` (`stick` below the top, `room` the most it may go
/// down): of the row being built that holds it, where it is in the row, and whether it is held now.
fn Ctx::row_stuck(self : Ctx, s : Int, y : Double, stick : Double, room : Double) -> Unit {
  match self.row_holding(s) {
    Some(rk) => {
      let r = self.nodes[rk.node]
      rk.sticks.push((y - r.y, stick, room))
      if self.nodes[s].y != y {
        rk.held = true
      }
    }
    None => ()
  }
}

///|
/// What a row drew from instance `i0` (its shapes' pieces from `g0`), each in its clip, of which it leaves nothing:
/// dropped, the pieces of the shapes kept alone kept, in order (where none of glass is among them: their runs are the
/// frame's). What of a row is drawn is what shows in its list, built (in the band past it, or plainly) or drawn again.
fn Ctx::row_drop(self : Ctx, i0 : Int, g0 : Int) -> Unit {
  let a = self.inst
  for q in i0..<self.ninst {
    let kind = a[q * inst_size + 5]
    if kind == 5.0 || kind == 6.0 || kind == 7.0 {
      return
    }
  }
  let mut w = i0
  for q in i0..<self.ninst {
    let b = q * inst_size
    let kind = a[b + 5]
    // (how far past its rect it draws: a line's half width, a shadow's blur; the shapes' pieces, and what is turned,
    // never dropped)
    let past = if kind == 10.0 {
      a[b + 4]
    } else if kind == 2.0 {
      3.0 * a[b + 7]
    } else {
      0.0
    }
    let gone = kind != 12.0 &&
      a[b + 32] == 0.0 &&
      (
        a[b + 18] <= a[b + 16] ||
        a[b + 19] <= a[b + 17] ||
        a[b] - past >= a[b + 18] ||
        a[b + 1] - past >= a[b + 19] ||
        a[b] + a[b + 2] + past <= a[b + 16] ||
        a[b + 1] + a[b + 3] + past <= a[b + 17]
      )
    if gone {
      continue
    }
    if w != q {
      a.blit_to(a, len=inst_size, src_offset=b, dst_offset=w * inst_size)
    }
    w = w + 1
  }
  if w == self.ninst {
    return
  }
  self.ninst = w
  // (each kept moved down over what went: they lie in order)
  let segs = self.segs
  let mut to = g0
  for q in i0..<self.ninst {
    let b = q * inst_size
    if a[b + 5] == 11.0 {
      let from = a[b + 12].to_int() * 4
      let n = a[b + 13].to_int() * 4
      a[b + 12] = (to / 4).to_double()
      if from != to {
        for v in 0..<n {
          segs[to + v] = segs[from + v]
        }
      }
      to = to + n
    }
  }
  segs.truncate(to)
}

///|
/// A list's row built where none can be drawn again (Ctx::row_of: what moves round them, a press held), painted as it is
/// (node `i`): what its list's clip leaves nothing of dropped, as of a row built in its band (row_drop).
fn Ctx::row_paint_plain(self : Ctx, i : Int, alpha : Double) -> Unit {
  let i0 = self.ninst
  let g0 = self.segs.length()
  let t0 = dr.tops.length()
  let o0 = dr.overlay.length()
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  if dr.tops.length() == t0 && dr.overlay.length() == o0 {
    self.row_drop(i0, g0)
  }
}
