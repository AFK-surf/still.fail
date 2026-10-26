///|
test "wide: the rail's 对话, Profile and 用量 places, the pointer resting on each, say what they are about at a glance: figures first, what they are made of, the last 7 days" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  rail_card_shown(t, "对话", ["3 个对话正在运行", "等你处理", "出错", "未读", "今天归档"])
  rail_card_shown(t, "Profile", [
    "1 个账号额度用完了", "额度充足", "快用完", "已用完", "用 6 个 Claude 订阅账号消耗了 489% 的周额度", "claude-3 的额度 2 小时后刷新",
  ])
  rail_card_shown(t, "用量", ["近 7 天折合 $1,911", "$362", "输入 token", "Opus 5.5", "$1,207 · 63%", "10/20", "10/26"])
}

///|
/// The card over the rail's place `label` as the pointer rests on it: each of `words` in it, nothing of it against the
/// corners' rule or too faint; gone once the pointer has left.
fn rail_card_shown(t : @ui.Tester, label : String, words : Array[String]) -> Unit raise {
  let place = t.query(Button, label~).unwrap()
  let (x, y, w, h) = place.rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  for s in words {
    assert_true(t.find(s) is Some(_), msg=label + ": " + s)
  }
  assert_eq(t.corner_faults(), [])
  assert_eq(t.contrast_faults(), [])
  assert_eq(t.squeeze_faults(), [])
  t.move(x + w + 600.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  assert_true(t.find(words[0]) is None, msg=label + ": its card gone")
}
