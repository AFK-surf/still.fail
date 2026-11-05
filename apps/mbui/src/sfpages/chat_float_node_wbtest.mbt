///|
test "floating chat actions keep their clearance through content changes and pane resizing" {
  @sfbase.reset()
  composing_reset()
  let rows = @signals.signal(2)
  let raised = @signals.signal(false)
  let button : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=700.0, platform=2)
  @ui.set_view_app(fn(root) {
    let composer = root.box(fn(v) {
      v.width(Is(Some(200.0))).height(By(fn() { Some(rows.get().to_double() * 20.0) })) |> ignore
    })
    chat_float_node(root, fn() { composer.natural_height(200.0) },
      fn() { float_lift + (if raised.get() { float_above } else { 0.0 }) }, fn(content) {
        button.val = Some(content.box(fn(b) { b.width(Is(Some(32.0))).height(Is(Some(32.0))) |> ignore }))
      }) |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  for (w, h, n, up) in [(390.0, 700.0, 4, false), (720.0, 900.0, 2, true), (1280.0, 900.0, 6, false)] {
    let before = tree.work().computes
    @signals.start_batch()
    rows.set(n)
    raised.set(up)
    @signals.end_batch()
    t.resize(w, h)
    let (x, y, bw, bh) = button.val.unwrap().rect()
    assert_eq((bw, bh), (32.0, 32.0))
    assert_eq(w - x - bw, (w - composer_width(w)) / 2.0 + float_in)
    assert_eq(h - y - bh, n.to_double() * 20.0 + float_lift + (if up { float_above } else { 0.0 }))
    assert_eq(tree.work().computes - before, 1,
      msg="measuring the composer clearance must not publish another layout input")
  }
}
