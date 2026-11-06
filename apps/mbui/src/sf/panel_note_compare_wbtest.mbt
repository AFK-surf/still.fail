// Temporary migration verification: compare the immediate and retained components at identical sizes.

///|
fn panel_note_drawn(node : Bool, width : Double, scale : Double, dark : Bool, value : String) -> Array[String] {
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    if !node {
      c.with_theme(ui_theme(), fn() {
        c.box(style=@ui.style(w=Fixed(width)), fn() { panel_note(c, value) }) |> ignore
      })
    }
  }, w=500.0, h=500.0, dark~)
  t.set_font_scale(scale)
  set_dark(Some(dark))
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(panel) {
        panel.width(Is(Some(width))) |> ignore
        panel_note_node(panel, fn() { value }) |> ignore
      }) |> ignore
    })
  }
  t.draw()
  let all = t.drawn_instances().map(fn(a) {
    a.mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    }).join(",")
  })
  all.sort()
  all
}

///|
test "panel note migration comparison across widths, themes, scales and languages" {
  for width in [140.0, 260.0, 480.0] {
    for scale in [1.0, 2.0] {
      for dark in [false, true] {
        for value in ["Automatic frame rate", "The recommended resolution changes with the screen.\nA second line.", "推荐分辨率会随画面变化。\n调试结果已更新。"] {
          let old = panel_note_drawn(false, width, scale, dark, value)
          let made = panel_note_drawn(true, width, scale, dark, value)
          assert_eq(made, old, msg="width=\{width}, scale=\{scale}, dark=\{dark}, words=\{value}")
        }
      }
    }
  }
}
