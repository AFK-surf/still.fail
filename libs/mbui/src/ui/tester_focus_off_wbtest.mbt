// What a key the Tester presses is held to (tester_focus_off.mbt): the focus moved onto what is wholly outside the
// window said, where it is and where it was made (Tester::focus_off_said, the first of its two steps); none where some
// of it is in the window.

///|
/// Three buttons of the window's tree read out by their names, each laid out 80×40 down the window's left edge, then
/// moved by its offset:
/// "里" not, "半" half past the window's left edge, "外" wholly past it; the window 400×200.
fn focus_off_tester() -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    for b in [("里", 0.0), ("半", -48.0), ("外", -300.0)] {
      root.box(fn(v) {
        v
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .offset(Is((b.1, 0.0)))
        .says(Is(Some(@view.said(Button, label=b.0))))
        .focusable(Is(true))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t
}

///|
test "the focus on a node wholly past the window's edge said, with where it is, the window and where it was made; on one in the window, or partly, nothing said" {
  let t = focus_off_tester()
  t.act(Button, Focus, label="里")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("里"))
  assert_eq(t.focus_off_said(), None)
  t.act(Button, Focus, label="半")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("半"))
  assert_eq(t.focus_off_said(), None, msg="partly in the window")
  t.act(Button, Focus, label="外")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("外"))
  match t.focus_off_said() {
    Some(said) => {
      assert_true(said.contains("wholly outside the window"), msg=said)
      assert_true(said.contains("\"外\""), msg=said)
      assert_true(said.contains("the window 400×200"), msg=said)
      assert_true(said.contains("tester_focus_off_wbtest.mbt"), msg="where it was made: \{said}")
    }
    None => fail("the focus wholly past the window's left edge, nothing said")
  }
}

///|
/// How long the sliding button of focus_way_tester takes to go its way.
// kept across runs: a value
let focus_way_ms : Double = 300.0

///|
/// A button "甲" in the window, and after it a button "动" moved along its way from `from` to `to` across, over
/// focus_way_ms from the moment `start` says (none: not moving, at `from`), each 80×40 in a column; the window 400×200;
/// what the check finds kept, not stopping the test.
fn focus_way_tester(start : @signals.Signal[Double?], from : Double, to : Double) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  t.focus_off_unheld()
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .says(Is(Some(@view.said(Button, label="甲"))))
      .focusable(Is(true))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .says(Is(Some(@view.said(Button, label="动"))))
      .focusable(Is(true))
      .on_press(fn() {  })
      .moved_by(
        fn(_w, _h, now) {
          match start.get() {
            Some(t0) => {
              let r = (now - t0) / focus_way_ms
              let k = if r < 0.0 { 0.0 } else if r > 1.0 { 1.0 } else { r }
              (from + (to - from) * k, 0.0)
            }
            None => (from, 0.0)
          }
        },
        fn(_w, _h) {
          match start.get() {
            Some(t0) => t0 + focus_way_ms
            None => -1.0
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "Tab onto a button sliding in from past the window's edge, its way ending in the window: judged where it stops, nothing said, at the key or at its end" {
  let start : @signals.Signal[Double?] = @signals.signal(None)
  let t = focus_way_tester(start, -300.0, 0.0)
  t.act(Button, Focus, label="甲")
  start.set(Some(t.time()))
  t.draw()
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("动"))
  let (x, _, w, _) = t.focused().unwrap().rect
  assert_true(x + w <= 0.0, msg="past the window's edge as Tab came: \{x}")
  assert_eq(t.focus_off_found(), [], msg="said as Tab came, its way under way")
  t.run_for(focus_way_ms)
  assert_eq(t.focus_off_found(), [], msg="said where it stopped, in the window")
}

///|
test "Tab onto a button in the window sliding out past its edge, its way ending there: judged where it stops, said at its end" {
  let start : @signals.Signal[Double?] = @signals.signal(None)
  let t = focus_way_tester(start, 0.0, -300.0)
  t.act(Button, Focus, label="甲")
  start.set(Some(t.time()))
  t.draw()
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("动"))
  assert_eq(t.focus_off_found(), [], msg="said as Tab came, in the window then, its way under way")
  t.run_for(focus_way_ms)
  let found = t.focus_off_found()
  assert_eq(found.length(), 1, msg="\{Repr(found)}")
  assert_true(found[0].contains("\"动\"") && found[0].contains("where it stops"), msg=found[0])
}

///|
test "Tab onto a button past the window's edge with nothing on its way: said at once, where it is" {
  let start : @signals.Signal[Double?] = @signals.signal(None)
  let t = focus_way_tester(start, -300.0, -300.0)
  t.act(Button, Focus, label="甲")
  t.tab()
  let found = t.focus_off_found()
  assert_eq(found.length(), 1, msg="\{Repr(found)}")
  assert_true(found[0].contains("nothing on its way"), msg=found[0])
}
