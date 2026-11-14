// A list moving to another position has already told the paint that its picture may differ. The frame must still be
// presented, and a later still frame must be able to establish what it drew for the looks-only path.

///|
fn fingerprint_list(color : @signals.Signal[Int64]) -> Tester {
  let t = Tester::new(fn(c) {
    c.list("rows", 30, 40.0, fn(i) {
      c.box(h=Px(40.0), bg=if i == 2 { color.get() } else { 0x3366CCFFL }, fn() {
        c.text("row \{i}", wrap=false) |> ignore
      }) |> ignore
    }, rows_read=true) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t
}

///|
test "a moved list draws its new place without fingerprinting it as a still frame" {
  let color = @signals.signal(0xCC6633FFL)
  let t = fingerprint_list(color)
  let before = t.list_offset()
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 25.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  assert_true(t.list_offset() > before + 1.0, msg="the wheel must actually move the list")
  assert_true(!looks_base.built, msg="a known movement need not fingerprint the changed drawing")
  assert_true(!looks_base.settled, msg="the moved drawing cannot be declared the previous drawing")
  // Observe the same moment twice: the scrollbar's own fade must not change the drawing under this assertion.
  // The frame after the movement was not fingerprinted, so a still paint establishes its own fingerprint again.
  t.frame_at(at + 16.0)
  assert_true(looks_base.built, msg="a still frame must fingerprint again")
  t.frame_at(at + 16.0)
  assert_true(looks_base.settled, msg="a still paint after it can use the looks-only path again: paint \{painted_why.val}")
}

///|
test "a change during scroll is drawn and remains visible on the next still frame" {
  let color = @signals.signal(0xCC6633FFL)
  let t = fingerprint_list(color)
  let at = t.time()
  color.set(0x229944FFL)
  t.wheel_told(100.0, 100.0, 0.0, 25.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL }), msg="the changed row is drawn")
  t.frame_at(at + 32.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL }), msg="the changed row stays drawn")
}
