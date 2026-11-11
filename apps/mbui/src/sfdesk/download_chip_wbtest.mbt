// A file of the drive coming down (download_chip): told a new share, its fill goes there as each frame is painted,
// laid out across the chip and drawn narrowed from its left, nothing built for it on the way.

///|
test "a file coming down told a new share: its chip's fill goes there as each frame is painted, nothing built for it, as wide as the share at its end" {
  let percent = @signals.signal(20, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(
    fn(c) { c.box(w=Px(300.0), h=Px(200.0), align=AStart, fn() { download_chip(c, "k", percent.get()) }) |> ignore },
    w=400.0,
    h=300.0,
  )
  t.check_looks(false)
  t.draw()
  // (the fill: the accent at 20%; the chip's ground, the rect it starts at, as high)
  let fill = fn() { t.drawn_rects().filter(fn(r) { (r.4 & 0xFFL) == 51L }) }
  let first = fill()
  assert_eq(first.length(), 1, msg="\{Repr(t.drawn_rects())}")
  let ground = t.drawn_rects().filter(fn(r) { r.0 == first[0].0 && r.3 == first[0].3 && r.4 != first[0].4 })
  assert_eq(ground.length(), 1, msg="\{Repr(t.drawn_rects())}")
  let whole = ground[0].2
  assert_true((first[0].2 - whole * 0.2).abs() < 0.01, msg="\{Repr(first)} of \{whole}")
  // (told 60%: built for that, its fill told to go there)
  percent.set(60)
  t.draw()
  let end = t.time() + chip_fill_ms
  let built : Array[String] = []
  let widths : Array[Double] = []
  let mut once = true
  while t.time() < end {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    let why = t.built_why()
    // (the frame after one that laid out otherwise is built once more for that, as the frame after any such build is)
    if why != "" && !(once && why == "the one before it laid out otherwise") {
      built.push("\{t.time()}: \{why}")
    }
    once = false
    match fill() {
      [r] => if !widths.contains(r.2) { widths.push(r.2) }
      f => widths.push(-f.length().to_double())
    }
  }
  t.frame_at(t.display_frame(end))
  let ascending = widths.length() > 3 &&
    Array::makei(widths.length() - 1, fn(k) { widths[k] < widths[k + 1] }).iter().all(fn(b) { b })
  assert_true(ascending, msg="\{Repr(widths)}")
  assert_eq(built, [], msg="\{built.length()} frames built: \{Repr(built)}")
  match fill() {
    [r] => assert_true((r.2 - whole * 0.6).abs() < 0.01, msg="\{Repr(r)} of \{whole}")
    f => fail("\{Repr(f)}")
  }
}
