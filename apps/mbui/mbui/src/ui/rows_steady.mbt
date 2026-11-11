// Rows steady: no row of a list steps in one frame nor turns back again and again while what is in the list moves (2026-10-30
// the user: 「这么一个一个找合理吗？」「有没有通用的解决方案」). A row's place in its list is where the rows before
// it end, each as tall as the list's way has it (list_size.mbt): what changes a row's height for a cause goes there on
// the way, so a row never moves faster in one frame than in the frames round it, nor turns back but where what came
// sets the rows' sum to end the other way, once (rows_turn_ms). One that does had its height changed by what the list was not told of (a gap left till the last frame of a close,
// a height taken from another row), and shows as a jolt. Held on every frame a Tester draws, as words over words
// are (words_over.mbt): what a test walks through is checked, not only what a test of motion looks at. Nor does a row
// drawn come to rest one way and go back the other soon after with nothing done by the hand between
// (rows_return_ms): up as one thing came, down a moment later as another left, which reads as the list shaking however
// smooth each way is. Nor does a row go a whole step in the frame its list's way sets out again, many times as far as
// in the frames round it (rows_step_least): the way setting out lets a speed taken up by, not a height put on at once
// under it.
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
/// Where the list's way set out between the frames (the rows taking up its speed from where they were, no jolt of
/// itself), a frame this far (points, a 60 a second frame's) and this many times as far as both of the frames round it
/// is a step all the same: a row's height put on at once under the way's setting out (2026-11-10 the user: 「还是有很多
/// 问题导致它乱跳」; a card come to a post still coming in put all over it up by the card's whole room in one frame, and
/// the way set out again in that frame let it by).
let rows_step_least : Double = 12.0

///|
let rows_step_times : Double = 4.0

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
  /// how much bigger the system's setting made words as that frame was drawn (font_scale): its rows laid out anew too
  mut words : Double
  /// when each row (by its list's id and its key) last turned back (rows_turn_ms)
  turned : Map[String, Double]
  /// each row's last way (rows_return_ms): which way (1 down, -1 up), how far, when it last moved so, how far it has
  /// come back the other way since (0 none), when it set out, whether a row left on it with none come, and whether the
  /// row was drawn in a frame of its way back so far (not faint)
  went : Map[String, (Double, Double, Double, Double, Double, Bool, Bool)]
  /// when the hand last pressed, let go, typed, scrolled or went back (rows_steady_hand)
  mut hand : Double
}


///|
// kept across runs: begun anew by each Tester (rows_steady_begin)
let rows_steady : RowsSteady = {
  held: true,
  file: "",
  seen: {},
  found: Set([]),
  lists: {},
  window: (-1.0, -1.0),
  words: -1.0,
  turned: {},
  went: {},
  hand: -1.0e9,
}

///|
/// Each file's bar: how many jolts a Tester made there may show (the app's tests' known faults, falling as mended).
// kept across runs: said once as a test program starts (its packages' `init`)
let rows_steady_bars : Map[String, Int] = Map([])

///|
/// The jolts known in the tests of the files `bars` names (as words_over_known says its files), each how many a Tester
/// made there may show. Said by a test package as it starts (`fn init`); only falls.
pub fn rows_steady_known(bars : Array[(String, Int)]) -> Unit {
  motion_bars_said("rows_steady", bars)
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
  rows_steady.turned.clear()
  rows_steady.went.clear()
  rows_steady.hand = -1.0e9
  rows_steady.window = (-1.0, -1.0)
  rows_steady.words = -1.0
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
  let here : Set[String] = Set([])
  // (the window made another size, or words by the system's setting, since the last frame: what each list's rows are
  // laid out at for it is there at once, none of it a row's move; from this frame on anew, what was found kept)
  let words = @signals.untracked(font_scale)
  let resized = rows_steady.window != (self.width, self.height) || rows_steady.words != words
  rows_steady.window = (self.width, self.height)
  rows_steady.words = words
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
    let settled = shown_since < 0.0 || now > shown_since + rows_first_ms
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
      // row gone ahead of others leaves by a copy and comes in so, mbui's view/list_motion.mbt)
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
        rows_steady.went.remove(key)
      }
      // (coming or going where it is, less than half open: what it holds is not seen yet, or no more (row_gone_at),
      // and where its room stands as the rows round it take their places is no step of anything seen; nor one with no
      // room at all; nor its coming back, not seen, rows_steady_return)
      let faint = n.fh < 1.0 || (match st.causes {
        Some(c) if n.item >= 0 && n.item < keys.length() =>
          match c.opened.get(keys[n.item]) {
            Some((shown, natural)) => shown < row_gone_at * natural
            None => false
          }
        _ => false
      })
      // (moved one way, come to rest, then back the other way soon after: rows_return_ms)
      let returned = if free && shows && seen.length() > 0 {
        // (a row of it gone on the list's way, none come: what was at its end left with nothing in its place)
        let left = match st.causes {
          Some(c) =>
            c.by.iter().any(fn(kc) { kc.1.0 is Goes(_) }) && !c.by.iter().any(fn(kc) { kc.1.0 is Comes(_) })
          None => false
        }
        rows_steady_return(key, now, y - seen[seen.length() - 1].2, period, left~, faint~)
      } else {
        None
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
        // (when its list's way last set out: a speed taken up then from where the rows were, and a turn back for what came
        // then, are the way's)
        let set_out = match st.causes {
          Some(c) => c.start
          None => -1.0
        }
        let turned = rows_steady.turned.get(key).unwrap_or(-1.0e9)
        let (fault, turn) = rows_steady_fault(seen, period, set_out~, turned~, faint~)
        if turn != turned {
          rows_steady.turned[key] = turn
        }
        let fault = match fault {
          Some(_) => fault
          None => returned
        }
        match fault {
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
            out.push("row " + key + " (list " + st.named + ") " + f + " seen=[\{seen.map(fn(s) { "(\{s.0}, \{s.1}, \{s.2})" }).join(", ")}]" + why)
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
/// How soon after a row turned back a turn again is a jolt (2026-11-03 the user, of the rows' way going on with what
/// comes, the rows' sum turning where it now ends the other way: 「单次转向不是问题」「不能连续转向」).
let rows_turn_ms : Double = 600.0

///|
/// How soon after a row came to rest from going one way its going back the other is a jolt, however long it stood (the
/// user, 2026-11-09, of the list up as an answer came and down 0.6 s after as the agent's line left: 「点一个决策后上下
/// 摇晃」; again on words sent: 「现在发个消息都抖了」「能不能不要我一个一个报」). Turning as it goes, without a stop, is
/// the way's once (rows_turn_ms); turning back from rest is a second way the other way, which is what shakes.
let rows_return_ms : Double = 1500.0

///|
/// The hand did something (pressed, let go, typed, scrolled, went back) at its event's moment: what a row does after it
/// is an answer to it (rows_steady_return).
fn rows_steady_hand() -> Unit {
  rows_steady.hand = h_event_time()
}

///|
/// A row moved `d` (points, down the list) this frame at `now`: back the other way from its last way, which it had come
/// to rest from (no move for more than a frame) less than rows_return_ms ago, by rows_back_least each, the hand having
/// done nothing since that way set out, and neither way one a row left on with none come in its place (`left`: the
/// list's room going back for what left, as it must with nothing to take its place; the user, 2026-11-09: 「维持往回退，
/// 检查放行这种」): the jolt said. Unless the row was drawn in none of the frames of its way back (`faint` in each: under
/// row_gone_at, what it holds at alpha 0, or no room at all), from the frame it first moved back to this one, those it
/// stood in between too: what is not seen shakes nothing (the coordinator of the migration, 2026-11-11: the judge holds
/// what is seen on screen; words sent as a turn was over, 已完成 closing as their row opened and 处理中 opening under
/// it 350 ms later, the closing row 0.14 of its 40 points tall as it came back 2.90, said, every row seen going up only).
/// A row drawn in even one of them is said as before.
fn rows_steady_return(
  key : String,
  now : Double,
  d : Double,
  period : Double,
  left~ : Bool,
  faint~ : Bool,
) -> String? {
  if d.abs() < 0.25 {
    // (standing on its way back: a frame of it all the same)
    match rows_steady.went.get(key) {
      Some((w, far, at, back, from, was_left, false)) if back > 0.0 && !faint =>
        rows_steady.went[key] = (w, far, at, back, from, was_left, true)
      _ => ()
    }
    return None
  }
  let way = if d > 0.0 { 1.0 } else { -1.0 }
  match rows_steady.went.get(key) {
    None => {
      rows_steady.went[key] = (way, d.abs(), now, 0.0, now, left, false)
      None
    }
    Some((w, far, _, back, from, was_left, _)) if w == way => {
      // (on its way still, or on it again: what came back is forgotten)
      ignore(back)
      rows_steady.went[key] = (w, far + d.abs(), now, 0.0, from, was_left || left, false)
      None
    }
    Some((w, far, at, back, from, was_left, drawn)) => {
      let back = back + d.abs()
      let drawn = drawn || !faint
      if back < rows_back_least {
        rows_steady.went[key] = (w, far, at, back, from, was_left, drawn)
        return None
      }
      // (a way the other way now: from here its own)
      rows_steady.went[key] = (way, back, now, 0.0, now, left, false)
      if was_left || left || !drawn {
        return None
      }
      let rest = now - at
      // (the hand having pressed, typed or scrolled since the way set out, back is the answer to it or to what the app
      // was told by it (a card answered, a panel shut, the composer's words gone), not a jolt of the list's own)
      if far >= rows_back_least && rest > 2.5 * period && rest < rows_return_ms && rows_steady.hand < from {
        Some("went \{far} one way, stood \{rest} ms, came back \{back} at \{now}")
      } else {
        None
      }
    }
  }
}

///|
/// A row's last places (each frame's first time, the last position's time and that position, oldest first; the display's
/// frames `period` apart; its list's way set out last at `set_out`, the row last turned back at `turned`): the frame
/// before the last going at a speed off the frames round it (not where the way set out between them: the rows go on
/// from where they were, as fast as the way has them), or a move one way then back within rows_back_frames a second time
/// within rows_turn_ms of the turn before. And when it turned back now (`turned` as it was where it did not). Where the
/// way did set out between them, a frame many times as far as both of those round it is a step all the same
/// (rows_step_least, rows_step_times), unless `faint`: a row not half open, what it holds not seen.
fn rows_steady_fault(
  seen : Array[(Double, Double, Double)],
  period : Double,
  set_out~ : Double,
  turned~ : Double,
  faint? : Bool = false,
) -> (String?, Double) {
  let n = seen.length()
  let speed = fn(a : Int) {
    let (_, t0, y0) = seen[a]
    let (_, t1, y1) = seen[a + 1]
    (y1 - y0) / (t1 - t0)
  }
  // its speed off the way the frames round it go: a step (a spike), a stop on its way (a dip), a start at full speed
  if n >= 4 && seen[0].1 < seen[1].1 && seen[1].1 < seen[2].1 && seen[2].1 < seen[3].1 {
    let v0 = speed(0) * period
    let v1 = speed(1) * period
    let v2 = speed(2) * period
    if !(set_out > seen[0].1 && set_out <= seen[3].1) {
      let off = (v1 - (v0 + v2) / 2.0).abs()
      if off > rows_speed_least && off > 0.5 * dmax(v0.abs(), v2.abs()) {
        return (Some("went \{v1} a frame between \{v0} and \{v2} at \{seen[2].1}"), turned)
      }
    } else if !faint && v1.abs() > rows_step_least * period / frame_period_default &&
      v1.abs() > rows_step_times * dmax(v0.abs(), v2.abs()) {
      // (the way set out between them: the rows go on from where they were at the speed it has them, which may be
      // another than before; a frame many times as far as both of those round it is no speed taken up, but a step the
      // way's setting out hid)
      return (Some("went \{v1} in one frame as its list's way set out, between \{v0} and \{v2} at \{seen[2].1}"), turned)
    }
  }
  // one way, then back: once is the way's turning to where it now ends; again soon after, a jolt
  if n >= 3 {
    let e = seen[n - 1].2 - seen[n - 2].2
    for a in (n - 1 - rows_back_frames)..<(n - 2) {
      if a < 0 {
        continue
      }
      let d = seen[a + 1].2 - seen[a].2
      if d.abs() >= rows_back_least && e.abs() >= rows_back_least && d * e < 0.0 {
        // (the turn is where it stood furthest that way, whichever pair of frames finds it: one turn, found again as
        // the frames go on, is the same turn)
        let mut at = seen[a + 1].1
        let mut far = seen[a + 1].2
        for b in (a + 1)..<n {
          if (d > 0.0 && seen[b].2 > far) || (d < 0.0 && seen[b].2 < far) {
            far = seen[b].2
            at = seen[b].1
          }
        }
        if at == turned {
          return (None, turned)
        }
        if at < turned + rows_turn_ms {
          return (Some("moved \{d} at \{at}, back \{e} at \{seen[n - 1].1}, turned back at \{turned} before"), at)
        }
        return (None, at)
      }
    }
  }
  (None, turned)
}

///|
/// The rule held on the frame just drawn: a jolt not found before by this Tester, past its file's bar, fails the test
/// at once, with what and where.
fn Tester::hold_rows_steady(self : Tester) -> Unit {
  let c = g()
  let faults = c.rows_steady_faults(self.fake.time, self.motion_period())
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
    motion_known_said("rows_steady", rows_steady.file, rows_steady.found.length(), bar, f)
    if self.motion == Count {
      println("MOTION rows_steady \{rows_steady.file}: \{f} (the Tester made at \{looks_made_at.val})")
      continue
    }
    if rows_steady.found.length() > bar {
      let said = "rows not steady (rows_steady.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{f}; \{rows_steady.found.length()} now, \{bar} known in \{rows_steady.file}"
      @halt.saying(said)
    }
  }
}
