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
  assert_true(t.find("个 agent 正在为我工作") is Some(_), msg="the picture's words beside its number")
  assert_true(t.find("扫码打开 still.fail") is Some(_))
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
test "the card to share: the number of agents at work large, where, each station at work with how many and its machine, the models, the last 7 days, still.fail's QR code; none for a station at rest" {
  reset()
  let src = fixture_app("share-card")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@kit.presence_in_ms)
  let word = fn(s : String) { t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }) }
  let number = word("9")
  assert_true(number.length() == 1 && word("个 agent 正在为我工作").length() == 1, msg="\{number}")
  // the stations at work, two a line in their order; MBA, at rest, not on it
  let names = ["Studio", "ccvm", "Mini1"].map(fn(n) { word(n) })
  assert_true(names.iter().all(fn(n) { n.length() == 1 }), msg="\{names}")
  assert_true(names[0][0].2 == names[1][0].2 && names[0][0].1 < names[1][0].1 && names[1][0].2 < names[2][0].2)
  assert_eq(word("MBA").length(), 0)
  // how many at the end of each one's line, its machine under it; the models at work; the last 7 days
  let fives = word("×5").filter(fn(w) { (w.2 - names[0][0].2).abs() < 8.0 })
  assert_true(fives.length() == 1 && fives[0].1 > names[0][0].1 + names[0][0].3, msg="\{fives}")
  assert_true(t.find("Apple M2 Max · 64 GB") is Some(_) && t.find("分布在 3 台设备 · 3 种模型") is Some(_))
  assert_true(t.find("48,231 次") is Some(_) && t.find("$1,911") is Some(_))
  assert_true(t.find("扫码打开 still.fail") is Some(_) && t.find("在任何一台上，用所有设备") is Some(_))
  assert_eq(t.corner_faults(), [])
  assert_eq(t.contrast_faults(), [])
}
