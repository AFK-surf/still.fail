// A list's rows kept as they were drawn (Ctx::list): a row that nothing it shows can have changed since it was built is
// not built, laid out nor painted again as the list scrolls; its last build's drawing is drawn again where the row now
// is, moved with it. (Zed's GPUI replays a cached view's paint with its hitboxes and what it said of the frame;
// Chromium keeps a layer's display list recorded past what shows, its interest rect, so that scrolling replays it.)
//
// What builds a row again is a part's (kept_part.mbt's head): what it read of signals and of time (the frame, a
// moment, what moves what it laid out), an event from outside, its key (the list's width, its rows' count, its scope),
// the layout's epoch; and a row's own: a press held but for the list's own drag, the mouse's pointer over it (it lights
// what it points at), what it holds held at the list's top as it scrolls past (Ctx::stick: a message's picture), and
// where it now
// shows more than its last build drew of it (row_reach past its list's clip, both ways: a row taller than that is built
// again every so often as it scrolls). A row that holds what must be built each frame (a field, a native view, a list
// of its own, a scroll bar its list's rows share, what is drawn over everything) is always built.
//
// Its list's rows are laid on the pixels, each as tall as whole pixels (Ctx::row_slot, rows_on_pixels): a row is drawn
// again only moved by whole device pixels, as its laying out there would set its words and boxes.
//
// Drawn again, it says again what its build and its paint said of the frame, taken by their ranges and said again by
// one rule (said.mbt): what takes the focus, what asks for a menu, the pointer's shape, what is told outside, its
// targets (where presses, the wheel and the pointer go) and the rest of the frame's lists; and its words. A list's rows
// say what their builds said in their order, built or drawn again (Ctx::row_build_said). Its instances are recorded in
// the band (its list's clip as built, row_reach past it) unclipped by its list, and put in its list's clip as it is
// drawn (kept_clip_into), built or drawn again alike, what its paint said too (only what shows there): a row drawn again
// is drawn as its build would draw it there. A part drawn again holds the rows it drew (kept_part.mbt).

///|
/// How far past its list's clip a row's build draws what is recorded of it (the band): what it may scroll by before
/// it is built again, where it is taller than its list.
let row_reach : Double = 480.0

///|
/// What a row kept holds besides its drawing (KeptPart's `row`): where it was built, what of it was drawn, and what its
/// build and its paint said of the frame, said again each frame it is drawn again.
priv struct RowKept {
  /// its list's id, its item; the part its list was built in (0: none), which drawn again draws it again with it
  list : Int
  item : Int
  mut part : Int
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
  /// this pass: drawn again (not built), its node; how far below where it was built it is drawn, and how far down its
  /// list's rows (on_drawn_again's)
  mut kept : Bool
  mut node : Int
  mut dy : Double
  mut rel : Double
  /// where its box was as it was last drawn (x, y, w, h: the pointer over it lights what it points at)
  mut last : (Double, Double, Double, Double)
  /// the words it marked (Ctx::words), as laid out
  words : Array[(String, Words)]
  /// how its list builds a row (Ctx::list's `row`, this build's): its part's build runs it
  mut build : (Int) -> Unit
  /// how far down its list's rows it was as its build was drawn (ListState::above)
  mut above : Double
  /// what it says to what reads the widgets out (SemNode, as its build said it: where, from its node; under what, among
  /// its own, -1 what holds it; how deep, below what holds it), and whether that was taken since it was last built
  sems : Array[SemNode]
  mut read_out : Bool
  /// the words its build held, as what holds it is named by them (Ctx::words_in), and as a box pressed is (own_words)
  mut read_words : String
  mut read_own : String
}

///|
fn RowKept::new(list : Int, item : Int) -> RowKept {
  {
    list,
    item,
    part: 0,
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
    rel: 0.0,
    last: (0.0, 0.0, 0.0, 0.0),
    words: [],
    build: fn(_) {  },
    above: 0.0,
    sems: [],
    read_out: false,
    read_words: "",
    read_own: "",
  }
}

///|
/// What its build says of the frame, from none (its build runs again; what is said of it in the frame's build lists is
/// its part's: kept_new).
fn RowKept::build_starts(self : RowKept) -> Unit {
  self.words.clear()
  self.sticks.clear()
  self.held = false
  self.sems.clear()
  self.read_out = false
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
/// (its id), the build, its rows' key.
priv struct RowsRound {
  mut list : Int
  mut build : Int
  mut key : String
}

///|
// kept across runs: worked out anew for each list and build (Ctx::rows_round)
let rows_round : RowsRound = { list: 0, build: -1, key: "" }

///|
/// Whether a part kept and a list's row kept may be drawn again (a test's: false, each built every frame, its drawing
/// taken as when it is kept: what drawing it again must match).
// kept across runs: put back by each Tester (Tester::new)
let drawn_again_on : Ref[Bool] = Ref(true)

///|
/// Whether a list's rows may be kept this frame, and are laid on the device's pixels (Ctx::rows_on_pixels, row_slot):
/// as parts are (a host's always, a Tester's where it keeps parts: what every frame builds is laid as it always was),
/// and not while anything reads what each frame builds as it was (a test's instance owners, a test lighting
/// everything). What reads the widgets out (a screen reader) reads a row kept as its build said it (semantics.mbt's
/// row_read_out).
fn Ctx::rows_on(self : Ctx) -> Bool {
  parts_on.val && !inst_owners.on && !self.lit_every
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
      let st = kept_new(id, row=true)
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
  // (while a press is held but by the list's own drag, none of them is drawn again: each built as where none is kept,
  // nothing of its drawing taken)
  if self.down && !(self.dragging && st.held) {
    kp.built = -1
    // (what its build says of the frame said where its list's rows say theirs, as of a row built to be kept)
    self.build_marks(kp.built_marks)
    let r = self.build_row(li, st, k)
    self.build_take(kp.built_marks, kp.built_said, cut=true)
    rk.part = st.part
    // (what its list's clip leaves nothing of dropped, as of a row built to be kept)
    let e = self.drawn_of(r)
    e.row = -1
    e.said_row = id
    return r
  }
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
    // (read out: what it said taken as it was built, else built so that it is)
    (rk.read_out || !self.reads_out)
  rk.build = st.row
  rk.part = st.part
  if !same {
    kp.tracker.invalidate()
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
  let r = self.alloc_part(kind_box, true, true, key=item_key(k))
  self.nodes[r].item = k
  // (in a part kept: what the row tells moves the part's too, kept_part.mbt)
  let (row_was, part_was) = (part_now.row, part_now.part)
  part_now.row = id
  part_now.part = st.part
  let mut ran = false
  self.with_parent(r, fn() {
    self.scope(k, fn() {
      // (its computed none of what holds it reads, else what holds it would run the row's build to see whether it
      // changed, out of its list's layout)
      let reading = @signals.set_active_sub(None)
      let stamp = kp.tracker.get()
      @signals.set_active_sub(reading) |> ignore
      if stamp != kp.stamp {
        ran = true
        kp.stamp = stamp
      }
    })
  })
  part_now.row = row_was
  part_now.part = part_was
  // what it read, built or drawn again, read by the part its list is in: built before its rows are laid, it is drawn
  // again only while nothing they show changed (a row that holds a list of its own is built each frame: its list's
  // rows' are the part's alone)
  if st.part != 0 {
    match kept_parts.get(st.part) {
      Some(p) => kp.tracker.lend(p.tracker)
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
  e.said_row = id
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
    // (what its build read of the layout, the part's its list is in too: drawn again with it later, the part keeps it)
    if st.part != 0 {
      match kept_parts.get(st.part) {
        Some(p) => {
          for id, rect in kp.reads.laid {
            p.reads.laid[id] = rect
          }
          for id, v in kp.reads.shown {
            p.reads.shown[id] = v
          }
          for id, v in kp.reads.left {
            p.reads.left[id] = v
          }
        }
        None => ()
      }
    }
  }
  r
}

///|
/// What the rows of list `list` (`st`, `iw` wide) are kept by in this build (RowsRound), worked out at its first row:
/// their key (its width, its rows' count, its scope, picking, its layer, its direction, what the press is on: one taken
/// from it, as the list takes the drag, shows it pressed no more; the theme each build works out anew from what changes
/// only by what builds it again: a setting, the system, a motion).
fn Ctx::rows_round(self : Ctx, list : Int, st : ListState, iw : Double) -> RowsRound {
  let r = rows_round
  if r.list == list && r.build == self.build_no {
    return r
  }
  r.list = list
  r.build = self.build_no
  r.key = "\{iw} \{st.count} \{st.seed} \{st.owner} \{st.sel} \{st.layer} \{st.direction} \{self.active} \{self.down}"
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
      Some(e) => {
        // built: what its build said, said in its rows' order
        match kept_rows.get(e.said_row) {
          Some(b) => self.row_build_said(b, r)
          None => ()
        }
        continue
      }
      None => continue
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
    // (moved by whole device pixels, as its list lays rows (Ctx::rows_on_pixels): laid out there, its words and boxes
    // would be set on the pixels as they are)
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
      rk.rel = st.above(n.item) - rk.above
      self.row_build_said(kp, r)
      self.drawn_again_told((1, kp.id), 0.0, dy, rk.rel)
      continue
    }
    // built where it is
    let k = n.item
    let r2 = self.row_of(li, st, k, iw, force=true)
    let h = self.row_slot(r2, self.layout(r2, ix, n.y, iw, nan))
    if h != n.fh {
      moved = moved + (h - n.fh)
      st.set_height(k, h)
    }
    self.nodes[r2].parent = li
    order[j] = r2
    built = true
    self.row_build_said(kp, r2)
  }
  built
}

///|
/// What row `kp`'s build said of the frame (its node `r` now), said where its list's rows say theirs, in their order,
/// built or drawn again (its targets are said as it is painted); the part its list is in told it said it there, to say
/// it again there as it is drawn again.
fn Ctx::row_build_said(self : Ctx, kp : KeptPart, r : Int) -> Unit {
  self.say_again(kp.built_said, moved_to(r))
  match kp.row {
    Some(rk) if rk.part != 0 =>
      match kept_parts.get(rk.part) {
        Some(p) => p.rows_said.push(kp.id)
        None => ()
      }
    _ => ()
  }
}

///|
/// Row `id`'s build (node `i`) painted, as its list paints it: in the band (its list's clip, row_reach past it both
/// ways, nothing else of its list's), what it draws and what it says of the frame taken; then put in its list's clip,
/// as what drawing it again puts there (what it said, said in it by the rule it is said again by: said.mbt's Moved).
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
  let g0 = self.segs.length()
  let a0 = self.across_seen.length()
  let t0 = dr.tops.length()
  let o0 = dr.overlay.length() + dr.raised.length()
  kp.plots.clear()
  kp.plot_seen.clear()
  kp.images.clear()
  self.paint_marks(kp.marks)
  // (the band: a clip of its own, nothing of its list's, nor any outer)
  for v in [x0, y0 - row_reach, x1, y1 + row_reach] {
    clip_stack.push(v)
  }
  for _ in 0..<20 {
    clip_stack.push(0.0)
  }
  kept_cuts.push(k)
  let was = part_now.painting_row
  part_now.painting_row = id
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  part_now.painting_row = was
  kept_cuts.pop() |> ignore
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
  // (how far down its list's rows: what a package keeps of it is kept as it moves among them, on_drawn_again)
  if n.parent >= 0 {
    match self.lists.get(self.nodes[n.parent].id) {
      Some(ls) => rk.above = ls.above(n.item)
      None => ()
    }
  }
  rk.band0 = y0 - row_reach
  rk.band1 = y1 + row_reach
  rk.band_l = x0
  rk.band_r = x1
  rk.dy = 0.0
  rk.rel = 0.0
  // what its paint said, as said in the band: what the hand is found on; what is said again, said now in its list's
  // clip as it is when it is drawn again
  self.take_found(kp)
  self.paint_take(kp.marks, kp.said)
  self.paint_cut(kp.marks)
  self.say_again(kp.said, rk.moved(0.0, k))
  // (what must be built each frame: drawn over everything, a scroll bar of its rows', a native view's hole, a field, a
  // list of its own)
  rk.keepable = rk.keepable &&
    dr.tops.length() == t0 &&
    dr.overlay.length() + dr.raised.length() == o0 &&
    self.across_seen.length() == a0 &&
    !kp.holds_native() &&
    !self.holds_built(i)
  // in its list's clip
  self.kept_clip_into(k, i0, g0, drops=dr.tops.length() == t0 && dr.overlay.length() + dr.raised.length() == o0)
  rk.last = (n.x, n.y, n.fw, n.fh)
  kp.lit = self.part_lit(kp)
}

///|
/// Where what row `self`'s paint said is said: `dy` below where it was built, in the clip at `k` (its list's).
fn RowKept::moved(self : RowKept, dy : Double, k : Int) -> Moved {
  {
    dx: 0.0,
    dy,
    cut: k,
    band_l: self.band_l,
    band_t: self.band0,
    band_r: self.band_r,
    band_b: self.band1,
    node: -1,
    by: 0,
  }
}

///|
/// What of row `self` was recorded (its band: left, top, right, bottom).
fn RowKept::band(self : RowKept) -> (Double, Double, Double, Double) {
  (self.band_l, self.band0, self.band_r, self.band1)
}

///|
/// Row part `kp` drawn again (node `i`), as its build drew it, moved down by how far its node is below where it was
/// built: its instances, and what its paint said of the frame (said.mbt); put in its list's clip.
fn Ctx::row_paint_again(self : Ctx, i : Int, kp : KeptPart) -> Unit {
  let rk = kp.row.unwrap()
  let dy = self.nodes[i].y - rk.y
  rk.dy = dy
  let k = clip_top()
  let i0 = self.ninst
  let g0 = self.segs.length()
  if dr.mode != mode_hits {
    self.insts_again(kp)
    self.insts_moved(i0, rk.band(), 0.0, dy)
  }
  self.say_again(kp.said, rk.moved(dy, k))
  self.kept_clip_into(k, i0, g0, drops=true)
  let n = self.nodes[i]
  rk.last = (n.x, n.y, n.fw, n.fh)
}

///|
/// What a row or a part drew from instance `i0`, in its band (its shapes' pieces from `g0`, in the frame's `segs`), put
/// in the clip at `k` (its list's, the part's): each cut by it where they meet (clip_into); with `drops` (nothing of it
/// put off to be drawn over everything), what it leaves nothing of dropped (kept_drop). (What it said of the frame is
/// put there as it is said: said.mbt's Moved.)
fn Ctx::kept_clip_into(self : Ctx, k : Int, i0 : Int, g0 : Int, drops~ : Bool) -> Unit {
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
    self.kept_drop(i0, g0)
  }
}

///|
/// The clips what is being recorded in its band is put in (Ctx::kept_clip_into), the innermost last: a part's, a list's
/// row's, as it is painted.
// kept across runs: pushed and popped round each recording's paint
let kept_cuts : Array[Int] = []

///|
/// The clip being painted in, as what is drawn in it shows (put in each clip what is recorded is put in: kept_cuts): its
/// rect, its corners' radii. Not what is recorded (that is drawn as wherever it is put), but what is put outside the
/// drawing where it shows (a native view, put in the window by the host) reads this.
fn clip_shown() -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) {
  let k = clip_top()
  let c = shown_scratch
  for m in 0..<24 {
    c[m] = clip_stack[k + m]
  }
  for j = kept_cuts.length() - 1; j >= 0; j = j - 1 {
    clip_into(kept_cuts[j], c)
  }
  ((c[0], c[1], c[2], c[3]), (c[4], c[5], c[6], c[7]))
}

///|
/// A clip's 24 numbers, worked on in place (clip_shown).
// kept across runs: scratch, written before it is read
let shown_scratch : FixedArray[Double] = FixedArray::make(24, 0.0)

///|
/// A clip's 24 numbers, worked on in place (Ctx::kept_clip_into).
// kept across runs: scratch, written before it is read
let clip_scratch : FixedArray[Double] = FixedArray::make(24, 0.0)

///|
/// A clip `c` (a level's 24 numbers: its rect, its corners' radii, how smooth they are, its outer's 12) as what is in
/// the clip at `k` (in `clip_stack`) is cut where they meet, by the rule a clip pushed in it is (push_round_clip,
/// push_clip_r): their rects' intersection; each corner its own where it is still its own (the rounder where it is also
/// the outer clip's), else the outer clip's where it is that one's, else square; its outer, of its own, that clip and
/// that clip's outer, the one whose curves cut into it (push_clip_r's rule), none where none does. One that holds that clip's rect whole, square and
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
  c[0] = x0
  c[1] = y0
  c[2] = x1
  c[3] = y1
  // its outer: of its own, that clip and that clip's outer, the one whose curves cut into it (push_clip_r's rule)
  let r = (c[4], c[5], c[6], c[7])
  let sm = (c[8], c[9], c[10], c[11])
  let beyond = clip_has_outer(k)
  let apart = beyond && clip_is_apart(k)
  let own = if c[16] > 0.0 || c[17] > 0.0 || c[18] > 0.0 || c[19] > 0.0 {
    clip_cut_depth(c, 12, x0, y0, x1, y1, r, sm)
  } else {
    -1.0e9
  }
  let mut most = dmax(own, clip_cut_least)
  let mut from = if own > clip_cut_least { -2 } else { -1 }
  for o in if beyond && !apart { [k, k + 12] } else { [k] } {
    let d = clip_cut_depth(s, o, x0, y0, x1, y1, r, sm)
    if d > most {
      most = d
      from = o
    }
  }
  if from >= 0 || (from == -1 && apart) {
    let from = if from >= 0 { from } else { k + 12 }
    for m in 0..<12 {
      c[12 + m] = s[from + m]
    }
  } else if from == -1 {
    for m in 12..<24 {
      c[m] = 0.0
    }
  }
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
            Some(was) if (was.text != w.1.text || !same_shape(was.pieces, pieces)) &&
              self.words_shape_reads.contains(w.0) => self.read_changed("words_shape_of \"" + w.0 + "\"")
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
/// A clip's rect (from `at` in `a`: x0 y0 x1 y1) moved `dx` across and `dy` down, but for its edges that are `band`'s
/// (left, top, right, bottom), a recording's own and not what cuts it: those as far off as nothing cuts, so that the
/// clip it is drawn again in cuts it there as it would have cut its build there.
fn unband(
  a : FixedArray[Double],
  at : Int,
  band : (Double, Double, Double, Double),
  dx : Double,
  dy : Double,
) -> Unit {
  let (l, t, r, b) = band
  a[at] = if a[at] == l { -1.0e9 } else { a[at] + dx }
  a[at + 1] = if a[at + 1] == t { -1.0e9 } else { a[at + 1] + dy }
  a[at + 2] = if a[at + 2] == r { 1.0e9 } else { a[at + 2] + dx }
  a[at + 3] = if a[at + 3] == b { 1.0e9 } else { a[at + 3] + dy }
}

///|
/// What a row or a part drew again from instance `i0` to the frame's last, as recorded in `band`: moved `dx` across and
/// `dy` down, its rects, its clips (what of them was the band's let go of: unband), their outers and the points they
/// turn about with it.
fn Ctx::insts_moved(self : Ctx, i0 : Int, band : (Double, Double, Double, Double), dx : Double, dy : Double) -> Unit {
  let a = self.inst
  for q in i0..<self.ninst {
    let b = q * inst_size
    a[b] = a[b] + dx
    a[b + 1] = a[b + 1] + dy
    unband(a, b + 16, band, dx, dy)
    inst_fade_moved(a, b, 0.0, 1.0, dy)
    inst_fade_moved_across(a, b, 0.0, 1.0, dx)
    // (its outer, where it has one)
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
/// What a row or a part drew from instance `i0` (its shapes' pieces from `g0`), each in its clip, of which it leaves
/// nothing: dropped, the pieces of the shapes kept alone kept, in order (glass, and what lies between its first and
/// its last, kept: their runs are the frame's). What of a row is drawn is what shows in its list, built (in the band
/// past it, or plainly) or drawn again; of a part, what shows where it is drawn.
fn Ctx::kept_drop(self : Ctx, i0 : Int, g0 : Int) -> Unit {
  let a = self.inst
  let mut glass0 = self.ninst
  let mut glass1 = -1
  for q in i0..<self.ninst {
    let kind = a[q * inst_size + 5]
    if kind == 5.0 || kind == 6.0 || kind == 7.0 {
      if q < glass0 {
        glass0 = q
      }
      glass1 = q
    }
  }
  let mut w = i0
  for q in i0..<self.ninst {
    let b = q * inst_size
    let kind = a[b + 5]
    if q >= glass0 && q <= glass1 {
      if w != q {
        a.blit_to(a, len=inst_size, src_offset=b, dst_offset=w * inst_size)
      }
      w = w + 1
      continue
    }
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
/// (node `i`): what its list's clip leaves nothing of dropped, as of a row built in its band (Ctx::kept_drop).
fn Ctx::row_paint_plain(self : Ctx, i : Int, alpha : Double) -> Unit {
  let i0 = self.ninst
  let g0 = self.segs.length()
  let t0 = dr.tops.length()
  let o0 = dr.overlay.length() + dr.raised.length()
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  if dr.tops.length() == t0 && dr.overlay.length() + dr.raised.length() == o0 {
    self.kept_drop(i0, g0)
  }
}
