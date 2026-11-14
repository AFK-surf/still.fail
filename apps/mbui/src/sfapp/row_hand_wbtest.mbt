// A finger's row in the chats' list as the hand has it: swiped across, what it uncovers (归档 on its ground); held for
// its menu, lifted over the menu's scrim (chat_row_node's, as chat_row's was).

///|
/// The plain rects drawn in the last frame across the band of the row at `y` (its middle), and where each was drawn in
/// the frame's order.
fn row_band_rects(t : @ui.Tester, y : Double) -> Array[(Int, (Double, Double, Double, Double, Int64))] {
  let out = []
  let order = t.drawn_order()
  let rects = t.drawn_rects()
  let mut j = 0
  for k, o in order {
    if o.0 == 0 {
      let r = rects[j]
      j += 1
      if r.1 < y && r.1 + r.3 > y && r.3 < 120.0 {
        out.push((k, r))
      }
    }
  }
  out
}

///|
test "a row swiped left a little: what it uncovers past its end on the chip's ground, 归档 on it, as far as it has gone" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, y) = t.find("首页的列表改成按天分组").unwrap()
  // across 60, short of the line letting go archives at, the finger still down
  t.hold_drag(300.0, y, 240.0, y)
  let chip = @sf.theme().p.chip
  let under = row_band_rects(t, y).filter(fn(e) { (e.1).4 == chip })
  assert_true(
    under.iter().any(fn(e) { (e.1).0 <= 390.0 - 60.0 + 1.0 && (e.1).0 >= 390.0 - 60.0 - 1.0 && (e.1).0 + (e.1).2 >= 390.0 }),
    msg="the chip's ground from where the row ends to the window's: \{Repr(row_band_rects(t, y))}",
  )
  let (wx, _) = t.find("归档").unwrap()
  assert_true(wx > 390.0 - 60.0 && wx < 390.0, msg="归档 where the row has uncovered: \{wx}")
  t.release(240.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 0)
}

///|
test "a row swiped left less than 归档 is wide: of 归档 only what the row has uncovered shows, none over the row" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, y) = t.find("首页的列表改成按天分组").unwrap()
  // across 20, less than 归档 and the room at its end take
  t.hold_drag(300.0, y, 280.0, y)
  // (归档's glyphs: at the slot's end across its middle, where the row's own words are not; what of each shows, cut as
  // it is drawn)
  let (_, wy) = t.find("归档").unwrap()
  let words = t
    .glyph_clips()
    .filter(fn(e) { (e.0.0 + e.0.2) / 2.0 > 320.0 && e.0.1 < wy && e.0.3 > wy })
  assert_true(
    words.iter().all(fn(e) { dmin(e.0.2, e.1.2) <= dmax(e.0.0, e.1.0) || dmax(e.0.0, e.1.0) >= 390.0 - 20.0 - 0.5 }),
    msg="of 归档 only what is past where the row ends shows: \{Repr(words)}",
  )
  t.release(280.0, y)
  t.run_for(@ui.move_most_ms)
}

///|
test "a row swiped left past the line letting go archives at: what it uncovers in ink" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, y) = t.find("首页的列表改成按天分组").unwrap()
  t.hold_drag(340.0, y, 140.0, y)
  t.run_for(@ui.move_most_ms)
  let ink = @sf.theme().p.text
  assert_true(
    row_band_rects(t, y).iter().any(fn(e) { (e.1).4 == ink && (e.1).0 + (e.1).2 >= 390.0 && (e.1).0 <= 390.0 - 199.0 }),
    msg="the ink's ground past the row's end: \{Repr(row_band_rects(t, y))}",
  )
  t.release(140.0, y)
}

///|
test "a row held for its menu: lifted over the menu's scrim, a card of the raised ground drawn in from the sides, its shadow under it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, y) = t.find("盯着 CI，绿了告诉我").unwrap()
  hold_row(t, "盯着 CI，绿了告诉我")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("重命名") is Some(_), msg="its menu up")
  let order = t.drawn_order()
  // (the scrim: the whole window's)
  let mut scrim : Int? = None
  for k, o in order {
    if o.0 == 0 && o.3 >= 390.0 && o.4 >= 844.0 && o.1 <= 0.0 && o.2 <= 0.0 {
      scrim = Some(k)
    }
  }
  let raised = @sf.theme().p.raised
  let cards = row_band_rects(t, y).filter(fn(e) { (e.1).4 == raised && (e.1).2 > 300.0 })
  assert_true(cards.length() == 1, msg="one card of the raised ground: \{Repr(row_band_rects(t, y))}")
  let (k, (cx, _, cw, _, _)) = cards[0]
  // drawn in from the screen's sides
  assert_true(cx > 1.0 && cx + cw < 389.0, msg="drawn in: \{cx} \{cw}")
  match scrim {
    Some(s) => assert_true(k > s, msg="the card \{k} over the scrim \{s}")
    None => fail("no scrim drawn")
  }
  // its shadow under it
  assert_true(t.drawn_shadows().iter().any(fn(s) { s.1 < y && s.1 + s.3 > y && s.2 > 300.0 }), msg="its shadow")
  // its menu gone, it is let down: no card left
  t.tap(200.0, 60.0)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(row_band_rects(t, y).iter().all(fn(e) { (e.1).4 != raised }), msg="let down")
}

///|
test "a row low in the list held for its menu: lifted clear of the sheet its menu is in" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  let (_, y) = t.find("把旧的截图都换成新的").unwrap()
  hold_row(t, "把旧的截图都换成新的")
  t.run_for(@ui.move_most_ms)
  let (_, menu_y, _, _) = t.rect_of("重命名").unwrap()
  assert_true(y > menu_y - 40.0, msg="the row where the sheet comes up: \{y} against \{menu_y}")
  let raised = @sf.theme().p.raised
  let cards = t.drawn_rects().filter(fn(r) { r.4 == raised && r.2 > 300.0 && r.3 < 120.0 })
  assert_true(cards.length() == 1, msg="its card: \{Repr(cards)}")
  let (_, cy, _, ch, _) = cards[0]
  assert_true(cy + ch + 12.0 <= menu_y, msg="clear of the sheet: card \{cy}+\{ch}, its menu at \{menu_y}")
}
