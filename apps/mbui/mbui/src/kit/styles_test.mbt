// kit's recipes (styles.mbt): what they come to in the default theme, and the corner rule kept by how they are
// written (rows `Inner` in a list card).

///|
test "styles: rows in a list card are concentric with it, in every density, chosen and pressed too" {
  for density in [Density::Comfy, Density::Compact] {
    let t = @ui.Tester::new(fn(c) {
      c.box(pad=20.0, fn() {
        c.box(style=list_card(), fn() {
          for k in 0..<3 {
            c.box(style=list_row(density~), selected=k == 1, id=c.id("row" + k.to_string()), fn() {
              c.text("Row " + k.to_string(), style=row_title()) |> ignore
              c.box(w=Fill(1.0), fn() {  }) |> ignore
              c.text("value", style=row_value()) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    t.touch(0, 60.0, 40.0)
    t.draw()
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "styles: a button's size and tone; a small ghost one has no padding at its sides" {
  let th = @ui.Theme::light()
  let s = button_style().base
  assert_eq(s.bg, Some(Primary))
  assert_eq(s.h, Some(S9))
  assert_eq(s.px, Some(S4))
  assert_eq(th.color(s.bg.unwrap()), th.primary)
  let s = button_style(size=Sm, tone=Ghost).base
  assert_eq(s.px, Some(S0))
  assert_eq(s.h, Some(S7))
  assert_eq(button_style(size=Sm, tone=Soft).base.px, Some(S3))
}

///|
test "styles: a panel's items `Inner`, a field and a badge drawn in the theme" {
  let t = @ui.Tester::new(fn(c) {
    c.box(pad=20.0, gap=12.0, fn() {
      c.box(style=panel(), fn() {
        for k in 0..<2 {
          c.box(style=list_row(density=Compact), id=c.id("item" + k.to_string()), fn() {
            c.text("Item", style=row_title()) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      c.box(style=field(), fn() { c.text("Name", style=row_sub()) |> ignore }) |> ignore
      c.box(style=badge(tone=Danger), fn() { c.text("3", style=badge_text(tone=Danger)) |> ignore }) |> ignore
      c.box(style=card(tone=Lifted), fn() { c.text("Card", style=row_title()) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [])
  let k = t.census()
  // the badge's ground, the danger's words, the field's edge, the lifted card's ground
  let th = @ui.Theme::light()
  for want in [th.danger_bg, th.danger, th.border, th.raised] {
    let hex = StringBuilder()
    for i in 0..<8 {
      hex.write_char("0123456789ABCDEF"[((want >> ((7 - i) * 4)) & 0xFL).to_int()].unsafe_to_char())
    }
    assert_true(k.color.contains(hex.to_string()), msg=hex.to_string())
  }
}
