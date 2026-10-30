// A list's rows' heights as they change (still.fail's docs/list-motion.md, 2026-10-30 the user: 「那些会变长或缩短的消息
// 列表内容的动效协同起来的效果，需要系统性设计一下」「为啥每个改动都要自己处理一遍」). The page gives its list its rows
// each build, each by its key and its version (ListRows): from one build to the next the list itself works out what
// came (a key new to it: its room opening from nothing), what went (a key gone: kept in the list as it last was while
// its room closes) and what changed (another version: from the height it had to the new one), the row laid out that
// tall and cut there. Every row stands where the rows before it end, so rows never lie over one another nor leave a
// gap, however many change at once, and nothing waits for another; what is in view stays where the list's own rule has
// it. A row's height going is its layout's alone: what is kept of a row's build is kept (its height looked up by its
// key as it is laid out), nothing is built again for it.
//
// What changes together moves as one (2026-10-30 the user: 「在有决策卡片的时候发消息，整个消息列表会频繁来回移动」):
// the rows on their way go on one way, the list's, set out at the last cause's moment and over at the latest end any
// of them was given (a message sent, as long as its words fly). Each was off from its height by some way as it set
// out, and what is left of each is the same share of it at every moment, so what is over and under them, the sum of
// theirs, goes one way: a card's options closing over a message sent under it, each on a curve of its own, had what
// was over them go up for the one, then down for the other. What a row's content does to its height itself (what is
// in it opening or closing: Ctx::row_way) is its own, the list closing only what was off as it changed.

///|
/// What changed a row's height, and when (the frames' clock): it came into the list (from nothing), it goes from it
/// (to nothing: the row stays in the list till then), or what it holds changed (from the height it had then).
pub(all) enum RowSize {
  Comes(Double)
  Goes(Double)
  Changed(Double)
} derive(Eq)

///|
fn RowSize::at(self : RowSize) -> Double {
  match self {
    Comes(t) | Goes(t) | Changed(t) => t
  }
}

///|
/// A row on the list's way, as it stood the last time what it goes by changed (the way set out again or given another
/// end, what it is laid out at stepping, another cause): `h` tall at `at`, laid out `to` tall then, on the way from
/// `start` to `end`, going `v` (points a ms) then. Where it is at any moment after is worked out from that alone,
/// whatever frames came between: what was off of it then closing by the end, on a Move's way from that speed
/// (@ui.move_path), so a cause coming on its way neither stops it nor steps it.
priv struct RowSizing {
  mut cause : RowSize
  mut h : Double
  mut v : Double
  mut to : Double
  mut at : Double
  mut start : Double
  mut end : Double
  /// the frame it was last laid out in, and how it stood as that frame found it (a frame laid out twice, built again
  /// from what it read, lays it out the same: from there each time)
  mut frame : Int
  mut was : (RowSize, Double, Double, Double, Double, Double, Double)
}

///|
/// How long a row's height takes to go to its new one: a near Move's (docs/motion.md Curves). Not yet as long as its
/// way is far, as every other move is: a row's height is worked out by its key as the list is laid out (ListRows),
/// its way's length to come with that.
pub let row_size_ms : Double = 300.0

///|
/// How long a row going takes to leave before its room closes (2026-10-30 the user: 「一行消失的动效感觉有点生硬，现在都是
/// 裁剪」): it fades where it is, a little smaller to its middle (row_leave_scale), its room whole and nothing over or
/// under it moving; its room closes after, with nothing left in it to cut (ListRows::leave).
pub let row_leave_ms : Double = 150.0

///|
/// How small a row going is as it has left (ListRows::leave), to its middle.
pub let row_leave_scale : Double = 0.96

///|
/// Row `k`, laid out `natural` tall, as tall as what changed it has it at `now` (its list's ListRows, by its key): off
/// from it as it was as its cause came (from nothing, one coming; from the height it had, one changed), by less as the
/// list's way goes.
fn ListState::row_sized(self : ListState, k : Int, natural : Double, now : Double, frame : Int) -> Double {
  let (c, key, cause) = match self.causes {
    Some(c) if k < c.keys.length() => {
      c.read()
      match c.by.get(c.keys[k]) {
        Some((cause, _)) => (c, c.keys[k], cause)
        None => return natural
      }
    }
    _ => return natural
  }
  let to = match cause {
    Goes(_) => 0.0
    _ => natural
  }
  // (its way over before it was laid out on it, or as it is: as tall as it is; a hair short of its end, a sum of ms
  // rounded off, at it, as ListRows::rows has it over there, laid out again or built anew)
  if now >= c.end - 0.001 {
    return to
  }
  // (its rows laid out on the way till its end, as it was declared: what is dropped of it a hair before is the list's)
  self.sizes_end = c.end
  let own = c.own.contains(key)
  let r = match self.sizes.get(key) {
    Some(r) => r
    None => {
      let from = match cause {
        Comes(_) => 0.0
        // (as tall as it was last laid out, by its key: what is had by its place in the list may be another row's as
        // the rows given change)
        _ => self.shown_h.get(key).unwrap_or(natural)
      }
      // (off as its cause came, from its moment: laid out first a while on, it is where the way has it by then)
      let at = cause.at()
      let r = { cause, h: from, v: 0.0, to, at, start: c.start, end: c.end, frame: -1, was: (cause, from, 0.0, to, at, c.start, c.end) }
      self.sizes[key] = r
      r
    }
  }
  if r.frame == frame {
    let (was_cause, h, v, was_to, at, start, end) = r.was
    r.cause = was_cause
    r.h = h
    r.v = v
    r.to = was_to
    r.at = at
    r.start = start
    r.end = end
  } else {
    r.frame = frame
    r.was = (r.cause, r.h, r.v, r.to, r.at, r.start, r.end)
  }
  // where it is at `t` as it stood (laid out `now_to` tall then), and how fast it goes: what was off of it closing by
  // the way's end from the speed it had; one whose content goes on the way itself, only what was off of it as it
  // changed, what it does itself its own
  let at_t = fn(t : Double, now_to : Double) -> (Double, Double) {
    let off = if own { r.h - r.to } else { r.h - now_to }
    let (x, v) = move_path(off, r.v, t - r.at, r.end - r.at)
    (now_to + x, v)
  }
  // what it goes by changed (another cause, the way set out again or given another end, what it is laid out at
  // stepping: a picture come to its size, the core's row joined to the one before): on from where it is now, as fast
  // as it goes, so it neither steps nor stops
  if r.cause != cause || r.start != c.start || r.end != c.end || (!own && (to - r.to).abs() > 0.5) {
    let (h, v) = at_t(now, if own { to } else { r.to })
    r.h = h
    r.v = v
    r.to = to
    // (its own not set out yet: from then)
    r.at = dmax(now, cause.at())
    r.start = c.start
    r.end = c.end
    r.cause = cause
  }
  at_t(now, to).0
}

///|
/// Row `k` laid out `h` tall: so tall by its key, for a change of it from there (a list whose rows' heights move).
fn ListState::row_shown(self : ListState, k : Int, h : Double) -> Unit {
  match self.causes {
    Some(c) if k < c.keys.length() => {
      // (only the rows given now kept: what went from the list long since forgotten)
      if self.shown_h.length() > 2 * c.keys.length() + 16 {
        self.shown_h.clear()
      }
      self.shown_h[c.keys[k]] = h
    }
    _ => ()
  }
}

///|
/// Whether row `k`'s content goes to its height on the rows' way at `now` (Ctx::row_way).
fn ListState::row_own_way(self : ListState, k : Int, now : Double) -> Bool {
  match self.causes {
    Some(c) => now < c.end - 0.001 && k < c.keys.length() && c.own.contains(c.keys[k])
    None => false
  }
}

///|
/// When the list's way a row was last laid out on is over (-1: none was).
fn ListState::sizes_rest(self : ListState) -> Double {
  self.sizes_end
}

///|
/// The rows' ways forgotten once the list's is over.
fn ListState::sizes_kept(self : ListState, now : Double) -> Unit {
  match self.causes {
    Some(c) if now < c.end - 0.001 => ()
    _ => self.sizes.clear()
  }
}

///|
/// A list's rows' ways to their heights as what moves (frames till the last is over, the list laid out again each).
priv struct Sizes {
  st : ListState
}

///|
impl Moving for Sizes with rest_at(self, now, frame) {
  ignore(frame)
  // (over: at rest, whatever is kept of a way gone by)
  // (a hair past now, a sum of ms rounded off: at rest, as at its end)
  let t = self.st.sizes_rest()
  if t > now + 0.001 {
    t
  } else {
    -1.0
  }
}


///|
/// Why each row of a list goes to another height, by its key, and the keys of its rows in order as last given (its
/// ListRows' answer, for its layout: Ctx::list's `sized`).
pub struct RowCauses {
  by : Map[String, (RowSize, Double)]
  mut keys : Array[String]
  /// told as any of it changes: what its layout reads it by (Ctx::list), and what a row reads of it (ListRows::came,
  /// went)
  priv said : @signals.Signal[Int]
  priv mut n : Int
  /// the rows' way: set out at the last cause's moment, over at the latest end one was given (-1: none under way)
  priv mut start : Double
  priv mut end : Double
  /// the rows whose content goes on the way itself (Ctx::row_way), by their keys: the list closes only what was off
  /// as their cause came
  priv own : Set[String]
}

///|
/// Its rows' keys now (`keys`), and whether why any goes to another height changed (`moved`): what reads it told if
/// either did (not for the same keys given anew).
fn RowCauses::told(self : RowCauses, keys : Array[String], moved : Bool) -> Unit {
  let was = self.keys
  self.keys = keys
  if moved || !(physical_equal(was, keys) || was == keys) {
    self.n += 1
    self.said.set(self.n)
  }
}

///|
/// What reads it is told as it changes from now.
fn RowCauses::read(self : RowCauses) -> Unit {
  self.said.get() |> ignore
}

///|
/// A row gone from a list, in it still as it last was while its room closes: it, when it went, the row it came after.
priv struct GoingRow[T] {
  item : T
  at : Double
  after : String
}

///|
/// A list's rows as the page gives them each build (ListRows::rows), and what the list made of them.
pub struct ListRows[T] {
  priv was : Map[String, String]
  priv mut order : Array[(String, T)]
  priv going : Map[String, GoingRow[T]]
  priv causes : RowCauses
  priv mut given : Bool
  priv mut last_keys : Array[String]
  priv mut last_items : Array[T]
  /// the keys going, read by each row as whether it is one
  priv going_said : @signals.Keyed[String]
}

///|
pub fn[T] ListRows::new() -> ListRows[T] {
  { was: {}, order: [], going: {}, causes: { by: {}, keys: [], said: @signals.signal(0), n: 0, start: -1.0, end: -1.0, own: Set::new() }, given: false, last_keys: [], last_items: [], going_said: @signals.keyed() }
}

///|
/// The rows of a list as they are now (`keys`, `items` by the same index, `version` of each: what it shows), with what
/// went from them still among them (after the row each came after) while its room closes, and their keys. What changed
/// since they were last given is said from now: a key new comes, one gone goes, another version changes. Not
/// `watched` (the list not followed, its page another's, a page of it read anew): what changed is so at once.
/// `ms`: how long a row's coming takes where it goes with another motion of its cause (words flying to it), a row's
/// move otherwise; `from`: the moment such a row's change sets out where that motion has it later than now (words
/// sent coming in as they leave the composer, the composer's room let go as they do), from which it is `ms` long, the
/// row as it was till then. `comes`: whether a row new to the list comes now (false: it was there before, only brought now, as
/// what was caught up on), there at once.
pub fn[T] ListRows::rows(
  self : ListRows[T],
  c : Ctx,
  keys : Array[String],
  items : Array[T],
  version : (T) -> String,
  watched? : Bool = true,
  ms? : (String) -> Double? = fn(_) { None },
  from? : (String) -> Double? = fn(_) { None },
  comes? : (T) -> Bool = fn(_) { true },
) -> (Array[T], Array[String]) {
  let now = c.moment()
  // (the same arrays as last given: nothing of them changed, nothing to look over)
  let same = self.given &&
    physical_equal(keys, self.last_keys) &&
    physical_equal(items, self.last_items)
  self.last_keys = keys
  self.last_items = items
  let here : Map[String, Bool] = {}
  if !same {
    for k in keys {
      here[k] = true
    }
  }
  // (whether any of what the list and its rows read of it changed: told them as it did)
  let mut moved = false
  // the rows' way over: what went out of the list at its end, what made it forgotten
  // (a hair short of it, a sum of ms rounded off, is there)
  if self.causes.end >= 0.0 && now >= self.causes.end - 0.001 {
    moved = moved || !self.going.is_empty() || !self.causes.by.is_empty()
    self.going.clear()
    self.causes.by.clear()
    self.causes.start = -1.0
    self.causes.end = -1.0
    self.causes.own.clear()
  }
  // (whether a row sets out now: the rows' way sets out again from here)
  let mut began = false
  if same && watched {
    ()
  } else if self.given && watched {
    for i, k in keys {
      let v = version(items[i])
      match self.was.get(k) {
        None =>
          if comes(items[i]) {
            self.causes.by[k] = (Comes(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
            began = true
          }
        // (changed as it comes: still coming, on to what it is now)
        Some(w) if w != v =>
          match self.causes.by.get(k) {
            Some((Comes(_), _)) => ()
            _ => {
              self.causes.by[k] = (Changed(from(k).unwrap_or(now)), ms(k).unwrap_or(row_size_ms))
              began = true
            }
          }
        _ => ()
      }
      if self.going.contains(k) {
        self.going.remove(k)
        moved = true
      }
    }
    let mut prev = ""
    for r in self.order {
      let (k, item) = r
      if !here.contains(k) && !self.going.contains(k) {
        // (it leaves first, its room closing once it has: row_leave_ms)
        let at = from(k).unwrap_or(now)
        self.going[k] = { item, at, after: prev }
        self.causes.by[k] = (Goes(at + row_leave_ms), ms(k).unwrap_or(row_size_ms))
        began = true
      }
      if here.contains(k) || self.going.contains(k) {
        prev = k
      }
    }
  } else if !self.going.is_empty() || !self.causes.by.is_empty() {
    self.going.clear()
    self.causes.by.clear()
    moved = true
  }
  // (coming or changing with another motion of its cause, told anew when and how long: words sent, timed once they
  // know their way)
  let retimed : Array[(String, RowSize, Double)] = []
  self.causes.by.each(fn(k, cm) {
    let (cause, was) = cm
    // (when, only while it has not set out: one on its way goes on as it goes)
    let at = if cause.at() >= now { from(k).unwrap_or(cause.at()) } else { cause.at() }
    let now_ms = ms(k).unwrap_or(was)
    if cause is Goes(_) || (at == cause.at() && now_ms == was) {
      return
    }
    retimed.push((k, match cause { Comes(_) => Comes(at); _ => Changed(at) }, now_ms))
  })
  for r in retimed {
    self.causes.by[r.0] = (r.1, r.2)
    moved = true
    // (the way setting out with it, later than said: a row whose content goes on it itself goes from then, row_way)
    if r.1.at() > self.causes.start {
      self.causes.start = r.1.at()
    }
  }
  self.given = true
  // the rows' way: from the last cause's moment to the latest end any was given
  if began {
    // (from the latest moment one sets out: now, or later where one's cause has it so: `from`)
    // (a row going sets out as it starts to leave: its room closing row_leave_ms on is its own, the list's way not
    // put off for it)
    let mut start = now
    self.causes.by.each(fn(_, cm) {
      start = dmax(start, match cm.0 {
        Goes(t) => t - row_leave_ms
        t => t.at()
      })
    })
    self.causes.start = start
    moved = true
  }
  let mut end = -1.0
  self.causes.by.each(fn(_, cm) { end = dmax(end, cm.0.at() + cm.1) })
  if self.causes.by.is_empty() {
    self.causes.start = -1.0
    self.causes.own.clear()
  }
  self.causes.end = end
  // (built again at its end: what goes out of the list then)
  if !self.going.is_empty() && end > now {
    c.shows_until(end - 0.001)
  }
  if !same {
    self.was.clear()
    for i, k in keys {
      self.was[k] = version(items[i])
    }
    self.order = keys.mapi(fn(i, k) { (k, items[i]) })
  }
  self.going_said.set(self.going.keys().collect())
  // (nothing going: the arrays as given, the same ones while they are, so what is worked out of them is kept)
  if self.going.is_empty() {
    self.causes.told(keys, moved)
    return (items, keys)
  }
  // the rows going among them, each after the row it came after (the first, before all)
  let all_keys = keys.copy()
  let all_items = items.copy()
  {
    let order = self.going.to_array()
    order.sort_by(fn(a, b) { a.1.at.compare(b.1.at) })
    for g in order {
      let (k, go) = g
      let mut at = 0
      if go.after != "" {
        for i, kk in all_keys {
          if kk == go.after {
            at = i + 1
          }
        }
      }
      all_keys.insert(at, k)
      all_items.insert(at, go.item)
    }
  }
  self.causes.told(all_keys, moved)
  (all_items, all_keys)
}

///|
/// What changed its rows' heights, for the list's layout (Ctx::list's `sized`).
pub fn[T] ListRows::sized(self : ListRows[T]) -> RowCauses {
  self.causes
}

///|
/// When row `key` came into the list as it was watched, while it opens its room (None: it did not, or it is open).
pub fn[T] ListRows::came(self : ListRows[T], key : String) -> Double? {
  self.causes.read()
  match self.causes.by.get(key) {
    Some((Comes(at), _)) => Some(at)
    _ => None
  }
}

///|
/// When row `key` went from the list, as it leaves and its room closes after (None: it is in it): the moment it starts
/// to leave (ListRows::leave), its room closing row_leave_ms on.
pub fn[T] ListRows::went(self : ListRows[T], key : String) -> Double? {
  if !self.going_said.has(key) {
    return None
  }
  self.going.get(key).map(fn(g) { g.at })
}

///|
/// Row `key`, built as node `i`, as it goes from the list (ListRows::went): it fades where it is on `Leave` over
/// row_leave_ms, to row_leave_scale of its size to its middle, drawn only (nothing in it tapped); then gone from view
/// as its room closes. Read as it is painted, its row not built again for it. Nothing for a row not going.
pub fn[T] ListRows::leave(self : ListRows[T], c : Ctx, i : Int, key : String) -> Unit {
  match self.went(key) {
    Some(at) => {
      c.draw_only(i)
      c.look_by(i, fn() {
        let p = Ease::Leave.at((c.moment() - at) / row_leave_ms)
        look(alpha=1.0 - p, scale=1.0 - (1.0 - row_leave_scale) * p, ox=0.5, oy=0.5)
      })
    }
    None => ()
  }
}

///|
/// Whether a row come into the list still opens its room: built again as the last of them is open.
pub fn[T] ListRows::opening(self : ListRows[T], c : Ctx) -> Bool {
  let now = c.moment()
  // (by the end it was given: where another changed after it came, the rows' way it goes on is longer, the last of
  // its opening, most of it in view by then)
  let mut last = -1.0
  self.causes.by.each(fn(_, cm) {
    match cm {
      (Comes(at), ms) if at + ms > now => last = dmax(last, at + ms)
      _ => ()
    }
  })
  if last > now {
    c.shows_until(last)
    true
  } else {
    false
  }
}

///|
/// What changes the heights of the rows the list laying them out now has (Ctx::place_list): what a row's content reads
/// of its way as it is built.
// kept across runs: set and put back as each list lays its rows out
let rows_laid_by : Ref[(RowCauses, Int)?] = Ref(None)

///|
/// The way the rows of the list a row is built in go to their heights (its start, how long), while it is under way:
/// what in the row changes its height itself as its version changes (a card's options closing as it is answered) goes
/// on it, from its start and as long, so that it moves as one with the rows round it (None: built in no such list, or
/// none on its way).
pub fn Ctx::row_way(self : Ctx) -> (Double, Double)? {
  match rows_laid_by.val {
    Some((c, k)) if c.end > self.clock && c.start >= 0.0 && k < c.keys.length() => {
      // (what it does to its row's height its own from now: ListState::row_sized)
      c.own.add(c.keys[k])
      Some((c.start, c.end - c.start))
    }
    _ => None
  }
}
