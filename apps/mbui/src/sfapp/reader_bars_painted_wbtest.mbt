// A text read on a phone, tapped: its bars come in (sf/reader.mbt reader_narrow_bars), faded and stepped in as each
// frame is painted, built as they are told to come and at their declared end, nothing built for them on the way.

///|
test "a text read, tapped: its bars fade in as each frame is painted, nothing built for them on the way" {
  let t = drive_tester("drive")
  t.tap_text("长篇小说.txt")
  nav_rested(t)
  t.run_for(@sf.reader_place_ms)
  assert_true(t.find("上一章") is None)
  // (tapped: built for that, its bars told to come)
  t.tap(195.0, 420.0)
  let alpha = fn() {
    match t.words().filter(fn(w) { w.0 == "目录" }) {
      [w] => w.5
      _ => -1.0
    }
  }
  let end = t.time() + @sf.reader_bars_ms
  let built : Array[String] = []
  let seen : Array[Double] = []
  let mut first = true
  while t.time() < end && alpha() < 1.0 {
    let w = t.wanted_after()
    if w == @double.infinity || w > end {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    let why = t.built_why()
    let a = alpha()
    // (the frame after one that laid out otherwise is built once more for that, as the frame after any such build is;
    // the one at their declared end, where they are whole, is built for it: the line of how far it is read, there
    // while they were away, goes)
    if why != "" && a < 1.0 && !(first && why == "the one before it laid out otherwise") {
      built.push("\{t.time()}: \{why}")
    }
    first = false
    if !seen.contains(a) {
      seen.push(a)
    }
  }
  // (through alphas between, each more than the one before, to whole)
  let ascending = seen.length() > 3 &&
    seen[0] >= 0.0 &&
    Array::makei(seen.length() - 1, fn(k) { seen[k] < seen[k + 1] }).iter().all(fn(b) { b })
  assert_true(ascending, msg="\{Repr(seen)}")
  assert_eq(alpha(), 1.0)
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
}
