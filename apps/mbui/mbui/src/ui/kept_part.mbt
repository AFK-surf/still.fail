// A part kept as it was drawn while nothing it shows can have changed (Ctx::kept_part): what the view builds is built
// every frame, but a part nobody uses where it is (a panel behind the one in use, on still.fail's tape) changes only
// by what comes from outside the hand on another part: the core's data, a timer, the system, a press or a key; its
// size and its ground; or what it said changes with time (a motion of its own, a cycle, a wake). A frame with none of
// those (a list elsewhere scrolled, by a finger or a wheel, flung on) draws it again from what its last build drew,
// not built, laid out nor painted anew: its instances as they were, where they were. (Zed's GPUI keeps a view so,
// `AnyView::cached`: its last frame's paint replayed while it was not notified and its bounds are the same.)
//
// What it read of the core and of what was worked out of it (mbui/signals) is followed as it is built: a computed of
// its own runs its build, so a topic it read changed builds it again whatever else said, and what it read stays kept
// while it shows (what follows a computed keeps it). What is not a signal is caught by what changes it: an event from
// outside (outside_events: what the host or the runtime did, not a pointer moved nor a wheel turned elsewhere), its
// `key` (what it is built from by its caller), the layout's epoch, what moves what it holds (its own motions, and what
// moves a list or a box built in it, whenever it was told: a list flung before the part was kept flings on in it), its
// wakes, a press held down on it or a wheel turned over it (what it holds may take them), the mouse's pointer over it
// (it lights what it points at). It is built whole the first frames it shows, while a motion going on as it came may
// still move what it holds. Drawn again, what its build's paint said of the frame is said again, where it was: its
// targets, what scrolls in it, the words that can be picked, so presses, the wheel and the pointer find in it what they
// found as it was built. It is never read out, built or not, so what is read out does not come and go with it.

///|
/// A part kept (Ctx::kept_part): what its build drew (its instances, where they were; the pieces of its shapes; the
/// glyphs' plots and the pictures they draw from), the computed its build runs in, and what it was built from.
priv struct KeptPart {
  id : Int
  /// its build's instances (the first `floats` numbers), the pieces of their shapes
  mut insts : FixedArray[Double]
  mut floats : Int
  segs : Array[Double]
  /// the atlases' plots its glyphs are drawn from (colour ones by part_colour_plot), the pictures it shows
  plots : Array[Int]
  plot_seen : Map[Int, Bool]
  images : Array[ImageEntry]
  /// its build, run by `tracker` as what it read changes or `force` is said; the build now, and what the tracker
  /// answered as it last ran it
  tracker : @signals.Computed[Int]
  force : @signals.Signal[Int]
  body : Ref[() -> Unit]
  mut forced : Int
  mut stamp : Int
  /// what it was built from: its caller's key, the events from outside seen, the layout's epoch, the scale, the hand
  mut key : String
  mut outside : Int
  mut epoch : Int
  mut scale : Double
  mut pointing : Pointing
  /// the frame it was built in (-1: not yet), the frame its build was drawn in (painted, its instances taken), the
  /// frame it last showed in
  mut built : Int
  mut drawn : Int
  mut shown : Int
  /// what its build asked of time: a frame each frame (a motion it set out, a cycle drawn each frame, a frame owed, a
  /// layer opened, back taken, a picture of the system's, the focus), the earliest wake it asked for and whether what is
  /// shown waits for it
  mut live : Bool
  mut due : Double
  mut due_later : Bool
  /// the motions going on as it first showed: it is built while any of them still goes
  waits : Array[MoverEntry]
  /// drawn again this frame (not built)
  mut again : Bool
  /// a Tester's: the words its build drew (KeptWord), what the Tester finds in it while it is drawn again
  words : Array[KeptWord]
  /// what its build drew covers (x, y, w, h: its instances where they show): a press held or a wheel turned there is
  /// its; the mouse's pointer there lights what is in it
  mut rect : (Double, Double, Double, Double)
  /// what its build's paint said of the frame, said again as it is drawn again: its targets (where presses go: their
  /// ids, their ends from the first, their rects, their clips), what is only pointed at, what scrolls (ids, rects), the
  /// paragraphs that can be picked; where they began among the frame's as it was painted
  hit_ids : Array[Int]
  hit_ends : Array[Int]
  hit_rects : Array[Double]
  hit_clips : Array[Double]
  points : Array[Int]
  scroll_ids : Array[Int]
  scroll_rects : Array[Double]
  sels : Array[SelTarget]
  mut from : (Int, Int, Int)
  /// whether what the pointer is over was one of its targets as it was built (Ctx::hovered: it lights what it points
  /// at)
  mut lit : Bool
  /// a list's row kept (kept_rows.mbt): what more it keeps; None a part's
  mut row : RowKept?
}

///|
/// Words a part kept drew as it was built, as a Tester finds words (Tester::find, rect_of, words): the node's words,
/// where it is laid out (x, y, w, h), where it is drawn and how opaque.
priv struct KeptWord {
  text : String
  x : Double
  y : Double
  w : Double
  h : Double
  drawn_x : Double
  drawn_y : Double
  alpha : Double
}

///|
/// The part being built now (0 none) and what its build asks of time; the part whose build is being painted (0 none);
/// the same of a list's row kept (kept_rows.mbt: its id among the rows').
priv struct PartNow {
  mut part : Int
  mut live : Bool
  mut due : Double
  mut due_later : Bool
  mut painting : Int
  mut row : Int
  mut painting_row : Int
}

///|
// kept across runs: set round each part's build and paint and put back after it
let part_now : PartNow = {
  part: 0,
  live: false,
  due: @double.infinity,
  due_later: true,
  painting: 0,
  row: 0,
  painting_row: 0,
}

///|
/// The parts kept, by id, and the run (its Ctx) they are kept in.
// kept across runs: let go of as another run's first frame begins (parts_frame_start)
let kept_parts : Map[Int, KeptPart] = {}

///|
priv struct PartsRun {
  mut ctx : Ctx?
  /// the runtime's steps as the last frame began (an event of its own since then is one from outside)
  mut steps : Int
}

///|
// kept across runs: the run it holds is compared with the frame's as each frame begins (parts_frame_start)
let parts_run : PartsRun = { ctx: None, steps: -1 }

///|
/// How many events have come from outside the hand on another part (kept_part.mbt's head): an input other than a pointer
/// moved or a wheel turned, a message, a host's answer, a step of the runtime's fibers or timers, a test's draw.
// kept across runs: it only counts on
let outside_events : Ref[Int] = Ref(0)

///|
/// An event from outside came (kept_part.mbt's head): every part kept is built anew by the next frame.
fn outside_came() -> Unit {
  outside_events.val = outside_events.val + 1
}

///|
/// Whether parts are kept at all: on a host's frames; off in a Tester's but where a test of them says so
/// (Tester::keep_parts), so what a test reads of a frame's nodes (its words, its boxes, its corners) reads all of it,
/// built: what is drawn again is what was built.
// kept across runs: set by each Tester (Tester::new, keep_parts)
let parts_on : Ref[Bool] = Ref(true)

///|
/// Parts kept as a host keeps them (Ctx::kept_part), from now on, or not (every frame built whole: a Tester's own).
pub fn Tester::keep_parts(self : Tester, on : Bool) -> Unit {
  ignore(self)
  parts_on.val = on
}

///|
/// Whether (x, y) is on a part kept, as the last frame drew it: a wheel turned there is the part's, an event from
/// outside for it (it scrolls in its build).
fn part_under(x : Double, y : Double) -> Bool {
  let frame = g().frame_no
  for _, st in kept_parts {
    let (px, py, pw, ph) = st.rect
    if st.shown == frame && x >= px && x < px + pw && y >= py && y < py + ph {
      return true
    }
  }
  false
}

///|
/// A frame begins: the parts of another run forgotten; the runtime's steps since the last frame an event from outside.
fn parts_frame_start(c : Ctx) -> Unit {
  match parts_run.ctx {
    Some(was) if physical_equal(was, c) => ()
    _ => {
      parts_forget()
      parts_run.ctx = Some(c)
    }
  }
  let steps = fx.val.steps
  if steps != parts_run.steps {
    parts_run.steps = steps
    outside_came()
  }
}

///|
/// The frame is built: the parts that did not show in it let go (what they read no longer kept by them).
fn parts_frame_end(c : Ctx) -> Unit {
  if kept_parts.is_empty() {
    rows_frame_end(c)
    return
  }
  let gone = []
  for id, st in kept_parts {
    if st.shown != c.frame_no {
      gone.push(id)
    }
  }
  for id in gone {
    match kept_parts.get(id) {
      Some(st) => st.tracker.dispose()
      None => ()
    }
    kept_parts.remove(id) |> ignore
  }
  rows_frame_end(c)
}

///|
fn parts_forget() -> Unit {
  for _, st in kept_parts {
    st.tracker.dispose()
  }
  kept_parts.clear()
  for _, st in kept_rows {
    st.tracker.dispose()
  }
  kept_rows.clear()
  row_ids.clear()
  part_now.part = 0
  part_now.painting = 0
  part_now.row = 0
  part_now.painting_row = 0
}

///|
/// What `body` builds, in a box of its own filling the one being built (out of the flow: the one being built laid out
/// as if it held nothing else), not read out, and kept: built again only once something it shows can have changed
/// (kept_part.mbt's head), else drawn again as its last build drew it, nothing of it built. `id` names it; `key` is what
/// its caller builds it from besides what it reads (its size, where it is, its ground: what else changes it), another
/// key building it anew. For a part nobody uses where it is (a panel behind the one in use).
pub fn Ctx::kept_part(self : Ctx, id : Int, key : String, body : () -> Unit) -> Unit {
  let st = match kept_parts.get(id) {
    Some(st) => st
    None => {
      let st = kept_new(id)
      kept_parts[id] = st
      st
    }
  }
  // (shown in the frame before, or in this one's build before: else it comes now, the motions going on waited for)
  // (what moves asked as the last frame left it: this frame's build has not said yet what it moves, a list not built
  // yet says it is at rest)
  let last = self.frame_no - 1
  if st.shown < last {
    st.built = -1
    st.waits.clear()
    for e in self.movers {
      if e.m.rest_at(self.now, last) > self.now {
        st.waits.push(e)
      }
    }
  }
  st.shown = self.frame_no
  st.waits.retain(fn(e) { e.m.rest_at(self.now, last) > self.now })
  // (what moves what it holds, told as it was built or not: a list in it flung before it was kept)
  let moving = self.movers.iter().any(fn(e) {
    (e.part == id || e.who.part == id) && e.m.rest_at(self.now, last) > self.now
  })
  // (a finger or a button held down on it: what it holds may take the press, a hold picking its words)
  let (rx, ry, rw, rh) = st.rect
  let held = self.down &&
    self.press_x >= rx &&
    self.press_x < rx + rw &&
    self.press_y >= ry &&
    self.press_y < ry + rh
  // (the mouse's pointer over it, or what the pointer is over one of its targets as it was built or now: it lights what
  // it points at, a frame late)
  let pointed = st.lit ||
    self.part_lit(st) ||
    (pointing() is Mouse && self.px >= rx && self.px < rx + rw && self.py >= ry && self.py < ry + rh)
  let same = parts_on.val &&
    drawn_again_on.val &&
    !held &&
    !pointed &&
    !inst_owners.on &&
    st.built >= 0 &&
    st.built != self.frame_no &&
    st.drawn == st.built &&
    st.key == key &&
    st.outside == outside_events.val &&
    st.epoch == self.epoch &&
    st.scale == self.scale &&
    st.pointing == pointing() &&
    !st.live &&
    self.now < st.due &&
    st.waits.is_empty() &&
    !moving
  st.body.val = body
  if !same {
    st.forced = st.forced + 1
    st.force.set(st.forced)
  }
  let mut ran = false
  let i = self.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
    let (part, live, due, due_later) = (part_now.part, part_now.live, part_now.due, part_now.due_later)
    let layers = self.layers.length()
    let back = self.back_next
    part_now.part = id
    part_now.live = false
    part_now.due = @double.infinity
    part_now.due_later = true
    // (not read out: it is only drawn, built or drawn again alike)
    self.hidden_from_semantics(fn() {
      let stamp = st.tracker.get()
      if stamp != st.stamp {
        ran = true
        st.stamp = stamp
        st.live = part_now.live ||
          self.layers.length() != layers ||
          !physical_equal(self.back_next, back)
        st.due = part_now.due
        st.due_later = part_now.due_later
      }
    })
    // (what holds it asks what it asked of time)
    part_now.part = part
    part_now.live = live || part_now.live
    if part_now.due >= due {
      part_now.due = due
      part_now.due_later = due_later
    }
  })
  let e = self.drawn_of(i)
  st.again = !ran
  if ran {
    st.built = self.frame_no
    st.key = key
    st.outside = outside_events.val
    st.epoch = self.epoch
    st.scale = self.scale
    st.pointing = pointing()
    // what it draws taken as it is painted
    e.part = id
  } else {
    // drawn again: what it draws from kept through this frame, the frame it asked for coming
    e.again = Some(st)
    for p in st.plots {
      if p >= part_colour_plot {
        atlas_for(true).0.drawn(p - part_colour_plot)
      } else {
        atlas_for(false).0.drawn(p)
      }
    }
    for img in st.images {
      img.used = self.frame_no
    }
    // (what holds it, a part or a row being built, told as its own build would: part_wake)
    if st.due < @double.infinity {
      self.wake_at_time(st.due, later=st.due_later)
    }
  }
}

///|
/// A part kept, not built yet: its build run by a computed of its own (`body` as it is set, again as what it read
/// changes or `force` is said).
fn kept_new(id : Int) -> KeptPart {
  let force = @signals.signal(0)
  let body_now : Ref[() -> Unit] = Ref(fn() {  })
  {
    id,
    insts: FixedArray::make(0, 0.0),
    floats: 0,
    segs: [],
    plots: [],
    plot_seen: {},
    images: [],
    tracker: @signals.computed(fn(_) {
      force.get() |> ignore
      (body_now.val)()
      part_stamp.val = part_stamp.val + 1
      part_stamp.val
    }),
    force,
    body: body_now,
    forced: 0,
    stamp: 0,
    key: "",
    outside: -1,
    epoch: -1,
    scale: 0.0,
    pointing: Finger,
    built: -1,
    drawn: -1,
    shown: -1,
    live: false,
    due: @double.infinity,
    due_later: true,
    waits: [],
    again: false,
    words: [],
    rect: (0.0, 0.0, 0.0, 0.0),
    hit_ids: [],
    hit_ends: [],
    hit_rects: [],
    hit_clips: [],
    points: [],
    scroll_ids: [],
    scroll_rects: [],
    sels: [],
    from: (0, 0, 0),
    lit: false,
    row: None,
  }
}

///|
/// The tracker's answers, one more each time a part's build runs.
// kept across runs: it only counts on
let part_stamp : Ref[Int] = Ref(0)

///|
/// Plots of the colour atlas, as a part keeps them (KeptPart.plots): past those of the other.
let part_colour_plot : Int = 1 << 20

///|
/// How many parts the last frame drew again as their last build drew them (Ctx::kept_part), not built.
pub fn Tester::parts_kept(self : Tester) -> Int {
  ignore(self)
  let c = g()
  let mut n = 0
  for _, st in kept_parts {
    if st.shown == c.frame_no && st.again {
      n = n + 1
    }
  }
  n
}

///|
/// Whether part `id` was drawn again this frame, as its last build drew it, not built.
pub fn Ctx::part_kept(self : Ctx, id : Int) -> Bool {
  ignore(self)
  match kept_parts.get(id) {
    Some(st) => st.shown == self.frame_no && st.again
    None => false
  }
}

///|
/// What `build` (a row of a list in part `part`, built as the list is laid out, after the part's own build) asks of
/// time, the part's (0: no part's).
fn part_rows(part : Int, build : () -> Unit) -> Unit {
  if part == 0 || part_now.part == part {
    build()
    return
  }
  let (was, live, due, due_later) = (part_now.part, part_now.live, part_now.due, part_now.due_later)
  part_now.part = part
  part_now.live = false
  part_now.due = @double.infinity
  part_now.due_later = true
  build()
  match kept_parts.get(part) {
    Some(st) => {
      st.live = st.live || part_now.live
      if part_now.due < st.due {
        st.due = part_now.due
        st.due_later = part_now.due_later
      }
    }
    None => ()
  }
  part_now.part = was
  part_now.live = live
  part_now.due = due
  part_now.due_later = due_later
}

///|
/// Whether what is built now is kept as it was built: a part's build, or a list's row's (kept_rows.mbt), a row on its own
/// as much as one in a part (on 小屏 a chat's messages are in none): what it asks of time is its own.
fn part_building() -> Bool {
  part_now.part != 0 || part_now.row != 0
}

///|
/// What the build of the part or row being built asks of time: a frame each frame from now on (as what it holds
/// moves).
fn part_live() -> Unit {
  if part_building() {
    part_now.live = true
  }
}

///|
/// The build of the part or row being built asks for a frame at `t` (`later`: what is shown does not wait for it).
fn part_wake(t : Double, later : Bool) -> Unit {
  if part_building() && t < part_now.due {
    part_now.due = t
    part_now.due_later = later
  }
}

///|
/// Picture `e` drawn, as a part's build is painted.
fn part_image(e : ImageEntry) -> Unit {
  // (a row's in a part's: both's)
  if part_now.painting != 0 {
    match kept_parts.get(part_now.painting) {
      Some(st) => st.image_used(e)
      None => ()
    }
  }
  if part_now.painting_row != 0 {
    match kept_rows.get(part_now.painting_row) {
      Some(st) => st.image_used(e)
      None => ()
    }
  }
}

///|
fn KeptPart::image_used(self : KeptPart, e : ImageEntry) -> Unit {
  for x in self.images {
    if physical_equal(x, e) {
      return
    }
  }
  self.images.push(e)
}

///|
/// A glyph drawn from `plot` of the colour atlas or the other, as a part's build is painted.
fn part_plot(colour : Bool, plot : Int) -> Unit {
  let p = if colour { plot + part_colour_plot } else { plot }
  // (a row's in a part's: both's)
  if part_now.painting != 0 {
    match kept_parts.get(part_now.painting) {
      Some(st) => st.plot_used(p)
      None => ()
    }
  }
  if part_now.painting_row != 0 {
    match kept_rows.get(part_now.painting_row) {
      Some(st) => st.plot_used(p)
      None => ()
    }
  }
}

///|
fn KeptPart::plot_used(self : KeptPart, p : Int) -> Unit {
  if !self.plot_seen.contains(p) {
    self.plot_seen[p] = true
    self.plots.push(p)
  }
}

///|
/// Part `id`'s build about to be painted from instance `i0`: its plots taken anew as its glyphs are drawn.
fn Ctx::part_paint_begin(self : Ctx, id : Int) -> Int {
  let was = part_now.painting
  match kept_parts.get(id) {
    Some(st) => {
      st.plots.clear()
      st.plot_seen.clear()
      st.images.clear()
      st.points.clear()
      st.from = (self.next_hit_ids.length(), self.next_scroll_ids.length(), desk.next_sels.length())
    }
    None => ()
  }
  part_now.painting = id
  was
}

///|
/// Part `id`'s build painted (its box node `node`), instances `i0` to the frame's last so far: kept as they are, where
/// they are, with the pieces of their shapes.
fn Ctx::part_paint_end(self : Ctx, id : Int, node : Int, i0 : Int, was : Int) -> Unit {
  part_now.painting = was
  match kept_parts.get(id) {
    Some(st) => {
      self.take_said(st)
      st.lit = self.part_lit(st)
      st.take_insts(self, i0)
      st.drawn = self.frame_no
      // (a Tester's: its words, found while it is drawn again)
      st.words.clear()
      if fake.val is Some(_) {
        st.words.append(self.part_words(node))
      }
    }
    None => ()
  }
}

///|
/// What part `st`'s paint said of the frame from where it began (`from`) taken: its targets, what scrolls in it, its
/// paragraphs that can be picked (what is only pointed at is taken as it is said: Ctx::point_said).
fn Ctx::take_said(self : Ctx, st : KeptPart) -> Unit {
  let (h0, s0, sel0) = st.from
  st.hit_ids.clear()
  st.hit_ends.clear()
  st.hit_rects.clear()
  st.hit_clips.clear()
  for h in h0..<self.next_hit_ids.length() {
    st.hit_ids.push(self.next_hit_ids[h])
    st.hit_ends.push(self.next_hit_ends[h] - h0)
  }
  for v in (h0 * 4)..<self.next_hit_rects.length() {
    st.hit_rects.push(self.next_hit_rects[v])
  }
  for v in (h0 * clip_n)..<self.next_hit_clips.length() {
    st.hit_clips.push(self.next_hit_clips[v])
  }
  st.scroll_ids.clear()
  st.scroll_rects.clear()
  for j in s0..<self.next_scroll_ids.length() {
    st.scroll_ids.push(self.next_scroll_ids[j])
  }
  for v in (s0 * 4)..<self.next_scroll_rects.length() {
    st.scroll_rects.push(self.next_scroll_rects[v])
  }
  st.sels.clear()
  for j in sel0..<desk.next_sels.length() {
    st.sels.push(desk.next_sels[j])
  }
}

///|
/// `id` is only pointed at (Ctx::box `points`), said as it is painted: and of the part kept and the list's row kept
/// being painted, said again as they are drawn again.
fn Ctx::point_said(self : Ctx, id : Int) -> Unit {
  self.next_points[id] = true
  if part_now.painting != 0 {
    match kept_parts.get(part_now.painting) {
      Some(st) => st.points.push(id)
      None => ()
    }
  }
  if part_now.painting_row != 0 {
    match kept_rows.get(part_now.painting_row) {
      Some(st) => st.points.push(id)
      None => ()
    }
  }
}

///|
/// Whether what the pointer is over (Ctx::hovered) is one of part `st`'s targets, as its paint said them.
fn Ctx::part_lit(self : Ctx, st : KeptPart) -> Bool {
  if self.hover == 0 && self.hover_in.is_empty() {
    return false
  }
  for id in st.hit_ids {
    if id == self.hover || self.hover_in.contains(id) {
      return true
    }
  }
  false
}

///|
/// The frame's instances from `i0` to its last so far taken as part `self`'s drawing, as they are, where they are, with
/// the pieces of their shapes; what they cover (`rect`).
fn KeptPart::take_insts(self : KeptPart, c : Ctx, i0 : Int) -> Unit {
  let st = self
  let a = c.inst
  let floats = (c.ninst - i0) * inst_size
  if st.insts.length() < floats {
    st.insts = FixedArray::make(floats, 0.0)
  }
  a.blit_to(st.insts, len=floats, src_offset=i0 * inst_size)
  st.floats = floats
  st.segs.clear()
  // (what it covers, where its instances show: their rects within their cuts)
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = -@double.infinity
  let mut y1 = -@double.infinity
  let d = st.insts
  let mut q = 0
  while q < floats {
    if d[q + 5] == 11.0 {
      let first = d[q + 12].to_int()
      d[q + 12] = (st.segs.length() / 4).to_double()
      for v in (first * 4)..<((first + d[q + 13].to_int()) * 4) {
        st.segs.push(c.segs[v])
      }
    }
    let l = dmax(d[q], d[q + 16])
    let t = dmax(d[q + 1], d[q + 17])
    let r = dmin(d[q] + d[q + 2], d[q + 18])
    let b = dmin(d[q + 1] + d[q + 3], d[q + 19])
    if r > l && b > t {
      x0 = dmin(x0, l)
      y0 = dmin(y0, t)
      x1 = dmax(x1, r)
      y1 = dmax(y1, b)
    }
    q = q + inst_size
  }
  st.rect = if x1 > x0 { (x0, y0, x1 - x0, y1 - y0) } else { (0.0, 0.0, 0.0, 0.0) }
}

///|
/// Whether part `self`'s drawing holds a native view's hole (drawn where the view is put each frame: native.mbt).
fn KeptPart::holds_native(self : KeptPart) -> Bool {
  let mut q = 0
  while q < self.floats {
    if self.insts[q + 5] == 9.0 {
      return true
    }
    q = q + inst_size
  }
  false
}

///|
/// The words of what node `root` holds (the part's box), as a Tester finds them.
fn Ctx::part_words(self : Ctx, root : Int) -> Array[KeptWord] {
  let out = []
  let inside = FixedArray::make(self.count, false)
  inside[root] = true
  for i in (root + 1)..<self.count {
    let n = self.nodes[i]
    if n.parent >= 0 && n.parent < self.count && inside[n.parent] {
      inside[i] = true
      if (n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor) && n.text != "" {
        let (x, y) = self.drawn_at(i)
        let mut alpha = 1.0
        let mut p = i
        while p >= 0 {
          alpha = alpha * self.nodes[p].opacity
          match self.drawn_entry(p) {
            Some(e) => alpha = alpha * e.look.alpha
            None => ()
          }
          p = self.nodes[p].parent
        }
        out.push({ text: n.text, x: n.x, y: n.y, w: n.fw, h: n.fh, drawn_x: x, drawn_y: y, alpha })
      }
    }
  }
  out
}

///|
/// The words drawn by the part kept that node `i` stands for this frame (drawn again), as a Tester finds them; none
/// for any other node.
fn Ctx::kept_words_at(self : Ctx, i : Int) -> Array[KeptWord] {
  match self.drawn_entry(i) {
    Some({ again: Some({ row: Some(rk), words, .. }), .. }) =>
      words.map(fn(w) { { ..w, y: w.y + rk.dy, drawn_y: w.drawn_y + rk.dy } })
    Some({ again: Some(st), .. }) => st.words
    _ => []
  }
}

///|
/// Part `st` drawn again: its instances as its build drew them, where they were (its key the same: nothing round it
/// moved), its shapes' pieces among this frame's, its glass frosting captures of this frame's.
fn Ctx::part_paint_again(self : Ctx, st : KeptPart) -> Unit {
  let count = st.floats / inst_size
  while (self.ninst + count + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let i0 = self.ninst
  let a = self.inst
  let base = i0 * inst_size
  st.insts.blit_to(a, len=st.floats, dst_offset=base)
  let seg0 = (self.segs.length() / 4).to_double()
  self.segs.append(st.segs)
  let caps : Map[Int, Int] = {}
  for j in 0..<count {
    let b = base + j * inst_size
    let kind = a[b + 5]
    if kind == 11.0 {
      a[b + 12] = a[b + 12] + seg0
    } else if (kind == 5.0 || kind == 6.0) && a[b + 20] < 0.0 {
      // (a capture of its own in this frame, as it took one of its own in its build's)
      let was = (-a[b + 20]).to_int()
      let now = match caps.get(was) {
        Some(n) => n
        None => {
          glass_paint.run = glass_paint.run + 1
          caps[was] = glass_paint.run
          glass_paint.run
        }
      }
      a[b + 20] = -now.to_double()
      glass_paint.run_start = -1
      glass_paint.run_len = 0
    }
  }
  self.ninst = i0 + count
}

///|
/// Part `st` drawn again: what its build's paint said of the frame said again, where it said it (nothing round it
/// moved: its key the same): its targets, what is only pointed at, what scrolls in it, its paragraphs that can be
/// picked. So presses, the wheel and the pointer find in it what they found as it was built.
fn Ctx::part_targets_again(self : Ctx, st : KeptPart) -> Unit {
  let h0 = self.next_hit_ids.length()
  for j in 0..<st.hit_ids.length() {
    self.next_hit_ids.push(st.hit_ids[j])
    self.next_hit_ends.push(st.hit_ends[j] + h0)
  }
  self.next_hit_rects.append(st.hit_rects)
  self.next_hit_clips.append(st.hit_clips)
  for id in st.points {
    self.point_said(id)
  }
  self.next_scroll_ids.append(st.scroll_ids)
  self.next_scroll_rects.append(st.scroll_rects)
  for t in st.sels {
    selectable_painted(t.base, t.at, t.lay, t.text, t.ox, t.oy, t.x0, t.y0, t.x1, t.y1)
  }
}
