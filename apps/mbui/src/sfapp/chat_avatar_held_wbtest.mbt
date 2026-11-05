// A long message keeps its author's picture by the top of the chat while the message scrolls past it.

///|
test "a long message's avatar stays below the chat bar as its head scrolls out on a large screen" {
  let t = kept_rows_open("chat-long", 1280.0, 800.0)
  // The latest long message's head is above the viewport, but its last words are still in view.
  let last = t.shown_of("有问题随时说")
  assert_true(last is Some((_, _, _, h)) && h > 0.0, msg="the end of the long message is visible: \{last}")
  let head = t.shown_of("列表改成虚拟列表")
  assert_true(head is None || head is Some((_, _, _, h)) && h == 0.0, msg="the long message's head has scrolled away: \{head}")
  let names = t.words().filter(fn(w) { w.0 == "Claude" && w.2 > 80.0 && w.2 < 700.0 })
  assert_false(names.is_empty(), msg="another agent's name gives the message column's position")
  let avatar_x = names[0].1 - 29.0
  let faces = t.drawn_rects().filter(fn(r) {
    r.0 >= avatar_x - 0.5 && r.0 <= avatar_x + 0.5 && r.2 == 18.0 && r.3 == 18.0
  })
  // The old page held the picture's room 53 below the list's top; the picture itself is 3 lower.
  assert_true(faces.iter().any(fn(r) { r.1 >= 55.5 && r.1 <= 56.5 }),
    msg="the long message's avatar is held below the bar; faces at \{faces}")
}

///|
test "the held avatar still opens its agent's card below the picture" {
  let t = kept_rows_open("chat-long", 1280.0, 800.0)
  let names = t.words().filter(fn(w) { w.0 == "Claude" && w.2 > 80.0 && w.2 < 700.0 })
  assert_false(names.is_empty())
  let x = names[0].1 - 29.0
  t.move(x + 9.0, 65.0)
  t.frame()
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t.frame()
  // A small panel's shadow is drawn 12 points below the panel. The card starts 6 under the 18-point picture.
  let cards = t.drawn_cut().filter(fn(d) {
    d.0 == 2 && (d.1 - x).abs() < 1.0 && d.3 >= 200.0 && d.3 <= 420.0 && d.4 < 200.0
  })
  assert_false(cards.is_empty(), msg="the held picture opens its agent's card: \{cards}")
  assert_true((cards[0].2 - 12.0 - (56.0 + 18.0 + 6.0)).abs() < 1.0,
    msg="the card is under the held picture: \{cards}")
}
