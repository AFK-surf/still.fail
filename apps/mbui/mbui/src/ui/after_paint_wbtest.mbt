// What the tree says to tell once its frame is painted (Tree::take_after_paint: a node first drawn, a list's rows
// sighted) is told once the frame is whole, its checks done: an answer it gets at once is shown by the frame after it,
// and no check of the frame painted again from nothing sees the tree changed under it.

///|
test "a first-drawn request answered at once: told once, after the frame and its checks, the answer shown by the frame after" {
  let shown = @signals.signal(false)
  let loaded = @signals.signal(false)
  let calls = Ref(0)
  let t = Tester::new(fn(_) { }, w=200.0, h=100.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(slot) {
      slot.width(Is(Some(120.0))).height(Is(Some(60.0))).radius(Is(12.0)).ground(Is(0x777777FFL)) |> ignore
      // The host may answer a request synchronously, just as it can answer an image decode immediately.
      slot.on_first_drawn(fn() {
        calls.val += 1
        loaded.set(true)
      }) |> ignore
      slot.show(fn() { loaded.get() }, fn(image) {
        image.width(Is(Some(120.0))).height(Is(Some(60.0))).ground(Is(0x3366CCFFL)) |> ignore
      })
    })
  })
  t.draw()
  shown.set(true)
  t.clock_frame()
  t.frames_owed()
  assert_eq(calls.val, 1, msg="the drawn request was made once")
  assert_true(loaded.get(), msg="its synchronous answer was kept")
}
