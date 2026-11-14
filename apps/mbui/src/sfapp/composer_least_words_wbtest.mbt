// A chat's composer opened with one line and let go of, the system's words larger (1.3) and as they are (1.0): the
// chat's messages stay where they are (composer_room keeps it at least as tall as it takes opened with one line,
// composer_least, worked out of the line its field is laid out on). Main's (b805f72e7d) worked that out of the theme's
// line (22), its field's drawn at the system's size of words (25 at 1.3): let go of, the room under the list 3 less
// than opened, every row of it 3 lower.

///|
/// Whether draft "ws1/st1:s-c1"'s composer has the keyboard (its field's: Field::focused).
fn least_words_focused() -> Bool {
  match @sfbase.writings.get("ws1/st1:s-c1") {
    Some(w) => w.field.focused()
    None => false
  }
}

///|
/// The chat open in a window `w` by `h` on `platform` (2 a finger's, else keyboard and mouse), the system's words
/// `scale`, its composer opened with one line and let go of: where the words of a message of it stand opened, on the
/// way to its capsule and there, each the same.
fn least_words_walk(w : Double, h : Double, platform : Int, scale : Double) -> Unit raise {
  // (made as the window's tree is first made, its fake host in place: what the app's state and shell are made of)
  let src : Ref[Source?] = Ref(None)
  let made = fn() {
    match src.val {
      Some(s) => s
      None => {
        new_run()
        let s = fixture("chat")
        open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(fn(c) { view(c, made()) }, tree=fn(root) { app_tree(made())(root) }, w~, h~, platform~)
  t.set_font_scale(scale)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let at = "\{w}x\{h} platform \{platform}, words \{scale}"
  let finger = platform == 2
  // (keyboard and mouse: it opens with the cursor in it; let go of, as a click elsewhere in the window lets it go)
  if !finger {
    t.ctx().blur()
    t.draw()
    t.run_for(@sfpages.let_go_ms + @sfpages.composer_shape_ms)
  }
  assert_true(!least_words_focused(), msg="\{at}: a capsule as it starts")
  // opened: its field pressed (a finger's), Space (keyboard and mouse: 按空格输入)
  if finger {
    let field = t.semantics().filter(fn(s) { s.role == TextField })[0]
    t.tap_text(field.label)
  } else {
    t.key(@ui.key_space)
  }
  assert_true(least_words_focused(), msg="\{at}: opened")
  t.run_for(@sfpages.composer_shape_ms)
  let words = "做完了：列表、跳到最新的按钮"
  let opened = t.find(words).unwrap().1
  // let go of: the keyboard gone (a finger's), a click elsewhere (keyboard and mouse)
  if finger {
    t.keyboard_gone()
  } else {
    t.ctx().blur()
    t.draw()
  }
  assert_true(!least_words_focused(), msg="\{at}: let go of")
  // (a box a moment longer, let_go_ms, then on its way to its capsule, composer_shape_ms: a quarter, half, all of it)
  t.run_for(@sfpages.let_go_ms)
  let mut was = 0.0
  for k in [0.25, 0.5, 1.0] {
    t.run_for(@sfpages.composer_shape_ms * k - was)
    was = @sfpages.composer_shape_ms * k
    let y = t.find(words).unwrap().1
    assert_eq(y, opened, msg="\{at}: its message where it was opened (\{opened}), \{k} of the way to its capsule: \{y}")
  }
}

///|
test "小屏, a finger's: the composer opened with one line and let go of moves none of the chat's messages, the system's words 1 and 1.3" {
  for scale in [1.0, 1.3] {
    least_words_walk(390.0, 844.0, 2, scale)
  }
}

///|
test "中屏, a window with keyboard and mouse: the composer opened with one line and let go of moves none of the chat's messages, the system's words 1 and 1.3" {
  for scale in [1.0, 1.3] {
    least_words_walk(600.0, 760.0, 0, scale)
  }
}

///|
/// The chat open on 小屏 with a finger (390x844), the system's words `scale`, its composer pressed and "第一行" typed in
/// it, at rest (send_hold_wbtest's hold_chat: words the core's answers are kept for).
fn least_words_small(scale : Double) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_font_scale(scale)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("第一行")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// How tall the composer's field is laid out (its words' room).
fn least_words_field_h(t : @ui.Tester) -> Double {
  t.semantics().filter(fn(s) { s.role == TextField })[0].rect.3
}

///|
/// Words of three lines sent from the composer hold it as tall as they took in it (composer_held_lines), its field's
/// lines as it lays them out at the system's size of words: main's held it at the theme's line (24.75 a finger's, laid
/// out 26.85 at 1.3), the box 6.3 shorter at the press, its room with it.
test "小屏, a finger's: words of three lines sent hold the composer as tall as they took in it till they let go of it, the system's words 1 and 1.3" {
  let draft = "ws1/st1:s-c1"
  for scale in [1.0, 1.3] {
    let t = least_words_small(scale)
    t.type_text("\n第二行\n第三行")
    t.run_for(@ui.move_most_ms)
    let room = @sfpages.composer_room(t.ctx(), draft)
    let box = @motion.measured(t.ctx(), "composer/content")
    tap_send(t)
    let press = t.time()
    let go = match @sfbase.flight_lets_go(draft) {
      Some((go, _)) => go
      None => @halt.saying("words \{scale}: what holds the composer not said at the press")
    }
    assert_true(go > press, msg="words \{scale}: let go of at \{go}, pressed at \{press}")
    // (at the press, and half way from it to their letting go of it)
    for k in [0.0, 0.5] {
      t.run_for(press + (go - press) * k - t.time())
      let at = "words \{scale}, \{k} of the way to their letting go of it"
      let now_box = @motion.measured(t.ctx(), "composer/content")
      let now_room = @sfpages.composer_room(t.ctx(), draft)
      assert_eq(now_box, box, msg="\{at}: its box \{Repr(now_box)}, \{Repr(box)} before the press")
      assert_eq(now_room, room, msg="\{at}: its room \{now_room}, \{room} before the press")
    }
  }
}

///|
/// The field grows to as many lines as are as tall as text_most (480) or text_window_share (0.4) of the window at
/// most, whichever is less, its words past them scrolled to: main's counted its lines by the theme's line, at 1.3 on
/// a 390x844 phone 13 lines of 26.85, 349.05 where it may be 337.6.
test "小屏, a finger's: more lines typed than it shows, the field grows to a line short of its most and no taller, the system's words 1 and 1.3" {
  let most = if 480.0 < 844.0 * 0.4 { 480.0 } else { 844.0 * 0.4 }
  for scale in [1.0, 1.3] {
    let t = least_words_small(scale)
    // (send_hold_wbtest's lines more than the field shows: words the core's answers are kept for)
    t.type_text("\n" + Array::makei(12, fn(i) { "第\{i + 2}行，一句话写得长一些，让它折成两行再往下" }).join("\n"))
    t.run_for(@sfpages.composer_shape_ms + @ui.move_most_ms)
    let h = least_words_field_h(t)
    assert_true(h <= most, msg="words \{scale}: the field \{h} tall, at most \{most}")
    // (grown as far as a line short of it: a line more would pass it)
    let line = least_words_field_h(least_words_small(scale))
    assert_true(h + line > most, msg="words \{scale}: the field \{h} tall, a line \{line}, at most \{most}")
  }
}
