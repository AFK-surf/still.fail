// A tip on something that points but does not press, in a pressable row of a scrolling column.

///|
fn passive_tip_tester(
  there : @signals.Signal[Bool],
  label : @signals.Signal[String],
  parent_hold : Bool,
  press_node? : Bool = false,
  platform? : Int = 2,
  accepts? : () -> Bool = fn() { true },
  covered? : Bool = false,
) -> (@ui.Tester, @view.Scroll, Ref[Int], Ref[Int]) {
  let taps = Ref(0)
  let holds = Ref(0)
  let scroll = @view.Scroll::list()
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(200.0))).scrolls(scroll, fn(body) {
        for _ in 0..<8 {
          body.box(fn(row) {
            row.width(Is(Some(300.0))).height(Is(Some(50.0))).row(Is(true)) |> ignore
            if press_node {
              row.on_press(fn() { taps.val += 1 }) |> ignore
            } else if parent_hold {
              row.gesture(@ui.touch_slop(), tap=fn(_) { taps.val += 1 }, hold=(@ui.long_press_ms, fn(_) { holds.val += 1 })) |> ignore
            } else {
              row.gesture(@ui.touch_slop(), tap=fn(_) { taps.val += 1 }) |> ignore
            }
            row.show(fn() { there.get() }, fn(slot) {
              let anchor = slot.box(fn(b) {
                b.width(Is(Some(80.0))).height(Is(Some(50.0))).presses(By(accepts)).points(By(fn() { label.get() != "" })) |> ignore
              })
              tip_node(tips, anchor, fn() { label.get() }, passive_hold=true) |> ignore
            })
            if covered {
              row.box(fn(over) {
                over.over(Is(true)).width(Is(Some(80.0))).height(Is(Some(50.0))).on_press(fn() { taps.val += 1 }) |> ignore
              }) |> ignore
            }
          }) |> ignore
        }
      }) |> ignore
    }) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  (t, scroll, taps, holds)
}

///|
fn passive_tip_shown(t : @ui.Tester) -> Bool {
  t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Quota" && !s.hidden })
}

///|
/// A passive anchor over a slider that competes with an enclosing scroll for the finger.
fn passive_slider_tester() -> (@ui.Tester, @view.Scroll, Array[String]) {
  let t = @ui.Tester::new(fn(_c) {  }, w=240.0, h=100.0, platform=2)
  t.check_looks(false)
  let scroll = @view.Scroll::new()
  let events : Array[String] = []
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(panel) {
      panel.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(scroll, fn(contents) {
        contents.box(fn(gap) { gap.height(Is(Some(30.0))) |> ignore }) |> ignore
        let slider = slider_node(
          contents, fn() { 50.0 }, fn() { 0.0 }, fn() { 100.0 },
          fn(_) { events.push("preview") }, fn(_) { events.push("commit") },
          label=fn() { "Reading" }, cancel=fn() { events.push("cancel") },
        )
        let anchor = slider.box(fn(v) { v.over(Is(true)).points(Is(true)) |> ignore })
        tip_node(tips, anchor, fn() { "Quota" }, passive_hold=true) |> ignore
        contents.box(fn(gap) { gap.height(Is(Some(300.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
    layer.val = Some(root.box(fn(v) { v.over(Is(true)) |> ignore }))
  })
  t.draw()
  (t, scroll, events)
}

///|
test "a passive tip and a slider keep their competing hold, horizontal drag and ancestor scroll" {
  for action in [0, 1, 2] {
    let (t, scroll, events) = passive_slider_tester()
    let (x, y, w, h) = t.get(Slider, label="Reading").rect
    let (px, py) = (x + w / 2.0, y + h / 2.0)
    t.touch(0, px, py)
    if action == 0 {
      t.touch(1, px + 40.0, py)
      t.touch(2, px + 40.0, py)
      assert_eq(events, ["preview", "preview", "commit"], msg="the slider keeps its horizontal drag")
      assert_eq(scroll.at(@ui.view_tree().unwrap()), 0.0)
    } else if action == 1 {
      t.touch(1, px, py - 30.0)
      t.touch(2, px, py - 30.0)
      assert_eq(events, ["preview", "cancel"], msg="the scroll cancels the slider once")
      assert_true(scroll.at(@ui.view_tree().unwrap()) > 0.0)
    } else {
      t.run_for(@ui.long_press_ms + a_moment_ms)
      assert_true(passive_tip_shown(t))
      t.touch(2, px, py)
      assert_eq(events, ["preview", "cancel"], msg="the tip's hold cancels the slider without committing")
    }
    if action != 2 {
      t.run_for(@ui.long_press_ms + @kit.pop_out_ms * 2.0)
      assert_false(passive_tip_shown(t), msg="a drag does not show the tip")
    }
  }
}

///|
test "a non-pressing tip anchor passes a short tap to its row, but a long press shows the tip and is no tap" {
  for press_node in [false, true] {
    let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false, press_node~)
    t.touch(0, 20.0, 125.0)
    t.touch(2, 20.0, 125.0)
    t.draw()
    assert_eq(taps.val, 1, msg="a short tap belongs to the row")
    t.touch(0, 20.0, 125.0)
    t.run_for(@ui.long_press_ms + a_moment_ms)
    assert_true(passive_tip_shown(t), msg="a finger held still shows the tip")
    t.touch(2, 20.0, 125.0)
    t.draw()
    assert_eq(taps.val, 1, msg="the hold consumed its press")
    assert_true(passive_tip_shown(t), msg="the tip remains briefly after lifting")
    t.run_for(@kit.tooltip_lifted_ms + @kit.pop_out_ms * 2.0)
    assert_false(passive_tip_shown(t))
  }
}

///|
test "a passive tip held and lifted between frames is shown, and does not press its row" {
  let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
  t.touch(0, 20.0, 125.0)
  t.advance(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_true(passive_tip_shown(t))
  assert_eq(taps.val, 0)
}

///|
test "a passive tip still follows a mouse over its non-pressing anchor" {
  let (t, _, _, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false, platform=0)
  t.move(20.0, 125.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_true(passive_tip_shown(t))
  t.move(250.0, 125.0)
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_false(passive_tip_shown(t))
}

///|
test "a non-pressing tip anchor lets a scroll take the finger before or after the hold" {
  for after_hold in [false, true] {
    let (t, scroll, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
    let tree = @ui.view_tree().unwrap()
    t.touch(0, 20.0, 125.0)
    if after_hold {
      t.run_for(@ui.long_press_ms + a_moment_ms)
      assert_true(passive_tip_shown(t))
    }
    t.touch(1, 20.0, 25.0)
    t.touch(2, 20.0, 25.0)
    t.run_for(@ui.long_press_ms + @kit.pop_out_ms * 2.0)
    assert_true(scroll.at(tree) > 0.0, msg="the ancestor scrolled")
    assert_eq(taps.val, 0)
    assert_false(passive_tip_shown(t), msg="the moved finger does not keep a tip")
  }
}

///|
test "a passive hold is cancelled with its anchor, on system cancellation, and by the row's own hold" {
  let there = @signals.signal(true)
  let (t, _, taps, _) = passive_tip_tester(there, @signals.signal("Quota"), false)
  t.touch(0, 20.0, 125.0)
  there.set(false)
  t.draw()
  t.run_for(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_false(passive_tip_shown(t), msg="no hold after its anchor was removed")
  assert_eq(taps.val, 1, msg="removing the observer did not take the row's tap")
  let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
  t.touch(0, 20.0, 125.0)
  t.touch(3, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  assert_false(passive_tip_shown(t))
  assert_eq(taps.val, 0)
  let (t, _, taps, holds) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), true)
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_eq((taps.val, holds.val), (0, 1), msg="the row's own hold wins")
  assert_false(passive_tip_shown(t))
}

///|
test "a passive tip held when the window goes away is cancelled without another finger event" {
  let (t, scroll, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
  let tree = @ui.view_tree().unwrap()
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  assert_true(passive_tip_shown(t))
  t.app_state(false, false)
  t.app_state(true, true)
  t.touch(1, 20.0, 25.0)
  t.touch(2, 20.0, 25.0)
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_false(passive_tip_shown(t))
  assert_eq(taps.val, 0)
  assert_eq(scroll.at(tree), 0.0, msg="a cancelled finger cannot start a scroll")
}

///|
test "a passive tip is cancelled when the system takes the held finger, or a second finger arrives" {
  let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  assert_true(passive_tip_shown(t))
  t.touch(3, 20.0, 125.0)
  t.run_for(@kit.pop_out_ms * 2.0)
  assert_false(passive_tip_shown(t))
  assert_eq(taps.val, 0)
  let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal("Quota"), false)
  t.touch(0, 20.0, 125.0)
  t.touch(4, 30.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  assert_false(passive_tip_shown(t))
  assert_eq(taps.val, 0)
}

///|
test "a passive tip does not take a press with an empty label, even when held" {
  let (t, _, taps, _) = passive_tip_tester(@signals.signal(true), @signals.signal(""), false)
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_eq(taps.val, 1)
  assert_false(passive_tip_shown(t))
  let (t, _, taps, holds) = passive_tip_tester(@signals.signal(true), @signals.signal(""), true)
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_eq((taps.val, holds.val), (0, 1), msg="the row's hold still works")
}

///|
test "a passive tip covered by another press target does not observe that target's finger" {
  let (t, _, taps, _) = passive_tip_tester(
    @signals.signal(true), @signals.signal("Quota"), false, covered=true,
  )
  t.touch(0, 20.0, 125.0)
  t.run_for(@ui.long_press_ms + a_moment_ms)
  t.touch(2, 20.0, 125.0)
  t.draw()
  assert_false(passive_tip_shown(t))
  assert_eq(taps.val, 1)
}

///|
test "a passive hold does not restart when its label or input is lost and restored during the press" {
  for lose_label in [false, true] {
    let label = @signals.signal("Quota")
    let accepts = @signals.signal(true)
    let (t, _, taps, _) = passive_tip_tester(
      @signals.signal(true), label, false, accepts=fn() { accepts.get() },
    )
    t.touch(0, 20.0, 125.0)
    if lose_label { label.set("") } else { accepts.set(false) }
    t.draw()
    if lose_label { label.set("Quota") } else { accepts.set(true) }
    t.draw()
    t.run_for(@ui.long_press_ms + a_moment_ms)
    assert_false(passive_tip_shown(t))
    t.touch(2, 20.0, 125.0)
    t.draw()
    assert_eq(taps.val, 1, msg="the row keeps the press")
  }
}
