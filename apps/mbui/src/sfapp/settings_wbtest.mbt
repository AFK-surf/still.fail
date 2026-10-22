// The settings' pages (src/sfapp/settings) over the made-up ones (settings/fixture.mbt), as the app shows them.

///|
/// The app over the settings' fixture, a page of them open (by its name, @settings.route_of); `shows`: a fixture mode
/// of the settings' (MBUI_FIXTURE=settings-…) whose page this is, as it sets its fixture up (a step of a flow).
fn settings_tester(page : String, mode? : String = "settings", shows? : String = "") -> @ui.Tester {
  reset()
  if shows != "" {
    @settings.fixture_page(shows) |> ignore
  }
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_setting(page)
  // the pages opened slide in from the frame that takes them
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "settings: the account, the workspace's rows and how each stands, this device's" {
  let t = settings_tester("home")
  assert_true(t.find("设置") is Some(_))
  assert_true(t.find("lin@example.com") is Some(_))
  // the workspace's heading: its name and the viewer's role
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("Workspace") is Some(_))
  // 3 members, an email added and an invitation out
  assert_true(t.find("3 人") is Some(_))
  assert_true(t.find("1/2 在线") is Some(_))
  assert_true(t.find("外观") is Some(_))
  // a tap on the account's card: the account
  t.tap_text("lin@example.com")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("lin@example.com · Google") is Some(_))
  assert_true(t.find("Chrome · macOS") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "appearance: 深色 chosen, the app is drawn dark at once and the core keeps it" {
  let t = settings_tester("appearance")
  assert_true(t.find("跟随系统") is Some(_))
  assert_false(@sf.theme().dark)
  t.tap_text("深色")
  assert_true(@sf.theme().dark)
  t.tap_text("浅色")
  assert_false(@sf.theme().dark)
  // (not idle yet: the choice's thumb is on a Ctx::spring (settings/parts.mbt), whose end the app cannot read)
}

///|
test "a station renamed from its page's …: the new name is the station's" {
  let t = settings_tester("stations")
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.find("MBA") is Some(_))
  t.tap_text("Studio")
  t.run_for(@ui.nav_push_ms)
  // its machine, large
  assert_true(t.find("内存剩") is Some(_))
  assert_true(t.find("在此 station 上") is Some(_))
  // "…" at the bar's end
  t.tap(357.0, 22.0)
  t.tap_text("重命名")
  assert_true(t.find("station 名称") is Some(_))
  for _ in 0..<6 {
    t.backspace()
  }
  t.type_text("工作室")
  t.tap_text("保存")
  assert_true(t.find("工作室") is Some(_))
  // (not idle yet: the sheet is still sinking on its spring (kit/sheet.mbt), till mbui#25 declares its end)
}

///|
test "a settings sheet goes down on the sheet's spring, only drawn: its 保存 tapped meanwhile renames nothing" {
  let t = settings_tester("stations")
  // the station as the tests before left it
  let name = if t.find("Studio") is Some(_) { "Studio" } else { "工作室" }
  t.tap_text(name)
  t.run_for(@ui.nav_push_ms)
  t.tap(357.0, 22.0)
  t.tap_text("重命名")
  for _ in 0..<name.length() {
    t.backspace()
  }
  t.type_text("没改成的名字")
  assert_true(t.find("保存") is Some(_))
  // the scrim, tapped: it goes down, drawn as it goes, the keyboard let go of
  t.tap_once(195.0, 60.0)
  t.frame()
  t.frame()
  let (sx, sy) = t.find("保存").unwrap()
  let (active, _, _, _) = t.ime()
  assert_true(!active)
  t.tap_once(sx, sy)
  // down at once (only drawn as it sinks), the station's name as it was
  assert_true(!@settings.sheet_up())
  assert_true(t.find(name) is Some(_))
  // (not idle yet: the sheet is still sinking on its spring (kit/sheet.mbt), till mbui#25 declares its end)
}

///|
test "the archive: its chats by day; one restored leaves it" {
  let t = settings_tester("archive")
  assert_true(t.find("已归档") is Some(_))
  assert_true(t.find("整理上个月的发票") is Some(_))
  assert_true(t.find("周会纪要") is Some(_))
  assert_true(t.find("昨天") is Some(_))
  // 还原 at the row's end (its first round button, before 删除), said with the chat's title
  assert_true(t.query(Button, label="删除「整理上个月的发票」") is Some(_))
  let (x, y, w, h) = t.query(Button, label="恢复「整理上个月的发票」").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(t.find("整理上个月的发票") is None)
  assert_true(t.find("周会纪要") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "the workspace: its people, those added, the invitations out" {
  let t = settings_tester("workspace")
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("Ana") is Some(_))
  assert_true(t.find("zhou@example.com") is Some(_))
  assert_true(t.find("he@example.com") is Some(_))
  assert_true(t.find("qin@example.com") is Some(_))
  assert_true(t.find("撤回") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "security mode: a device waiting, confirmed in its sheet by its code" {
  let t = settings_tester("security")
  assert_true(t.find("安全") is Some(_))
  assert_true(t.find("482 917") is Some(_))
  t.tap_text("482 917")
  assert_true(t.find("一致，批准") is Some(_))
  assert_true(t.find("不一致，拒绝") is Some(_))
  // (not idle yet: the sheet is still rising on kit's spring (kit/sheet.mbt), whose end it does not say)
}

///|
test "memory: a station's global memory, its projects, a skill's page" {
  let t = settings_tester("memory:ws1/st1")
  assert_true(t.find("全局记忆") is Some(_))
  assert_true(t.find("发布流程") is Some(_))
  t.tap_text("发布流程")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("步骤") is Some(_))
  assert_true(t.find("checklist") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  t.assert_idle()
}

///|
test "usage: the totals, the days, 30 天 picked" {
  let t = settings_tester("usage")
  assert_true(t.find("$118") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  t.tap_text("30 天")
  assert_true(t.find("$486") is Some(_))
  // (not idle yet: a Ctx::spring still moves, till mbui#25 declares its end)
}

///|
test "profiles, connects, the vault: their lists" {
  let t = settings_tester("profiles")
  assert_true(t.find("Claude 主账号") is Some(_))
  assert_true(t.find("Claude 订阅") is Some(_))
  // its allowance a line of its own under its words, at the row's start (Profiles.kt)
  let (nx, ny) = t.find("Claude 主账号").unwrap()
  let (qx, qy) = t.find("62%").unwrap()
  assert_true(qy > ny + 20.0)
  assert_true(qx < nx)
  let t2 = settings_tester("connects")
  assert_true(t2.find("星火助手 · 星火") is Some(_))
  assert_true(t2.find("值班机器人") is Some(_))
  let t3 = settings_tester("vault")
  assert_true(t3.find("GitHub token") is Some(_))
  assert_true(t3.find("git push origin main") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t3.run_for(bar.rest() - t3.time())
  t3.assert_idle()
}

///|
test "下方栏: a place's \"−\" takes it off its bar (the bars kept as the workspace's)" {
  let t = settings_tester("bars")
  bars_picked.val = None
  assert_true(t.find("第 1 栏") is Some(_))
  // under the title, what the bars are of (BarSettings.kt LargeTitle's small words)
  assert_true(t.find("此设备") is Some(_))
  // Station's "−", at its icon's top right over the first bar's last slot, said as what it takes off
  let (x, y, w, h) = t.query(Button, label="从此栏移除Station").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  match bars_picked.val {
    Some((sets, _)) => {
      assert_eq(sets[0].length(), 3)
      assert_false(sets[0].contains("stations"))
    }
    None => fail("the bars were not changed")
  }
}

///|
test "下方栏: a place held and slid sideways goes where it is let go, by the slots it went; a tap moves nothing" {
  let t = settings_tester("bars")
  bars_picked.val = None
  let (x, y, w, h) = t.query(@ui.Group, label="对话").unwrap().rect
  // a tap: nothing (BarSettings.kt: a place has no tap, only its drag)
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(bars_picked.val is None)
  // held and slid a slot and a third to the right: after 文件
  t.drag(x + w / 2.0, y + h / 2.0, x + w * 1.8, y + h / 2.0)
  match bars_picked.val {
    Some((sets, _)) => assert_eq(sets[0], ["files", "chats", "profiles", "stations"])
    None => fail("the bars were not changed")
  }
}

///|
test "下方栏: a screen reader moves a place one slot along" {
  let t = settings_tester("bars")
  bars_picked.val = None
  t.act(@ui.Group, @ui.Increment, label="文件")
  t.draw()
  match bars_picked.val {
    Some((sets, _)) => assert_eq(sets[0], ["chats", "profiles", "files", "stations"])
    None => fail("the bars were not changed")
  }
}

///|
test "添加成员: what is typed counts at once, 添加 lit by it" {
  let t = settings_tester("workspace")
  t.tap(362.0, 22.0)
  assert_true(t.find("添加成员") is Some(_))
  t.tap_text("name@example.com")
  t.type_text("he2@example.com")
  // the sheet's 添加, its last words (the page's 添加中继 lies under it)
  match t.find_last("添加") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no 添加")
  }
  // the fixture adds them: the sheet says what came of it
  assert_true(t.find("完成") is Some(_))
}

///|
test "飞书: a new connect picks its platform first, Slack's and 飞书's said (FeishuConnect.kt)" {
  let t = settings_tester("new-connect:ws1/st1", shows="settings-new-connect-platform")
  assert_true(t.find("选择平台") is Some(_))
  assert_true(t.find("在 Slack 的频道和私信中使用") is Some(_))
  assert_true(t.find("在飞书的群和私聊中使用，含国际版 Lark") is Some(_))
  assert_true(t.find("下一步") is Some(_))
  // no QR code before the bot is being made
  assert_true(t.find("在飞书中打开") is None)
}

///|
test "飞书: scanning, its QR code drawn on white and 在飞书中打开 handed to the system" {
  let t = settings_tester("new-connect:ws1/st1", shows="settings-new-connect-scan")
  assert_true(t.find("使用飞书扫描二维码，按提示创建机器人") is Some(_))
  assert_true(t.find("也可用另一台设备上的飞书扫码") is Some(_))
  // the code's dark runs, black on the white square
  let dark = t.drawn_rects().filter(fn(r) { r.4 == 0x000000FFL })
  assert_true(dark.length() > 25)
  t.tap_text("在飞书中打开")
  assert_eq(t.opened(), ["https://open.feishu.cn/page/launcher?code=made-up"])
}

///|
test "settings: the account's page has the accounts on this device on its one card (Me.kt): 退出登录 beside who it is" {
  let t = settings_tester("me")
  assert_true(t.find("此设备上的账号") is None)
  let (_, name_y) = t.find("lin@example.com · Google").unwrap()
  let (_, out_y) = t.find("退出登录").unwrap()
  // on the account's own row, not on one of its own below it
  assert_true((out_y - name_y).abs() < row_h)
  assert_true(t.find("登录另一个账号") is Some(_))
}

///|
/// A row of a settings card, at most (its two lines and its 12 above and below).
let row_h : Double = 64.0

///|
test "settings: a station's network not open yet (stationNet's null) waits as grey bars, no arrows over nothing" {
  reset()
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "stationNet" {
        { value: Some(Json::null()), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  open_setting("stations")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("Studio") is Some(_))
  // (the line it would be is there, unseen, keeping its room)
  let shown = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).length() > 0 }
  assert_false(shown("↑"))
  assert_false(shown("↓"))
}

///|
test "a subscription signing in: what to do said once, its page's step solid, then the code with 完成 in its field (Profiles.kt LoginSteps)" {
  let t = settings_tester("profile:ws1/st1#cc", shows="settings-profile-login")
  assert_true(t.find("在打开的页面用 still.fail 要使用的 Claude 账号登录，并同意授权") is Some(_))
  assert_true(t.find("打开授权页面") is Some(_))
  // nothing typed: no 完成 yet
  assert_true(t.find("完成") is None)
  t.tap_text("粘贴授权码")
  t.type_text("abc-123")
  assert_true(t.find("完成") is Some(_))
  // (and the way to sign in by hand, beside the button, once not signing in: 在机器上手动登录)
}
