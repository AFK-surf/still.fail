///|
fn check_clean_card(view : (@ui.Ctx) -> Unit, alignment : Bool, alternate : Bool) -> Unit raise {
  let started = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if !started.val {
      @sf.set_dark(Some(true))
      started.val = true
    }
    view(c)
  }, w=clean_canvas_width, h=clean_canvas_height, corners_held=false)
  let boxes = t.boxes()
  let ground = @sf.theme().p.card
  let cards = boxes.filter(fn(b) { b.bg == ground && (b.w - clean_card_width).abs() < 0.001 })
  assert_eq(cards.length(), 1)
  let card = cards[0]
  assert_true((card.x + card.w / 2.0 - clean_canvas_width / 2.0).abs() < 0.001)
  assert_true((card.y + card.h / 2.0 - clean_canvas_height / 2.0).abs() < 0.001)
  // No explanatory text is placed outside the actual card.
  for word in boxes.filter(fn(b) { b.text != "" }) {
    assert_true(
      word.x >= card.x && word.y >= card.y && word.x + word.w <= card.x + card.w && word.y + word.h <= card.y + card.h,
      msg="unexpected words outside the card: \{word.text}",
    )
  }
  let faults = t.corner_faults()
  if alignment && !alternate {
    assert_true(alignment_corner_faults_ok(faults), msg=faults.join("\n"))
  } else {
    assert_true(faults.is_empty(), msg=faults.join("\n"))
  }
  if alignment {
    let (title_x, _, _, _) = t.rect_of("Quota check failed").unwrap()
    let (label_x, _, _, _) = t.rect_of("Try again").unwrap()
    let button = t.drawn_rects().iter().find_first(fn(r) { (r.3 - @sf.button_height()).abs() < 0.01 }).unwrap()
    if alternate {
      assert_true((title_x - label_x).abs() < 0.01)
      assert_true(button.0 < title_x)
    } else {
      assert_true((title_x - button.0).abs() < 0.01)
      assert_true(label_x > title_x)
    }
  } else {
    let first = boxes.iter().find_first(fn(b) { b.text == "Use password manager" }).unwrap()
    let last = boxes.iter().find_first(fn(b) { b.text == "Save to vault" }).unwrap()
    if alternate { assert_true(last.y < first.y) } else { assert_true(last.y > first.y) }
  }
  @sf.set_dark(None)
}

///|
test "clean graphics contain one centered card with the requested layout" {
  check_clean_card(fn(c) { wrap_card_figure(c, false) }, false, false)
  check_clean_card(fn(c) { wrap_card_figure(c, true) }, false, true)
  check_clean_card(fn(c) { alignment_card_figure(c, false) }, true, false)
  check_clean_card(fn(c) { alignment_card_figure(c, true) }, true, true)
}
