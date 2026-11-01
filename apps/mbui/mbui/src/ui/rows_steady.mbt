// Rows steady: no row of a list steps in one frame nor goes one way and back while what is in the list moves (2026-10-30
// the user: 「这么一个一个找合理吗？」「有没有通用的解决方案」). A row's place in its list is where the rows before
// it end, each as tall as the list's way has it (list_size.mbt): what changes a row's height for a cause goes there on
// the way, so a row never moves faster in one frame than in the frames round it, nor turns back within a few frames.
// One that does had its height changed by what the list was not told of (a gap left till the last frame of a close,
// a height taken from another row), and shows as a jolt. Held on every frame a Tester draws, as words over words
// are (words_over.mbt): what a test walks through is checked, not only what a test of motion looks at.
//
// Measured on the rows' places in their list as laid out (from the list's top: the list carried by its page moves
// none of them), by their keys where the list is given them (ListRows) and else by their index; not while the list
// is scrolled by the hand or put elsewhere at once by the app (a frame it did so starts it anew), nor across a gap of
// more than a few frames in the frames' times, nor across the window made another size (what it lays out anew for that
// is there at once, no move of its rows: from that frame on anew).
//
// What steps now is known, a file at a time (`rows_steady_known`, given by the app's tests as their package starts): a
// Tester made in a file shows at most as many as its file's bar, which only falls as they are mended.

///|
/// A frame's speed (points a frame) this far from the mean of the frames' round it, and by more than half the faster of
/// theirs, is a jolt: a step, a stop on the way, a start at full speed (a smooth way starts from rest and slows to it).
let rows_speed_least : Double = 3.0

///|
/// How long after a list is first shown its rows may still come to stand at their own heights (guessed till laid out).
let rows_first_ms : Double = 100.0

///|
/// A move one way then back within this many frames, each this far (points) or more, is a jolt.
let rows_back_frames : Int = 3

///|
let rows_back_least : Double = 2.0

///|
/// What one Tester has found: where each row stood the last few frames (by its list's id and its key), whether it holds
/// the rule, the file it was made in, and what it found.
priv struct RowsSteady {
  mut held : Bool
  mut file : String
  /// each sample's first time in the frame, the time of its last position, and that position
  seen : Map[String, Array[(Double, Double, Double)]]
  found : Set[String]
  /// each list's id, and when it was first shown (-1e9: long since)
  lists : Map[Int, Double]
  /// the window's size as the last frame measured was drawn (its rows measured anew from a frame drawn another size)
  mut window : (Double, Double)
}

///|
/// Every jolt said, none failing: what the tests show counted (to take the known down to it).
let rows_steady_counting : Bool = false

///|
// kept across runs: begun anew by each Tester (rows_steady_begin)
let rows_steady : RowsSteady = { held: true, file: "", seen: {}, found: Set::new(), lists: {}, window: (-1.0, -1.0) }

///|
/// Each file's bar: how many jolts a Tester made there may show (the app's tests' known faults, falling as mended).
// kept across runs: said once as a test program starts (its packages' `init`)
let rows_steady_bars : Map[String, Int] = {}

///|
/// The jolts known in the tests of the files `bars` names (as words_over_known says its files), each how many a Tester
/// made there may show. Said by a test package as it starts (`fn init`); only falls.
pub fn rows_steady_known(bars : Array[(String, Int)]) -> Unit {
  for b in bars {
    rows_steady_bars.set(b.0, b.1)
  }
}

///|
/// A Tester made at `loc` starts finding: none found yet; `held`, whether a fault fails it.
fn rows_steady_begin(loc : String, held : Bool) -> Unit {
  rows_steady.held = held
  rows_steady.seen.clear()
  rows_steady.found.clear()
  rows_steady.lists.clear()
  rows_steady.window = (-1.0, -1.0)
  rows_steady.file = match loc.find(":") {
    Some(i) => loc.unsafe_substring(start=0, end=i)
    None => loc
  }
}

///|
/// The jolts the frame just drawn (at `now`, the display's frames `period` apart) shows of the rows of its lists, each
/// said once: by whose row, how, when.
fn Ctx::rows_steady_faults(self : Ctx, now : Double, period : Double) -> Array[String] {
  let out : Array[String] = []
  let here : Set[String] = Set::new()
  // (the window made another size since the last frame: what each list's rows are laid out at for it is there at once,
  // none of it a row's move; from this frame on anew, what was found kept)
  let resized = rows_steady.window != (self.width, self.height)
  rows_steady.window = (self.width, self.height)
  for i in 0..<self.count {
    let ln = self.nodes[i]
    if ln.kind != kind_list {
      continue
    }
    let st = match self.lists.get(ln.id) {
      Some(st) => st
      None => continue
    }
    // (scrolled by the hand or eased by a wheel, or put elsewhere by the app or the hand this frame or the one before (put
    // as it is laid out next): what moves it is no row's;
    // nor in its first frames shown, its rows laid out at the heights they are guessed at, then at their own)
    let shown_since = match rows_steady.lists.get(ln.id) {
      Some(t) if now - t <= 2.5 * period + rows_first_ms => t
      Some(_) => -1.0
      None => {
        rows_steady.lists[ln.id] = now
        now
      }
    }
    rows_steady.lists[ln.id] = if shown_since < 0.0 { -1.0e9 } else { shown_since }
    let settled = shown_since < 0.0 || now - shown_since > rows_first_ms
    let free = settled && !(st.held || st.moving() || st.easing() || now - st.put_at <= 1.5 * period)
    let view = st.vp_h
    let keys = match st.causes {
      Some(c) => c.keys
      None => []
    }
    let mut said = false
    let mut r = ln.first
    while r >= 0 {
      let n = self.nodes[r]
      let key = "\{ln.id}/" + (if n.item >= 0 && n.item < keys.length() { keys[n.item] } else { "#\{n.item}" })
      here.add(key)
      let y = n.y - ln.y
      // (only what shows: a row wholly out of the list's view, or with nothing in it, jolts no one)
      let shows = y + n.fh > 0.0 && y < view && n.first >= 0
      let seen = match rows_steady.seen.get(key) {
        Some(s) => s
        None => {
          let s = []
          rows_steady.seen[key] = s
          s
        }
      }
      // (the frame before not the display's last, or the list not free: from here anew)
      let gap = seen.length() > 0 && now - seen[seen.length() - 1].1 > 2.5 * period
      // (a row coming in where it is from nothing, its room opening: it has no place before this one to go on from: a
      // row gone ahead of others leaves by a copy and comes in so, docs/list-motion.md)
      let anew = match st.causes {
        Some(c) if n.item >= 0 && n.item < keys.length() =>
          match c.by.get(keys[n.item]) {
            Some((Comes(t), _)) => n.fh < 1.0 || now - t < 0.5 * period
            _ => false
          }
        _ => false
      }
      if !free || gap || anew || resized {
        seen.clear()
      }
      if seen.length() > 0 && now - seen[seen.length() - 1].0 < 0.5 * period {
        // (laid out again in the frame, or drawn again within half of one, a moment something outside said: one frame,
        // as it stands now; its speed over a sliver of a frame is none to read. Keep the first time to bound the frame,
        // and the last with its position: an earlier time paired with a later position invents a speed change.)
        seen[seen.length() - 1] = (seen[seen.length() - 1].0, now, y)
      } else {
        seen.push((now, now, y))
      }
      while seen.length() > 4 {
        seen.remove(0) |> ignore
      }
      if free && shows && !said {
        match rows_steady_fault(seen, period) {
          Some(f) => {
            // (one a list a frame: the rows under what changed all move with it)
            let why = match st.causes {
              Some(c) => {
                let a : Array[String] = []
                c.by.each(fn(k, cm) { a.push(k + "=" + (match cm.0 { Comes(t) => "comes@\{t}"; Goes(t) => "goes@\{t}"; Changed(t) => "changed@\{t}" }) + "/\{cm.1}") })
                " causes[" + a.join(" ") + "] way \{c.start}-\{c.end}"
              }
              None => ""
            }
            out.push("row " + key + " " + f + " seen=\{seen}" + why)
            said = true
          }
          None => ()
        }
      }
      r = n.next
    }
  }
  // (rows gone: forgotten)
  let gone : Array[String] = []
  rows_steady.seen.each(fn(k, _) { if !here.contains(k) { gone.push(k) } })
  for k in gone {
    rows_steady.seen.remove(k)
  }
  out
}

///|
/// A row's last places (each frame's first time, the last position's time and that position, oldest first; the display's
/// frames `period` apart): the frame before the last going at a speed off the frames round it, or a move one way then
/// back within rows_back_frames.
fn rows_steady_fault(seen : Array[(Double, Double, Double)], period : Double) -> String? {
  let n = seen.length()
  let speed = fn(a : Int) {
    let (_, t0, y0) = seen[a]
    let (_, t1, y1) = seen[a + 1]
    (y1 - y0) / dmax(t1 - t0, 1.0)
  }
  // its speed off the way the frames round it go: a step (a spike), a stop on its way (a dip), a start at full speed
  if n >= 4 {
    let v0 = speed(0) * period
    let v1 = speed(1) * period
    let v2 = speed(2) * period
    let off = (v1 - (v0 + v2) / 2.0).abs()
    if off > rows_speed_least && off > 0.5 * dmax(v0.abs(), v2.abs()) {
      return Some("went \{v1} a frame between \{v0} and \{v2} at \{seen[2].1}")
    }
  }
  // one way, then back
  if n >= 3 {
    let e = seen[n - 1].2 - seen[n - 2].2
    for a in (n - 1 - rows_back_frames)..<(n - 2) {
      if a < 0 {
        continue
      }
      let d = seen[a + 1].2 - seen[a].2
      if d.abs() >= rows_back_least && e.abs() >= rows_back_least && d * e < 0.0 {
        return Some("moved \{d} at \{seen[a + 1].1}, back \{e} at \{seen[n - 1].1}")
      }
    }
  }
  None
}

///|
/// The rule held on the frame just drawn: a jolt not found before by this Tester, past its file's bar, fails the test
/// at once, with what and where.
fn Tester::hold_rows_steady(self : Tester) -> Unit {
  let c = g()
  let faults = c.rows_steady_faults(self.fake.time, self.period)
  if !rows_steady.held {
    return
  }
  for f in faults {
    // (each row's once)
    let row = match f.find(" went") {
      Some(i) => f.unsafe_substring(start=0, end=i)
      None =>
        match f.find(" moved") {
          Some(i) => f.unsafe_substring(start=0, end=i)
          None => f
        }
    }
    if rows_steady.found.contains(row) {
      continue
    }
    rows_steady.found.add(row)
    let bar = rows_steady_bars.get(rows_steady.file).unwrap_or(0)
    if rows_steady_counting {
      println("ROWS-STEADY \{rows_steady.file}: \{f} (the Tester made at \{looks_made_at.val})")
      continue
    }
    if rows_steady.found.length() > bar {
      let said = "rows not steady (rows_steady.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{f}; \{rows_steady.found.length()} now, \{bar} known in \{rows_steady.file}"
      println(said)
      abort(said)
    }
  }
}
