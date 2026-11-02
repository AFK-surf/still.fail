// A page's list on the window's tree (Scroll::list) by itself: flung into its end, where it is, how far it shows past
// it and what is drawn of it at each moment the same at 60 Hz, at 120 Hz or in one jump to each (where it meets its end
// worked out as it is let go, not found at a frame); what goes back past an end gone with it as it goes; its bar on its
// own track while what it holds is stretched; grown above what is in sight as it moves by itself, what is in sight
// staying where it is drawn and what moves it going on to its end moved as much (list_scroll_same_wbtest.mbt holds it
// to an old view's list).

///|
/// How far apart the moments it is looked at are (met_at): on the grid of the display's frames at 60 and at 120 Hz.
let met_step_ms : Double = 50.0

///|
/// Flung into its end on `platform` (same_tree's 40 rows), the display's frames `period` apart (0: none between, each
/// moment come to in one jump): every 50 ms from the hand let go for 2 s, where it is, how far it shows past its end and
/// what is drawn of its rows; and when it is at rest, as said as it was let go.
fn met_at(platform : Int, period : Double) -> (Array[(Double, Double, Double)], Array[Array[Array[Double]]], Double?) {
  let (t, s) = same_tree(40, platform)
  swipe(t, 700.0, -24.0, 12)
  let tree = view_tree().unwrap()
  let rest = s.glides_till()
  if period > 0.0 {
    t.set_frame_period(period)
  }
  let at = []
  let drawn = []
  for _ in 0..<40 {
    if period > 0.0 {
      t.run_for(met_step_ms)
    } else {
      t.run_for_exact(50.0)
    }
    at.push((t.time(), s.at(tree), s.past(tree)))
    drawn.push(same_drawn(t))
  }
  (at, drawn, rest)
}

///|
test "a page's list flung into its end: what it shows at each moment the same at any frame rate" {
  let differ = []
  for platform in [1, 2] {
    let (a, ad, ar) = met_at(platform, 1000.0 / 60.0)
    // (it met its end and showed past it)
    if !a.iter().any(fn(f) { f.2.abs() > 0.01 }) || a.last().unwrap().1 != 40.0 * 50.0 - 844.0 {
      differ.push("\{platform}: not past its end: \{a}")
    }
    for period in [1000.0 / 120.0, 0.0] {
      let (b, bd, br) = met_at(platform, period)
      if ar != br {
        differ.push("\{platform} at \{period}: at rest at \{br}, at 60 Hz \{ar}")
      }
      for k in 0..<a.length() {
        // (the same moment, however its time was summed: to a millionth of a ms; what shows then to a millionth)
        if (a[k].0 - b[k].0).abs() > 1.0e-6 || (a[k].1 - b[k].1).abs() > 1.0e-6 || (a[k].2 - b[k].2).abs() > 1.0e-6 {
          differ.push("\{platform} at \{period}: \{b[k]}, at 60 Hz \{a[k]}")
          break
        }
        let alike = ad[k].length() == bd[k].length() &&
          (0).until(ad[k].length()).iter().all(fn(i) {
            ad[k][i].length() == bd[k][i].length() &&
            (0).until(ad[k][i].length()).iter().all(fn(j) { (ad[k][i][j] - bd[k][i][j]).abs() <= 1.0e-6 })
          })
        if !alike {
          differ.push("\{platform} at \{period}: drawn at \{a[k].0} \{bd[k][:imin(3, bd[k].length())]}, at 60 Hz \{ad[k][:imin(3, ad[k].length())]}")
          break
        }
      }
    }
  }
  if differ.length() > 0 {
    fail(differ.join("\n"))
  }
}

///|
test "a page's list let go of as what it was pulled past its top goes back: nothing of it said to move after" {
  for platform in [1, 2] {
    let shown = @signals.signal(true)
    let (t, s) = same_tree(100, platform, shown~)
    t.touch(0, 200.0, 300.0)
    for k in 1..=10 {
      t.advance(drag_step_ms)
      t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
      t.draw()
    }
    t.advance(tracker_horizon_ms)
    t.touch(2, 200.0, 400.0)
    t.draw()
    t.advance(same_back_ms)
    t.draw()
    // (going back, no fling: said to move till then)
    let tree = view_tree().unwrap()
    assert_true(s.past(tree) > 0.0, msg="\{platform}: nothing past its top")
    let rest = s.glides_till().unwrap()
    assert_eq(rest_of("a list's fling, the tree's"), rest)
    // (let go: at rest at once, nothing past its end, nothing said to move)
    shown.set(false)
    t.draw()
    assert_eq(s.glides_till(), None)
    assert_eq(s.past(tree), 0.0)
    assert_eq(rest_of("a list's fling, the tree's"), -1.0)
  }
}

///|
/// Android's list with its bar, held by a finger dragged up from (200, 800) by `by` (after the slop): its bar's and its
/// rows' drawing.
fn bar_held(by : Double) -> (Array[Array[Double]], Array[Array[Double]]) {
  let (t, _) = same_tree(100, 2, pointing=Mouse, bar=true)
  t.touch(0, 200.0, 800.0)
  let steps = 20
  for k in 1..=steps {
    t.advance(drag_step_ms)
    t.touch(1, 200.0, 800.0 - (8.0 + by) * k.to_double() / steps.to_double())
    t.draw()
  }
  let rows = same_drawn(t)
  // (what else is drawn: the bar)
  let bar = t.drawn_instances().filter(fn(a) { a[5] == 0.0 && a[0] > 350.0 && a[2] < 20.0 }).map(fn(a) { a[0:5].to_array() })
  (bar, rows)
}

///|
test "Android: a page's list pulled past its foot, its rows stretched: its bar on its own track, as at its foot unstretched" {
  // (5000 high, 844 shown: at its foot, and 200 past it)
  let (at_foot, rows) = bar_held(5000.0 - 844.0)
  let (past, stretched) = bar_held(5000.0 - 844.0 + 200.0)
  assert_true(at_foot.length() > 0, msg="no bar drawn")
  assert_true(rows != stretched, msg="its rows not stretched")
  assert_eq(past, at_foot)
}

///|
/// How long a page's list is left to move by itself before what it holds grows above what is in sight, and by how much.
let grown_after_ms : Double = 100.0

///|
let grown_by : Double = 120.0

///|
/// Long enough for what it moves by to be over.
let grown_rest_ms : Double = 3000.0

///|
/// A page's list on `platform` set moving by `hand`, grown `by` above what is in sight `grown_after_ms` on (0: not): what
/// is drawn of its rows and where it is drawn then, as it was just before, when it is at rest as said then and where it
/// comes to rest.
fn grown(
  platform : Int,
  hand : (Tester) -> Unit,
  by : Double,
) -> (Array[Array[Double]], Array[Array[Double]], Double, Double, Double?, Double?, Double) {
  let above = @signals.signal(0.0)
  let (t, s) = same_tree(100, platform, above~)
  hand(t)
  t.draw()
  let tree = view_tree().unwrap()
  t.run_for(grown_after_ms)
  let was = same_drawn(t)
  let x = s.drawn(tree)
  let rest = s.glides_till()
  if by != 0.0 {
    above.set(by)
    s.grew_above(by)
  }
  t.draw()
  let now = same_drawn(t)
  let y = s.drawn(tree)
  let rest_now = s.glides_till()
  t.run_for(grown_rest_ms)
  (was, now, x, y, rest, rest_now, s.at(tree))
}

///|
test "a page's list grown above what is in sight as it moves by itself: what is in sight stays where it is drawn, what moves it goes on, moved as much" {
  let hands : Array[(String, (Tester) -> Unit)] = [
    ("flung", fn(t) { swipe(t, 700.0, -10.0, 6) }),
    (
      "the wheel's notches",
      fn(t) {
        t.wheel_phase(200.0, 400.0, 40.0, 4)
        t.advance(same_notch_ms)
        t.wheel_phase(200.0, 400.0, 40.0, 4)
      },
    ),
  ]
  for platform in [0, 1, 2] {
    for h in hands {
      let (name, hand) = h
      let (was, now, x, y, rest, rest_now, end) = grown(platform, hand, grown_by)
      let (_, _, _, _, _, _, end_alone) = grown(platform, hand, 0.0)
      assert_true(rest is Some(_), msg="\{platform} \{name}: not moving by itself")
      let alike = was.length() > 0 &&
        was.length() == now.length() &&
        (0).until(was.length()).iter().all(fn(i) {
          (0).until(was[i].length()).iter().all(fn(j) { (was[i][j] - now[i][j]).abs() <= 1.0e-6 })
        })
      assert_true(alike, msg="\{platform} \{name}: drawn \{was[:imin(2, was.length())]}, grown \{now[:imin(2, now.length())]}")
      assert_true((y - (x + grown_by)).abs() < 1.0e-6, msg="\{platform} \{name}: at \{y}, was \{x}")
      assert_eq(rest_now, rest, msg="\{platform} \{name}")
      assert_true((end - (end_alone + grown_by)).abs() < 1.0e-6, msg="\{platform} \{name}: at rest at \{end}, not grown \{end_alone}")
    }
  }
}
