// An option of a card being sent turns at its row's end (options_card): sent, its spinner fades out as each frame is
// painted, built until the end its fading declared and gone then, nothing built for it on the way.

///|
test "an option sent: its spinner fades out as each frame is painted, nothing built for it, gone at its declared end" {
  let busy : @signals.Signal[Int?] = @signals.signal(Some(0), same=fn(a, b) { a == b })
  let t = @ui.Tester::new(
    fn(c) { options_card(c, "o", [("甲", "", false), ("乙", "", false)], true, busy.get()) },
    w=600.0,
    h=400.0,
  )
  t.check_looks(false)
  t.draw()
  // (the spinner's ring and arc: the only lines the card draws)
  let inks = fn() { t.drawn_lines().map(fn(l) { l.5 & 0xFFL }) }
  assert_true(inks().length() > 0, msg="turning: \{Repr(t.drawn_lines())}")
  // (sent: built for that, its spinner told to go)
  busy.set(None)
  t.draw()
  let end = t.time() + dur_ms
  let built : Array[String] = []
  let seen : Array[Int64] = []
  let mut first = true
  while t.time() < end {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    let why = t.built_why()
    // (the frame after one that laid out otherwise is built once more for that, as the frame after any such build is;
    // the one at its declared end is built for it: the spinner goes)
    if t.time() < end && why != "" && !(first && why == "the one before it laid out otherwise") {
      built.push("\{t.time()}: \{why}")
    }
    first = false
    match inks().get(0) {
      Some(a) => if !seen.contains(a) { seen.push(a) }
      None => ()
    }
  }
  t.frame_at(t.display_frame(end))
  assert_true(seen.length() > 2, msg="fading: \{Repr(seen)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
  assert_eq(t.drawn_lines().length(), 0, msg="gone at \{end}: \{Repr(t.drawn_lines())}")
}
