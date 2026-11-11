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
      differ.push("\{platform}: not past its end: \{Repr(a)}")
    }
    for period in [1000.0 / 120.0, 0.0] {
      let (b, bd, br) = met_at(platform, period)
      if ar != br {
        differ.push("\{platform} at \{period}: at rest at \{Repr(br)}, at 60 Hz \{Repr(ar)}")
      }
      for k in 0..<a.length() {
        // (the same moment, however its time was summed: to a millionth of a ms; what shows then to a millionth)
        if (a[k].0 - b[k].0).abs() > 1.0e-6 || (a[k].1 - b[k].1).abs() > 1.0e-6 || (a[k].2 - b[k].2).abs() > 1.0e-6 {
          differ.push("\{platform} at \{period}: \{Repr(b[k])}, at 60 Hz \{Repr(a[k])}")
          break
        }
        let alike = ad[k].length() == bd[k].length() &&
          (0).until(ad[k].length()).iter().all(fn(i) {
            ad[k][i].length() == bd[k][i].length() &&
            (0).until(ad[k][i].length()).iter().all(fn(j) { (ad[k][i][j] - bd[k][i][j]).abs() <= 1.0e-6 })
          })
        if !alike {
          differ.push("\{platform} at \{period}: drawn at \{a[k].0} \{Repr(bd[k][:imin(3, bd[k].length())])}, at 60 Hz \{Repr(ad[k][:imin(3, ad[k].length())])}")
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
    assert_true(rest_of("a list's fling, the tree's") <= t.time())
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
  let bar = t.drawn_instances().filter(fn(a) { a[5] == 0.0 && a[0] > 350.0 && a[2] < 20.0 }).map(fn(a) { a[0:5].to_owned() })
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
      assert_true(alike, msg="\{platform} \{name}: drawn \{Repr(was[:imin(2, was.length())])}, grown \{Repr(now[:imin(2, now.length())])}")
      assert_true((y - (x + grown_by)).abs() < 1.0e-6, msg="\{platform} \{name}: at \{y}, was \{x}")
      assert_eq(rest_now, rest, msg="\{platform} \{name}")
      assert_true((end - (end_alone + grown_by)).abs() < 1.0e-6, msg="\{platform} \{name}: at rest at \{end}, not grown \{end_alone}")
    }
  }
}

///|
/// How far a page's list is down before it is flung back up to its top.
let up_from : Double = 600.0

///|
/// A page's list on `platform` at up_from, flung up toward its top (a finger moved down), grown `by` above what is in
/// sight grown_after_ms on, on its way there: what is drawn then and just before, each moment of the display's after
/// it (where it is, how far past its end it shows) for grown_rest_ms, and where it comes to rest.
fn grown_up(
  platform : Int,
  by : Double,
) -> (Array[Array[Double]], Array[Array[Double]], Array[(Double, Double)], Double) {
  let above = @signals.signal(0.0)
  let (t, s) = same_tree(100, platform, above~)
  t.wheel(200.0, 400.0, up_from)
  t.draw()
  swipe(t, 200.0, 24.0, 12)
  t.draw()
  let tree = view_tree().unwrap()
  t.run_for(grown_after_ms)
  let was = same_drawn(t)
  above.set(by)
  s.grew_above(by)
  t.draw()
  let now = same_drawn(t)
  let after = []
  let end = t.time() + grown_rest_ms
  while t.time() < end {
    t.frame()
    after.push((s.at(tree), s.past(tree)))
  }
  (was, now, after, s.at(tree))
}

///|
test "a page's list flung up toward its top, grown above what is in sight on its way: it meets its top where its top is now, and only there" {
  for platform in [0, 1, 2] {
    // (grown a little: it still gets there, later; grown much: it stops short of it)
    for by in [400.0, 4000.0] {
      let (was, now, after, end) = grown_up(platform, by)
      let alike = was.length() > 0 &&
        was.length() == now.length() &&
        (0).until(was.length()).iter().all(fn(i) {
          (0).until(was[i].length()).iter().all(fn(j) { (was[i][j] - now[i][j]).abs() <= 1.0e-6 })
        })
      assert_true(alike, msg="\{platform} \{by}: what is in sight moved as it grew")
      // (past its top only at its top)
      match after.iter().find_first(fn(f) { f.1 != 0.0 && f.0 != 0.0 }) {
        Some(f) => fail("\{platform} \{by}: past its end \{f.1} at \{f.0}")
        None => ()
      }
      let past = after.iter().any(fn(f) { f.1 != 0.0 })
      if by < 1000.0 {
        assert_true(end == 0.0, msg="\{platform} \{by}: at rest at \{end}")
        assert_true(platform == 0 || past, msg="\{platform} \{by}: never past its top")
      } else {
        assert_true(end > 0.0 && !past, msg="\{platform} \{by}: at rest at \{end}, past its top \{past}")
      }
    }
  }
}

///|
/// A page's list on `platform` flung down toward its foot (a finger moved up, same_tree's 40 rows), what it holds grown
/// grown_after_ms on, on its way: `above` above what is in sight (told so: Scroll::grew_above), under it from `below`'s
/// first to its second; each
/// moment of the display's after it (where it is, how far past its end it shows, how far it can go) for grown_rest_ms,
/// and where it comes to rest and how far it can go then.
fn grown_down(
  platform : Int,
  above : Double,
  below : (Double, Double),
) -> (Array[(Double, Double, Double)], Double, Double) {
  let up = @signals.signal(0.0)
  let down = @signals.signal(below.0)
  let (t, s) = same_tree(40, platform, above=up, below=down)
  swipe(t, 700.0, -32.0, 12)
  t.draw()
  let tree = view_tree().unwrap()
  t.run_for(grown_after_ms)
  up.set(above)
  down.set(below.1)
  s.grew_above(above)
  t.draw()
  let after = []
  let end = t.time() + grown_rest_ms
  while t.time() < end {
    t.frame()
    after.push((s.at(tree), s.past(tree), s.most()))
  }
  (after, s.at(tree), s.most())
}

///|
test "a page's list flung down toward its foot, what it holds grown on its way: it meets its foot where it is laid out now, and only there" {
  // (grown under what is in sight; grown above and as much less under, as far as it can go the same)
  for grown in [(0.0, (0.0, 400.0)), (300.0, (300.0, 0.0))] {
    for platform in [0, 1, 2] {
      let (after, end, most) = grown_down(platform, grown.0, grown.1)
      match after.iter().find_first(fn(f) { f.1 != 0.0 && (f.0 - f.2).abs() > 1.0e-6 }) {
        Some(f) => fail("\{platform} \{Repr(grown)}: past its end \{f.1} at \{f.0} of \{f.2}")
        None => ()
      }
      assert_true((end - most).abs() < 1.0e-6, msg="\{platform} \{Repr(grown)}: at rest at \{end} of \{most}")
      assert_true(platform == 0 || after.iter().any(fn(f) { f.1 != 0.0 }), msg="\{platform} \{Repr(grown)}: never past its foot")
    }
  }
}

///|
test "a page's list grown above as what was pulled past its top goes back: what is in sight stays, what is past its top goes on back, none comes anew" {
  // (as an old view's list: what is past its end drawn so till it is back, wherever it then stands, Ctx::place_list)
  for platform in [1, 2] {
    let above = @signals.signal(0.0)
    let (t, s) = same_tree(100, platform, above~)
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
    let tree = view_tree().unwrap()
    let was = same_drawn(t)
    let past = s.past(tree)
    assert_true(past > 0.0, msg="\{platform}: nothing past its top")
    above.set(grown_by)
    s.grew_above(grown_by)
    t.draw()
    let now = same_drawn(t)
    let alike = was.length() == now.length() &&
      (0).until(was.length()).iter().all(fn(i) {
        (0).until(was[i].length()).iter().all(fn(j) { (was[i][j] - now[i][j]).abs() <= 1.0e-6 })
      })
    assert_true(alike, msg="\{platform}: what is in sight moved as it grew")
    // (what is past its top only going back, never more of it)
    let mut last = s.past(tree)
    let end = t.time() + grown_rest_ms
    while t.time() < end {
      t.frame()
      let p = s.past(tree)
      assert_true(p <= last + 1.0e-9, msg="\{platform}: past its top \{p} after \{last}")
      last = p
    }
    assert_eq(s.past(tree), 0.0)
    assert_true((s.at(tree) - grown_by).abs() < 1.0e-6, msg="\{platform}: at rest at \{s.at(tree)}")
  }
}

///|
/// How short of its foot a page's list flung down toward it is when what is above what is in sight grows.
let near_foot : Double = 40.0

///|
test "a page's list flung down, short of its foot by a little as what is above grows by much: no meeting where its foot was, it meets it where it is laid out now" {
  for platform in [0, 1, 2] {
    let above = @signals.signal(0.0)
    let (t, s) = same_tree(40, platform, above~)
    swipe(t, 700.0, -32.0, 12)
    t.draw()
    let tree = view_tree().unwrap()
    while s.at(tree) < s.most() - near_foot {
      t.frame()
    }
    assert_true(s.at(tree) < s.most(), msg="\{platform}: at its foot already")
    let was = same_drawn(t)
    above.set(grown_by * 3.0)
    s.grew_above(grown_by * 3.0)
    t.draw()
    let now = same_drawn(t)
    let alike = was.length() == now.length() &&
      (0).until(was.length()).iter().all(fn(i) {
        (0).until(was[i].length()).iter().all(fn(j) { (was[i][j] - now[i][j]).abs() <= 1.0e-6 })
      })
    assert_true(alike, msg="\{platform}: what is in sight moved as it grew")
    let end = t.time() + grown_rest_ms
    let mut past = false
    while t.time() < end {
      t.frame()
      let p = s.past(tree)
      if p != 0.0 {
        past = true
        assert_true((s.at(tree) - s.most()).abs() < 1.0e-6, msg="\{platform}: past its end \{p} at \{s.at(tree)} of \{s.most()}")
      }
    }
    assert_true((s.at(tree) - s.most()).abs() < 1.0e-6, msg="\{platform}: at rest at \{s.at(tree)} of \{s.most()}")
    assert_true(platform == 0 || past, msg="\{platform}: never past its foot")
  }
}

///|
test "a page's list flung down near its foot, as much grown above as gone under what is in sight: as far as it can go the same, it meets its foot now" {
  for platform in [1, 2] {
    let above = @signals.signal(0.0)
    let below = @signals.signal(grown_by * 3.0)
    let (t, s) = same_tree(40, platform, above~, below~)
    swipe(t, 700.0, -32.0, 12)
    t.draw()
    let tree = view_tree().unwrap()
    while s.at(tree) < s.most() - near_foot {
      t.frame()
    }
    let most = s.most()
    above.set(grown_by * 3.0)
    below.set(0.0)
    s.grew_above(grown_by * 3.0)
    t.draw()
    assert_eq(s.most(), most)
    // (past what it had left to go: at its foot, and past it from now, going back; at rest by when that is back)
    let rest = s.glides_till().unwrap()
    let mut past = false
    let end = t.time() + grown_rest_ms
    while t.time() < end {
      t.frame()
      if s.past(tree) != 0.0 {
        past = true
      }
    }
    assert_true(past, msg="\{platform}: never past its foot")
    assert_true((s.at(tree) - most).abs() < 1.0e-6, msg="\{platform}: at rest at \{s.at(tree)} of \{most}")
    assert_true(rest < t.time(), msg="\{platform}: at rest at \{rest}")
  }
}

///|
/// How tall what is under a page's list's rows is before it is measured shorter.
let shrunk_from : Double = 2000.0

///|
test "a page's list flung down, what is under it measured shorter as it is let go, its foot where it stands now: it meets it there, goes past it and back" {
  for platform in [1, 2] {
    let below = @signals.signal(shrunk_from)
    let (t, s) = same_tree(20, platform, below~)
    let tree = view_tree().unwrap()
    // (flung from up_from; as it is let go, its foot where it stands)
    t.wheel(200.0, 400.0, up_from)
    t.draw()
    swipe(t, 700.0, -24.0, 12)
    let at = s.at(tree)
    assert_true(s.most() - at < shrunk_from, msg="\{platform}: \{s.most() - at} to go")
    below.set(shrunk_from - (s.most() - at))
    t.draw()
    let rest = s.glides_till()
    assert_true(rest is Some(r) && r > t.time(), msg="\{platform}: at rest at \{Repr(rest)}, now \{t.time()}")
    let mut past = false
    let end = t.time() + grown_rest_ms
    while t.time() < end {
      t.frame()
      if s.past(tree) != 0.0 {
        past = true
      }
    }
    assert_true(past, msg="\{platform}: never past its foot")
    assert_true((s.at(tree) - s.most()).abs() < 1.0e-6, msg="\{platform}: at rest at \{s.at(tree)} of \{s.most()}")
  }
}

///|
test "a page's list flung down, its foot laid out where it stands and back again in the moment it is let go: no meeting there, it goes on to its foot" {
  for platform in [1, 2] {
    let below = @signals.signal(shrunk_from)
    let (t, s) = same_tree(20, platform, below~)
    let tree = view_tree().unwrap()
    t.wheel(200.0, 400.0, up_from)
    t.draw()
    swipe(t, 700.0, -24.0, 12)
    let at = s.at(tree)
    let most = s.most()
    below.set(shrunk_from - (most - at))
    t.draw()
    below.set(shrunk_from)
    t.draw()
    let end = t.time() + grown_rest_ms
    while t.time() < end {
      t.frame()
      assert_true(s.past(tree) == 0.0 || (s.at(tree) - s.most()).abs() < 1.0e-6, msg="\{platform}: past its end at \{s.at(tree)} of \{s.most()}")
    }
    assert_true(s.at(tree) > at + 100.0, msg="\{platform}: at rest at \{s.at(tree)}, let go at \{at}")
  }
}

///|
/// A page's list on the Mac turned a notch of the wheel (`notches` 2: then another as that one eases in, its target
/// said again, no frame between the two: what a host gives as input is on its frames, so a notch turned between them
/// is at another moment at each rate), the display's frames `period` apart from then (0: none between): when it said
/// it would be at rest as the last was turned, where it is at that moment, where it is each 50 ms for half a second
/// after, and whether it says it moves by itself then.
fn notch_rests(notches : Int, period : Double) -> (Double?, Double, Array[Double], Double?) {
  let (t, s) = same_tree(40, 0)
  let tree = view_tree().unwrap()
  t.wheel_phase(200.0, 400.0, 40.0, 4)
  if notches > 1 {
    t.advance(same_notch_ms)
    t.wheel_phase(200.0, 400.0, 40.0, 4)
  }
  let rest = s.glides_till()
  if period > 0.0 {
    t.set_frame_period(period)
  }
  // (to the moment said, the display's frames on the way where there are any: run_for_exact)
  t.run_for_exact(rest.unwrap_or(t.time()) - t.time())
  let at_end = s.at(tree)
  let after = []
  for _ in 0..<10 {
    t.run_for_exact(met_step_ms)
    after.push(s.at(tree))
  }
  (rest, at_end, after, s.glides_till())
}

///|
test "a page's list's wheel notch: when it is at rest said from what it was as it set out alone, the same at any frame rate, and still from then" {
  let ones = []
  for notches in [1, 2] {
    let (rest, at_end, after, then) = notch_rests(notches, 0.0)
    assert_true(rest is Some(_), msg="\{notches}: not moving by itself")
    assert_true(after.iter().all(fn(x) { x == at_end }), msg="\{notches}: at rest at \{at_end}, after \{Repr(after)}")
    assert_eq(then, None)
    ones.push(rest)
    for period in [1000.0 / 60.0, 1000.0 / 120.0, 1000.0 / 24.0, 1000.0 / 7.0] {
      let got = notch_rests(notches, period)
      assert_eq(got, (rest, at_end, after, then), msg="\{notches} at \{period}: \{Repr(got)}, in one jump \{Repr((rest, at_end, after, then))}")
    }
  }
  // (turned again, said again: at rest later than the one alone)
  assert_true(ones[1].unwrap() > ones[0].unwrap(), msg="\{Repr(ones)}")
}

///|
/// How much is grown above a page's list's rows as a notch of the wheel eases in: a part of a point, so its rows are
/// set on other pixels than they were.
let notch_grown_by : Double = 0.3

///|
test "a page's list grown above by a part of a pixel as a notch eases in: at rest at the moment it says, nothing of it drawn anew after" {
  let above = @signals.signal(0.0)
  let (t, s) = same_tree(40, 0, above~)
  let tree = view_tree().unwrap()
  t.set_frame_period(1000.0 / 60.0)
  t.wheel_phase(200.0, 400.0, 40.0, 4)
  t.run_for(same_notch_ms)
  above.set(notch_grown_by)
  t.draw()
  let rest = s.glides_till().unwrap()
  t.run_for_exact(rest - t.time())
  let at = s.at(tree)
  let drawn = same_drawn(t)
  for _ in 0..<10 {
    t.run_for(met_step_ms)
    assert_eq((s.at(tree), same_drawn(t)), (at, drawn), msg="at \{t.time()}, at rest at \{rest}")
  }
  assert_eq(s.glides_till(), None)
}
