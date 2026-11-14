// A tip of a control that goes as its room closes on a Move (what holds it shown no more down a column): the tip gone at
// the moment it starts going (View::lives_with), not as it is let go; the control called back before it has gone,
// its tip shown again as the pointer rests on it, and again as it is pointed at anew.

///|
/// A column: room, then a tool (复制) while `there` says so, then room; the tips' layer over all of it.
fn tip_leaving_tester(there : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(col) {
      col.box(fn(b) { b.height(Is(Some(40.0))) |> ignore }) |> ignore
      col.show(fn() { there.get() }, fn(b) {
        tool_node(
          b,
          fn() { { icon: "copy", label: "复制", on: false, disabled: false } },
          fn() { page_viewer_ink() },
          Is(tool_side / 2.0),
          fn() {  },
          tip=tips,
        )
        |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(40.0))) |> ignore }) |> ignore
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  t
}

///|
test "a tool's tip, its tool's room closing on a Move: gone as it starts going; the tool called back before it has gone: shown again as the pointer rests on it, and as it is pointed at anew" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = tip_leaving_tester(there)
  let tips = fn() { t.semantics().filter(fn(s) { s.role == Tooltip && s.label == "复制" }).length() }
  let n = t.get(Button, label="复制")
  t.move_to(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tips(), 1, msg="shown")
  there.set(false)
  t.draw()
  assert_eq(tips(), 0, msg="gone as its tool starts going")
  // (shown again before its Move is over: the same tool, back, the pointer resting on it all along)
  there.set(true)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tips(), 1, msg="shown again, the pointer resting on it")
  t.leave()
  t.run_for(tip_settled_ms)
  assert_eq(tips(), 0, msg="gone as the pointer leaves")
  let n = t.get(Button, label="复制")
  t.move_to(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tips(), 1, msg="shown again, pointed at anew")
}
