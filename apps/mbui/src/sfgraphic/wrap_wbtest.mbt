///|
fn example_positions(width : Double, reverse : Bool) -> (Double, Double, Double, Double) {
  let t = @ui.Tester::new(fn(c) {
    c.set_theme(@sf.ui_theme_now())
    sign_in_example(c, width, reverse, "example")
  }, w=width, h=250.0, words_over_held=false, corners_held=false)
  @sf.set_dark(Some(true))
  t.draw()
  let (_, primary_y, _, _) = t.rect_of("Use password manager").unwrap()
  let (_, screen_y, _, _) = t.rect_of("Sign in here").unwrap()
  let (vault_x, vault_y, _, _) = t.rect_of("Save to vault").unwrap()
  (primary_y, screen_y, vault_x, vault_y)
}

///|
test "the same three sign-in actions fit wide and wrap in the requested direction when narrow" {
  let wide = example_positions(686.0, true)
  assert_true((wide.0 - wide.1).abs() < 1.0)
  assert_true((wide.0 - wide.3).abs() < 1.0)
  let normal = example_positions(398.0, false)
  assert_true((normal.0 - normal.1).abs() < 1.0)
  assert_true(normal.3 > normal.0)
  let reverse = example_positions(398.0, true)
  assert_true((reverse.0 - reverse.1).abs() < 1.0)
  assert_true(reverse.3 < reverse.0)
  assert_true((normal.2 - reverse.2).abs() < 1.0)
  @sf.set_dark(None)
}

///|
test "the figure's white panels keep mbui's corners and room around their cards and words" {
  let started = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if !started.val {
      @sf.set_dark(Some(true))
      started.val = true
    }
    wrap_figure(c)
  }, w=960.0, h=540.0, corners_held=false, words_over_held=false)
  let boxes = t.boxes()
  let panels = boxes.filter(fn(b) { b.bg == white && (b.w == 860.0 || b.w == 418.0) })
  assert_eq(panels.length(), 3)
  let card_ground = @sf.theme().p.card
  for panel in panels {
    assert_eq(panel.radii, (@sf.pane_corner, @sf.pane_corner, @sf.pane_corner, @sf.pane_corner))
    let card = boxes.iter().find_first(fn(b) {
      b.bg == card_ground && b.x >= panel.x && b.y >= panel.y && b.x + b.w <= panel.x + panel.w && b.y + b.h <= panel.y + panel.h
    }).unwrap()
    assert_true((panel.x + panel.w - card.x - card.w - @sf.corner_inset).abs() < 0.000001)
    if panel.w == 860.0 {
      assert_true((card.y - panel.y - @sf.corner_inset).abs() < 0.000001)
      assert_true((panel.y + panel.h - card.y - card.h - @sf.corner_inset).abs() < 0.000001)
    } else {
      assert_eq(card.x - panel.x, @sf.corner_inset)
      let caption = boxes.iter().find_first(fn(b) {
        b.text.has_prefix("The primary action") && b.x >= panel.x && b.y >= panel.y && b.x + b.w <= panel.x + panel.w && b.y + b.h <= panel.y + panel.h
      }).unwrap()
      assert_true(panel.y + panel.h - caption.y - caption.h >= @sf.card_pad)
    }
  }
  let faults = t.corner_faults()
  assert_true(faults.is_empty(), msg=faults.join("\n"))
  @sf.set_dark(None)
}
