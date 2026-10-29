// A list's rows' heights as they change (still.fail's docs/list-motion.md, 2026-10-30 the user: 「那些会变长或缩短的消息
// 列表内容的动效协同起来的效果，需要系统性设计一下」). A row that comes, goes or changes says so as it is built, with
// the moment it did (Ctx::row_size): from then its height goes from the one it had to the one it is laid out at (none
// for one going) on a move's curve, and it is laid out that tall, what it holds cut there. Every row stands where
// the rows before it end at that moment, so rows never lie over one another nor leave a gap, however many change at
// once, and nothing waits for another: what is in view stays where it shows as the list's own rule has it (held at
// its end, its foot stays; anywhere else, the row read from stays and what changes above it goes up, below it down).
// Nothing here is a layout's difference made a motion (docs/motion.md rule 1): a row moves only for the cause it says.

///|
/// What changed a row's height, and when (the frames' clock): it came into the list (from nothing), it goes from it
/// (to nothing: the row stays in the list till then, Ctx::row_gone), or what it holds changed (from the height it had
/// then).
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
/// A row's way from one height to another: from `from` at `start` (its cause's moment, or later where what it is
/// laid out at changed on its way), over `ms`, to what it is laid out at (none, going); `last` the height it was last
/// laid out at, `to` the one it went to then.
priv struct RowSizing {
  mut cause : RowSize
  mut from : Double
  mut start : Double
  mut ms : Double
  mut last : Double
  mut to : Double
  /// the frame it was last laid out in, and its way as that frame found it (a frame laid out twice, built again from
  /// what it read, lays it out the same: from there each time)
  mut frame : Int
  mut was : (Double, Double, Double)
}

///|
/// How long a row's height takes to go to its new one: a row's move (docs/motion.md Curves).
pub let row_size_ms : Double = move_near_ms

///|
/// What each row built this frame said changed its height (None: nothing), by its node: taken by its layout.
// kept across runs: put by a row's build, taken by its layout
let row_built_said : Map[Int, (String, RowSize, Double)?] = {}

///|
/// In a list's row build: the row (`key`, its own in the list as it moves) came, goes or changed as `cause` says, at
/// its moment. Said each time it is built, the same moment while it is the same change: a new moment sets it out
/// again from where it is.
/// `ms`: how long its way takes, where it goes with another motion of the same cause (words sent flying to it: as
/// long as their way), a row's move otherwise.
pub fn Ctx::row_size(self : Ctx, key : String, cause : RowSize, ms? : Double = row_size_ms) -> Unit {
  ignore(self)
  // (the innermost row being built: a list in a row has rows of its own)
  if row_causes_built.length() > 0 {
    row_causes_built[row_causes_built.length() - 1] = Some((key, cause, ms))
  }
}

///|
/// What each row being built (innermost last) said changed its height, and over how long (Ctx::build_row).
// kept across runs: pushed and popped by each row's build
let row_causes_built : Array[(String, RowSize, Double)?] = []

///|
/// Whether the row `key` of list `list` is gone (its way to nothing over by `now`): what keeps it in the list till
/// then drops it (its declared end, never whether it moves: docs/motion.md rule 3).
pub fn row_gone(at : Double, now : Double) -> Bool {
  // (a hair short of it, a sum of ms rounded off, is there)
  now >= at + row_size_ms - 0.001
}

///|
/// Row `k`, laid out `natural` tall, as tall as its cause has it at `now` (Ctx::row_size): its way set out the first
/// time it is said (from the height it was had at, nothing for one coming), and again from where it is for a new one.
fn ListState::row_sized(self : ListState, k : Int, r : Int, natural : Double, now : Double, frame : Int) -> Double {
  // (a row built now says what changed it or nothing; one kept as it was, what it said as it was built)
  let said = match row_built_said.get(r) {
    Some(Some(c)) => {
      self.row_causes[k] = c
      Some(c)
    }
    Some(None) => {
      self.row_causes.remove(k) |> ignore
      None
    }
    None => self.row_causes.get(k)
  }
  row_built_said.remove(r) |> ignore
  let (key, cause, ms) = match said {
    Some(c) => c
    None => return natural
  }
  let r = match self.sizes.get(key) {
    Some(r) => r
    // (its way over before it was ever laid out: as tall as it is)
    None if now >= cause.at() + ms => return if cause is Goes(_) { 0.0 } else { natural }
    None => {
      let from = match cause {
        Comes(_) => 0.0
        _ => if self.heights[k] >= 0.0 { self.heights[k] } else { natural }
      }
      let r = { cause, from, start: cause.at(), ms, last: from, to: -1.0, frame: -1, was: (from, from, -1.0) }
      self.sizes[key] = r
      r
    }
  }
  if r.frame == frame {
    let (from, last, to) = r.was
    r.from = from
    r.last = last
    r.to = to
  } else {
    r.frame = frame
    r.was = (r.from, r.last, r.to)
  }
  if r.cause != cause {
    // set out again from where it is (as last laid out: the way it was on gives way to the new one)
    r.from = match cause {
      Comes(_) if r.cause is Goes(_) => r.last
      Comes(_) => 0.0
      _ => r.last
    }
    r.cause = cause
    r.start = cause.at()
    r.ms = ms
    r.to = -1.0
  }
  let to = match cause {
    Goes(_) => 0.0
    _ => natural
  }
  // (what it is laid out at changed on its way, a picture in it come to its size: on from where it is to that, as a
  // move's way given another end goes on, never a step)
  // (not for what lays it out a hair otherwise: on the device's pixels or not, a frame built again)
  // (its end kept where its cause put it: the way from where it is now to the new end in what is left of it)
  let p = Ease::Move.at((now - r.start) / r.ms)
  if r.to >= 0.0 && (to - r.to).abs() > 0.5 && p < 0.9 {
    r.from = (r.last - to * p) / (1.0 - p)
  }
  r.to = to
  let h = if p >= 1.0 { to } else { r.from + (to - r.from) * p }
  r.last = h
  h
}

///|
/// When the last of a list's rows' ways to their heights is over (-1: none under way).
fn ListState::sizes_rest(self : ListState) -> Double {
  let mut t = -1.0
  self.sizes.each(fn(_, r) { t = dmax(t, r.start + r.ms) })
  t
}

///|
/// What is over of the rows' ways forgotten once its row is no longer in the list's last build (the keys said this
/// time), the causes of rows past its end with them.
fn ListState::sizes_kept(self : ListState, now : Double) -> Unit {
  let past : Array[String] = []
  self.sizes.each(fn(k, r) {
    // (one going kept a while past its end: its row out of the list by then, Ctx::row_gone)
    if now >= r.start + r.ms + (if r.cause is Goes(_) { row_size_ms } else { 0.0 }) {
      past.push(k)
    }
  })
  for k in past {
    self.sizes.remove(k)
  }
  let gone : Array[Int] = []
  self.row_causes.each(fn(k, _) { if k >= self.count { gone.push(k) } })
  for k in gone {
    self.row_causes.remove(k)
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
/// Whether a row of the list may be kept as it was built while its rows' heights go to others (none: each built again,
/// saying again what changed it, so that the frame built keeping none comes out the same; `k` for what may one day
/// tell them apart).
fn ListState::row_sizing(self : ListState, k : Int, now : Double) -> Bool {
  ignore(k)
  self.sizes_rest() > now
}
