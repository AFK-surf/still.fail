// A station retired from its workspace (sfpages station_retire_node.mbt): its ⋯'s 迁走聊天并移出… over 移出 only while
// it may be (the core's `canRetire`), opening a panel of what goes and what stays as the station counts them
// (`copies.retirePreview`), the station to move to chosen in it, then `copies.retire`; as it goes, 迁移 at the top of its
// page, its steps a row each and what may be done now, each press the core's call with what the call needs (the
// settings' fixture refuses one without it); and a station taking retired ones' chats in, a row each.

///|
/// Willow's page in the fixture's `mode` (settings-station-retire…), its calls kept in `calls`, on a phone's screen
/// unless said.
fn retire_tester(calls : Array[Made], mode : String, w? : Double = 390.0, h? : Double = 844.0, platform? : Int = 2) -> @ui.Tester {
  let t = wide_tester(calls, mode~, w~, h~, platform~)
  open_fixture_mode(mode)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Whether words `w` are drawn whole as words of their own.
fn retire_said(t : @ui.Tester, w : String) -> Bool {
  t.words().iter().any(fn(x) { x.0 == w })
}

///|
/// Where words `w` are drawn (their top), drawn as words of their own.
fn retire_y(t : @ui.Tester, w : String) -> Double {
  match t.words().iter().find_first(fn(x) { x.0 == w }) {
    Some(x) => x.2
    None => @halt.saying("no words \"\{w}\": " + t.words().map(fn(x) { x.0 }).join("|"))
  }
}

///|
/// Presses words `w`, drawn as words of their own, and lets what it opens come.
fn retire_press(t : @ui.Tester, w : String) -> Unit {
  match t.words().iter().find_first(fn(x) { x.0 == w }) {
    Some(x) => t.tap(x.1 + x.3 / 2.0, x.2 + x.4 / 2.0)
    None => @halt.saying("no words \"\{w}\" to press: " + t.words().map(fn(x) { x.0 }).join("|"))
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
}

///|
/// The calls of `name` made, their params.
fn retire_calls(calls : Array[Made], name : String) -> Array[Json] {
  calls.filter(fn(m) { m.name == name }).map(fn(m) { m.params })
}

///|
test "迁移 as a station is retired: its steps a row each at the top of its page, the one thing to do now, the core called with the station" {
  let steps = ["传文件", "暂停聊天，补传改动", "Maple 接收聊天", "移账号", "移连接"]
  // (mode, words its rows say besides the steps, what is pressed at its head's end, the call that press makes)
  let states = [
    ("settings-station-retire-sending", ["1.5 GB / 3.2 GB"], ["取消"], "copies.retireCancel"),
    // (all of it sent, the hand-over waiting for its card; back there after a hand-over failed, the chats working again)
    ("settings-station-retire-sent", ["等待确认"], ["取消"], "copies.retireCancel"),
    ("settings-station-retire-sent-failed", ["Maple 放入聊天时出错，聊天已恢复"], ["取消", "重试"], "copies.retireAgain"),
    ("settings-station-retire-quiet", [], ["取消"], "copies.retireCancel"),
    ("settings-station-retire-failed", ["连不上 Maple"], ["取消", "重试"], "copies.retireAgain"),
  ]
  for state in states {
    let (mode, words, buttons, call) = state
    let calls : Array[Made] = []
    let t = retire_tester(calls, mode)
    assert_eq(t.audit(), [], msg=mode)
    for w in ["迁移", "迁到 Maple"] + steps + words {
      assert_true(retire_said(t, w), msg="\{mode}: \{w}: " + t.words().map(fn(x) { x.0 }).join("|"))
    }
    // (at the top: over the parts to pick from; the steps in their order)
    assert_true(retire_y(t, "迁移") < retire_y(t, "概览"), msg=mode)
    for i in 1..<steps.length() {
      assert_true(retire_y(t, steps[i - 1]) < retire_y(t, steps[i]), msg="\{mode}: \{steps[i]}")
    }
    for b in ["取消", "重试", "移出 workspace"] {
      assert_eq(retire_said(t, b), buttons.contains(b), msg="\{mode}: \{b}")
    }
    // (at `sent` the note is 暂停聊天's: under it, over the next row)
    if mode.has_prefix("settings-station-retire-sent") {
      let note = words[0]
      assert_true(retire_y(t, steps[1]) < retire_y(t, note) && retire_y(t, note) < retire_y(t, steps[2]), msg="\{mode}: \{note}")
    }
    assert_true(!retire_said(t, "备份"), msg=mode)
    // (no row of its own for the end: once there every row is done)
    assert_true(!retire_said(t, "完成"), msg=mode)
    // its last action pressed: the core asked of this station, which the fixture takes only so
    retire_press(t, buttons[buttons.length() - 1])
    let asked = retire_calls(calls, call)
    assert_eq(asked.length(), 1, msg=mode)
    assert_eq(text(Some(asked[0]), "station"), "ws1/st1", msg=mode)
    assert_eq(@settings.fixture_retire_asked.map(fn(a) { a.0 }), [call], msg=mode)
  }
  // its accounts moving: nothing to press but what its station says
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-accounts")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "移账号") && !retire_said(t, "重试") && !retire_said(t, "移出 workspace"))
  // a failed one let go of too
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-failed")
  retire_press(t, "取消")
  assert_eq(retire_calls(calls, "copies.retireCancel").map(fn(p) { text(Some(p), "station") }), ["ws1/st1"])
  t.run_for(@ui.move_most_ms)
  assert_true(!retire_said(t, "迁移"), msg=t.words().map(fn(x) { x.0 }).join("|"))
}

///|
test "迁移 once the chats are moved: 移出 workspace, asked as the ⋯'s 移出 is, then the station taken out; the accounts left behind a row of their own" {
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-done")
  assert_eq(t.audit(), [])
  assert_true(!retire_said(t, "取消") && !retire_said(t, "重试"))
  assert_true(!retire_said(t, "2 个账号没移过去"))
  assert_true(retire_said(t, "移连接") && !retire_said(t, "完成"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  retire_press(t, "移出 workspace")
  assert_true(retire_said(t, "移除「Willow」？"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  retire_press(t, "移除 station")
  let asked = retire_calls(calls, "workspace.removeStation")
  assert_eq(asked.length(), 1)
  let p = Some(asked[0])
  assert_eq(text(p, "workspace"), "ws1")
  assert_eq(text(p, "station"), "st1")
  assert_true(text(p, "account") != "")
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-done-left")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "2 个账号没移过去"))
  assert_true(retire_said(t, "cuesurf5@proton.me 和 Kimi Code key：需要在 Maple 上重新添加"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(retire_y(t, "移连接") < retire_y(t, "2 个账号没移过去"))
  assert_true(retire_said(t, "移出 workspace"))
}

///|
test "迁移 on a station taking retired ones' chats in: a row each, nothing to press" {
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-taking")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "迁移"))
  for w in ["从 Old Mac 迁来", "正在重建工作目录", "从 Birch 迁来", "没接收成：出错了，详情在 station 日志里"] {
    assert_true(retire_said(t, w), msg=w + ": " + t.words().map(fn(x) { x.0 }).join("|"))
  }
  assert_true(retire_y(t, "迁移") < retire_y(t, "概览"))
  for b in ["取消", "重试", "移出 workspace"] {
    assert_true(!retire_said(t, b), msg=b)
  }
  // and none on a station neither retired nor taking any in
  let t = retire_tester(calls, "settings-station-retire")
  assert_true(!retire_said(t, "迁移"))
}

///|
test "its ⋯: 迁走聊天并移出… over 移出 only while it may be retired; pressed, its panel once the station said what goes, Maple chosen, then copies.retire to it" {
  // (no copies said by the station, or one being retired already: none)
  for mode in ["settings-station", "settings-station-retire-sending", "settings-station-retire-done"] {
    let calls : Array[Made] = []
    let t = retire_tester(calls, mode)
    t.click(Button, label="更多")
    t.run_for(@ui.move_most_ms)
    assert_true(retire_said(t, "从 workspace 移除"), msg=mode)
    assert_true(!retire_said(t, "迁走聊天并移出…"), msg=mode)
  }
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire")
  t.click(Button, label="更多")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.audit(), [])
  // (directly over 移出)
  assert_true(retire_y(t, "迁走聊天并移出…") < retire_y(t, "从 workspace 移除"))
  retire_press(t, "迁走聊天并移出…")
  // asked of the station what goes, then its panel: Maple the one up, chosen; each kind counted and named
  assert_eq(retire_calls(calls, "copies.retirePreview").map(fn(p) { text(Some(p), "station") }), ["ws1/st1"])
  for w in ["迁走 Willow 的聊天", "迁到", "Maple", "一起迁到 Maple", "聊天", "594 个", "其中 525 个已归档", "连接", "5 个", "账号", "9 个", "无法迁移的", "正在运行的任务和服务", "6 个", "station 外的工作目录", "聊天迁过去，文件留在原处", "3 个", "开始迁移"] {
    assert_true(retire_said(t, w), msg=w + ": " + t.words().map(fn(x) { x.0 }).join("|"))
  }
  // (which they are: three at most, then 等; none cut short, none past two lines)
  let accounts = "cuesurf5@proton.me、lin@example.com、studio-ci@cue.surf 等"
  for w in [accounts, "发布助手 · Slack、飞书助手、Comma 助手 等", "pnpm dev、station tests、preview :5173 等"] {
    assert_true(retire_said(t, w), msg=w + ": " + t.words().map(fn(x) { x.0 }).join("|"))
  }
  assert_eq(t.words().filter(fn(x) { x.0.has_suffix("…") }).map(fn(x) { x.0 }), [])
  let line = t.words().iter().find_first(fn(x) { x.0 == "其中 525 个已归档" }).unwrap().4
  let note = t.words().iter().find_first(fn(x) { x.0 == accounts }).unwrap().4
  assert_true(note <= line * 2.0 + 1.0, msg="its accounts' note \{note} high, a line \{line}")
  assert_eq(t.audit(), [])
  retire_press(t, "开始迁移")
  let asked = retire_calls(calls, "copies.retire")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "station"), "ws1/st1")
  assert_eq(text(Some(asked[0]), "to"), "st2")
  // (taken: the fixture's station says it goes, 迁移 at the top)
  t.run_for(@ui.move_most_ms)
  assert_true(retire_said(t, "1.5 GB / 3.2 GB"))
}

///|
test "its panel with two other stations up: none chosen and 开始迁移 does nothing till one is; with none up, said in its row; a joined workspace's accounts stay" {
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-panel-pick")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "选择 station"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(retire_said(t, "一起迁过去"))
  retire_press(t, "开始迁移")
  assert_eq(retire_calls(calls, "copies.retire").length(), 0)
  retire_press(t, "选择 station")
  retire_press(t, "Cedar")
  assert_true(retire_said(t, "一起迁到 Cedar"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  retire_press(t, "开始迁移")
  assert_eq(retire_calls(calls, "copies.retire").map(fn(p) { (text(Some(p), "station"), text(Some(p), "to")) }), [("ws1/st1", "st3")])
  // none up
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-panel-none")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "没有别的在线 station"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  retire_press(t, "开始迁移")
  assert_eq(retire_calls(calls, "copies.retire").length(), 0)
  // a workspace it only joined: its accounts in what stays, not in what goes
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-panel-joined")
  assert_eq(t.audit(), [])
  assert_true(retire_y(t, "无法迁移的") < retire_y(t, "账号"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  // the one up named long: its name whole where it is chosen, no words cut short, no note past two lines
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-station-retire-panel-long")
  assert_eq(t.audit(), [])
  assert_true(retire_said(t, "一起迁到 Lin's MacBook Pro (2021)"), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_eq(t.words().filter(fn(x) { x.0.has_suffix("…") }).map(fn(x) { x.0 }), [])
  let line = t.words().iter().find_first(fn(x) { x.0 == "其中 525 个已归档" }).unwrap().4
  for x in t.words() {
    if x.0.has_suffix(" 等") {
      assert_true(x.4 <= line * 2.0 + 1.0, msg="\{x.0}: \{x.4} high, a line \{line}")
    }
  }
}

///|
test "an account not shared, a subscription or a key: the station it is on, moved to another up to take it; after, back to the list, said where it went" {
  for mode in ["settings-profile-move", "settings-profile-move-key"] {
    let calls : Array[Made] = []
    let t = retire_tester(calls, mode)
    t.wheel(195.0, 500.0, 3000.0)
    t.run_for(@ui.move_most_ms)
    assert_true(retire_said(t, "所在 station"), msg="\{mode}: " + t.words().map(fn(x) { x.0 }).join("|"))
    assert_eq(t.audit(), [], msg=mode)
    retire_press(t, "所在 station")
    assert_true(retire_said(t, "移到哪台 station？"), msg="\{mode}: " + t.words().map(fn(x) { x.0 }).join("|"))
    assert_true(t.find("账号移到选中的 station，Willow 上不再有它；这里用它的聊天改用这台的其他账号。") is Some(_), msg=mode)
    retire_press(t, "Maple")
    let asked = retire_calls(calls, "profile.move")
    assert_eq(asked.length(), 1, msg=mode)
    let p = Some(asked[0])
    assert_eq(text(p, "station"), "ws1/st1", msg=mode)
    assert_eq(text(p, "id"), if mode == "settings-profile-move" { "cx" } else { "k2" }, msg=mode)
    assert_eq(text(p, "to"), "st2", msg=mode)
    // (its page here has nothing to show after: back where it was opened from, the move said)
    t.run_for(@ui.move_most_ms)
    assert_true(!retire_said(t, "所在 station"), msg=mode)
    assert_true(t.find("已移到 Maple") is Some(_), msg="\{mode}: " + t.words().map(fn(x) { x.0 }).join("|"))
  }
  // no other station up: no row to move it
  let calls : Array[Made] = []
  let t = retire_tester(calls, "settings-profile-key")
  t.wheel(195.0, 500.0, 3000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(!retire_said(t, "所在 station"))
}
