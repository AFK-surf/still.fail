// The chat's retained parts keep the surrounding page's ground and the native input's spacing.

///|
test "the visible words of a message are reachable by a scripted long press" {
  let t = chat_tester("chat")
  let words = "做完了：列表、跳到最新的按钮"
  let at = t.locate(words)
  assert_false(at.is_empty())
  let tree = @ui.view_tree().unwrap()
  let targets = at.map(fn(p) { match tree.target_at(p.0, p.1) {
    Pressed(id) => "pressed \{tree.view_of(id).unwrap().rect()}"
    Dragged(id) => "dragged \{tree.view_of(id).unwrap().rect()}"
    Hosted(id) => "hosted \{tree.view_of(id).unwrap().rect()}"
    TopRow(_) => "window"
    Off(id) => "off \{tree.view_of(id).unwrap().rect()}"
    Nothing => "nothing"
  } })
  assert_false(t.reachable(words).is_empty(), msg="visible words \{at}; targets \{targets}")
}

///|
test "a medium chat's header shares its page's ground while behind the sidebar and when brought over" {
  let t = tape_chat(2, 740.0, 844.0)
  let grounds = fn() raise {
    let boxes = t.boxes_held()
    let bar = boxes.iter().find_first(fn(b) {
      b.x > 40.0 && b.w > 400.0 && b.h >= 40.0 && b.h <= 80.0 && (b.bg & 0xFFL) == 0xFFL
    }).unwrap()
    let page = boxes.iter().find_first(fn(b) {
      b.x > 40.0 && b.w > 400.0 && b.h > 700.0 && (b.bg & 0xFFL) == 0xFFL
    }).unwrap()
    let drawn = t.drawn_instances()
    let header = drawn.iter().find_first(fn(b) {
      b[0] == bar.x && b[1] == bar.y && b[2] == bar.w && b[3] == bar.h && b[11] == 1.0
    }).unwrap()
    let dots = drawn.filter(fn(b) {
      b[0] > bar.x && b[1] < bar.y + bar.h && b[2] == 10.0 && b[3] == 10.0 && b[6] == 2.0
    })
    assert_false(dots.is_empty(), msg="the station's connection mark is in the header")
    for dot in dots {
      assert_eq(Array::makei(4, fn(i) { dot[i + 12] }), Array::makei(4, fn(i) { header[i + 8] }),
        msg="the connection mark's edge follows the panel's ground")
    }
    (bar.bg, page.bg)
  }
  let behind = grounds()
  assert_eq(behind.0, behind.1, msg="the header belongs to the panel behind")
  page_over(t, 740.0)
  let over = grounds()
  assert_eq(over.0, over.1, msg="the header belongs to the panel in use")
  assert_true(over.0 != behind.0, msg="bringing the page over restores its ground")
}

///|
test "a message's header keeps the native input's spacing above its body, also while hovered" {
  for platform in [0, 2] {
    let t = wide_tester([], mode="chat", w=1280.0, h=844.0, platform~)
    t.run_for(@ui.move_most_ms)
    let body = t.words().iter().find_first(fn(w) { w.0.has_prefix("做完了：") && w.5 > 0.99 }).unwrap()
    let name = t.words().filter(fn(w) { w.0 == "Claude" && w.2 < body.2 && w.5 > 0.99 }).last().unwrap()
    // The name is centred in the 24-point header. Mouse actions use the room before the header;
    // a finger's header leaves four points before the body, as the original message does.
    let expected = (24.0 + name.4) / 2.0 + (if platform == 0 { 0.0 } else { 4.0 })
    assert_true((body.2 - name.2 - expected).abs() < 0.001,
      msg="platform \{platform}: header \{name}, body \{body}")
    t.move(body.1 + 12.0, body.2 + 10.0)
    t.run_for(@ui.move_most_ms)
    let hovered = t.words().iter().find_first(fn(w) { w.0.has_prefix("做完了：") && w.5 > 0.99 }).unwrap()
    assert_eq(hovered.2, body.2, msg="hovering only reveals the header's actions")
  }
}

///|
test "a login card fits a narrow message column without widening its slot" {
  let t = chat_tester("chat")
  let title = t.rect_of("在 Willow 上登录 gh").unwrap()
  let cards = t.boxes_held().filter(fn(b) {
    b.radius >= 18.0 && b.h > 50.0 && b.h < 300.0 && b.bg != 0L &&
    b.x <= title.0 && b.y <= title.1 && b.x + b.w >= title.0 + title.2 && b.y + b.h >= title.1 + title.3
  })
  assert_true(!cards.is_empty(), msg="the login card is drawn")
  for card in cards {
    assert_true(card.x >= 16.0 && card.x + card.w <= 374.000001,
      msg="the card stays in the message column: \{(card.x, card.y, card.w, card.h)}")
  }
}
