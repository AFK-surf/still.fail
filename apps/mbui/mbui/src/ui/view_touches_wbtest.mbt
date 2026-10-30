// A touch screen's fingers as the hosts hand them on (each by the system's id for it: touches.mbt), made the app's two:
// what they come to, and a node of the window's tree taking two told each by its own finger from down to end.

///|
/// What each of `events` (phase, the system's id) comes to (touches.mbt), from no finger down.
fn kinds_of(events : Array[(Int, Int)]) -> Array[Int] {
  touches_forget()
  events.map(fn(e) { touch_kind(e.0, e.1) })
}

///|
test "touches: the first let go before the second, the second after, a third while two are down, one called off" {
  // (A 7, B 9: A let go first, B the first from then, its moves the first's)
  assert_eq(kinds_of([(0, 7), (0, 9), (1, 7), (1, 9), (2, 7), (1, 9), (2, 9)]), [0, 4, 1, 5, 8, 1, 2])
  // (B let go first: A the first still)
  assert_eq(kinds_of([(0, 7), (0, 9), (2, 9), (1, 7), (2, 7)]), [0, 4, 6, 1, 2])
  // (C 11 down while A and B are: none of the app's to its end, whatever is let go meanwhile, never put in a place
  // let go; D 13 down once one is, the second, the first as B is let go)
  assert_eq(
    kinds_of([(0, 7), (0, 9), (0, 11), (1, 11), (2, 7), (1, 11), (1, 9), (0, 13), (1, 11), (2, 11), (2, 9), (2, 13)]),
    [0, 4, -1, -1, 8, -1, 1, 4, -1, -1, 8, 2],
  )
  // (one called off: all of it, once; nothing more of either, their ends none)
  assert_eq(kinds_of([(0, 7), (0, 9), (3, 9), (1, 7), (2, 7), (2, 9)]), [0, 4, 3, -1, -1, -1])
  // (one not the app's called off: nothing)
  assert_eq(kinds_of([(0, 7), (0, 9), (0, 11), (3, 11), (1, 7)]), [0, 4, -1, -1, 1])
  touches_forget()
}

///|
/// A Tester with a node taking two fingers over the window's top left (200 by 200), what it is told said in `seen`
/// (which, which finger, where) and when in `at`.
fn touches_tester(seen : Array[String], at? : Array[Double] = []) -> Tester {
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  touches_app(seen, at~)
  t.draw()
  t.drawn_now()
  t
}

///|
fn touches_app(seen : Array[String], at? : Array[Double] = []) -> Unit {
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) {
        h
        .width(Is(Some(200.0)))
        .height(Is(Some(200.0)))
        .on_drag(
          fn(d) {
            seen.push("\{d.kind} \{d.finger} \{d.x},\{d.y}")
            at.push(d.at)
          },
          fingers=2,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The host's touches `events` (phase, the system's id, x, y), 10 ms apart, through a Tester with the window in front
/// till `lost` of them were handed on (none: all along): what the node taking two was told (which, which finger).
fn touched(events : Array[(Int, Int, Double, Double)], lost? : Int = -1) -> Array[String] {
  let seen : Array[String] = []
  let t = touches_tester(seen)
  t.app_state(true, true)
  let t0 = t.time()
  for i, e in events {
    if i == lost {
      t.app_state(true, false)
    }
    t.touch_raw(e.0, e.1, e.2, e.3, t0 + 10.0 * (i + 1).to_double())
  }
  t.drawn_now()
  seen.map(fn(s) {
    let w = s.split(" ").collect()
    "\{w[0]} \{w[1]}"
  })
}

///|
test "touches on the window's tree: the first let go, the second goes on as the same finger, its down and its moves its own" {
  let seen : Array[String] = []
  let at : Array[Double] = []
  let t = touches_tester(seen, at~)
  let t0 = t.time()
  for i, e in [(0, 7, 10.0, 10.0), (0, 9, 50.0, 50.0), (2, 7, 12.0, 12.0), (1, 9, 60.0, 70.0), (2, 9, 61.0, 71.0)] {
    t.touch_raw(e.0, e.1, e.2, e.3, t0 + 10.0 * (i + 1).to_double())
  }
  t.drawn_now()
  assert_eq(seen, ["Down 0 10,10", "Down 1 50,50", "Up 0 12,12", "Moved 1 60,70", "Up 1 61,71"])
  assert_eq(at, [t0 + 10.0, t0 + 20.0, t0 + 30.0, t0 + 40.0, t0 + 50.0])
}

///|
test "touches on the window's tree: a third finger never told, the second then let go and another put down a new one; one called off ends it all" {
  let seen = touched([
    (0, 7, 10.0, 10.0),
    (0, 9, 50.0, 50.0),
    (0, 11, 90.0, 90.0),
    (1, 11, 95.0, 95.0),
    (2, 9, 50.0, 50.0),
    (1, 11, 99.0, 99.0),
    (0, 13, 30.0, 30.0),
    (3, 13, 30.0, 30.0),
    (1, 7, 11.0, 11.0),
    (2, 7, 11.0, 11.0),
  ])
  assert_eq(seen, ["Down 0", "Down 1", "Up 1", "Down 2", "Off 0", "Off 2"])
}

///|
test "touches on the window's tree: the window no longer in front with two down: called off then, both, nothing more of them" {
  let seen = touched([(0, 7, 10.0, 10.0), (0, 9, 50.0, 50.0), (1, 9, 55.0, 55.0), (1, 7, 15.0, 15.0), (2, 7, 15.0, 15.0)], lost=3)
  assert_eq(seen, ["Down 0", "Down 1", "Moved 1", "Off 0", "Off 1"])
}

///|
test "touches kept on the tape as the app took them (the first let go as such, each at its own moment) and given again: told the same" {
  let seen1 : Array[String] = []
  let at1 : Array[Double] = []
  let t1 = Tester::new(fn(_c) {  })
  t1.check_looks(false)
  touches_app(seen1, at=at1)
  t1.draw()
  t1.run_for(16.0)
  t1.start_tape()
  let events = [(0, 7, 10.0, 10.0), (0, 9, 50.0, 50.0), (0, 11, 80.0, 80.0), (2, 7, 12.0, 12.0), (1, 9, 60.0, 70.0)]
  for i, e in events {
    t1.advance(3.0)
    t1.touch_raw(e.0, e.1, e.2, e.3, t1.time())
    if i == 2 {
      t1.run_for(16.0)
    }
  }
  t1.run_for(16.0)
  t1.advance(3.0)
  t1.touch_raw(2, 9, 61.0, 71.0, t1.time())
  t1.run_for(16.0)
  let tape = t1.tape()
  let lines = tape.split("\n").map(l => l.to_owned()).to_array()
  // (the app's kinds kept, the first let go as 8, never the host's own)
  let kinds = lines
    .filter(l => l.has_prefix("INPUT "))
    .map(l => @json.parse(l.view(start_offset=6).to_owned()) catch { _ => Json::null() })
    .map(j => match j {
      Object(m) =>
        match m.get("a") {
          Some(Array(a)) =>
            match a[0] {
              Number(k, ..) => k.to_int()
              _ => -1
            }
          _ => -1
        }
      _ => -1
    })
  assert_eq(kinds, [0, 4, 8, 1, 2])
  let seen2 : Array[String] = []
  let at2 : Array[Double] = []
  let t2 = Tester::new(fn(_c) {  })
  t2.check_looks(false)
  touches_app(seen2, at=at2)
  t2.draw()
  t2.run_for(16.0)
  let frames = t2.replay_frames(tape)
  for f in frames {
    assert_eq(f.2, f.1)
  }
  assert_eq((seen2, at2), (seen1, at1))
  assert_eq(seen1, ["Down 0 10,10", "Down 1 50,50", "Up 0 12,12", "Moved 1 60,70", "Up 1 61,71"])
}
