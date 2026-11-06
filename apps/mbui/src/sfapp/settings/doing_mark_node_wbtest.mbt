// The operation mark follows the operation, including a new failure reason and a retry, without taking the row's input.

///|
test "doing mark nodes follow the operation, its reason and its lifetime at both sizes" {
  for inline in [false, true] {
    let running = @signals.signal(false, same=fn(a, b) { a == b })
    let failed : @signals.Signal[String?] = @signals.signal(None, same=fn(a, b) { a == b })
    let shown = @signals.signal(true, same=fn(a, b) { a == b })
    let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=160.0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      let layer : Ref[@view.View?] = Ref(None)
      let tips = @sf.TipLayer::new(fn() { layer.val })
      root.box(fn(row) {
        row.width(Is(Some(100.0))).height(Is(Some(44.0))).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        row.show(fn() { shown.get() }, fn(p) {
          doing_mark_node(p, fn() { running.get() }, fn() { failed.get() }, tips, inline~)
        })
      }) |> ignore
      layer.val = Some(root.box(fn(over) { over.over(Is(true)) |> ignore }))
    })
    let status = fn() { t.semantics().filter(fn(s) { s.role == Status && !s.hidden }).map(fn(s) { s.label }) }
    let tips = fn() { t.semantics().filter(fn(s) { s.role == Tooltip && !s.hidden }).map(fn(s) { s.label }) }
    t.draw()
    assert_eq(status(), [])
    failed.set(Some("First failure"))
    t.draw()
    let mark = t.get(Status, label="First failure")
    let size = if inline { 12.0 } else { 14.0 }
    assert_eq((mark.rect.2, mark.rect.3), (size, size))
    t.move(mark.rect.0 + size / 2.0, mark.rect.1 + size / 2.0)
    t.run_for(@sf.tip_delay_ms + @kit.pop_out_ms)
    assert_eq(tips(), ["First failure"])
    failed.set(Some("Another failure"))
    t.draw()
    assert_eq(status(), ["Another failure"])
    assert_eq(tips(), ["Another failure"])
    // A retry takes precedence over a still-present error; a second failure and the empty-reason fallback follow it.
    running.set(true)
    t.draw()
    assert_eq(status(), [])
    assert_eq(tips(), [])
    assert_true(t.drawn_instances().iter().any(fn(i) { i[5] == 10.0 }), msg="the spinner is drawn")
    running.set(false)
    failed.set(Some(""))
    t.draw()
    assert_eq(status(), [@sf.t("web-main.doing.failed")])
    // Removing its owner removes its tip and its pending work as well; it may be made again.
    let fallback = t.get(Status, label=@sf.t("web-main.doing.failed"))
    t.move(290.0, 140.0)
    t.move(fallback.rect.0 + size / 2.0, fallback.rect.1 + size / 2.0)
    t.run_for(@sf.tip_delay_ms + @kit.pop_out_ms)
    assert_eq(tips(), [@sf.t("web-main.doing.failed")])
    shown.set(false)
    t.draw()
    assert_eq(status(), [])
    assert_eq(tips(), [])
    shown.set(true)
    t.draw()
    assert_eq(status(), [@sf.t("web-main.doing.failed")])
    failed.set(None)
    t.draw()
    assert_eq(status(), [])
  }
}

///|
test "the failure mark does not take its row's mouse, touch or keyboard action" {
  let failed : @signals.Signal[String?] = @signals.signal(Some("Could not save"), same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=160.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = @sf.TipLayer::new(fn() { layer.val })
    root.box(fn(row) {
      row.width(Is(Some(100.0))).height(Is(Some(44.0))).row(Is(true)).lines_up(Is(Some(Middle)))
      .says(Is(Some(@view.said(Button, label="Retry")))) |> ignore
      @sf.presses_node(row, fn() { pressed.val = pressed.val + 1 })
      doing_mark_node(row, fn() { false }, fn() { failed.get() }, tips)
    }) |> ignore
    layer.val = Some(root.box(fn(over) { over.over(Is(true)) |> ignore }))
  })
  t.draw()
  let mark = t.get(Status, label="Could not save")
  let x = mark.rect.0 + mark.rect.2 / 2.0
  let y = mark.rect.1 + mark.rect.3 / 2.0
  t.tap(x, y)
  assert_eq(pressed.val, 1, msg="mouse")
  t.host_says_finger(Some(true))
  t.tap(x, y)
  assert_eq(pressed.val, 2, msg="touch")
  t.host_says_finger(Some(false))
  t.tab()
  failed.set(None)
  t.draw()
  t.enter()
  assert_eq(pressed.val, 3, msg="keyboard focus remains on the row when the mark goes")
}
