// The bar across the top of a file opened (viewer_bar), told to go up out of the way: it goes as each frame is painted,
// told once as it is built, nothing built again for its way up; it takes no press from the moment it is told to go.

///|
test "the viewer's bar going up out of the way: drawn higher each frame as it is painted, nothing built for its way" {
  let ink : ViewerInk = {
    ground: 0x222222FFL,
    ink: 0xFFFFFFFFL,
    muted: 0xAAAAAAFFL,
    line: 0x444444FFL,
    hover: 0x2427E70FL,
    chosen: 0x2427E71FL,
  }
  let hidden = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(
    fn(c) { viewer_bar(c, "bar", "整理发布清单", "a.png", "18 KB", hidden.get(), ink, fn() {  }) |> ignore },
    w=1280.0,
    h=800.0,
  )
  t.check_looks(false)
  t.draw()
  // (the bar's glass, across the window: where its top is drawn)
  let top = fn() { t.drawn_glass().filter(fn(g) { g.2 >= 1000.0 }).map(fn(g) { g.1 }) }
  let rest = top()
  assert_true(rest.length() == 1, msg="\{Repr(t.drawn_glass())}")
  // (told to go: built for that)
  hidden.set(true)
  t.draw()
  let end = t.time() + viewer_bar_ms
  let built : Array[String] = []
  let tops : Array[Double] = []
  let mut first = true
  while t.time() < end {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    // (the frame after one that laid out otherwise is built once more for that, as the frame after any such build is)
    let why = t.built_why()
    if why != "" && !(first && why == "the one before it laid out otherwise") {
      built.push("\{t.time()}: \{why}")
    }
    first = false
    match top().get(0) {
      Some(y) => if !tops.contains(y) { tops.push(y) }
      None => ()
    }
  }
  // (up, frame by frame, from where it rested)
  let higher = tops.length() > 3 &&
    tops[0] < rest[0] &&
    Array::makei(tops.length() - 1, fn(k) { tops[k + 1] < tops[k] }).iter().all(fn(b) { b })
  assert_true(higher, msg="\{Repr(rest)} then \{Repr(tops)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
}
