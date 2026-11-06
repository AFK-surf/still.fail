// The retained slider: its event-time preview and commit, its live inputs, focus and cancellation.

///|
struct SliderCase {
  tester : @ui.Tester
  value : @signals.Signal[Double]
  lo : @signals.Signal[Double]
  hi : @signals.Signal[Double]
  step : @signals.Signal[Double]
  ink : @signals.Signal[Int64]
  accent : @signals.Signal[Int64]
  ground : @signals.Signal[Int64]
  disabled : @signals.Signal[Bool]
  there : @signals.Signal[Bool]
  node : Ref[@view.View?]
  events : Array[(String, Double, Double)]
}

///|
fn slider_case(platform : Int, step0 : Double, width? : Double = 200.0) -> SliderCase {
  let value = @signals.signal(50.0)
  let lo = @signals.signal(0.0)
  let hi = @signals.signal(100.0)
  let step = @signals.signal(step0)
  let ink = @signals.signal(0x111111FFL)
  let accent = @signals.signal(0x3366FFFFL)
  let ground = @signals.signal(0xFFFFFFFFL)
  let disabled = @signals.signal(false)
  let there = @signals.signal(true)
  let node : Ref[@view.View?] = Ref(None)
  let events : Array[(String, Double, Double)] = []
  let tester = @ui.Tester::new(fn(_c) {  }, w=300.0, h=100.0, platform~)
  tester.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(holder) {
      holder.width(Is(Some(width))) |> ignore
      holder.show(fn() { there.get() }, fn(at) {
        node.val = Some(slider_node(
          at,
          fn() { value.get() },
          fn() { lo.get() },
          fn() { hi.get() },
          fn(x) { events.push(("preview", x, node.val.unwrap().cause_at())) },
          fn(x) {
            events.push(("commit", x, node.val.unwrap().cause_at()))
            value.set(x)
          },
          step=fn() { step.get() },
          label=fn() { "Reading" },
          ink=fn() { ink.get() },
          accent=fn() { accent.get() },
          ground=fn() { ground.get() },
          disabled=fn() { disabled.get() },
          cancel=fn() { events.push(("cancel", 0.0, node.val.unwrap().cause_at())) },
        ))
      })
    }) |> ignore
  })
  tester.draw()
  { tester, value, lo, hi, step, ink, accent, ground, disabled, there, node, events }
}

///|
test "slider node: pointer down and up with no frame preview and commit at their own times" {
  for platform in [0, 2] {
    let c = slider_case(platform, 5.0)
    let (x, y, w, h) = c.tester.get(Slider, label="Reading").rect
    c.tester.touch_at(0, x + 11.0, y + h / 2.0, 100.0)
    assert_eq(c.events, [("preview", 0.0, 100.0)])
    assert_eq(c.value.get(), 50.0)
    c.tester.touch_at(2, x + w - 11.0, y + h / 2.0, 150.0)
    assert_eq(c.events, [("preview", 0.0, 100.0), ("preview", 100.0, 150.0), ("commit", 100.0, 150.0)])
    assert_eq(c.value.get(), 100.0)
  }
}

///|
test "slider node: a track no wider than its thumb does not jump to an endpoint" {
  let c = slider_case(2, 0.0, width=18.0)
  let (x, y, w, h) = c.tester.get(Slider, label="Reading").rect
  c.tester.touch_at(0, x + w / 2.0, y + h / 2.0, 10.0)
  c.tester.touch_at(2, x + w / 2.0, y + h / 2.0, 20.0)
  assert_eq(c.value.get(), 50.0)
}

///|
test "slider node: drag follows each event, last place wins, system cancellation does not commit" {
  let c = slider_case(2, 5.0)
  let (x, y, w, h) = c.tester.get(Slider, label="Reading").rect
  c.tester.touch_at(0, x + 11.0, y + h / 2.0, 10.0)
  c.tester.touch_at(1, x + w / 2.0, y + h / 2.0, 20.0)
  c.tester.touch_at(2, x + w - 11.0, y + h / 2.0, 30.0)
  assert_eq(c.events, [("preview", 0.0, 10.0), ("preview", 50.0, 20.0), ("preview", 100.0, 30.0), ("commit", 100.0, 30.0)])
  c.events.clear()
  c.tester.touch_at(0, x + w / 2.0, y + h / 2.0, 40.0)
  c.tester.touch_at(3, x + w / 2.0, y + h / 2.0, 50.0)
  assert_eq(c.events, [("preview", 50.0, 40.0), ("cancel", 0.0, 50.0)])
  assert_eq(c.value.get(), 100.0)
}

///|
test "slider node: a move within the slop previews at its own time" {
  let c = slider_case(2, 0.0)
  let (x, y, _, h) = c.tester.get(Slider, label="Reading").rect
  c.tester.touch_at(0, x + 11.0, y + h / 2.0, 10.0)
  c.tester.touch_at(1, x + 14.0, y + h / 2.0, 20.0)
  assert_eq(c.events.length(), 2)
  assert_eq((c.events[1].0, c.events[1].2), ("preview", 20.0))
  assert_true(c.events[1].1 > 0.0)
  c.tester.touch_at(2, x + 14.0, y + h / 2.0, 30.0)
  assert_eq((c.events[2].0, c.events[2].2), ("commit", 30.0))
}

///|
test "slider node: removal during a hold cancels once and takes no later release" {
  let c = slider_case(2, 1.0)
  let (x, y, _, h) = c.tester.get(Slider, label="Reading").rect
  c.tester.touch_at(0, x + 11.0, y + h / 2.0, 10.0)
  c.there.set(false)
  c.tester.touch_at(2, x + 150.0, y + h / 2.0, 20.0)
  assert_eq(c.events.map(fn(e) { e.0 }), ["preview", "cancel"])
  assert_eq(c.value.get(), 50.0)
}

///|
test "slider node: disabled during a hold cancels its preview immediately" {
  let c = slider_case(2, 1.0)
  let (x, y, _, h) = c.tester.get(Slider, label="Reading").rect
  c.tester.touch_at(0, x + 11.0, y + h / 2.0, 10.0)
  c.disabled.set(true)
  c.tester.touch_at(2, x + 150.0, y + h / 2.0, 20.0)
  assert_eq(c.events.map(fn(e) { e.0 }), ["preview", "cancel"])
  assert_eq(c.value.get(), 50.0)
}

///|
test "slider node: a key previews and commits at its own time without a frame" {
  let c = slider_case(0, 5.0)
  c.tester.key(@ui.key_tab)
  c.events.clear()
  c.tester.key_told(@ui.key_code_right, 0, 100.0)
  assert_eq(c.events, [("preview", 55.0, 100.0), ("commit", 55.0, 100.0)])
}

///|
test "slider node: focus, arrows, page and ends use live bounds and step; disabled takes neither focus nor input" {
  let c = slider_case(0, 5.0)
  c.tester.key(@ui.key_tab)
  assert_true(c.tester.get(Slider, label="Reading").focused)
  c.tester.key(@ui.key_code_right)
  assert_eq(c.value.get(), 55.0)
  c.tester.key(@ui.key_code_down)
  assert_eq(c.value.get(), 50.0)
  c.lo.set(40.0)
  c.hi.set(60.0)
  c.step.set(2.0)
  c.tester.key(@ui.key_code_page_up)
  assert_eq(c.value.get(), 60.0)
  c.tester.key(@ui.key_code_home)
  assert_eq(c.value.get(), 40.0)
  c.step.set(0.0)
  c.tester.key(@ui.key_code_up)
  assert_true((c.value.get() - 40.2).abs() < 0.000001)
  c.tester.draw()
  let s = c.tester.get(Slider, label="Reading")
  assert_eq(s.range, Some((40.0, c.value.get(), 60.0)))
  c.disabled.set(true)
  c.tester.key(@ui.key_code_end)
  assert_true((c.value.get() - 40.2).abs() < 0.000001)
  assert_true(c.tester.get(Slider, label="Reading").disabled)
}

///|
test "slider node: value and colours are followed after it is made" {
  let c = slider_case(0, 0.0)
  let id = c.node.val.unwrap().id()
  let tree = @ui.view_tree().unwrap()
  let layouts = tree.work().computes
  c.value.set(75.0)
  c.accent.set(0xEE0033FFL)
  c.ink.set(0x000000FFL)
  c.ground.set(0x222222FFL)
  c.tester.draw()
  assert_eq(c.node.val.unwrap().id(), id)
  let s = c.tester.get(Slider, label="Reading")
  assert_eq(s.range, Some((0.0, 75.0, 100.0)))
  assert_true(c.tester.drawn_rects().any(fn(r) { r.4 == 0xEE0033FFL }))
  assert_true(c.tester.drawn_rects().any(fn(r) { r.4 == 0x00000029L }))
  let before_ground = c.tester.drawn_instances()
  c.ground.set(0x33EE55FFL)
  c.tester.draw()
  assert_true(before_ground != c.tester.drawn_instances(), msg="the thumb's ring follows its ground")
  assert_eq(tree.work().computes, layouts, msg="moving the thumb paints without another layout")
}

///|
test "slider node: a vertical finger drag over it scrolls the enclosing list and cancels the preview" {
  let t = @ui.Tester::new(fn(_c) {  }, w=240.0, h=100.0, platform=2)
  t.check_looks(false)
  let list = @view.Scroll::new()
  let events : Array[String] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(panel) {
      panel.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(list, fn(contents) {
        contents.box(fn(gap) { gap.height(Is(Some(30.0))) |> ignore }) |> ignore
        slider_node(
          contents,
          fn() { 50.0 },
          fn() { 0.0 },
          fn() { 100.0 },
          fn(_) { events.push("preview") },
          fn(_) { events.push("commit") },
          label=fn() { "Reading" },
          cancel=fn() { events.push("cancel") },
        ) |> ignore
        contents.box(fn(gap) { gap.height(Is(Some(300.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(Slider, label="Reading").rect
  t.touch_at(0, x + w / 2.0, y + h / 2.0, 10.0)
  t.touch_at(1, x + w / 2.0, y + h / 2.0 - 30.0, 20.0)
  t.touch_at(2, x + w / 2.0, y + h / 2.0 - 30.0, 30.0)
  assert_true(list.at(@ui.view_tree().unwrap()) > 0.0)
  assert_eq(events, ["preview", "cancel"])
}

///|
test "slider node: a mouse keeps a vertical drag over a scrollable parent" {
  let t = @ui.Tester::new(fn(_c) {  }, w=240.0, h=100.0, platform=0)
  t.check_looks(false)
  let list = @view.Scroll::new()
  let events : Array[String] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(panel) {
      panel.width(Is(Some(200.0))).height(Is(Some(100.0))).scrolls(list, fn(contents) {
        contents.box(fn(gap) { gap.height(Is(Some(30.0))) |> ignore }) |> ignore
        slider_node(contents, fn() { 50.0 }, fn() { 0.0 }, fn() { 100.0 },
          fn(_) { events.push("preview") }, fn(_) { events.push("commit") },
          label=fn() { "Reading" }, cancel=fn() { events.push("cancel") }) |> ignore
        contents.box(fn(gap) { gap.height(Is(Some(300.0))) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.get(Slider, label="Reading").rect
  t.touch_at(0, x + w / 2.0, y + h / 2.0, 10.0)
  t.touch_at(1, x + w / 2.0 + 2.0, y + h / 2.0 - 30.0, 20.0)
  t.touch_at(2, x + w / 2.0 + 2.0, y + h / 2.0 - 30.0, 30.0)
  assert_eq(list.at(@ui.view_tree().unwrap()), 0.0)
  assert_eq(events, ["preview", "preview", "commit"])
}

///|
test "slider node: a finger leaves a focused field's keyboard, a mouse moves focus to the slider" {
  for platform in [0, 2] {
    let f = @ui.Field::new()
    let t = field_node_case(platform~, fn(b) {
      input_node(b, f, placeholder="Name") |> ignore
      slider_node(b, fn() { 0.5 }, fn() { 0.0 }, fn() { 1.0 }, fn(_) {  }, fn(_) {  }, label=fn() { "Reading" }) |> ignore
    })
    let (fx, fy) = field_middle(t, "Name")
    t.tap(fx, fy)
    t.host_says_finger(Some(platform == 2))
    let (x, y, w, h) = t.get(Slider, label="Reading").rect
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq(t.focused().map(fn(s) { s.label }), Some(if platform == 2 { "Name" } else { "Reading" }))
    if platform == 2 {
      t.type_text("A")
      assert_eq(f.text(), "A")
    }
  }
}

///|
test "slider node: declared accessibility actions change and commit the live value at the request's time" {
  let c = slider_case(0, 5.0)
  c.tester.set_a11y(true)
  let s = c.tester.get(Slider, label="Reading")
  assert_true(s.actions.contains(Increment))
  assert_true(s.actions.contains(Decrement))
  let t0 = c.tester.time()
  let action_step_ms = 50.0
  c.tester.advance(action_step_ms)
  c.tester.ctx().ask_action(s.id, Increment)
  c.tester.advance(action_step_ms)
  c.tester.ctx().ask_action(s.id, Decrement)
  assert_eq(c.events, [
    ("preview", 55.0, t0 + action_step_ms), ("commit", 55.0, t0 + action_step_ms),
    ("preview", 50.0, t0 + 2.0 * action_step_ms), ("commit", 50.0, t0 + 2.0 * action_step_ms),
  ])
  c.disabled.set(true)
  c.tester.ctx().ask_action(s.id, Increment)
  assert_eq(c.value.get(), 50.0)
  assert_eq(c.events.length(), 4)
}

///|
test "slider node: accessibility steps use fractional live bounds" {
  let c = slider_case(0, 0.05)
  c.lo.set(0.0)
  c.hi.set(1.0)
  c.value.set(0.5)
  c.tester.draw()
  let s = c.tester.get(Slider, label="Reading")
  c.tester.ctx().ask_action(s.id, Increment)
  assert_true((c.value.get() - 0.55).abs() < 0.000001)
  c.tester.ctx().ask_action(s.id, Decrement)
  assert_true((c.value.get() - 0.5).abs() < 0.000001)
  assert_eq(c.events.map(fn(e) { e.0 }), ["preview", "commit", "preview", "commit"])
}
