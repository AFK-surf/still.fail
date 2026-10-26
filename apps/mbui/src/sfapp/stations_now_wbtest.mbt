///|
test "wide: the rail's 用量 place, the pointer resting on it, offers 分享卡片, which copies its picture" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let place = t.query(Button, label="用量").unwrap()
  let (x, y, w, h) = place.rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // the card to share, opened from it: the picture, 复制图片 under it
  t.click(Button, label="分享卡片")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("用 1 个 Claude 订阅账号消耗了") is Some(_), msg="the picture's words beside its number")
  assert_true(t.find("一生万物，万物归一") is Some(_))
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
test "the card to share in a dialog: the subscriptions' weekly quota used as rings, the first's said round its share beside them, today and the last 7 days side by side, each day a bar, the chats at work, still.fail's line" {
  let src = fixture_app("share-card")
  share_card_laid(@ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0), false)
}

///|
test "the card to share on a phone: the rings smaller, what leads the first's share over them, today over the last 7 days, nothing cut short; 保存到相册 keeps the picture in the photo album" {
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
  // the first kind's said round its share, read down: what leads it (beside the rings with the share, or over them
  // both), the share large, what it is of under it; the other kind's the same in a line of its own
  let lead = word("用 6 个 Claude 订阅账号消耗了")
  let share = word("489%")
  let of = word("的周额度")
  assert_true(lead.length() == 1 && share.length() == 1 && of.length() == 1 && share[0].4 > of[0].4 * 2.0, msg="\{(lead, share, of)}")
  assert_true(
    lead[0].2 < share[0].2 && of[0].2 > share[0].2 && of[0].1 == share[0].1 && (lead[0].1 < share[0].1) == narrow,
    msg="\{(lead, share, of)}",
  )
  assert_true(t.find("用 2 个 ChatGPT 订阅账号消耗了 17% 的周额度") is Some(_))
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
    // the picture all in the sheet, over its button
    let line = word("一生万物，万物归一")
    let (_, by, _, _) = t.query(Button, label="保存到相册").unwrap().rect
    assert_true(line.length() == 1 && line[0].2 + line[0].4 <= by, msg="\{(line, by)}")
    // the other kind's line and the chats at work's each on one line (as tall as each other, both Meta's)
    match (t.rect_of("用 2 个 ChatGPT 订阅账号消耗了"), t.rect_of("9 个对话正在运行")) {
      (Some((_, _, _, oh)), Some((_, _, _, ch))) => assert_true(oh == ch, msg="\{(oh, ch)}")
      _ => fail("no other kind's line, or no chats at work")
    }
    // what it says on a line of its own, the more of it under it: neither broken onto two
    let lead = word("近 7 天 agent 跨设备执行了 312 个任务")
    let more = word("平均每个对话 5.2 个")
    assert_true(lead.length() == 1 && more.length() == 1 && lead[0].4 == more[0].4 && more[0].2 > lead[0].2, msg="\{(lead, more)}")
  }
  assert_true(t.find("一生万物，万物归一") is Some(_))
  assert_eq(t.squeeze_faults(), [])
  assert_eq(t.corner_faults(), [])
  assert_eq(t.contrast_faults(), [])
}

///|
test "the 用量 page: 分享卡片 beside its days once something was spent (no pointer to rest on 用量's card), opening the card to share" {
  let t = place_tester("usage")
  assert_eq(@sf.presenting(), false)
  t.click(Button, label="分享卡片")
  t.frame()
  assert_eq(@sf.presenting(), true)
}
