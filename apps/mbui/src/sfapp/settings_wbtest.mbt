// The settings' pages (src/sfapp/settings) over the made-up ones (settings/fixture.mbt), as the app shows them.

///|
/// The app over the settings' fixture, a page of them open (by its name, @settings.route_of); `shows`: a fixture mode
/// of the settings' (MBUI_FIXTURE=settings-…) whose page this is, as it sets its fixture up (a step of a flow).
fn settings_tester(
  page : String,
  mode? : String = "settings",
  shows? : String = "",
  platform? : Int = 0,
) -> @ui.Tester {
  reset()
  if shows != "" {
    @settings.fixture_page(shows) |> ignore
  }
  let src = fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform~)
  open_setting(page)
  // the pages opened slide in from the frame that takes them
  t.draw()
  t.run_for(@ui.move_most_ms)
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
  assert_true(end - t.time() <= @ui.move_most_ms)
  // from a page's width to the left of where they stand, rightwards
  let x0 = t.find("lin@example.com").unwrap().0
  t.run_for(end - @ui.move_most_ms / 2.0 - t.time())
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
  t.run_for(end - @ui.move_most_ms / 2.0 - t.time())
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
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("lin@example.com · Google 账号") is Some(_))
  assert_true(t.find("Chrome · macOS") is Some(_))
  // the bottom bar going out of the way, on its own springs and glides, to where it rests
  t.run_for(bar.rest() - t.time())
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
/// How late a phone's core gives each topic's first value, in the test below (round_trip): well after a page has slid
/// in (@ui.move_most_ms).
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
  t.run_for(@ui.move_most_ms)
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
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("关于") is Some(_))
    assert_true(t.find(case.1) is Some(_))
    t.tap_text("关于")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("still.fail mbui " + case.1) is Some(_))
    assert_true(t.find("更新日志") is Some(_))
  }
}

///|
test "settings: the workspace's card opens its page" {
  let t = settings_tester("home")
  t.tap_text("星火工作室")
  t.run_for(@ui.move_most_ms)
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
test "appearance: another theme picked, it spreads from where it was picked, the page as it was under it" {
  let t = settings_tester("appearance")
  t.tap_text("深色")
  t.frame()
  assert_true(@sf.theme().dark)
  assert_true(@ui.reveal_spreading())
  t.run_for(@ui.reveal_ms)
  t.frame()
  assert_false(@ui.reveal_spreading())
}

///|
test "appearance: 动画 减少 chosen, motion is reduced at once whatever the system says; 不减少, it is not" {
  let t = settings_tester("appearance")
  assert_false(@ui.reduced_motion())
  t.tap_text("减少")
  t.draw()
  assert_true(@ui.reduced_motion())
  // the system's own reduced: 不减少 holds motion all the same, 跟随系统 follows it
  t.set_reduce_motion(true)
  t.tap_text("不减少")
  t.draw()
  assert_false(@ui.reduced_motion())
  t.tap_text("跟随系统")
  t.draw()
  t.set_reduce_motion(false)
}

///|
test "a station renamed from its page's …: the new name is the station's" {
  let t = settings_tester("stations")
  assert_true(t.find("Studio") is Some(_))
  assert_true(t.find("MBA") is Some(_))
  t.tap_text("Studio")
  t.run_for(@ui.move_most_ms)
  // its page (src/sfpages station_page.mbt), its overview first
  assert_true(t.find("概览") is Some(_))
  // its ⋯ (the presenters' menu, a sheet on a phone) → 重命名, the name asked
  let log = t.drive(
    "tap icon:more\nuntil 重命名\ntap =重命名\nuntil station 名称\nclear\ntype 工作室\ntap =保存\ngone 保存\n",
  )
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  sheet_rested(t, "sf-present")
  t.draw()
  assert_true(t.find("工作室") is Some(_))
}

///|
test "a sheet asking goes down on the sheet's spring, only drawn: its 保存 tapped meanwhile renames nothing" {
  // (touch's: keyboard and mouse's asks in a dialog, gone at once as it closes)
  let t = settings_tester("profile:ws1/st1#cx", platform=2)
  let name = "ChatGPT 团队"
  assert_true(t.find(name) is Some(_))
  // its rename (its name pressed, a phone's head's title): the name asked in the presenters' sheet (src/sfdesk
  // accounts.mbt profile_head)
  let (x, y) = t.find(name).unwrap()
  t.tap(x, y)
  sheet_rested(t, "sf-present")
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
  // down at once (only drawn as it sinks), the profile's name as it was
  sheet_rested(t, "sf-present")
  t.draw()
  assert_true(t.find("没改成的名字") is None)
  // (the sheet sinking takes no press: the tap is the page's under it, which opens what stands there, a row of the
  // profile's: back on the profile, its name)
  if t.find(name) is None {
    t.back()
    nav_rested(t)
  }
  assert_true(t.find(name) is Some(_))
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
test "memory: a station's global memory, its projects, a skill's page" {
  let t = settings_tester("memory:ws1/st1")
  assert_true(t.find("全局记忆") is Some(_))
  assert_true(t.find("发布流程") is Some(_))
  t.tap_text("发布流程")
  t.run_for(@ui.move_most_ms)
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
  // the lists, the people's first (the web's)
  assert_true(t.find("68%") is Some(_))
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
  // (its Slack workspace after its name)
  assert_true(t2.find("星火助手") is Some(_))
  assert_true(t2.find("星火") is Some(_))
  assert_true(t2.find("值班机器人") is Some(_))
  // 密钥: the request waiting on the viewer, its secrets a page under it (全部密钥)
  let t3 = settings_tester("vault")
  assert_true(t3.find("git push origin main") is Some(_))
  assert_true(t3.find("部署机") is None)
  assert_true(settings_tester("vault-items").find("部署机") is Some(_))
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
  // (the ＋ at the title's end)
  let (x, y, w, h) = t.query(Button, label="添加成员").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
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
  let t = settings_tester("connects", mode="settings-new-connect-platform", shows="settings-new-connect-platform")
  assert_true(t.find("选择平台") is Some(_))
  assert_true(t.find("在 Slack 的频道和私信中使用") is Some(_))
  assert_true(t.find("在飞书的群和私聊中使用，含 Lark") is Some(_))
  assert_true(t.find("下一步") is Some(_))
  // no QR code before the bot is being made
  assert_true(t.find("在飞书中打开") is None)
}

///|
test "飞书: scanning, its QR code drawn on white and 在飞书中打开 handed to the system" {
  let t = settings_tester("connects", mode="settings-new-connect-scan", shows="settings-new-connect-scan")
  assert_true(t.find("使用飞书扫描二维码，按提示创建机器人") is Some(_))
  assert_true(t.find("本机已登录飞书时，也可直接打开") is Some(_))
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
  let (_, name_y) = t.find("lin@example.com · Google 账号").unwrap()
  let (_, out_y) = t.find("退出登录").unwrap()
  // on the account's own row, not on one of its own below it
  assert_true((out_y - name_y).abs() < row_h)
  assert_true(t.find("登录另一个账号") is Some(_))
}

///|
/// The card drawn under the box at `rect` (the smallest of the card's ground holding it, however faded: in its bones
/// as well), as (x, y, w, h).
fn card_under(t : @ui.Tester, rect : (Double, Double, Double, Double)) -> (Double, Double, Double, Double)? {
  let (x, y, w, h) = rect
  let card = @sf.ui_theme().card
  let mut best : (Double, Double, Double, Double)? = None
  for r in t.drawn_rects() {
    let (rx, ry, rw, rh, color) = r
    if color >> 8 == card >> 8 && rx <= x && ry <= y && rx + rw >= x + w && ry + rh >= y + h {
      match best {
        Some((_, _, bw, bh)) if bw * bh <= rw * rh => ()
        _ => best = Some((rx, ry, rw, rh))
      }
    }
  }
  best
}

///|
test "settings: where the account is signed in, read the first time, is its card in its bones where the card will be, no words" {
  // (2026-10-26, 「这个 loading 很怪」: a wait's line stood in its place, at the card's edge, 注销账号's card right
  // under it; then 「骨架对不上实际内容的轮廓」: the card itself, in its bones)
  let read = settings_tester("me")
  let (_, read_delete, _, _) = read.rect_of("注销账号").unwrap()
  let (read_x, read_y, read_w, read_h) = card_under(read, read.rect_of("Pixel 9 · still.fail").unwrap()).unwrap()
  let t = settings_tester("me", mode="settings-me-reading")
  t.run_for(@sf.later_ms)
  assert_true(t.find("正在读取") is None)
  let (x, y, w, _) = t.get(Status, label="正在读取").rect
  // its card where the card will be, no glyph in it
  let (card_x, card_y, card_w, card_h) = card_under(t, (x, y, w, 1.0)).unwrap()
  assert_eq((card_x, card_y, card_w), (read_x, read_y, read_w))
  assert_true(t.drawn_glyphs().iter().all(fn(g) { g.1 < card_y || g.1 > card_y + card_h }))
  // 注销账号's card as far under it as under the card once read
  let (_, delete, _, _) = t.rect_of("注销账号").unwrap()
  assert_eq(delete - (card_y + card_h), read_delete - (read_y + read_h))
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
  t.run_for(@ui.move_most_ms)
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
    if (r.3 == @sf.fill_chip_h || r.3 == @sf.fill_chip_small_h) && r.0 <= x && x <= r.0 + r.2 && r.1 <= y && y <= r.1 + r.3 && r.2 > chip.2 {
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
test "settings: a station's network not open yet (stationNet's null) waits as its line's bones, no arrows over nothing" {
  let t = stations_unread_net()
  assert_true(t.find("Studio") is Some(_))
  // (the line it would be is there, unseen, keeping its room; its bones over it draw no words)
  let shown = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).length() > 0 }
  assert_false(shown("↑"))
  assert_false(shown("↓"))
}

///|
test "settings: a station's network not open yet waits where its line goes (StationBody): its bones over the line's room, 10 under the load's boxes" {
  let t = stations_unread_net()
  // Studio's: its low box (20 high round its words), the line's room 10 under it, two lines of 18 2 apart
  let (_, box_mid) = t.find("剩 11.5 G").unwrap()
  let room = unseen_lines(t)[0]
  assert_true((room - (box_mid + 10.0 + 10.0)).abs() < 0.5, msg="the line's room from \{room}, the box's middle \{box_mid}")
  // its bones the line it keeps the room of (the same made-up one, unseen): a bar where each of its words starts, in
  // that word's line
  let unseen = t.words().filter(fn(w) { w.5 == 0.0 && w.2 >= room - 0.5 && w.2 < room + 38.0 && w.0 != " " })
  let line = @sf.theme().p.line >> 8
  let bars = t.drawn_rects().filter(fn(r) { r.4 >> 8 == line && r.1 > box_mid && r.1 < room + 38.0 })
  assert_eq(bars.length(), unseen.length())
  for r in bars {
    assert_true(
      unseen.iter().any(fn(w) { (r.0 - w.1).abs() < 0.5 && r.1 > w.2 && r.1 + r.3 < w.2 + w.4 }),
      msg="a bar at \{r.0}, \{r.1}",
    )
  }
}

///|
test "settings: an offline station's picture and line centred across its card's room (StationBody), not over the 10 above it" {
  let t = stations_unread_net()
  // MBA's room: its load's 20 and 10 over its unseen line, the line's 38
  let room = unseen_lines(t)[1] - 30.0
  let (_, said) = t.find("长时间未连接").unwrap()
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
test "a chat's info on a phone: each agent's name whole and its allowance under how it is, a line of its own" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info")
  // (beside its name the allowance cut the name to 「Claud…」, then left the row on a phone: the allowance gone,
  // 2026-10-26)
  let (_, name_y) = t.find("Claude · Opus 5.5").unwrap()
  let (_, chip_y) = t.find("62%").unwrap()
  assert_true(t.find("18%") is Some(_))
  assert_true(chip_y > name_y, msg="its allowance \{chip_y} under its name \{name_y}")
  // and in its sheet, its account's allowance under the account
  let t = decide_core(calls, "chat-agent")
  let (_, account_y) = t.find("林的 Max · 自动").unwrap()
  let (_, chip_y) = t.find("62%").unwrap()
  assert_true(chip_y > account_y, msg="its allowance \{chip_y} under its account \{account_y}")
}

///|
test "a subscription signing in: what to do in the browser, then the code typed and 完成登录 sends it (Accounts.tsx LoginSteps)" {
  let t = settings_tester("profile:ws1/st1#cc", shows="settings-profile-login")
  let y = fn(words : String) { t.find(words).unwrap().1 }
  // first on its page, under its head: what is under way, the browser's step, the code's field
  assert_true(y("正在登录 Claude") > y("订阅有效") && y("额度") > y("正在登录 Claude"))
  assert_true(t.find("打开授权页面，用 still.fail 要使用的 Claude 账号登录并同意授权") is Some(_))
  assert_true(y("粘贴授权码") > y("打开授权页面"))
  // nothing typed: 完成登录 there, but not to be pressed
  assert_true(t.find("完成登录") is Some(_))
  t.tap_text("粘贴授权码")
  t.type_text("abc-123")
  t.tap_text("完成登录")
  t.draw()
  assert_true(t.find("abc-123") is None, msg="sent, its field emptied")
}

///|
test "本机缓存: the drives' files kept, counted with the chats', let go when asked" {
  let t = settings_tester("kept")
  // (what is kept asked of the core as the page is first built: drawn with its answer)
  t.draw()
  // all of it first: 文件浏览, 38.5 MB of them; with the chats' 18.3 MB and the 900 KB of no chat known, 57.7 MB
  assert_true(t.find("文件浏览") is Some(_))
  assert_true(t.find("38.5 MB") is Some(_))
  assert_true(t.find("57.7 MB") is Some(_))
  // tapped, asked first; 删除: let go, read again
  t.tap_text("文件浏览")
  sheet_rested(t, "sf-present")
  // (its button: the words 删除 alone, not those that tell what it does)
  match t.words().iter().find_first(fn(w) { w.0 == "删除" }) {
    Some((_, x, y, w, h, _)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("no 删除")
  }
  // (asked again once it is let go, drawn with the answer: nothing of it left, its row gone)
  t.draw()
  t.draw()
  assert_true(t.find("38.5 MB") is None)
  assert_true(t.find("19.2 MB") is Some(_))
}

///|
test "本机缓存 with many chats: the ones keeping most first, all when asked, only the rows in view laid out" {
  let t = settings_tester("kept", shows="settings-kept-many")
  t.draw()
  // the first few, the one keeping most first: of the 200 made up the biggest, not the smallest
  let built = fn() { t.words().filter(fn(w) { w.0.has_prefix("测试会话 ") }).length() }
  let shows = fn(words : String) { t.words().iter().any(fn(w) { w.0 == words }) }
  assert_true(shows("整理发布清单"))
  assert_true(shows("测试会话 200"))
  assert_true(!shows("测试会话 1"))
  assert_eq(t.corner_faults(), [])
  t.scroll_to_end()
  t.draw()
  t.tap_text("显示全部 203 个")
  t.draw()
  // a block each: of 203 rows a screen's (one block of them all was built whole each frame, every row's words with it)
  t.scroll_to_end()
  t.draw()
  assert_true(shows("测试会话 1"))
  assert_true(built() > 0 && built() < 20)
  assert_eq(t.corner_faults(), [])
  // the last row taps as any
  t.tap_text("测试会话 1")
  nav_rested(t)
  assert_true(t.find("测试会话 1") is Some(_))
  assert_true(t.find("消息记录") is Some(_))
}

///|
test "本机缓存: a chat's files opened, each let go by its bin; those of no chat known apart" {
  let t = settings_tester("kept")
  t.draw()
  // the chat: its messages and its 2 files (KeptFiles.kt chat.both), what is kept of it all
  assert_true(t.find("消息 2.3 MB · 2 个文件 15.2 MB") is Some(_))
  assert_true(t.find("17.5 MB") is Some(_))
  // a chat of its messages alone: its size once, at its end
  assert_true(t.find("夜里的构建又失败了") is Some(_))
  assert_true(t.find("消息 40 KB") is None)
  // of no chat known: a part of all that is kept, of its own, its page named in full
  t.tap_text("其他文件")
  nav_rested(t)
  assert_true(t.find("无法确定所属对话的文件") is Some(_))
  t.back()
  nav_rested(t)
  t.tap_text("整理发布清单")
  t.run_for(@ui.move_most_ms)
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
  // its editor, agents let ask for it: 跟随默认 first, what it means under it; each of its own offered from it (Small:
  // the editor a sheet the window's width, its four side by side; seg_wbtest.mbt has them in a pick where they do not
  // fit)
  let e = settings_tester("vault-items", shows="settings-vault-editor")
  sheet_rested(e, "sf-present")
  assert_true(e.find("跟随默认") is None)
  e.click(Switch, label="允许 agent 申请")
  e.draw()
  assert_true(e.find("跟随默认") is Some(_))
  assert_true(e.find("批准这个密钥的申请时") is Some(_))
  assert_true(e.find("仅一次") is Some(_))
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
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a profile's page: who it is and whether it works, then its allowance, what it spent, who uses it, its models, how it runs, sharing, its account" {
  let t = profile_whole("profile:ws1/st1#cc")
  let y = fn(words : String) { t.find(words).unwrap().1 }
  // its head is its title: its name, what it is, its last check and when (no title over it)
  assert_true(y("订阅账号 · 只在 Studio") > y("Claude 主账号"))
  assert_true(y("订阅有效") > y("订阅账号 · 只在 Studio"))
  assert_true(t.find("5 分钟前检查") is Some(_))
  // then its parts by what it is come to for: how much is left and what it spent, who uses it, how it runs, whom it is
  // shared with, the account itself
  assert_true(y("额度") > y("订阅有效"))
  assert_true(y("5 小时") > y("额度") && t.find("本周") is Some(_))
  assert_true(y("近 7 天") > y("5 小时"))
  assert_true(y("使用它的连接") > y("近 7 天"))
  assert_true(y("选择模型（2 / 3）") > y("使用它的连接"))
  assert_true(y("默认 Fast") > y("选择模型（2 / 3）"))
  assert_true(y("分享给其他 station") > y("默认 Fast"))
  assert_true(y("同时用于 个人") > y("分享给其他 station"))
  assert_true(y("重新登录") > y("同时用于 个人"))
  // its models chosen in place: the whole list under it, the one off too
  assert_true(t.find("Haiku 5") is None)
  t.tap_text("选择模型（2 / 3）")
  t.draw()
  assert_true(t.find("收起") is Some(_))
  assert_true(t.find("Haiku 5") is Some(_))
}

///|
test "a profile in trouble: what is wrong a pill in its head before what its check said; its key masked on its account's card" {
  let t = profile_whole("profile:ws1/st1#k2")
  let (px, py) = t.find("没能使用").unwrap()
  let (cx, cy) = t.find("订阅有效").unwrap()
  assert_true((py - cy).abs() < 2.0 && cx > px)
  assert_true(t.find("sk-…a41f").unwrap().1 > t.find("API key").unwrap().1)
}

///|
test "a subscription's page signed in: 重新登录 and the way by hand, rows of its account" {
  let t = profile_whole("profile:ws1/st1#cc")
  let (_, by) = t.find("重新登录").unwrap()
  let (_, my) = t.find("也可以在服务器上手动登录").unwrap()
  assert_true(my > by)
  // the command to run by hand, shown once asked
  assert_true(t.find("claude setup-token") is None)
  t.tap_text("也可以在服务器上手动登录")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("claude setup-token") is Some(_))
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  // 重新登录: begun on the station, its steps on the page
  t.tap_text("重新登录")
  t.draw()
  t.draw()
  t.draw()
  assert_true(t.find("打开授权页面") is Some(_))
}

///|
test "a subscription's sign-in that failed: why, then 重新登录 with the way by hand beside it (Accounts.tsx SignIn)" {
  let t = settings_tester("profile:ws1/st1#cc", shows="settings-profile-login-failed")
  shown_on_page(t, "在机器上手动登录")
  let (_, why_y) = t.find("上次登录失败：授权码已过期").unwrap()
  let (bx, by) = t.find("重新登录").unwrap()
  let (mx, my) = t.find("在机器上手动登录").unwrap()
  assert_true(by > why_y)
  assert_true((my - by).abs() < 2.0 && mx > bx)
}

///|
test "a connect's page: its model the one its station's profiles turned on, at its effort and account" {
  let t = settings_tester("connect:ws1/st1#k1")
  assert_true(t.find("星火助手") is Some(_))
  assert_true(t.find("Opus 5.5") is Some(_))
  assert_true(t.find("自动分配") is Some(_))
  assert_true(t.find("尚未启用模型") is None)
}

///|
/// What was just presented, in: a sheet (with a finger short of the Large tier) at rest; a panel by what opened it or
/// a dialog (with a pointer) past its coming.
fn presented_in(t : @ui.Tester) -> Unit {
  let rest = @kit.sheet_rest("sf-present")
  t.run_for(if rest > t.time() { rest - t.time() } else { @ui.move_most_ms })
}
