///|
test "presented_rest: a sheet's end said as it opens, the same whichever frames are drawn on its way and once it is over" {
  let t = panel_with_confirm(phone)
  t.tap_text("打开")
  assert_eq(presented_how, [AsSheet])
  let end = presented_rest()
  assert_true(end > t.time() && end < 1.0e300, msg="\{end} at \{t.time()}")
  // (a frame more, half way, at its end, past it: its end as it was said, not as tall as the frame last drawn had it)
  t.frame()
  assert_eq(presented_rest(), end)
  t.run_for((end - t.time()) / 2.0)
  assert_eq(presented_rest(), end)
  t.run_for(end - t.time())
  assert_eq(presented_rest(), end)
  t.run_for(@ui.move_most_ms)
  assert_eq(presented_rest(), end)
}

///|
test "presented_rest: on a display's 7 frames a second, the end it said as it opened, when the frames have passed it" {
  let t = panel_with_confirm(phone)
  t.set_frame_period(seven_a_second)
  t.tap_text("打开")
  let end = presented_rest()
  assert_true(end > t.time() && end < 1.0e300, msg="\{end} at \{t.time()}")
  t.run_for(end - t.time() + seven_a_second)
  assert_true(t.time() > end)
  assert_eq(presented_rest(), end)
}

///|
/// A display's frame period at 7 frames a second (ms): frames far apart, one well past a sheet's end.
let seven_a_second : Double = 1000.0 / 7.0

///|
test "presented_rest: a step further in whose page grows, asked before a frame draws it: where the sheet comes to rest, what it holds coming in counted" {
  let more = @signals.signal(false)
  let t = presenting_tester(phone, fn(_) {
    panel_nodes("信息", from=Unanchored, fn(v, close) {
      words_node(v, fn() { "信息内容" }, fn() { secondary }) |> ignore
      button_node(v, fn() { "看详情" }, fn() {
        close()
        panel_nodes("详情", from=Unanchored, fn(d, _) {
          words_node(d, fn() { "详情内容" }, fn() { secondary }) |> ignore
          d.show(fn() { more.get() }, fn(b) { b.box(fn(x) { x.height(Is(Some(grown_by))) |> ignore }) |> ignore })
        })
      })
      |> ignore
    })
  })
  open_it(t)
  t.run_for(@ui.move_most_ms)
  t.tap_text("看详情")
  // (the page put on at rest, then grown, no frame drawn since. Grown while it still slides in, the sheet's place went
  // back against its way a frame (2.97 points at 120 a second, sizes_steady at sheet_node.mbt's col, 2026-11-11): the
  // smoothness line's to mend and to hold with a test of its own, judged, once it is; this one holds only the rest)
  t.run_for(@ui.move_most_ms)
  more.set(true)
  let end = presented_rest()
  assert_true(end > t.time() && end < 1.0e300, msg="\{end} at \{t.time()}")
  t.run_for(end - t.time())
  let (top, h) = one_sheet(t)
  t.run_for(@ui.move_most_ms)
  assert_eq(one_sheet(t), (top, h), msg="at rest by \{end}: \{Repr((top, h))}, then \{Repr(one_sheet(t))}")
}

///|
/// How much taller the page put on comes to (presented_rest's step further in): more than the slide's way.
let grown_by : Double = 600.0
