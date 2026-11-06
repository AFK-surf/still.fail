// The panel separator in the retained tree has the same geometry and ink as the old panel separator.

///|
fn panel_rule_drawing(node : Bool, dark : Bool, width : Double, start : Bool) -> Array[(Double, Double, Double, Double, Int64)] {
  set_dark(Some(dark))
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    if !node {
      c.with_theme(ui_theme(), fn() {
        c.box(w=Px(width), align=if start { AStart } else { AStretch }, fn() { menu_rule(c) }) |> ignore
      })
    }
  }, w=400.0, h=80.0, dark~)
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(panel) {
        panel.width(Is(Some(width))).lines_up(Is(if start { Some(Start) } else { None })) |> ignore
        menu_rule_node(panel)
      }) |> ignore
    })
  }
  t.draw()
  let drawn = t.drawn_rects()
  set_dark(None)
  drawn
}

///|
test "panel rule node draws like menu_rule at both widths and themes" {
  for dark in [false, true] {
    for width in [160.0, 320.0] {
      for start in [false, true] {
        let old = panel_rule_drawing(false, dark, width, start)
        let node = panel_rule_drawing(true, dark, width, start)
        assert_eq(node, old, msg="width \{width}, dark \{dark}, start \{start}")
        assert_true(node.iter().any(fn(r) { r.0 == 0.0 && r.1 == 6.0 && r.2 == width && r.3 == 1.0 }))
      }
    }
  }
}
