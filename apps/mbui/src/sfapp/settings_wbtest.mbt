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
test "settings come in from the left, as the gear is at the list's top left, and go back that way" {
  reset()
  let t = @ui.Tester::new(fn(c) { view(c, fixture("settings")) }, w=390.0, h=844.0)
  t.draw()
  // the gear's (App.kt transition: Settings slide in from the left, the list out to the right), once the core has
  // said what they show
  open_setting("home")
  t.draw()
  t.draw()
  let end = @ui.nav_rest()
  assert_true(end - t.time() <= @ui.nav_push_ms)
  // from a page's width to the left of where they stand, rightwards
  let x0 = t.find("lin@example.com").unwrap().0
  t.run_for(end - @ui.nav_push_ms / 2.0 - t.time())
  let x1 = t.find("lin@example.com").unwrap().0
  t.run_for(end - t.time())
  let x = t.find("lin@example.com").unwrap().0
  assert_eq((x - x0).round(), 390.0)
  assert_true(x0 < x1 && x1 < x)
  // a page under them comes from the right as any does
  t.tap_text("lin@example.com")
  nav_rested(t)
  t.back()
  nav_rested(t)
  // back to the list: out to the left again
  t.back()
  t.draw()
  let end = @ui.nav_rest()
  t.run_for(end - @ui.nav_push_ms / 2.0 - t.time())
  assert_true(t.find("lin@example.com").unwrap().0 < x - 195.0)
  t.run_for(end - t.time())
  assert_true(t.find("lin@example.com") is None)
}

///|
test "settings: the account, the workspace's rows and how each stands, this device's" {
  let t = settings_tester("home")
  assert_true(t.find("设置") is Some(_))
  assert_true(t.find("lin@example.com") is Some(_))
  // the workspace's card: its name, the viewer's role and its people (3 members, an email added and an invitation out)
  assert_true(t.find("星火工作室") is Some(_))
  assert_true(t.find("Owner · 3 人 · 2 人待加入") is Some(_))
  assert_true(t.find("1/2 在线") is Some(_))
  assert_true(t.find("外观") is Some(_))
  // a tap on the account's card: the account
  t.tap_text("lin@example.com")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("lin@example.com") is Some(_))
  assert_true(t.find("Chrome · macOS") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
/// How late a phone's core gives each topic's first value, in the test below (round_trip): well after a page has slid
/// in (@ui.nav_push_ms).
let core_late_ms : Double = 600.0

///|
test "settings: the vault's row there before the core has said how it stands, the page under it not moved when it does" {
  reset()
  // a phone's core: each topic's first value a while late (the lock's read on Home already, the vaults' first by
  // settings)
  let src = round_trip(fixture("settings"), core_late_ms)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=1600.0)
  t.draw()
  // Home, its topics one after another (the accounts, the workspaces, the workspace's)
  t.run_for(core_late_ms * 5.0)
  open_setting("home")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  // in, the core yet to answer: the rows there, their words not yet
  assert_true(t.find("1/2 在线") is None)
  assert_true(t.find("安全") is Some(_))
  assert_true(t.find("密钥") is Some(_))
  let at = t.find("外观").unwrap()
  // answered (the workspace's view, then what its stations say): what each says, nothing under them moved
  t.run_for(core_late_ms * 3.0)
  t.draw()
  assert_true(t.find("1/2 在线") is Some(_))
  assert_true(t.find("1 个待批准") is Some(_))
  assert_eq(t.find("外观").unwrap(), at)
}

///|
test "settings: 关于 says the build, as Android's versionName (0.1.<build>), its page the app's name before it; the line alone where the host has none" {
  for case in [(4566, "0.1.4566"), (0, "0.1")] {
    reset()
    let src = fixture("settings")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=1600.0, app_version=case.0)
    open_setting("home")
    t.draw()
    t.run_for(@ui.nav_push_ms)
    assert_true(t.find("关于") is Some(_))
    assert_true(t.find(case.1) is Some(_))
    t.tap_text("关于")
    t.run_for(@ui.nav_push_ms)
    assert_true(t.find("still.fail mbui " + case.1) is Some(_))
    assert_true(t.find("更新日志") is Some(_))
  }
}

///|
test "settings: the workspace's card opens its page" {
  let t = settings_tester("home")
  t.tap_text("星火工作室")
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("zhou@example.com") is Some(_))
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
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
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
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
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
  let (_, name_y) = t.find("lin@example.com").unwrap()
  let (_, out_y) = t.find("退出登录").unwrap()
  // on the account's own row, not on one of its own below it
  assert_true((out_y - name_y).abs() < row_h)
  assert_true(t.find("登录另一个账号") is Some(_))
}

///|
/// A row of a settings card, at most (its two lines and its 12 above and below).
let row_h : Double = 64.0

///|
/// The stations' list over the settings' made-up data, no station's network open yet (stationNet's null): Studio online,
/// its memory low, MBA offline.
fn stations_unread_net() -> @ui.Tester {
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
  t
}

///|
/// The tops of the list's network lines laid out unseen (their 直连 keeping the room), down the list.
fn unseen_lines(t : @ui.Tester) -> Array[Double] {
  let tops = t.words().filter(fn(w) { w.0 == "直连" && w.5 == 0.0 }).map(fn(w) { w.2 })
  tops.sort()
  tops
}

///|
/// The chip whose words are `words` and its ground's fill as drawn (Parts.kt FillChip): the fill's width (0: none) and
/// the chip's, the fill from the chip's left, as tall as it.
fn chip_fill(t : @ui.Tester, words : String) -> (Double, Double) {
  let (x, y) = t.find(words).unwrap()
  let rects = t.drawn_rects()
  let mut chip = (0.0, 0.0, 0.0, 0.0)
  for r in rects {
    if (r.3 == 20.0 || r.3 == 16.0) && r.0 <= x && x <= r.0 + r.2 && r.1 <= y && y <= r.1 + r.3 && r.2 > chip.2 {
      chip = (r.0, r.1, r.2, r.3)
    }
  }
  let mut fill = 0.0
  for r in rects {
    if (r.0 - chip.0).abs() < 0.01 && (r.1 - chip.1).abs() < 0.01 && (r.3 - chip.3).abs() < 0.01 && r.2 < chip.2 - 0.01 {
      fill = r.2
    }
  }
  (fill, chip.2)
}

///|
test "settings: a station's network not open yet (stationNet's null) waits as grey bars, no arrows over nothing" {
  let t = stations_unread_net()
  assert_true(t.find("Studio") is Some(_))
  // (the line it would be is there, unseen, keeping its room)
  let shown = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).length() > 0 }
  assert_false(shown("↑"))
  assert_false(shown("↓"))
}

///|
test "settings: a station's network not open yet waits where its line goes (StationBody): its bars centred across the line's room, 10 under the load's boxes" {
  let t = stations_unread_net()
  // Studio's: its low box (20 high round its words), the line's room 10 under it, two lines of 18 2 apart
  let (_, box_mid) = t.find("剩 11.5 G").unwrap()
  let room = unseen_lines(t)[0]
  assert_true((room - (box_mid + 10.0 + 10.0)).abs() < 0.5, msg="the line's room from \{room}, the box's middle \{box_mid}")
  // its four bars (34 and 96, 132 and 132), two rows 9 apart, as much room over them as under
  let bars = t.drawn_rects().filter(fn(r) { r.3 == 10.0 && r.1 > box_mid && r.1 < room + 38.0 })
  assert_eq(bars.length(), 4)
  let top = bars.fold(init=1.0e9, fn(m, r) { if r.1 < m { r.1 } else { m } })
  let bottom = bars.fold(init=-1.0e9, fn(m, r) { if r.1 + r.3 > m { r.1 + r.3 } else { m } })
  assert_true((top - room - 4.5).abs() < 0.5, msg="the bars from \{top}, the line's room from \{room}")
  assert_true((room + 38.0 - bottom - 4.5).abs() < 0.5, msg="the bars to \{bottom}, the line's room to \{room + 38.0}")
}

///|
test "settings: an offline station's picture and line centred across its card's room (StationBody), not over the 10 above it" {
  let t = stations_unread_net()
  // MBA's room: its load's 20 and 10 over its unseen line, the line's 38
  let room = unseen_lines(t)[1] - 30.0
  let (_, said) = t.find("此机器已长时间未连接 still.fail").unwrap()
  assert_true((said - (room + 34.0)).abs() < 0.5, msg="the line's middle \{said}, the room's \{room + 34.0}")
}

///|
test "settings: a station's low box filled as far as is used (FillChip): 内存 18% left, 82% of it" {
  let t = stations_unread_net()
  let (fill, chip) = chip_fill(t, "剩 11.5 G")
  assert_true(chip > 0.0)
  assert_true((fill - chip * 0.82).abs() < 0.5, msg="the fill \{fill} of \{chip}")
}

///|
test "an agent's allowance in its sheet filled as far as is left (QuotaChips): 5H 62%, W 18%" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent")
  for each in [("62%", 0.62), ("18%", 0.18)] {
    let (words, part) = each
    let (fill, chip) = chip_fill(t, words)
    assert_true(chip > 0.0, msg=words)
    assert_true((fill - chip * part).abs() < 0.5, msg="\{words}: the fill \{fill} of \{chip}")
  }
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

///|
test "本机缓存: the drives' files kept, counted with the chats', let go when asked" {
  let t = settings_tester("kept")
  // (what is kept asked of the core as the page is first built: drawn with its answer)
  t.draw()
  // under 其他: 文件浏览, 38.5 MB of them; with the chats' 18.3 MB and the 900 KB of no chat known, 57.7 MB in all
  // (KeptFiles.kt)
  assert_true(t.find("其他") is Some(_))
  assert_true(t.find("文件浏览") is Some(_))
  assert_true(t.find("38.5 MB") is Some(_))
  assert_true(t.find("共 57.7 MB") is Some(_))
  // tapped, asked first; 删除: let go, read again
  t.tap_text("文件浏览")
  sheet_rested(t, "settings-sheet")
  // (its button: the words 删除 alone, not those that tell what it does)
  match t.words().iter().find_first(fn(w) { w.0 == "删除" }) {
    Some((_, x, y, w, h, _)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("no 删除")
  }
  // (asked again once it is let go, drawn with the answer)
  t.draw()
  t.draw()
  assert_true(t.find("38.5 MB") is None)
  assert_true(t.find("0 B") is Some(_))
  assert_true(t.find("共 19.2 MB") is Some(_))
}

///|
test "本机缓存 with many chats: only the rows in view laid out, one card all the same, the last one reached" {
  let t = settings_tester("kept", shows="settings-kept-many")
  t.draw()
  // a block each: of 203 rows a screen's (one block of them all was built whole each frame, every row's words with it)
  let built = fn() { t.words().filter(fn(w) { w.0.has_prefix("测试会话 ") }).length() }
  assert_true(t.find("测试会话 1") is Some(_))
  assert_true(built() > 0 && built() < 20)
  // one card: its corners where it begins and ends only, as any (the pieces' patches its own ground)
  assert_eq(t.corner_faults(), [])
  t.scroll_to_end()
  t.draw()
  assert_true(t.find("测试会话 200") is Some(_))
  assert_true(built() < 20)
  assert_eq(t.corner_faults(), [])
  // the last row taps as any
  t.tap_text("测试会话 200")
  nav_rested(t)
  assert_true(t.find("测试会话 200") is Some(_))
  assert_true(t.find("消息记录") is Some(_))
}

///|
test "本机缓存: a chat's files opened, each let go by its bin; those of no chat known apart" {
  let t = settings_tester("kept")
  t.draw()
  // the chat: its messages and its 2 files (KeptFiles.kt chat.both), what is kept of it all
  assert_true(t.find("消息 2.3 MB · 2 个文件 15.2 MB") is Some(_))
  assert_true(t.find("17.5 MB") is Some(_))
  // of no chat known: a row of its own under 其他
  assert_true(t.find("无法确定所属 chat 的文件") is Some(_))
  assert_true(t.find("1 个文件") is Some(_))
  t.tap_text("整理发布清单")
  t.run_for(@ui.nav_push_ms)
  // its files: how much, when opened, or only a part of it come
  assert_true(t.find("已打开的文件") is Some(_))
  assert_true(t.find("2 个 · 15.2 MB") is Some(_))
  assert_true(t.find("季度报告.pdf") is Some(_))
  assert_true(t.find("3.2 MB · 5 分钟前打开") is Some(_))
  assert_true(t.find("12 MB · 未下载完成") is Some(_))
  // its bin: let go, read again
  let (x, y, w, h) = t.query(Button, label="删除「季度报告.pdf」").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.draw()
  assert_true(t.find("季度报告.pdf") is None)
  assert_true(t.find("1 个 · 12 MB") is Some(_))
}

///|
test "a secret's longest grant: on its page its own or its vault's, in its editor 跟随默认 or one of its own" {
  // its page: none of its own, its vault's (Vault.kt: 跟随默认 · …)
  let t = settings_tester("vault-item:v1#it1")
  t.draw()
  assert_true(t.find("最长授权") is Some(_))
  assert_true(t.find("跟随默认 · 直到对话归档") is Some(_))
  // its editor, agents let ask for it: 跟随默认 first, each of its own, what it means under them
  let e = settings_tester("vault", shows="settings-vault-editor")
  sheet_rested(e, "settings-sheet")
  assert_true(e.find("跟随默认") is None)
  e.tap_text("允许 agent 申请")
  e.draw()
  assert_true(e.find("跟随默认") is Some(_))
  assert_true(e.find("仅一次") is Some(_))
  assert_true(e.find("批准这个密钥的申请时") is Some(_))
}

///|
test "the run's 账号: what 自动分配 means, then 自动分配 and each account with its provider's mark and its allowance" {
  let t = settings_tester("run:ws1/st1#s-c1", mode="settings-run-accounts", shows="settings-run-accounts")
  t.draw()
  // (AccountList: the note, 自动分配, each account without a line under it, its windows as the allowance's boxes)
  assert_true(t.find("自动分配时，额度用完或登录失效会切换账号") is Some(_))
  assert_true(t.find("Claude 主账号") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("38%") is Some(_))
  assert_true(t.find("70%") is Some(_))
}

///|
/// A profile's page in a window tall enough for all of it (the order of what it holds read off at once).
fn profile_whole(page : String) -> @ui.Tester {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0)
  open_setting(page)
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "a profile's page: whether the account works and how much is left first; then who uses it, how it runs, whom it is shared with" {
  let t = profile_whole("profile:ws1/st1#cc")
  let y = fn(words : String) { t.find(words).unwrap().1 }
  // the account: what its check said, under it a dot and its words with when it was checked (no pill)
  assert_true(y("可用 · 5 分钟前检查") > y("订阅有效"))
  // its allowance under it with no title over it, when it was read under its windows; read again from the "…"
  assert_true(y("5 小时") > y("可用 · 5 分钟前检查"))
  assert_true(y("3 分钟前查询") > y("5 小时"))
  assert_true(t.find("查询额度") is None)
  // then who uses it, how it runs (its models a row: 2 of 3 on), whom it is shared with
  assert_true(y("使用它的连接") > y("3 分钟前查询"))
  assert_true(y("运行") > y("使用它的连接"))
  assert_true(y("2 / 3") > y("运行") && y("默认 Fast") > y("2 / 3"))
  assert_true(y("分享") > y("默认 Fast"))
  assert_true(y("分享给其他 station") > y("分享"))
  // the models themselves not on it
  assert_true(t.find("筛选模型") is None && t.find("Haiku 5") is None)
  // 2 / 3: their page, how many on under its title
  t.tap_text("2 / 3")
  nav_rested(t)
  assert_true(t.find("已选 2 项") is Some(_))
  assert_true(t.find("只有勾选的模型可在新对话和连接中选择。") is Some(_))
  assert_true(t.find("Haiku 5") is Some(_))
}

///|
test "a profile in trouble: what is wrong the first line of its card, why and its button under it, no section of its own" {
  let t = profile_whole("profile:ws1/st1#k2")
  let y = fn(words : String) { t.find(words).unwrap().1 }
  assert_true(y("服务商拒绝了这个 key") > y("key 已失效"))
  // (its words under the title, red: 没能使用)
  assert_true(t.find("没能使用") is Some(_))
  // a key's allowance none to read: no card for it
  assert_true(t.find("暂无额度信息") is None)
}

///|
test "a subscription's page signed in: where it stands alone on its card; 重新登录 and 在机器上手动登录 under its …" {
  let t = settings_tester("profile:ws1/st1#cc")
  // one card for the account: its pill, no title over the card, nothing to do on it while it is signed in and well
  assert_true(t.find("可用") is Some(_))
  assert_true(t.find("Claude 订阅") is None)
  assert_true(t.find("重新登录") is None)
  assert_true(t.find("在机器上手动登录") is None)
  let more = fn() {
    let (x, y) = t.locate("icon:more")[0]
    t.tap(x, y)
    sheet_rested(t, "settings-sheet")
  }
  // its …: the command to run by hand, in a sheet of its own
  more()
  t.tap_text("在机器上手动登录")
  sheet_rested(t, "settings-sheet")
  assert_true(t.find("claude setup-token") is Some(_))
  // (put away by a tap beside it)
  t.tap(195.0, 60.0)
  sheet_rested(t, "settings-sheet")
  // 重新登录: begun on the station, its steps on the card
  more()
  t.tap_text("重新登录")
  sheet_rested(t, "settings-sheet")
  t.draw()
  assert_true(t.find("打开授权页面") is Some(_))
}

///|
test "a subscription's sign-in that failed: why, then 重新登录 with 在机器上手动登录 beside it on its card (Profiles.kt SignIn)" {
  let t = settings_tester("profile:ws1/st1#cc", shows="settings-profile-login-failed")
  let (_, pill_y) = t.find("可用").unwrap()
  let (_, why_y) = t.find("上次登录失败：授权码已过期").unwrap()
  let (bx, by) = t.find("重新登录").unwrap()
  let (mx, my) = t.find("在机器上手动登录").unwrap()
  assert_true(why_y > pill_y && by > why_y)
  assert_true((my - by).abs() < 2.0 && mx > bx)
  // the command to run by hand, under them once asked
  t.tap_text("在机器上手动登录")
  t.draw()
  assert_true(t.find("claude setup-token") is Some(_))
}
