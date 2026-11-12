// A tool's tip shown as the pointer rests on it, the tool then carried from under the still pointer by the room over it
// growing on a way: the tip stays as the tool goes (what the pointer is over is not worked out on the way), and shuts
// once the way is over and the tool is found no longer under it (Tree::hand_at_end).

///|
/// How long the room over it takes to grow, carrying it off.
let carried_ms : Double = 300.0

///|
test "a tool's tip, the tool carried from under a still pointer on a way: shown as it goes, shut once the way is over" {
  let grow = @motion.Way::new(40.0)
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(col) {
      col.box(fn(b) { b.height(By(fn() { Some(grow.shown_on(b)) })) |> ignore }) |> ignore
      col.box(fn(b) {
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
      |> ignore
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  let tips = fn() { t.semantics().filter(fn(s) { s.role == Tooltip && s.label == "复制" }).length() }
  let n = t.get(Button, label="复制")
  t.move_to(n.rect.0 + 16.0, n.rect.1 + 16.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  assert_eq(tips(), 1, msg="shown")
  let tree = @ui.view_tree().unwrap()
  let at = t.time()
  tree.event(at, fn() { grow.go(140.0, @motion.tween(carried_ms, ease=Out), at~) })
  t.run_for(carried_ms / 2.0)
  let midway = tips()
  t.run_for(carried_ms / 2.0 + @kit.pop_out_ms * 2.0)
  assert_eq((midway, tips()), (1, 0))
}
