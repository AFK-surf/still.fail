// The paths walked every day, on every screen and at both sizes of words (the owner, 2026-11-12: 「两条都加」, after
// 0.1.8569 stopped on a foldable opened, 中屏 with touch, as a new chat's long first words were sent: #5736, a cell no
// test had walked): a new chat's first words sent, short and long; words sent in a chat; the chat's side opened and
// closed (中屏 and 大屏 its panel, 小屏 对话信息 and back); the window made shorter and given back (a soft keyboard up and
// down with touch, the window resized with a pointer). Each on 小屏 with touch (390 by 844), 中屏 with touch (864 by
// 954) and 大屏 with a pointer (1280 by 800), the system's words at 1 and at 1.3, the core answering a round trip
// later as a phone's does. Each comes to where it goes (the chat on top, the field emptied, the panel open, the send
// button over the keyboard), the Tester's own checks holding every frame on the way: no height under 0 (#5736's
// halt), how what moves goes (words_over, rows_steady, sizes_steady, gaps_steady, each file's bar).

///|
/// A screen a cell walks on: its name, the window's size and the input it was started with (`platform`, as @ui's).
priv struct Screen {
  name : String
  w : Double
  h : Double
  platform : Int
}

///|
let daily_small : Screen = { name: "小屏", w: 390.0, h: 844.0, platform: 2 }

///|
let daily_medium : Screen = { name: "中屏", w: 864.0, h: 954.0, platform: 2 }

///|
let daily_large : Screen = { name: "大屏", w: 1280.0, h: 800.0, platform: 0 }

///|
/// The app on `mode`'s made-up workspace in screen `s`, the system's words at `scale`, the core answering 60 ms later:
/// the moment it is at rest.
fn daily_open(mode : String, s : Screen, scale : Double) -> @ui.Tester {
  let src = @sffixture.round_trip(fixture_app(mode), 60.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Whether a button named `label` is on the screen now.
fn daily_has(t : @ui.Tester, label : String) -> Bool {
  t.semantics().iter().any(fn(n) { n.role == Button && n.label == label })
}

///|
/// The send button's box as drawn: (top, bottom).
fn daily_send_at(t : @ui.Tester) -> (Double, Double) raise {
  let send = t.semantics().filter(fn(n) { n.label == @sf.t("web-main.composer.send") })
  guard send.length() == 1 else { fail("\{send.length()} send buttons") }
  let (_, y, _, h) = send[0].rect
  (y, y + h)
}

///|
/// A new chat's first words `words` sent from Home: the chat on top once they have flown, and its field empty.
fn daily_new_chat(s : Screen, scale : Double, words : String) -> Unit raise {
  let t = daily_open("home", s, scale)
  if daily_has(t, "新建对话") {
    t.click(Button, label="新建对话")
  } else {
    // (小屏: the bar's 令, at its middle, as newchat_send_wbtest's new_chat_sent)
    let (_, y) = bar_places_at()
    t.tap(s.w / 2.0, y - 28.0 - 4.0)
  }
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.run_for(@sfbase.flight_desk_ms + new_leave_ms + @sfbase.sent_down_ms)
  assert_true(app.nav.top() is Chat(_), msg="\{s.name} at \{scale}: not the chat")
  let (_, field, _, _) = t.ime()
  assert_eq(field, "")
}

///|
/// Words sent in a chat: its field empty once they have flown, and they are seen.
fn daily_chat_send(s : Screen, scale : Double) -> Unit raise {
  let t = daily_open("chat", s, scale)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  let words = "看下进度"
  t.type_text(words)
  t.draw()
  tap_send(t)
  t.run_for(@sfbase.flight_ms + @sfbase.sent_down_ms)
  let (_, field, _, _) = t.ime()
  assert_eq(field, "", msg="\{s.name} at \{scale}")
  assert_true(t.find(words) is Some(_), msg="\{s.name} at \{scale}: 「\{words}」 not seen")
}

///|
/// The chat's side opened and closed: on 中屏 and 大屏 its panel (打开侧栏, then 收起侧栏), on 小屏 对话信息 and back.
fn daily_side(s : Screen, scale : Double) -> Unit raise {
  let t = daily_open("chat", s, scale)
  if daily_has(t, "打开侧栏") {
    t.click(Button, label="打开侧栏")
    t.run_for(@ui.move_most_ms)
    assert_true(daily_has(t, "收起侧栏"), msg="\{s.name} at \{scale}: the panel not open")
    t.click(Button, label="收起侧栏")
    t.run_for(@ui.move_most_ms)
    assert_true(daily_has(t, "打开侧栏"), msg="\{s.name} at \{scale}: the panel not closed")
  } else {
    t.click(Button, label="对话信息")
    t.run_for(@ui.move_most_ms)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_true(daily_has(t, "对话信息"), msg="\{s.name} at \{scale}: not back in the chat")
  }
  assert_true(app.nav.top() is Chat(_))
}

///|
/// The window made shorter and given back while the chat's field has the focus: with touch a soft keyboard up and down
/// (said from the window's foot, the window laid out above it, as Android's host does), with a pointer the window
/// resized; the send button whole in the window each time.
fn daily_shorter(s : Screen, scale : Double) -> Unit raise {
  let t = daily_open("chat", s, scale)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  let kb = 300.0
  if s.platform == 0 {
    t.resize(s.w, s.h - kb)
  } else {
    t.set_ime_inset(kb)
    t.resize(s.w, s.h - kb)
  }
  t.run_for(@ui.move_most_ms)
  let (_, bottom) = daily_send_at(t)
  assert_true(bottom <= s.h - kb + 0.5, msg="\{s.name} at \{scale}: send's foot at \{bottom}, the window's at \{s.h - kb}")
  if s.platform != 0 {
    t.set_ime_inset(0.0)
  }
  t.resize(s.w, s.h)
  t.run_for(@ui.move_most_ms)
  let (_, bottom) = daily_send_at(t)
  assert_true(bottom <= s.h + 0.5, msg="\{s.name} at \{scale}: send's foot at \{bottom} after")
}

///|
let daily_short : String = "把发布说明写一下"

///|
let daily_long : String = "把发布说明写一下，" +
  "先列出这次改了什么、为什么改、谁会注意到，再按页面分组，每组写清楚旧的和新的样子。".repeat(6)

///|
test "daily: new chat, short words, 小屏, 1" {
  daily_new_chat(daily_small, 1.0, daily_short)
}

///|
test "daily: new chat, short words, 小屏, 1.3" {
  daily_new_chat(daily_small, 1.3, daily_short)
}

///|
test "daily: new chat, short words, 中屏, 1" {
  daily_new_chat(daily_medium, 1.0, daily_short)
}

///|
test "daily: new chat, short words, 中屏, 1.3" {
  daily_new_chat(daily_medium, 1.3, daily_short)
}

///|
test "daily: new chat, short words, 大屏, 1" {
  daily_new_chat(daily_large, 1.0, daily_short)
}

///|
test "daily: new chat, short words, 大屏, 1.3" {
  daily_new_chat(daily_large, 1.3, daily_short)
}

///|
test "daily: new chat, long words, 小屏, 1" {
  daily_new_chat(daily_small, 1.0, daily_long)
}

///|
test "daily: new chat, long words, 小屏, 1.3" {
  daily_new_chat(daily_small, 1.3, daily_long)
}

///|
test "daily: new chat, long words, 中屏, 1" {
  daily_new_chat(daily_medium, 1.0, daily_long)
}

///|
test "daily: new chat, long words, 中屏, 1.3" {
  daily_new_chat(daily_medium, 1.3, daily_long)
}

///|
test "daily: new chat, long words, 大屏, 1" {
  daily_new_chat(daily_large, 1.0, daily_long)
}

///|
test "daily: new chat, long words, 大屏, 1.3" {
  daily_new_chat(daily_large, 1.3, daily_long)
}

///|
test "daily: send in a chat, 小屏, 1" {
  daily_chat_send(daily_small, 1.0)
}

///|
test "daily: send in a chat, 小屏, 1.3" {
  daily_chat_send(daily_small, 1.3)
}

///|
test "daily: send in a chat, 中屏, 1" {
  daily_chat_send(daily_medium, 1.0)
}

///|
test "daily: send in a chat, 中屏, 1.3" {
  daily_chat_send(daily_medium, 1.3)
}

///|
test "daily: send in a chat, 大屏, 1" {
  daily_chat_send(daily_large, 1.0)
}

///|
test "daily: send in a chat, 大屏, 1.3" {
  daily_chat_send(daily_large, 1.3)
}

///|
test "daily: the chat's side, 小屏, 1" {
  daily_side(daily_small, 1.0)
}

///|
test "daily: the chat's side, 小屏, 1.3" {
  daily_side(daily_small, 1.3)
}

///|
test "daily: the chat's side, 中屏, 1" {
  daily_side(daily_medium, 1.0)
}

///|
test "daily: the chat's side, 中屏, 1.3" {
  daily_side(daily_medium, 1.3)
}

///|
test "daily: the chat's side, 大屏, 1" {
  daily_side(daily_large, 1.0)
}

///|
test "daily: the chat's side, 大屏, 1.3" {
  daily_side(daily_large, 1.3)
}

///|
test "daily: the window shorter and back, 小屏, 1" {
  daily_shorter(daily_small, 1.0)
}

///|
test "daily: the window shorter and back, 小屏, 1.3" {
  daily_shorter(daily_small, 1.3)
}

///|
test "daily: the window shorter and back, 中屏, 1" {
  daily_shorter(daily_medium, 1.0)
}

///|
test "daily: the window shorter and back, 中屏, 1.3" {
  daily_shorter(daily_medium, 1.3)
}

///|
test "daily: the window shorter and back, 大屏, 1" {
  daily_shorter(daily_large, 1.0)
}

///|
test "daily: the window shorter and back, 大屏, 1.3" {
  daily_shorter(daily_large, 1.3)
}
