// 连接 and a connect's page (connects.mbt, connect.mbt, slack_app.mbt) alone, at each width, with a finger and with a
// mouse: the connects with how they run, one's page with how it runs and what is done to it
// less often (its ⋯, the presenters' menu).

///|
test "连接, at each width and with either hand: the connects, each with how it runs; one pressed, its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Connects(""), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_true(t.find("值班机器人") is Some(_), msg=at)
    let (x, y) = t.find_last("值班机器人").unwrap()
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.pages().iter().any(fn(p) { p is Setting(Connect(_, _)) }), msg=at)
  }
}

///|
test "连接 with a waiting Slack app and pictured and unpictured connects: cards apart, titles lined up, controls and facts across the row's middle" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Connects(""), w, platform~, mode="settings-connects")
    let at = "\{w} platform \{platform}"
    assert_eq(t.corner_faults(), [], msg=at)
    assert_eq(t.gap_faults(), [], msg=at)
    let waiting_title = drawn(t, "Gemini-Monoid")
    let pictured_title = drawn(t, "星火助手")
    let unpictured_title = drawn(t, "值班机器人")
    // (every row's lead is 28 wide, so pictured, unpictured and waiting titles start at the same x)
    assert_true((pictured_title.0 - unpictured_title.0).abs() <= 0.5, msg="\{at}: \{Repr(pictured_title)} vs \{Repr(unpictured_title)}")
    assert_true((pictured_title.0 - waiting_title.0).abs() <= 0.5, msg="\{at}: \{Repr(pictured_title)} vs \{Repr(waiting_title)}")
    let wait_card = ground_round(t, waiting_title)
    let list_card = ground_round(t, pictured_title)
    assert_true(list_card.1 - (wait_card.1 + wait_card.3) >= 20.0, msg="\{at}: \{Repr(wait_card)} over \{Repr(list_card)}")
    let more = t.query(Button, label=@sf.t("web-pages.connects.removeHere")).unwrap().rect
    let wait_mid = wait_card.1 + wait_card.3 / 2.0
    assert_true(((more.1 + more.3 / 2.0) - wait_mid).abs() <= 1.0, msg="\{at}: more \{Repr(more)} in \{Repr(wait_card)}")
    if laid_wide(w) {
      let cont = t.query(Button, label="继续").unwrap().rect
      assert_true(((cont.1 + cont.3 / 2.0) - wait_mid).abs() <= 1.0, msg="\{at}: continue \{Repr(cont)} in \{Repr(wait_card)}")
      if w >= 1100.0 {
        let owner = drawn(t, "林（你）")
        let online = t.words().filter(fn(word) { word.0 == "在线" && (word.2 - owner.1).abs() < 8.0 })[0]
        assert_true(online.1 > owner.0 + owner.2 + 8.0, msg="\{at}: owner \{Repr(owner)} before online \{Repr(online)}")
        let row_top = pictured_title.1
        let sub = drawn(t, "每个 thread 一个会话 · Claude Code · Opus 5.5")
        let row_mid = (row_top + sub.1 + sub.3) / 2.0
        assert_true(((owner.1 + owner.3 / 2.0) - row_mid).abs() <= 2.0, msg="\{at}: owner \{Repr(owner)} vs row_mid \{row_mid}")
      }
    }
  }
}

///|
test "a connect's page, at each width and with either hand: who it is, how it runs; its ⋯ a menu of what is done less often" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Connect("ws1/st1", "k1"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = t.query(Button, label="更多").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
  }
}

///|
test "a connect's Slack app, at a phone's width: its fold opened, the buddies and the makers to pick from, a picture to upload" {
  let calls : Array[String] = []
  let t = setting_tester(Connect("ws1/st1", "k1"), 390.0, platform=2, over=fn(s) {
    { ..s, call: fn(name, params, done) { calls.push(name); (s.call)(name, params, done) } }
  })
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  t.draw()
  let (x, y, w, h) = t.query(Link, label="Slack app").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  // the core's buddies asked for once, then the makers after them
  assert_eq(calls.filter(fn(m) { m == "buddies" }).length(), 1)
  for a in ["后端接口", "移动应用", "写文档", "Anthropic", "OpenAI"] {
    assert_true(t.query(Button, label=a) is Some(_), msg=a)
  }
  // a picture of one's own: its icon's button
  assert_true(t.query(Button, label="上传图片") is Some(_))
}

///|
test "a connect's Slack app's permissions opened: each section's 全选 at its line's end, its title at its start" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Connect("ws1/st1", "k1"), w, platform~)
    t.draw()
    let (x, y, bw, bh) = t.query(Link, label="Slack app").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    t.run_for(@ui.move_most_ms)
    let (x, y, bw, bh) = drawn(t, "权限 · 已开启 4 / 16 项")
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.draw()
    t.run_for(@ui.move_most_ms)
    // (as far in from the card's right as its title from its left)
    let title = drawn(t, "消息")
    let all = drawn(t, "全选")
    let card = ground_round(t, title)
    let start = title.0 - card.0
    let end = card.0 + card.2 - (all.0 + all.2)
    assert_true((start - end).abs() < 0.5, msg="\{at}: the title \{start} in at the start, 全选 \{end} at the end")
  }
}

///|
/// A connect's Slack app open `w` wide, pointed at as `platform` says, its picture's room's own drawn.
fn slack_app_tester(w : Double, platform : Int) -> @ui.Tester {
  let t = setting_tester(Connect("ws1/st1", "k1"), w, platform~)
  t.add_pixels("https://app.still.fail/avatars/backend.webp", 2, 2, FixedArray::make(16, b'\xFF'))
  t.draw()
  let (x, y, bw, bh) = t.query(Link, label="Slack app").unwrap().rect
  t.tap(x + bw / 2.0, y + bh / 2.0)
  t.frame()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The middle of what a screen reader finds as `role` named `label`.
fn middle_of(t : @ui.Tester, role : @view.Role, label : String) -> (Double, Double) raise {
  guard t.query(role, label~) is Some(n) else { fail("no \{label}") }
  let (x, y, w, h) = n.rect
  (x + w / 2.0, y + h / 2.0)
}

///|
test "a connect's Slack app: its picture's room edged 1 in the line's colour" {
  let t = slack_app_tester(390.0, 2)
  let (x, y) = middle_of(t, Button, "上传图片")
  assert_eq(edge_round(t, x, y), (1.0, edge_shown(t, x, y, @ui.tree_theme().color(Line))), msg="at \{x},\{y}: \{edges_at(t, x, y)}")
}

///|
test "a connect's Slack app: its colour's swatch edged 1 in the border's colour" {
  let t = slack_app_tester(390.0, 2)
  // (the swatch: the one square drawn 28 across, beside the colour's field)
  let swatches = t.drawn_rects().filter(fn(r) { r.2 == 28.0 && r.3 == 28.0 })
  assert_eq(swatches.length(), 1, msg="\{Repr(swatches)}")
  let (sx, sy, _, _, _) = swatches[0]
  let (x, y) = (sx + 14.0, sy + 14.0)
  assert_eq(edge_round(t, x, y), (1.0, edge_shown(t, x, y, @ui.tree_theme().color(Border))), msg="at \{x},\{y}: \{edges_at(t, x, y)}")
}

///|
test "a connect's Slack app's buddies to pick from, with a mouse: the picked edged 2 in the words' colour, the rest 1 in the line's, one under the pointer 1 in the field's hover" {
  let t = slack_app_tester(1280.0, 0)
  let th = @ui.tree_theme()
  // (移动应用 picked by a press; 后端接口 not)
  let (px, py) = middle_of(t, Button, "移动应用")
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="移动应用").unwrap().selected == Some(true))
  let (ox, oy) = middle_of(t, Button, "后端接口")
  assert_eq(edge_round(t, px, py), (2.0, edge_shown(t, px, py, th.color(Fg))), msg="picked at \{px},\{py}: \{edges_at(t, px, py)}")
  assert_eq(edge_round(t, ox, oy), (1.0, edge_shown(t, ox, oy, th.color(Line))), msg="not picked: \{edges_at(t, ox, oy)}")
  t.move_to(ox, oy)
  t.run_for(@ui.move_most_ms)
  assert_eq(edge_round(t, ox, oy), (1.0, edge_shown(t, ox, oy, th.color(FieldHover))), msg="under the pointer: \{edges_at(t, ox, oy)}")
  t.move_to(1.0, 1.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(edge_round(t, ox, oy), (1.0, edge_shown(t, ox, oy, th.color(Line))), msg="the pointer gone")
}

///|
/// The edge drawn round (x, y) (its width, its colour RRGGBBAA), of the least rect drawn there with one: none, (0, 0).
/// One on its own ground is drawn over it (as a host draws a translucent edge, mbui's view_host): what it shows as.
fn edge_round(t : @ui.Tester, x : Double, y : Double) -> (Double, Int64) {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  let mut best : (Double, Double, Int64)? = None
  for a in t.drawn_instances() {
    if a[5] == 0.0 && a[6] > 0.0 && a[15] > 0.0 && x >= a[0] && x <= a[0] + a[2] && y >= a[1] && y <= a[1] + a[3] {
      let color = (ch(a[12]) << 24) | (ch(a[13]) << 16) | (ch(a[14]) << 8) | ch(a[15])
      match best {
        Some((area, _, _)) if area <= a[2] * a[3] => ()
        _ => best = Some((a[2] * a[3], a[6], color))
      }
    }
  }
  match best {
    Some((_, w, c)) => (w, c)
    None => (0.0, 0L)
  }
}

///|
/// Colour `c` as an edge shows it on the ground drawn round (x, y) (the least ground there: @ui.over), or as it is
/// where none is.
fn edge_shown(t : @ui.Tester, x : Double, y : Double, c : Int64) -> Int64 {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  let mut best : (Double, Int64)? = None
  for a in t.drawn_instances() {
    if a[5] == 0.0 && a[11] > 0.0 && x >= a[0] && x <= a[0] + a[2] && y >= a[1] && y <= a[1] + a[3] {
      let g = (ch(a[8]) << 24) | (ch(a[9]) << 16) | (ch(a[10]) << 8) | ch(a[11])
      match best {
        Some((area, _)) if area <= a[2] * a[3] => ()
        _ => best = Some((a[2] * a[3], g))
      }
    }
  }
  match best {
    Some((_, g)) => @ui.over(g, c)
    None => c
  }
}

///|
/// Every rect drawn round (x, y), with its edge: what a failure says.
fn edges_at(t : @ui.Tester, x : Double, y : Double) -> String {
  t.drawn_instances().filter(fn(a) { a[5] == 0.0 && x >= a[0] && x <= a[0] + a[2] && y >= a[1] && y <= a[1] + a[3] }).map(fn(a) {
    "\{a[0]},\{a[1]} \{a[2]}x\{a[3]} e\{a[6]} a\{a[15]}"
  }).join("; ")
}
