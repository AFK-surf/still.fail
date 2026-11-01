///|
fn alignment_positions(text_aligned : Bool) -> (Double, Double, Double) {
  let started = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if !started.val {
      @sf.set_dark(Some(true))
      started.val = true
    }
    c.set_theme(@sf.ui_theme_now())
    alignment_example(c, 398.0, text_aligned, "example")
  }, w=398.0, h=240.0, corners_held=false)
  let (title_x, _, _, _) = t.rect_of("Quota check failed").unwrap()
  let (label_x, _, _, _) = t.rect_of("Try again").unwrap()
  let button = t.drawn_rects().iter().find_first(fn(r) { (r.3 - @sf.button_height()).abs() < 0.01 }).unwrap()
  (title_x, label_x, button.0)
}

///|
test "edge alignment lines up the button, text alignment lines up its label" {
  let edge = alignment_positions(false)
  assert_true((edge.0 - edge.2).abs() < 0.01)
  assert_true(edge.1 > edge.0)
  let words = alignment_positions(true)
  assert_true((words.0 - words.1).abs() < 0.01)
  assert_true(words.2 < words.0)
  @sf.set_dark(None)
}

///|
test "the white panels keep their corners and padding, with only the illustrated corner exception" {
  let started = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if !started.val {
      @sf.set_dark(Some(true))
      started.val = true
    }
    alignment_figure(c)
  }, w=960.0, h=540.0, corners_held=false, words_over_held=false)
  let boxes = t.boxes()
  let panels = boxes.filter(fn(b) { b.bg == white && b.w == 418.0 })
  assert_eq(panels.length(), 2)
  let card_ground = @sf.theme().p.card
  for panel in panels {
    assert_eq(panel.radii, (@sf.pane_corner, @sf.pane_corner, @sf.pane_corner, @sf.pane_corner))
    let card = boxes.iter().find_first(fn(b) {
      b.bg == card_ground && b.x >= panel.x && b.y >= panel.y && b.x + b.w <= panel.x + panel.w && b.y + b.h <= panel.y + panel.h
    }).unwrap()
    assert_eq(card.x - panel.x, @sf.corner_inset)
    assert_true((panel.x + panel.w - card.x - card.w - @sf.corner_inset).abs() < 0.000001)
    let caption = boxes.iter().find_first(fn(b) {
      (b.text.has_prefix("The button reaches") || b.text.has_prefix("The label sits")) &&
      b.x >= panel.x && b.y >= panel.y && b.x + b.w <= panel.x + panel.w && b.y + b.h <= panel.y + panel.h
    }).unwrap()
    assert_true(panel.y + panel.h - caption.y - caption.h >= @sf.card_pad)
  }
  let guides = boxes.filter(fn(b) { b.w <= 6.0 && b.h <= 2.5 && (b.bg == red || b.bg == blue) })
  assert_true(!guides.is_empty())
  for guide in guides {
    for label in boxes.filter(fn(b) {
      b.text == "Quota check failed" || b.text == "Request timed out." ||
      b.text == "Check your connection and try again." || b.text == "Try again"
    }) {
      assert_true(
        guide.x + guide.w <= label.x || label.x + label.w <= guide.x ||
        guide.y + guide.h <= label.y || label.y + label.h <= guide.y,
        msg="alignment guide at \{guide.x},\{guide.y} size \{guide.w}×\{guide.h} crosses \{label.text} at \{label.x},\{label.y} size \{label.w}×\{label.h}",
      )
    }
  }
  let faults = t.corner_faults()
  assert_true(alignment_corner_faults_ok(faults), msg=faults.join("\n"))
  assert_false(alignment_corner_faults_ok([]))
  assert_false(alignment_corner_faults_ok(faults + ["an unrelated corner"]))
  @sf.set_dark(None)
}
