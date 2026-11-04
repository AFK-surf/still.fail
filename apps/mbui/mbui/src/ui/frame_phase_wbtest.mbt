// A host frame takes its input snapshot before the retained tree is measured. Posts made while that frame is
// built belong to the next snapshot; they cannot make the same tree run twice in one host frame.

///|
test "posted state is committed before the host frame's only tree layout" {
  for signals_only in [false, true] {
    let height = @signals.signal(20.0)
    let t = Tester::new(fn(_) { }, w=200.0, h=300.0, stable=false)
    t.check_looks(false)
    let take = fn(_ : String, _ : Bytes?) { height.set(80.0) }
    if signals_only {
      on_message_said("test.frame-phase-signal", fn(j, b) { take(j, b); true })
    } else {
      on_message("test.frame-phase-handler", take)
    }
    set_view_app(fn(root) {
      root.box(fn(n) {
        n.height(By(fn() { Some(height.get()) })).ground(Is(0x13579bffL)) |> ignore
      }) |> ignore
    })
    t.post(if signals_only { "test.frame-phase-signal" } else { "test.frame-phase-handler" }, "height")
    t.frame(ms=16.0)
    assert_true(t.drawn_rects().contains((0.0, 0.0, 200.0, 80.0, 0x13579bffL)))
    assert_eq(view_tree().unwrap().work().computes, 1, msg="signal handler \{signals_only}: no layout before its input snapshot")
  }
}

///|
test "a post made while the host draws is seen by the next frame only" {
  let height = @signals.signal(20.0)
  let send = Ref(true)
  on_message("test.frame-phase-late", fn(_, _) { height.set(80.0) })
  let t = Tester::new(fn(_) { }, w=200.0, h=300.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.height(By(fn() { Some(height.get()) })).ground(Is(0x13579bffL)) |> ignore
    }) |> ignore
    old(root, fn(c) {
      if send.val {
        send.val = false
        fake_post(fake.val.unwrap(), "test.frame-phase-late", "height", None)
      }
      c.text("posted during this frame") |> ignore
    }).height(Is(Some(40.0))) |> ignore
  })
  t.frame(ms=16.0)
  assert_true(t.drawn_rects().contains((0.0, 0.0, 200.0, 20.0, 0x13579bffL)))
  assert_eq(t.messages_taken(), 0)
  assert_eq(t.posted(), 1)
  t.frame(ms=16.0)
  assert_true(t.drawn_rects().contains((0.0, 0.0, 200.0, 80.0, 0x13579bffL)))
  assert_eq(t.messages_taken(), 1)
  assert_eq(t.posted(), 0)
}

///|
test "an outside callback during paint keeps its own time and changes the next frame" {
  let height = @signals.signal(20.0)
  let send = Ref(true)
  let times : Array[Double] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=300.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.height(By(fn() { Some(height.get()) })).ground(Is(0x13579bffL)) |> ignore
    }) |> ignore
    old(root, fn(_) {
      if send.val {
        send.val = false
        view_event(fn() {
          times.push(view_tree().unwrap().logic_at())
          height.set(80.0)
        })
      }
    }).height(Is(Some(40.0))) |> ignore
  })
  t.frame_shown_at(16.0, 24.0)
  assert_eq(times, [])
  assert_true(t.drawn_rects().contains((0.0, 0.0, 200.0, 20.0, 0x13579bffL)))
  t.frame_shown_at(32.0, 40.0)
  assert_eq(times, [16.0])
  assert_true(t.drawn_rects().contains((0.0, 0.0, 200.0, 80.0, 0x13579bffL)))
}
