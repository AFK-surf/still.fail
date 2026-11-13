// The chats' list in the sidebar of a long account (sffixture's long-paged), the app put away and brought back with the
// host's glyphs moved on meanwhile (its scale or faces changed, its atlas lost: what a phone brought back from the
// background may do), then flung hard with a finger: its rows on every frame of the glide. The words redone forgot the
// heights of the blocks made round what showed, and the window going out from what showed stopped at the first of them,
// which nothing laid out to measure: the list's ground showed under the rows made, growing up to all of it, till the
// glide came to rest (an iPhone Duo's sidebar, 2026-11-13).

///|
/// The largest stretch down the list (left of `side_w`, from `top` to `foot`) with no words drawn, and where it starts.
fn side_gap(t : @ui.Tester, side_w : Double, top : Double, foot : Double) -> (Double, Double) {
  let ys = t
    .words()
    .filter(fn(w) { w.1 < side_w && w.2 + w.4 > top && w.2 < foot && w.5 > 0.05 })
    .map(fn(w) { w.2 })
  ys.sort()
  let mut most = 0.0
  let mut at = top
  let mut was = top
  for y in ys {
    if y - was > most {
      most = y - was
      at = was
    }
    was = @cmp.maximum(was, y)
  }
  if foot - was > most {
    most = foot - was
    at = was
  }
  (most, at)
}

///|
/// The most room between two words drawn down the sidebar's list where its rows are whole: a row and a day's line
/// (70 at most in the fixture).
let side_gap_most : Double = 150.0

///|
/// How long the app is put away: a while, longer than any way going as it went.
let side_away_ms : Double = 5000.0

///|
/// A phone's display's frames during a glide, each looked at.
let side_frame_ms : Double = 1000.0 / 120.0

///|
test "touch tablet: the sidebar's chats flung after the app was put away and brought back with its glyphs moved on show their rows on every frame of the glide" {
  let said : Array[String] = []
  for moved_on in [false, true] {
    new_run()
    let asked : Array[String] = []
    let src = window_asks(asked)
    let (w, h, side_w) = (840.0, 900.0, 300.0)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=2)
    let log = t.drive("system {\"size_class\":{\"width\":\"expanded\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    t.draw()
    t.run_for(window_opened_ms)
    t.drag(150.0, 780.0, 150.0, 300.0, steps=3)
    t.run_for(window_rest_ms)
    // put away a while, and brought back
    t.app_state(false, false)
    t.run_for(side_away_ms)
    if moved_on {
      t.glyphs_moved_on()
    }
    t.app_state(true, true)
    let back = t.time()
    let gaps : Array[String] = []
    for _ in 0..<3 {
      t.drag(150.0, 780.0, 150.0, 300.0, steps=3)
      let rest = t.time()
      while t.time() - rest < window_rest_ms - 1.0e-6 {
        t.run_for(side_frame_ms)
        let g = side_gap(t, side_w, 160.0, h - 120.0)
        if g.0 > side_gap_most {
          gaps.push("\{(t.time() - back).to_int()} ms: \{g.0.to_int()} from \{g.1.to_int()}")
        }
      }
    }
    said.push("glyphs moved on \{moved_on}: \{@ui.list_text(gaps)}")
  }
  assert_eq(said, ["glyphs moved on false: []", "glyphs moved on true: []"])
}
