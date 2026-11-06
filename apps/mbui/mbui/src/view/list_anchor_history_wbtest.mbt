// A list laid out from its anchor flung, the same input drawn by other histories of frames (60, 144 and 30 a second,
// none between, each frame at 60 drawn 16 ms after its moment): at each moment looked at, from the same input anew so
// no frame drawn to look is in another's history, what is drawn (each row's rectangle as laid out, before what shows
// past an end stretches it: not its pixels), how far past its end it shows, the row a press finds, when it is to rest,
// the rows living, the same in each. The input is the hand's, each step of it taken: the tree brought to the press's
// moment (no frame drawn), the press found on a row and taken by the list, each move and the lift taken, the list
// going on by itself once let go, at rest by the last moment. Rows of many heights over many windows never measured
// before it is flung; flung to its foot and short of it; what it holds changed at an event's moment as it goes (a row
// gone at its end, a row come at its end, a row 100 taller); a row measured on the way before, its room opening as it
// goes or its room by the width changed; pressed again after its glide would have ended, no frame drawn since.

///|
priv struct HistRun {
  step : Double
  ahead : Double
}

///|
/// The list flung: laid out from its end or its top, how many rows, the wheel that brings it where it is flung from
/// (none: the default, `up` toward its start), room kept under its last row, and where the hand presses.
priv struct HistShape {
  from_end : Bool
  n : Int
  wheel : Double?
  foot_room : Double
  press_y : Double
}

///|
let hist_long : HistShape = { from_end: true, n: 400, wheel: None, foot_room: 0.0, press_y: 90.0 }

///|
priv struct HistSeen {
  past : Double
  hit : Int?
  rows : Array[(Int, Double, Double)]
  rests : Double?
  told : Array[String]
  grabbed : Int?
  live : Array[Int]
  opened : Int
  dropped : Int
  laid : Int
}

///|
/// What happens on the way: nothing (-1), the last row gone (0), a row come at its end (1), row 396 100 taller (2),
/// row `room_row`'s room opening 100 more over 300 ms (3), the list 250 wide where row `room_row`'s room is as tall as
/// its natural height times the width over 300 (4), the list 250 wide where each row is as tall as its height times 300 over the width, as words wrapped again are (5).
fn hist_look(
  run : HistRun,
  up : Double,
  by : Double,
  tall : (Int) -> Double,
  change : Int,
  change_at : Double,
  at : Double,
  room_row? : Int = 392,
  room_below? : Bool = false,
  regrab? : Bool = false,
  rest_by? : Double = 1.0e9,
) -> HistSeen {
  let told : Array[String] = []
  faults_stop.val = false
  fault_told.val = Some(fn(said) { told.push("fault: " + said) })
  let keys = @signals.signal(Array::makei(n, fn(i) { i }))
  let heights : Map[Int, @signals.Signal[Double]] = {}
  for k in 0..<(n + 1) {
    heights[k] = @signals.signal(tall(k))
  }
  let wide = @signals.signal(300.0)
  let opening : @signals.Signal[Double?] = @signals.signal(None)
  let made : Map[Int, View] = {}
  let opened = Ref(0)
  let dropped = Ref(0)
  let scroll = Scroll::list()
  let list : Ref[View?] = Ref(None)
  // (where `room_below`, the row 3 under the one the hand presses: under the window, measured as the wheel went by)
  let room_key = Ref(room_row)
  // (row `room_row`'s room: as tall as it is, but opening (3) or by the width (4))
  let rooms = fn() -> (Int, Double, Double) -> ListRoom {
    match (change, opening.get(), list.val) {
      (3, Some(from), Some(v)) => {
        let k = dmin(1.0, dmax(0.0, (v.drawn_at() - from) / 300.0))
        fn(key, natural, _w) { if key == room_key.val { list_room(natural + 100.0 * k) } else { list_room(natural) } }
      }
      (4, _, _) => fn(key, natural, w) { if key == room_key.val { list_room(natural * w / 300.0) } else { list_room(natural) } }
      _ => fn(_, natural, _) { list_room(natural) }
    }
  }
  let tree = Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(wide.get()) })).height(Is(Some(100.0))) |> ignore
      list.val = Some(o)
      o.scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, from_end=shape.from_end, foot_room=fn() { shape.foot_room }, rooms~, fn(b, k) {
        made[k] = b
        opened.val += 1
        let h = heights[k]
        b
        .owns(fn() {
          made.remove(k)
          dropped.val += 1
        })
        .height(By(fn() { Some(if change == 5 { (h.get() * 300.0 / wide.get()).round() } else { h.get() }) }))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // (the logic's moments as the run goes, frames, the hand and what is told: never back)
  let logic = Ref(0.0)
  let moment = fn(t : Double, what : String) {
    if t < logic.val {
      told.push("\{what} at \{t}, after \{logic.val}")
    }
    logic.val = t
  }
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let wheel = shape.wheel.unwrap_or(-up)
  if wheel != 0.0 && !tree.wheel_at(150.0, 50.0, 0.0, wheel, 0, 10.0) {
    told.push("the wheel not taken")
  }
  // (the same frames before the press in each: the wheel's way drawn at 60 a second)
  let mut t = 10.0
  while t + 16.0 < 1500.0 {
    t = t + 16.0
    tree.frame(390.0, 844.0, now=t) |> ignore
  }
  let ids = fn() {
    let m : Map[Int, Int] = {}
    for k, v in made {
      m[v.id().at] = k
    }
    m
  }
  let row_at = fn(x : Double, y : Double) {
    match tree.target_at(x, y) {
      Pressed(pid) => ids().get(pid.at)
      _ => None
    }
  }
  // (the hand: brought to its moment, no frame drawn; found on a row, taken by the list, each step of it taken)
  tree.bring_to(1500.0)
  let grabbed = row_at(150.0, py)
  if room_below {
    room_key.val = grabbed.map_or(-1, fn(g) { g + 3 })
  }
  if grabbed is None {
    told.push("the press at (150, 90) finds no row")
  }
  match tree.claimer_of(tree.claimers_at(150.0, py), 0.0, -by) {
    Some(id) => {
      let steps = [
        ("down", Down, py, 1500.0),
        ("moved", Moved, py - by / 2.0, 1505.0),
        ("moved", Moved, py - by, 1510.0),
        ("up", Up, py - by, 1510.0),
      ]
      for s in steps {
        moment(s.3, s.0)
        if !tree.drag_at(id, s.1, 150.0, s.2, s.3) {
          told.push("\{s.0} at \{s.3} not taken")
        }
      }
    }
    None => told.push("no claimer for the drag")
  }
  match scroll.glides_till() {
    Some(e) if e > 1510.0 => ()
    g => told.push("let go, not going on by itself: rests at \{g}")
  }
  t = 1510.0
  let mut changed = change < 0
  let tell = fn(when : Double) {
    moment(when, "an event")
    tree.event(when, fn() {
      match change {
        0 => keys.set(keys.get()[0:keys.get().length() - 1].to_array())
        1 => {
          let ks = keys.get().copy()
          ks.push(n)
          keys.set(ks)
        }
        2 => heights[396].set(tall(396) + 100.0)
        3 => opening.set(Some(when))
        _ => wide.set(250.0)
      }
    })
  }
  // (a frame of the logic's moment `now`, drawn `ahead` after it)
  let frame = fn(now : Double) {
    if run.ahead > 0.0 {
      tree.at(now + run.ahead)
    }
    moment(now, "a frame")
    tree.frame(390.0, 844.0, now~) |> ignore
  }
  while t + run.step < at - run.ahead {
    if !changed && t + run.step >= change_at {
      changed = true
      tell(change_at)
    }
    t = t + run.step
    frame(t)
  }
  if !changed && change_at <= at {
    tell(change_at)
  }
  let laid_before = tree.work().laid
  // (pressed again at the moment looked at, no frame drawn since: what it finds and where the list is then)
  // (the press again: the tree brought to its moment, no frame drawn, then what it finds)
  if regrab {
    tree.bring_to(at)
  }
  let hit = if regrab {
    let hit = row_at(150.0, 50.0)
    match tree.claimer_of(tree.claimers_at(150.0, 50.0), 0.0, 20.0) {
      Some(id) => {
        moment(at, "the press again")
        if !tree.drag_at(id, Down, 150.0, 50.0, at) {
          told.push("the press again at \{at} not taken")
        }
        if !tree.drag_at(id, Up, 150.0, 50.0, at) {
          told.push("its lift at \{at} not taken")
        }
      }
      None => told.push("no claimer for the press again")
    }
    hit
  } else {
    None
  }
  // (looked at as drawn at `at`; pressed again at `at`, the frame after it of that moment, drawn `ahead` later)
  frame(if regrab { at } else { at - run.ahead })
  let m = ids()
  let rows = []
  for d in tree.drawn() {
    match m.get(d.id.at) {
      Some(k) => rows.push((k, d.y, d.h))
      None => ()
    }
  }
  let hit = if regrab { hit } else { row_at(150.0, 50.0) }
  if hit is None {
    told.push("a press at (150, 50) finds no row")
  }
  let rests = scroll.glides_till()
  if at >= rest_by {
    match rests {
      Some(e) if e > at => told.push("not at rest by \{at}: rests at \{e}")
      _ => ()
    }
  }
  let live = made.keys().collect()
  live.sort()
  let seen = {
    // (what shows past its end as drawn at the moment looked at: a frame drawn ahead is drawn at it, its logic before)
    past: @signals.untracked(fn() {
      match scroll.past_at(tree.drawn_at()) {
        Some((edge, x, _)) => x * edge.to_double()
        None => 0.0
      }
    }),
    hit,
    rows,
    rests,
    told,
    grabbed,
    live,
    opened: opened.val,
    dropped: dropped.val,
    laid: tree.work().laid - laid_before,
  }
  tree.dispose()
  faults_stop.val = true
  fault_told.val = None
  seen
}

///|
/// Where two lists of drawn rows differ: each row's key and its top and height in each (none where it is not drawn),
/// and the last row's foot in each.
fn hist_rows_differ(a : Array[(Int, Double, Double)], b : Array[(Int, Double, Double)]) -> String {
  let of = fn(rs : Array[(Int, Double, Double)]) {
    let m : Map[Int, (Double, Double)] = {}
    for r in rs {
      m[r.0] = (r.1, r.2)
    }
    m
  }
  let (ma, mb) = (of(a), of(b))
  let ks : Array[Int] = []
  for r in a {
    ks.push(r.0)
  }
  for r in b {
    if !ma.contains(r.0) {
      ks.push(r.0)
    }
  }
  ks.sort()
  let out = []
  for k in ks {
    let (x, y) = (ma.get(k), mb.get(k))
    let same = match (x, y) {
      (Some(p), Some(q)) => (p.0 - q.0).abs() < 0.0001 && (p.1 - q.1).abs() < 0.0001
      _ => false
    }
    if !same {
      out.push("row \{k} \{x} / \{y}")
    }
  }
  let foot = fn(rs : Array[(Int, Double, Double)]) {
    rs.iter().fold(init=None, fn(m : (Int, Double)?, r) { if m.map_or(true, fn(p) { r.0 > p.0 }) { Some((r.0, r.1 + r.2)) } else { m } })
  }
  "\{out.length()} rows differ (top, height): " + out.iter().take(6).collect().join("; ") +
  "; the last row drawn and its foot \{foot(a)} / \{foot(b)}"
}

///|
let hist_runs : Array[HistRun] = [
  { step: 1000.0 / 60.0, ahead: 0.0 },
  { step: 1000.0 / 144.0, ahead: 0.0 },
  { step: 1000.0 / 30.0, ahead: 0.0 },
  { step: 1.0e9, ahead: 0.0 },
  { step: 1000.0 / 60.0, ahead: 16.0 },
]

///|
fn hist_compare(
  what : String,
  up : Double,
  by : Double,
  tall : (Int) -> Double,
  change : Int,
  change_at : Double,
  moments : Array[Double],
  regrab? : Bool = false,
  rest_by? : Double = 1.0e9,
  room_below? : Bool = false,
  shape? : HistShape = hist_long,
) -> Array[String] {
  let wrong = []
  for at in moments {
    let look = fn(run) { hist_look(run, up, by, tall, change, change_at, at, regrab~, rest_by~, room_below~, shape~) }
    let base = look(hist_runs[0])
    let tail = base.rows[if base.rows.length() > 2 { base.rows.length() - 2 } else { 0 }:].to_array()
    println("HIST \{what} at \{at}, 60 a second: rests at \{base.rests}, past its end \{base.past}, a press finds \{base.hit}, grabbed \{base.grabbed}, last rows \{tail}, living \{base.live}, opened \{base.opened} dropped \{base.dropped} laid \{base.laid}")
    if base.told.length() > 0 {
      wrong.push("\{what} at \{at}, 60 a second: " + base.told.join(", "))
    }
    for i in 1..<hist_runs.length() {
      let o = look(hist_runs[i])
      let differs = []
      if (o.past - base.past).abs() > 0.0001 {
        differs.push("past its end \{o.past} against \{base.past}")
      }
      if o.hit != base.hit {
        differs.push("a press finds \{o.hit} against \{base.hit}")
      }
      if o.rests != base.rests {
        differs.push("rests at \{o.rests} against \{base.rests}")
      }
      if o.rows != base.rows {
        differs.push(hist_rows_differ(base.rows, o.rows))
      }
      if o.live != base.live {
        differs.push("rows living \{o.live.length()} against \{base.live.length()}")
      }
      if o.told.length() > 0 {
        differs.push("told: " + o.told.join(", "))
      }
      if differs.length() > 0 {
        wrong.push("\{what} at \{at}, a frame each \{hist_runs[i].step} ms drawn \{hist_runs[i].ahead} ahead: " + differs.join(" | "))
      }
    }
  }
  wrong
}

///|
/// Rows of many heights (20 to 296), never measured before it is flung: over many windows of them.
fn hist_tall(k : Int) -> Double {
  (20 + k * 37 % 277).to_double()
}

///|
fn hist_say(wrong : Array[String]) -> Unit {
  for w in wrong {
    println("HIST " + w)
  }
}

///|
test "scrolls_anchored flung over windows of rows of many heights not measured yet, to its foot and short of it: what is drawn, how far past its end, the row a press finds, when it rests, the same whatever frames are drawn" {
  let moments = [1530.0, 1560.0, 1600.0, 1700.0, 1850.0, 2100.0, 2600.0, 4000.0]
  let wrong = []
  wrong.append(hist_compare("to its foot", 2500.0, 140.0, hist_tall, -1, 0.0, moments, rest_by=4000.0))
  wrong.append(hist_compare("short of it", 6000.0, 30.0, hist_tall, -1, 0.0, moments, rest_by=4000.0))
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}

///|
test "scrolls_anchored flung to its foot, what it holds changed at an event's moment on the way (a row gone at its end, one come, one 100 taller): what is drawn, how far past its end, the row a press finds, when it rests, the same whatever frames are drawn" {
  let moments = [1540.0, 1600.0, 1700.0, 1850.0, 2600.0, 4000.0]
  let wrong = []
  for change in [0, 1, 2] {
    for change_at in [1520.0, 1545.0] {
      wrong.append(hist_compare("change \{change} at \{change_at}", 2500.0, 140.0, hist_tall, change, change_at, moments, rest_by=4000.0))
    }
  }
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}

///|
test "scrolls_anchored flung to its foot past a row measured before, its room opening on the way or its room by the width changed, before it is passed: the same whatever frames are drawn" {
  let moments = [1540.0, 1600.0, 1700.0, 1850.0, 2600.0, 4000.0]
  let wrong = []
  for change in [3, 4, 5] {
    wrong.append(hist_compare("room change \{change} at 1515", 2500.0, 140.0, hist_tall, change, 1515.0, moments, rest_by=4000.0))
    wrong.append(hist_compare("short of its foot, room change \{change} at 1515 of the row 3 under the press", 6000.0, 30.0, hist_tall, change, 1515.0, moments, rest_by=4000.0, room_below=true))
  }
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}

///|
test "scrolls_anchored flung to its foot, pressed again after its glide and its going back would have ended, no frame drawn since: the row the press finds and where the list is, the same whatever frames were drawn" {
  let wrong = []
  wrong.append(hist_compare("pressed again", 2500.0, 140.0, hist_tall, -1, 0.0, [4000.0], regrab=true, rest_by=4000.0))
  wrong.append(hist_compare("pressed again, a row 100 taller at 1545", 2500.0, 140.0, hist_tall, 2, 1545.0, [4000.0], regrab=true, rest_by=4000.0))
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}

///|
/// All of a list of rows of many heights, as tall as they are.
fn hist_all(n : Int, tall : (Int) -> Double) -> Double {
  let mut s = 0.0
  for k in 0..<n {
    s = s + tall(k)
  }
  s
}

///|
test "scrolls_anchored laid out from its top or its end, long or short, one row, room under its last row: flung to either end by the hand, the same whatever frames are drawn" {
  let moments = [1530.0, 1600.0, 1700.0, 1850.0, 2100.0, 2600.0, 4000.0]
  let forty = fn(_k : Int) { 40.0 }
  let wrong = []
  let top_long = { from_end: false, n: 400, wheel: Some(hist_all(400, hist_tall) - 100.0 - 2500.0), foot_room: 0.0, press_y: 90.0 }
  wrong.append(hist_compare("from its top, to its foot", 0.0, 140.0, hist_tall, -1, 0.0, moments, rest_by=4000.0, shape=top_long))
  wrong.append(hist_compare("from its top, to its top", 0.0, -140.0, hist_tall, -1, 0.0, moments, rest_by=4000.0, shape={ ..top_long, wheel: Some(2500.0), press_y: 10.0 }))
  wrong.append(hist_compare("from its top, a row gone at its foot on the way", 0.0, 140.0, hist_tall, 0, 1545.0, moments, rest_by=4000.0, shape=top_long))
  for from_end in [false, true] {
    for n in [1, 2] {
      let y = if from_end { 80.0 } else { 20.0 }
      for by in [140.0, -140.0] {
        wrong.append(hist_compare("from its \{if from_end { "end" } else { "top" }}, \{n} rows of 40, flung \{by}", 0.0, by, forty, -1, 0.0, moments, rest_by=4000.0, shape={ from_end, n, wheel: Some(0.0), foot_room: 0.0, press_y: y }))
      }
    }
  }
  wrong.append(hist_compare("room of 56 under its last row, to its foot", 2500.0, 140.0, hist_tall, -1, 0.0, moments, rest_by=4000.0, shape={ ..hist_long, foot_room: 56.0 }))
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}

///|
test "scrolls_anchored flung toward a foot it counts further than it is (its last rows short): met before a press that comes after its going back is over, no frame drawn since it was let go; the same whatever frames were drawn" {
  let short_tail = fn(k : Int) { if k >= 380 { 20.0 } else { hist_tall(k) } }
  let wrong = []
  wrong.append(hist_compare("its last rows short, pressed again", 2500.0, 140.0, short_tail, -1, 0.0, [1700.0, 1900.0, 2100.0, 2400.0, 4000.0], regrab=true, rest_by=4000.0))
  hist_say(wrong)
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(8).collect().join("\n"))
}
