///|
test "wide: the rail's 对话 and 用量 places, the pointer resting on each, say what they are about at a glance: figures first, what they are made of, the last 7 days, 分享卡片 on 用量's; Station and Profile only their tip" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  rail_card_shown(t, "对话", ["3 个对话正在运行", "等你处理", "出错", "未读", "今天归档"])
  rail_card_shown(t, "用量", ["近 7 天折合 $1,911", "$362", "输入 token", "Opus 5.5", "$1,207 · 63%", "10/20", "10/26", "分享卡片"])
  // (2026-10-26 用户「stations 和 profiles tab 的 hover 卡片去掉吧」)
  for label in ["Station：" + @sfdesk.rail_stations_label(fixture("home"), "ws1"), "Profile"] {
    let place = t.query(Button, label~).unwrap()
    let (x, y, w, h) = place.rect
    t.move_to(x + w / 2.0, y + h / 2.0)
    t.run_for(@sfpages.hover_open_ms * 2.0)
    assert_true(t.find("分享卡片") is None, msg=label)
    assert_true(t.query(Button, label="分享卡片") is None, msg=label)
    t.move_to(x + w + 600.0, y + h / 2.0)
    t.run_for(@sfpages.hover_open_ms * 2.0)
  }
}

///|
test "wide: a figure of 对话's card pressed opens the chats it counts (2026-11-10 用户「这里面不能点击跳转，光告诉我有几个没用啊」): 等你处理, 出错, 未读 待处理's panel, 今天归档 the archive; the card gone" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.host_says_finger(Some(false))
  for figure in ["等你处理 2", "出错 1", "未读 4"] {
    rail_card_figure_pressed(t, figure)
    assert_true(@sfdesk.wide.attention_open.get(), msg=figure)
    assert_true(t.find("3 个对话正在运行") is None, msg=figure + ": its card gone")
    t.key_told(@ui.key_escape, 0, t.time())
    t.draw()
    assert_true(!@sfdesk.wide.attention_open.get(), msg=figure)
  }
  rail_card_figure_pressed(t, "今天归档 8")
  assert_eq(@sfdesk.side_place(), "archive")
  assert_true(t.find("3 个对话正在运行") is None, msg="今天归档: its card gone")
}

///|
/// 对话's card opened as the pointer rests on its place, its figure `figure` (as a screen reader names it) pointed at,
/// nothing of it against the corners' rule, then pressed.
fn rail_card_figure_pressed(t : @ui.Tester, figure : String) -> Unit raise {
  let (x, y, w, h) = t.query(Button, label="对话").unwrap().rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  let (fx, fy, fw, fh) = t.query(Button, label=figure).unwrap().rect
  t.move_to(fx + fw / 2.0, fy + fh / 2.0)
  t.draw()
  // (its ground lit under the pointer, in the card's corner: concentric with it)
  assert_eq(t.corner_faults(), [], msg=figure)
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.draw()
}

///|
/// The card over the rail's place `label` as the pointer rests on it: each of `words` in it, nothing of it against the
/// corners' rule or too faint; gone once the pointer has left.
fn rail_card_shown(t : @ui.Tester, label : String, words : Array[String]) -> Unit raise {
  let place = t.query(Button, label~).unwrap()
  let (x, y, w, h) = place.rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  for s in words {
    assert_true(t.find(s) is Some(_), msg=label + ": " + s)
  }
  assert_eq(t.corner_faults(), [])
  assert_eq(t.contrast_faults(), [])
  assert_eq(t.squeeze_faults(), [])
  t.move_to(x + w + 600.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find(words[0]) is None, msg=label + ": its card gone")
}

///|
test "wide: a mouse's pointer over a rail card's ground is the arrow, over 分享卡片 the hand (@sf.ground_node)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let place = t.query(Button, label="用量").unwrap()
  let (x, y, w, h) = place.rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find("分享卡片") is Some(_), msg="its card")
  let shape_on = fn(px : Double, py : Double) {
    t.move_to(px, py)
    t.run_for(@ui.move_most_ms)
    t.cursor()
  }
  // (the card beside its place, at its right, its top level with it, 6 off, 320 wide: sfdesk's rail_card_off,
  // rail_card_w; points 3 in from its left, its top, its right)
  let left = x + w + 6.0
  let points = [(left + 3.0, y + 20.0), (left + 160.0, y + 3.0), (left + 317.0, y + 20.0)]
  let grounds = points.map(fn(p) { shape_on(p.0, p.1) })
  assert_eq(grounds, [Arrow, Arrow, Arrow], msg="its ground at \{Repr(points)}")
  let (sx, sy, sw, sh) = t.get(Button, label="分享卡片").rect
  assert_eq(shape_on(sx + sw / 2.0, sy + sh / 2.0), Hand, msg="分享卡片")
  assert_eq(t.corner_faults(), [], msg="分享卡片 lit in the card's foot corners")
}
