///|
test "wide: the rail's Station place, the pointer resting on it, says how many agents are at work on each station; 分享卡片 copies its picture" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let place = t.query(Button, label="Station：" + @sfdesk.rail_stations_label(fixture("home"), "ws1")).unwrap()
  let (x, y, w, h) = place.rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // (the card's words: beside the rail, the new chat's page under it says Studio too)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 && w.1 < 400.0 }) }
  // all of them in a line over the stations, each with what it is doing at its end (the core's words)
  let head = word("1 个 agent 正在运行")
  let studio = word("Studio")
  let busy = word("1 个正在运行")
  let mba = word("MBA")
  let away = word("离线")
  assert_true(
    head.length() == 1 && studio.length() == 1 && busy.length() == 1 && mba.length() == 1 && away.length() == 1,
    msg="\{(head, studio, busy, mba, away)}",
  )
  assert_true(head[0].2 < studio[0].2 && studio[0].2 < mba[0].2, msg="the line over the stations, in their order")
  assert_true(away[0].1 > mba[0].1 + mba[0].3, msg="what it is doing after its name")
  // nothing of it, nor of anything else, against the corners' rule; no tip over it in its place
  assert_eq(t.corner_faults(), [])
  // the card to share, opened from it: the picture, 复制图片 under it
  t.click(Button, label="分享卡片")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("1 个 Claude 订阅账号的周额度") is Some(_), msg="the picture's words beside its number")
  assert_true(t.find("拿起任何一台，就能用上所有设备") is Some(_))
  assert_eq(t.corner_faults(), [])
  t.click(Button, label="复制图片")
  t.frame()
  // what was drawn of the picture on the clipboard, as a PNG as large as it is drawn
  match t.clipboard_png() {
    Some(png) =>
      match png_size(png) {
        Some((pw, ph)) => {
          assert_true(pw > 300 && ph > 300, msg="\{(pw, ph)}")
          assert_eq(t.clipboard_label(), "still.fail")
        }
        None => fail("not a PNG")
      }
    None => fail("no picture copied")
  }
}

///|
test "the card to share in a dialog: the subscriptions' weekly quota used as rings, the first's share large and what it is of beside them, today and the last 7 days side by side, each day a bar, the chats at work, still.fail's line" {
  let src = fixture_app("share-card")
  share_card_laid(@ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0), false)
}

///|
test "the card to share on a phone: the rings smaller, what the first's share is of under them, today over the last 7 days, nothing cut short; 保存到相册 keeps the picture in the photo album" {
  let src = fixture_app("share-card")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  share_card_laid(t, true)
  // a phone keeps pictures in its photo album: what is drawn of the picture kept there, a PNG, said once it is
  assert_true(t.query(Button, label="复制图片") is None)
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
  match png_size(t.kept()[0].2) {
    Some((pw, ph)) => assert_true(pw > 300 && ph > 300, msg="\{(pw, ph)}")
    None => fail("not a PNG")
  }
  assert_true(t.find("已保存到相册") is Some(_))
}

///|
/// The card to share as `t` shows it, laid out narrow or not.
fn share_card_laid(t : @ui.Tester, narrow : Bool) -> Unit raise {
  t.run_for(@kit.presence_in_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // the first kind's share large; what it is of beside the rings under it, or under them both; the other kind's in a
  // line of its own
  let share = word("489%")
  let of = word("6 个 Claude 订阅账号的周额度")
  assert_true(share.length() == 1 && of.length() == 1 && share[0].4 > of[0].4 * 2.0, msg="\{(share, of)}")
  assert_true(of[0].2 > share[0].2 && (of[0].1 < share[0].1) == narrow, msg="\{(share, of)}")
  assert_true(t.find("17% 2 个 ChatGPT 订阅账号的周额度") is Some(_))
  // today and the last 7 days side by side, or one over the other (under the share: 今天 is the chats' heading too);
  // each day's date under its bar
  let today = word("今天").filter(fn(w) { w.2 > share[0].2 })
  let week = word("近 7 天")
  assert_true(today.length() == 1 && week.length() == 1, msg="\{(today, week)}")
  if narrow {
    assert_true(today[0].1 == week[0].1 && today[0].2 < week[0].2, msg="\{(today, week)}")
  } else {
    assert_true(today[0].2 == week[0].2 && today[0].1 < week[0].1, msg="\{(today, week)}")
  }
  assert_true(word("12 个").length() == 1 && word("57 个").length() == 1 && word("$1,911").length() == 1)
  let days = ["10/20", "10/26"].map(fn(d) { word(d) })
  assert_true(days.iter().all(fn(d) { d.length() == 1 }) && days[0][0].1 < days[1][0].1, msg="\{days}")
  // the chats at work now, the tasks run across devices, and still.fail's line
  assert_true(t.find("9 个对话正在运行") is Some(_) && t.find("分布在 3 台设备") is Some(_))
  assert_true(t.find("近 7 天 agent 跨设备执行了 312 个任务") is Some(_) && t.find("平均每个对话 5.2 个") is Some(_))
  if narrow {
    // what it says on a line of its own, the more of it under it: neither broken onto two
    let lead = word("近 7 天 agent 跨设备执行了 312 个任务")
    let more = word("平均每个对话 5.2 个")
    assert_true(lead.length() == 1 && more.length() == 1 && lead[0].4 == more[0].4 && more[0].2 > lead[0].2, msg="\{(lead, more)}")
  }
  assert_true(t.find("拿起任何一台，就能用上所有设备") is Some(_))
  assert_eq(t.squeeze_faults(), [])
  assert_eq(t.corner_faults(), [])
  assert_eq(t.contrast_faults(), [])
}
