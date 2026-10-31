// 待处理's panel on 大屏 (sfdesk's attention.mbt, a popover by the rail's bell) dismissed by the hand: Escape, a press
// on the page: closed as that input is taken, at its moment, no frame after it; the frame after closing nothing more,
// opened again from the bell its own.

///|
/// 大屏, a mouse's: 待处理's panel opened from the bell, dismissed by `how` (as the host hands it on, no frame after
/// it): whether it is open then, once a frame is drawn, as the bell opens it again and a frame after.
fn attention_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let seen = [@sfdesk.wide.attention_open.get()]
  how(t)
  seen.push(@sfdesk.wide.attention_open.get())
  t.draw()
  seen.push(@sfdesk.wide.attention_open.get())
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  seen.push(@sfdesk.wide.attention_open.get())
  t.draw()
  seen.push(@sfdesk.wide.attention_open.get())
  seen
}

///|
test "大屏: 待处理's panel dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(attention_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: 待处理's panel dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = attention_dismissed(fn(t) {
    t.touch_at(0, 900.0, 600.0, t.time())
    down.push(@sfdesk.wide.attention_open.get())
    t.touch_at(2, 900.0, 600.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: 待处理's panel, the bell pressed again: closed (the bell's own press, not a press outside), the frame after closing nothing more" {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let seen = [@sfdesk.wide.attention_open.get()]
  t.touch_at(0, bx + bw / 2.0, by + bh / 2.0, t.time())
  t.touch_at(2, bx + bw / 2.0, by + bh / 2.0, t.time())
  seen.push(@sfdesk.wide.attention_open.get())
  t.draw()
  seen.push(@sfdesk.wide.attention_open.get())
  assert_eq(seen, [true, false, false])
}

///|
/// 大屏 with the stations' trouble (wide_rail_wbtest's wide_with, chats_in_trouble): 待处理's panel opened from the bell
/// (the trouble listed, kept as seen), closed by `close` (as the host hands it on), a frame drawn after where `frames`,
/// then opened again from the bell and drawn: whether the trouble is listed still, the panel says there is nothing,
/// it was kept as seen as it first opened, and the page under it as it was.
fn trouble_again(close : (@ui.Tester, Double, Double) -> Unit, frames : Bool) -> (Bool, Bool, Bool, Bool) {
  let calls : Array[Made] = []
  let t = wide_with(calls, { "chats": chats_in_trouble() })
  t.host_says_finger(Some(false))
  t.frame()
  let page = (app.nav.depth(), app.nav.top())
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  let (x, y) = (bx + bw / 2.0, by + bh / 2.0)
  t.tap(x, y)
  t.frame()
  let kept = trouble_said(calls, "ws1\nseen") == Some(Json::string("MBA 连不上了")) && t.find("MBA 连不上了") is Some(_)
  close(t, x, y)
  if frames {
    t.frame()
  }
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  t.draw()
  (t.find("MBA 连不上了") is Some(_), t.find("暂无待处理") is Some(_), kept, (app.nav.depth(), app.nav.top()) == page)
}

///|
test "大屏: the stations' trouble looked at in 待处理's panel, the panel closed by Escape and opened again from the bell, a frame between or none: not listed again" {
  let esc = fn(t : @ui.Tester, _x : Double, _y : Double) { t.key_told(@ui.key_escape, 0, t.time()) }
  assert_eq((trouble_again(esc, true), trouble_again(esc, false)), ((false, true, true, true), (false, true, true, true)))
}

///|
test "大屏: the stations' trouble looked at in 待处理's panel, the panel closed by its bell and opened again from it, a frame between or none: not listed again" {
  let bell = fn(t : @ui.Tester, x : Double, y : Double) {
    t.touch_at(0, x, y, t.time())
    t.touch_at(2, x, y, t.time())
  }
  assert_eq((trouble_again(bell, true), trouble_again(bell, false)), ((false, true, true, true), (false, true, true, true)))
}
