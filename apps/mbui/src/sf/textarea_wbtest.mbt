// A textarea's placeholder and the room it offers to type in.

///|
test "a textarea shows both lines of its placeholder and takes a press throughout its empty area" {
  let hint = "ABCD\nEFGH"
  for (width, platform) in [(800.0, 0), (390.0, 1)] {
    let field = @ui.Field::new()
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          textarea(c, "env", rows=6, placeholder=hint, field~) |> ignore
        })
      },
      w=width,
      h=400.0,
      platform~,
    )
    t.draw()
    t.draw()
    assert_eq(field.text(), "", msg="the hint is not the field's value")
    assert_eq(t.glyphs_seen().length(), 8, msg="both lines of the hint are visible at width \{width}")
    let (x, y, _, h) = t.get(TextField, label=hint).rect
    t.tap(x + 8.0, y + h - 8.0)
    t.type_text("x")
    assert_eq(field.text(), "x", msg="the field takes a press at its foot")
    t.clear()
    t.draw()
    assert_eq(t.glyphs_seen().length(), 8, msg="both hint lines return when cleared")
    field.set("1\n2\n3\n4\n5\n6\n7")
    t.draw()
    assert_true(t.get(TextField, label=hint).rect.3 > h, msg="the field grows past its six rows")
  }
}
