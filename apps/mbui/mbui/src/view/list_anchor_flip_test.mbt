// A list laid out from its anchor flung down toward its foot where its rows are not as tall as they are counted to be
// (their mean, of those measured): how far it can go, worked out as it is laid out, is the same each pass of the frame
// whether the fling is to meet its foot now or later, so a frame's passes end (2026-11-06: a chat's list flung to its
// foot ran each frame to laid_passes_most, how far it could go said one way and the other each pass).

///|
test "scrolls_anchored: flung down to its foot, rows taller and shorter than counted: no frame runs its layout to the most" {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let cases = []
  for feel in [("Android", @view.ListFeel::Android), ("iOS", @view.ListFeel::Ios), ("desktop", @view.ListFeel::Desktop)] {
    for up in [300.0, 900.0, 2500.0] {
      for speed in [20.0, 60.0, 140.0] {
        cases.push((feel, up, speed))
      }
    }
  }
  let tall = fn(k : Int) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let not_at_end : Array[String] = []
  let not_flung : Array[String] = []
  for cs in cases {
    let ((name, feel), up, speed) = cs
    let c = anchored_case(200, tall_of=tall)
    c.tree.lists_feel(fn() { (feel, 3.0) })
    let was = told.length()
    // (frames every 16 ms till `till`)
    let run_to = fn(from : Double, till : Double) {
      let mut at = from
      while at < till {
        c.tree.frame(390.0, 844.0, now=at) |> ignore
        at = at + 16.0
      }
    }
    // (flung by a finger moved `by` (up, less than 0: toward its foot) at `at`: whether the list took the finger and each
    // of its events)
    let fling = fn(by : Double, at : Double) -> Bool {
      let from = if by < 0.0 { 90.0 } else { 10.0 }
      match c.tree.claimer_of(c.tree.claimers_at(150.0, from), 0.0, by) {
        Some(id) =>
          c.tree.drag_at(id, Down, 150.0, from, at) &&
          c.tree.drag_at(id, Moved, 150.0, from + by / 2.0, at + 5.0) &&
          c.tree.drag_at(id, Moved, 150.0, from + by, at + 10.0) &&
          c.tree.drag_at(id, Up, 150.0, from + by, at + 10.0)
        None => false
      }
    }
    // (where its rows are drawn: each made, its top)
    let drawn = fn() { c.made().map(fn(k) { (k, c.top(k).unwrap_or(0.0)) }) }
    // (how far what it holds moved up, by a row drawn before and after (one of the first, else by which rows are made:
    // further down the column, up); not by how far it counts itself scrolled, which it counts anew at its end)
    let moved_up = fn(was : Array[(Int, Double)], now : Array[(Int, Double)]) -> Double {
      for b in was {
        match now.iter().find_first(fn(a) { a.0 == b.0 }) {
          Some(a) => return b.1 - a.1
          None => ()
        }
      }
      match (was.get(0), now.get(0)) {
        (Some(b), Some(a)) => (a.0 - b.0).to_double()
        _ => 0.0
      }
    }
    // (a fling that is to move it: taken, and what it holds moved that way by its end)
    let flung = fn(what : String, by : Double, at : Double, till : Double) {
      let was = drawn()
      let took = fling(by, at)
      run_to(at + 16.0, till)
      let d = moved_up(was, drawn())
      if !took || (by < 0.0 && d <= 0.0) || (by > 0.0 && d >= 0.0) {
        not_flung.push("\{name} up \{up} speed \{speed}, \{what}: taken \{took}, moved up \{d}")
      }
    }
    // (up from its end, rows measured on the way)
    c.tree.wheel_at(150.0, 50.0, 0.0, -up, 0, 10.0) |> ignore
    run_to(26.0, 1500.0)
    // (flung down, toward its foot (the slowest short of it); again, unless at its foot already; up, away from it; and
    // down to it, hard)
    flung("down", -speed, 1500.0, 6000.0)
    let foot = fn() { c.top(199).map(fn(top) { top + tall(199) }) }
    if foot() == Some(100.0) {
      run_to(6016.0, 9000.0)
    } else {
      flung("down again", -speed, 6000.0, 9000.0)
    }
    flung("up", speed, 9000.0, 13000.0)
    flung("down hard", -speed * 3.0, 13000.0, 20000.0)
    if foot() != Some(100.0) {
      not_at_end.push("\{name} up \{up} speed \{speed}: its last row's foot at \{foot()} after the last fling")
    }
    c.tree.dispose()
    if told.length() > was {
      told[was] = "\{name} up \{up} speed \{speed}: " + told[was]
    }
  }
  @view.faults_stop.val = true
  @view.fault_told.val = None
  let passes = told.filter(fn(s) { s.contains("layout passes in one") })
  assert_true(passes.is_empty(), msg="\{passes.length()} of \{cases.length()}: " + passes.iter().take(3).collect().join("\n"))
  assert_true(not_flung.is_empty(), msg="\{not_flung.length()}: " + not_flung.iter().take(3).collect().join("\n"))
  assert_true(not_at_end.is_empty(), msg=not_at_end.iter().take(3).collect().join("\n"))
}

///|
/// The same list flung down to its foot, then up, with frames every `step` ms: where its rows are at each moment said
/// (2000 ms after each fling, and at the end), and whether a frame's layout ran to the most.
fn flip_run(step : Double, up : Double, speed : Double) -> (Array[(Int, Double?)], Array[(Int?, Double?)], Bool) raise {
  let told : Array[String] = []
  let missed : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let c = anchored_case(200, tall_of=fn(k) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } })
  c.tree.lists_feel(fn() { (@view.ListFeel::Android, 3.0) })
  let at = Ref(10.0)
  // (frames every `step` ms after the last, as long as they come before `till`; what is drawn at `till` itself, said)
  let frames_before = fn(till : Double) {
    while at.val + step < till {
      at.val = at.val + step
      c.tree.frame(390.0, 844.0, now=at.val) |> ignore
    }
  }
  let run_to = fn(till : Double) {
    frames_before(till)
    at.val = till
    c.tree.frame(390.0, 844.0, now=till) |> ignore
  }
  // (a finger moved `by` from t to t + 10, let go there: each of its events at its moment, the frames due before it
  // drawn before it, in the order of the one clock)
  let fling = fn(by : Double, t : Double) {
    frames_before(t)
    let from = if by < 0.0 { 90.0 } else { 10.0 }
    match c.tree.claimer_of(c.tree.claimers_at(150.0, from), 0.0, by) {
      Some(id) => {
        let down = c.tree.drag_at(id, Down, 150.0, from, t)
        frames_before(t + 5.0)
        let moved = c.tree.drag_at(id, Moved, 150.0, from + by / 2.0, t + 5.0)
        frames_before(t + 10.0)
        let last = c.tree.drag_at(id, Moved, 150.0, from + by, t + 10.0) &&
          c.tree.drag_at(id, Up, 150.0, from + by, t + 10.0)
        if !(down && moved && last) {
          missed.push("at \{t}: an event not taken")
        }
      }
      None => missed.push("at \{t}: the finger not taken")
    }
  }
  let seen : Array[(Int, Double?)] = []
  // (and at each: the row a finger at (150, 50) is on, by where the rows are put, and when what it is on by itself ends)
  let ends : Array[(Int?, Double?)] = []
  let look = fn() {
    for k in c.made() {
      seen.push((k, c.top(k)))
    }
    let on = c.made().iter().find_first(fn(k) {
      match c.live.get(k) {
        Some(b) => {
          let (_, y, _, h) = b.rect()
          y <= 50.0 && 50.0 < y + h
        }
        None => false
      }
    })
    ends.push((on, c.scroll.glides_till()))
  }
  c.tree.wheel_at(150.0, 50.0, 0.0, -up, 0, 10.0) |> ignore
  fling(-speed, 1500.0)
  run_to(3500.0)
  look()
  fling(-speed, 6000.0)
  run_to(8000.0)
  look()
  fling(speed, 9000.0)
  run_to(11000.0)
  look()
  run_to(20000.0)
  look()
  c.tree.dispose()
  @view.faults_stop.val = true
  @view.fault_told.val = None
  guard missed.is_empty() else { fail("step \{step} up \{up} speed \{speed}: \{missed}") }
  (seen, ends, told.iter().any(fn(s) { s.contains("layout passes in one") }))
}

///|
test "scrolls_anchored flung to its foot and back, its rows not as tall as counted: where they are, the row a finger is on and when it comes to rest, at each moment the same at 60, 144 and 30 frames a second" {
  for cs in [(300.0, 140.0), (900.0, 60.0), (2500.0, 20.0)] {
    let (up, speed) = cs
    let (at60, end60, ran60) = flip_run(1000.0 / 60.0, up, speed)
    let (at144, end144, ran144) = flip_run(1000.0 / 144.0, up, speed)
    let (at30, end30, ran30) = flip_run(1000.0 / 30.0, up, speed)
    assert_eq((ran60, ran144, ran30), (false, false, false), msg="up \{up} speed \{speed}: a frame's layout ran to the most")
    assert_eq(at144, at60, msg="up \{up} speed \{speed}: 144 against 60")
    assert_eq(at30, at60, msg="up \{up} speed \{speed}: 30 against 60")
    assert_eq(end144, end60, msg="up \{up} speed \{speed}: the row under the finger and the end, 144 against 60")
    assert_eq(end30, end60, msg="up \{up} speed \{speed}: the row under the finger and the end, 30 against 60")
  }
}
