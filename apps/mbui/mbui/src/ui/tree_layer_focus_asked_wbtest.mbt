///|
test "a retained field's initial request under a new modal is returned on close; a later request preserves the modal's original return target" {
  for initial in [true, false] {
    let open = @signals.signal(false)
    let page_field = Field::new()
    let t = Tester::new(fn(_) { }, w=400.0, h=300.0, platform=0)
    set_view_app(fn(root) {
      root.box(fn(b) {
        b.width(Is(Some(120.0))).height(Is(Some(40.0)))
        .focusable(Is(true)).says(Is(Some(@view.said(Button, label="Page button")))) |> ignore
      }) |> ignore
      field(root, page_field, placeholder="Page field") |> ignore
      root.show(fn() { open.get() }, fn(layer) {
        layer.over(Is(true)).stacked(Is(2)).modal(Is(true)) |> ignore
        let stop = layer.box(fn(b) {
          b.width(Is(Some(120.0))).height(Is(Some(40.0)))
          .focusable(Is(true)).says(Is(Some(@view.said(Button, label="Modal button")))) |> ignore
        })
        layer.focus_opens(stop) |> ignore
      })
    })
    t.draw()
    t.act(Button, Focus, label="Page button")
    open.set(true)
    if !initial { t.draw() }
    page_field.focus()
    t.draw()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Modal button"))
    open.set(false)
    t.draw()
    assert_eq(t.focused().map(fn(s) { s.label }), Some(if initial { "Page field" } else { "Page button" }))
  }
}
