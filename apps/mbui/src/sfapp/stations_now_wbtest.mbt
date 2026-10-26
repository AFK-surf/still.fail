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
  assert_true(t.find("用 1 个 Claude 订阅账号消耗了") is Some(_), msg="what leads the picture's number")
  assert_true(t.find("一生万物，万物归一") is Some(_))
  assert_eq(t.corner_faults(), [])
  t.click(Button, label="复制图片")
  t.frame()
  // the picture on the clipboard, as a PNG three pixels a point (as sharp from this window's two)
  match t.clipboard_png() {
    Some(png) =>
      match png_size(png) {
        Some((pw, ph)) => {
          assert_true(pw == 1080 && ph > 600, msg="\{(pw, ph)}")
          assert_eq(t.clipboard_label(), "still.fail")
        }
        None => fail("not a PNG")
      }
    None => fail("no picture copied")
  }
}

///|
test "the card to share is one picture, in a dialog as on a phone: what leads the first's share over the rings, the share beside them, today over the last 7 days, each day a bar, the chats at work, still.fail's line, each part in the same place" {
  // (windows with the room for all of it: @sf.whole_fitted draws it its own size; each its own app, the card opened
  // as it starts)
  let desk_src = fixture_app("share-card")
  let desk = @ui.Tester::new(fn(c) { view(c, desk_src) }, w=1440.0, h=1000.0, platform=0)
  share_card_laid(desk)
  let phone_src = fixture_app("share-card")
  let phone = @ui.Tester::new(fn(c) { view(c, phone_src) }, w=430.0, h=932.0, platform=2)
  share_card_laid(phone)
  // 「分享图片不应该分电脑和手机」: each part as far from what leads the share in either
  let (at_desk, at_phone) = (picture_parts(desk), picture_parts(phone))
  assert_eq(at_desk.map(fn(p) { p.0 }), picture_part_words)
  assert_eq(at_desk, at_phone)
}

///|
test "the card to share in a short window, in a 360 phone's sheet: all of it seen, drawn smaller; what is copied or kept the same picture, as large, wherever it is shared from" {
  let shared = fn(w : Double, h : Double, platform : Int) -> (Int, Int) raise {
    let src = fixture_app("share-card")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform~)
    t.run_for(@kit.presence_in_ms)
    assert_eq(t.squeeze_faults(), [])
    let png = if platform == 2 {
      t.click(Button, label="保存到相册")
      t.run_for(@kit.presence_in_ms)
      t.kept()[0].2
    } else {
      t.click(Button, label="复制图片")
      t.frame()
      t.clipboard_png().unwrap()
    }
    png_size(png).unwrap()
  }
  let (w0, h0) = shared(1440.0, 1000.0, 0)
  assert_eq(w0, 1080)
  for at in [(1280.0, 800.0, 0), (1280.0, 640.0, 0), (360.0, 740.0, 2)] {
    // (the whole picture, not the part of it a scroll shows; drawn apart, not as the window shows it)
    let got = shared(at.0, at.1, at.2)
    assert_true(got == (w0, h0), msg="\{(at, got, w0, h0)}")
  }
}

///|
/// The words of the picture whose places say how it is laid out (each said alone, not a part of a line of several).
// kept across runs: a table, never written
let picture_part_words : Array[String] = [
  "10月26日 04:12", "489%", "的周额度", "今天", "12 个", "近 7 天", "57 个", "$1,911", "10/20", "10/26", "平均每个对话 5.2 个",
  "一生万物，万物归一",
]

///|
/// Where each of picture_part_words is in the picture `t` shows, from what leads its share (用 6 个 Claude 订阅账号消耗了),
/// rounded to the point.
fn picture_parts(t : @ui.Tester) -> Array[(String, Int, Int)] {
  let words = t.words().filter(fn(w) { w.5 > 0.5 })
  let lead = words.filter(fn(w) { w.0 == "用 6 个 Claude 订阅账号消耗了" })
  if lead.length() != 1 {
    return []
  }
  let (lx, ly) = (lead[0].1, lead[0].2)
  let parts = []
  for s in picture_part_words {
    // (in the picture: under its head, as wide as it is; 今天 is the chats' heading too)
    for w in words {
      if w.0 == s && w.1 > lx - 40.0 && w.1 < lx + 360.0 && w.2 > ly - 40.0 {
        parts.push((s, (w.1 - lx).round().to_int(), (w.2 - ly).round().to_int()))
        break
      }
    }
  }
  parts
}

///|
test "the card to share on a phone: the picture as wide as its sheet lets it, nothing cut short; 保存到相册 keeps the picture in the photo album" {
  let src = fixture_app("share-card")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  share_card_laid(t)
  // a phone keeps pictures in its photo album: the picture kept there, a PNG three pixels a point, said once it is
  assert_true(t.query(Button, label="复制图片") is None)
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
  match png_size(t.kept()[0].2) {
    Some((pw, ph)) => assert_true(pw == 1080 && ph > 900, msg="\{(pw, ph)}")
    None => fail("not a PNG")
  }
  assert_true(t.find("已保存到相册") is Some(_))
}

///|
/// The card to share as `t` shows it: laid out the one way.
fn share_card_laid(t : @ui.Tester) -> Unit raise {
  t.run_for(@kit.presence_in_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  // the first kind's said round its share, read down: what leads it over the rings and the share, the share large,
  // what it is of under it; each other kind a line of its own, its ring's key: its name, its accounts, its share at
  // the line's end (the shares one under another)
  let lead = word("用 6 个 Claude 订阅账号消耗了")
  let share = word("489%")
  let of = word("的周额度")
  assert_true(lead.length() == 1 && share.length() == 1 && of.length() == 1 && share[0].4 > of[0].4 * 2.0, msg="\{(lead, share, of)}")
  assert_true(
    lead[0].2 < share[0].2 && of[0].2 > share[0].2 && of[0].1 == share[0].1 && lead[0].1 < share[0].1,
    msg="\{(lead, share, of)}",
  )
  let keys = [("ChatGPT 订阅", "17%"), ("OpenCode Go 订阅", "6%")].map(fn(k) { (word(k.0), word("2 个账号"), word(k.1)) })
  for k in keys {
    let (name, accounts, used) = k
    assert_true(name.length() == 1 && accounts.length() == 2 && used.length() == 1, msg="\{k}")
    // (on its line: its accounts after its name, its share at the end)
    assert_true(used[0].1 > name[0].1 + name[0].3 && (used[0].2 - name[0].2).abs() < 2.0, msg="\{k}")
  }
  assert_true((keys[0].2[0].1 + keys[0].2[0].3 - (keys[1].2[0].1 + keys[1].2[0].3)).abs() < 0.5, msg="\{keys}")
  // today over the last 7 days (under the share: 今天 is the chats' heading too); each day's date under its bar
  let today = word("今天").filter(fn(w) { w.2 > share[0].2 })
  let week = word("近 7 天")
  assert_true(today.length() == 1 && week.length() == 1, msg="\{(today, week)}")
  assert_true(today[0].1 == week[0].1 && today[0].2 < week[0].2, msg="\{(today, week)}")
  assert_true(word("12 个").length() == 1 && word("57 个").length() == 1 && word("$1,911").length() == 1)
  let days = ["10/20", "10/26"].map(fn(d) { word(d) })
  assert_true(days.iter().all(fn(d) { d.length() == 1 }) && days[0][0].1 < days[1][0].1, msg="\{days}")
  // the chats at work now, the tasks run across devices, and still.fail's line
  assert_true(t.find("9 个对话正在运行") is Some(_) && t.find("今天的对话分布在 3 台设备") is Some(_))
  assert_true(t.find("近 7 天 agent 跨设备执行了 312 个任务") is Some(_) && t.find("平均每个对话 5.2 个") is Some(_))
  // the picture all in its sheet or dialog, over its button
  let line = word("一生万物，万物归一")
  let button = match t.query(Button, label="保存到相册") {
    Some(b) => b
    None => t.query(Button, label="复制图片").unwrap()
  }
  assert_true(line.length() == 1 && line[0].2 + line[0].4 <= button.rect.1, msg="\{(line, button.rect)}")
  // another kind's line and the chats at work's each on one line (as tall as each other, both Meta's)
  match (t.rect_of("OpenCode Go 订阅"), t.rect_of("9 个对话正在运行")) {
    (Some((_, _, _, oh)), Some((_, _, _, ch))) => assert_true(oh == ch, msg="\{(oh, ch)}")
    _ => fail("no other kind's line, or no chats at work")
  }
  // what it says on a line of its own, the more of it under it: neither broken onto two
  let tasks = word("近 7 天 agent 跨设备执行了 312 个任务")
  let more = word("平均每个对话 5.2 个")
  assert_true(tasks.length() == 1 && more.length() == 1 && tasks[0].4 == more[0].4 && more[0].2 > tasks[0].2, msg="\{(tasks, more)}")
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
