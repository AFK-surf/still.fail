// A display's frames at 60, 120, 24 and 7 a second, each worked out at once from the grid's origin (tester_time.mbt's
// grid_moment): a moment two rates both draw is one double at both, to the bit, not two a few last bits apart (24's
// nth frame and 120's 5nth, k periods of 1000/24 against 5k of 1000/120 till 2026-11-12).

///|
/// The rates a test runs at (MBUI_TEST_FPS, scripts/fps_check.sh), frames a second.
let grid_rates : Array[Double] = [60.0, 120.0, 24.0, 7.0]

///|
/// How long each rate's frames are drawn: three seconds, every rate's frames meeting every other's three times and more.
let grid_run_ms : Double = 3000.0

///|
/// What is one moment of two rates' grids: each pair of frames (the `k`th of `a`'s, the `j`th of `b`'s, counted from
/// the same origin) that are one moment in whole numbers (k / a = j / b), said where the two doubles are not the same to
/// the bit; and how many such pairs there were.
fn grid_shared_differ(a : Double, at_a : Map[Int, Double], b : Double, at_b : Map[Int, Double]) -> (Array[String], Int) {
  let out = []
  let mut shared = 0
  for k, x in at_a {
    let kb = k * b.to_int()
    if kb % a.to_int() != 0 {
      continue
    }
    match at_b.get(kb / a.to_int()) {
      Some(y) => {
        shared = shared + 1
        if x.reinterpret_as_int64() != y.reinterpret_as_int64() {
          out.push("\{a} a second's frame \{k} at \{x}, \{b}'s \{kb / a.to_int()} at \{y}")
        }
      }
      None => ()
    }
  }
  (out, shared)
}

///|
test "a display's frames at 60, 120, 24 and 7 a second: every moment two rates' frames share is the same double at both" {
  let drawn : Array[Map[Int, Double]] = []
  for rate in grid_rates {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    t.set_frame_period(1000.0 / rate)
    let origin = t.time()
    let at : Map[Int, Double] = Map([])
    t.each_frame(Some(fn() {
      // (which of the grid's frames it is: its count of periods from the origin, a whole number)
      at[((t.time() - origin) * rate / 1000.0).round().to_int()] = t.time()
    }))
    t.run_for(grid_run_ms)
    t.each_frame(None)
    assert_eq(at.length(), (grid_run_ms * rate / 1000.0).floor().to_int())
    drawn.push(at)
  }
  let faults = []
  for i in 0..<grid_rates.length() {
    for j in (i + 1)..<grid_rates.length() {
      let (differ, shared) = grid_shared_differ(grid_rates[i], drawn[i], grid_rates[j], drawn[j])
      // (every pair meets: 7's frames every second, at 3 of them)
      assert_true(shared >= 3)
      for d in differ {
        faults.push(d)
      }
    }
  }
  assert_eq(faults, [])
}

///|
test "run_for's frames on its way at a rate (MBUI_TEST_FPS's grid, from the Tester's start): every moment two rates share is the same double at both" {
  // (between_after's grid, the same grid_moment: from 1000, a Tester's start, and from a clock of days, a device's)
  for origin in [1000.0, 3.0 * 86400000.0 + 0.3] {
    let grids = grid_rates.map(fn(rate) {
      let at : Map[Int, Double] = Map([])
      for k in 0..<(grid_run_ms * rate / 1000.0).to_int() {
        at[k] = grid_moment(origin, k.to_double(), 1000.0 / rate)
      }
      at
    })
    let faults = []
    for i in 0..<grid_rates.length() {
      for j in (i + 1)..<grid_rates.length() {
        let (differ, shared) = grid_shared_differ(grid_rates[i], grids[i], grid_rates[j], grids[j])
        assert_true(shared >= 3)
        for d in differ {
          faults.push(d)
        }
      }
    }
    assert_eq(faults, [])
  }
}

///|
test "a frame period that is no whole rate's (a run's tape's): its frames k times it from the origin, as ever" {
  let period = 16.68
  for k in [0, 1, 7, 600] {
    assert_eq(
      grid_moment(1000.0, k.to_double(), period).reinterpret_as_int64(),
      (1000.0 + k.to_double() * period).reinterpret_as_int64(),
    )
  }
}
