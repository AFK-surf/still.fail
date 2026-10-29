// Sharing a chat as a picture on a phone (sfpages' publish.mbt, the same as keyboard and mouse's; publish.mbt the
// info's rows) over the fixture's chat: its sheet's 分享图片 and the public links made before, the page with the picture
// as it would be, the attachments ticked, the picture taken and kept in the photo album, and a link revoked once asked.

///|
/// The chat's sheet open over the fixture's chat; `chat.publishPreview` answered with fix_preview, `chat.publish` with
/// its link, the rest with nothing.
fn publish_core(calls : Array[Made]) -> @ui.Tester {
  reset()
  let base = fixture("chat-info")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "chat.publishPreview" => done(Ok(fix_preview()))
        "chat.publish" =>
          done(
            Ok({
              "id": "p3",
              "link": "https://share.still.fail/#st1key.p3.k3",
              "createdAt": 0,
              "byName": "林",
              "mayRevoke": true,
            }),
          )
        _ => done(Ok(Json::object({})))
      }
    },
  }
  open_fixture_over("chat-info", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "分享图片: the chat's sheet opens it, and lists the public links made before; 复制 copies one" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  assert_true(t.find("分享图片") is Some(_))
  // when, then who: their face (their initial, without a picture) before their name
  assert_true(t.find("10 分钟前 · ") is Some(_) && t.find("Alice") is Some(_))
  assert_true(t.find("2 天前 · ") is Some(_) && t.find("Bob") is Some(_))
  // Bob's only copied: the viewer did not publish it (the one 撤销 is on the viewer's own row)
  let (_, mine) = t.find("Alice").unwrap()
  let (_, revoke) = t.find_last("撤销").unwrap()
  assert_true((revoke - mine).abs() < 1.0)
  // (Bob's 复制, the last, under 复制会话链接: the sheet's last row, brought up from under its foot)
  match t.find_last("复制") {
    Some((_, y)) if y > publish_fold => t.wheel(195.0, publish_fold, y - publish_fold)
    _ => ()
  }
  tap_last(t, "复制")
  assert_eq(t.clipboard(), "https://share.still.fail/#B5CrvEZwwZq7oct4Vs0Ld90SJHgZO4uOwQdhtJsLRNE.Qm9vSzVnUkN2dUdS.k3Yq-p1")
  assert_true(t.find("已复制链接") is Some(_))
}

///|
test "分享图片: the page shows the picture as it would be, 取消 and 保存到相册 at its foot; 保存到相册 keeps it in the album, without what was left out" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  t.tap_text("分享图片")
  // the chat's sheet put down (to where it rests, gone), the page over the whole screen (the pages', as on a computer)
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // the picture as it would be: the chat's name over its messages, still.fail's at its foot; what was hidden said
  // under its message (the floating bar of a small screen says no more than its name)
  assert_true(t.find("部署登录页") is Some(_))
  assert_true(t.find("截图、日志和构建缓存都附上了") is Some(_))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  // its messages as the chat's list draws them: the viewer's own at its end, in its bubble; an agent's request about a
  // vault item as the chat says it (allowed: how it ended), not the words its post has for where there is no card
  assert_true(picture_mine_at_end(t), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("已允许使用 Axiom 查询 token") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("申请使用「Axiom 查询 token」：查登录页的错误日志") is None)
  // the log and the cache left out: tapped, each is unticked (nothing opens); brought up from under the screen's foot
  // (a file's card says its name's stem and its extension apart, as the chat's)
  for _ in 0..<6 {
    match t.find("build-cache") {
      Some((_, y)) if y < publish_fold => break
      _ => t.wheel(195.0, 400.0, 300.0)
    }
  }
  t.tap_text(".log")
  t.tap_text(".tar")
  assert_true(@sfpages.publish_left_out("f1") && @sfpages.publish_left_out("f2"))
  assert_true(viewer.val is None)
  // nothing is published
  assert_true(t.query(Button, label="复制图片") is None)
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  assert_eq(named(calls, "chat.publish").length(), 0)
  // the picture taken: the chat's name, its messages, their times as dates, still.fail's; not the attachments left
  // out, nor the notes of what was hidden (for the one sharing it)
  let shots = t.shots()
  assert_eq(shots.length(), 1)
  let words = shots[0].join("|")
  assert_true(words.contains("部署登录页") && words.contains("截图、日志和构建缓存都附上了"), msg=words)
  assert_true(words.contains("10月15日 10:00") && !words.contains("分钟前"), msg=words)
  assert_true(!words.contains(".log") && !words.contains(".tar") && !words.contains("已隐藏 1 处"), msg=words)
  assert_true(words.contains("still.fail"), msg=words)
  // kept in the photo album, a PNG as wide as the picture on the page (the screen's 390, less the column of its boxes
  // to tick: a finger's 22 and 12) at the screen's scale, said once it is
  assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
  match png_size(t.kept()[0].2) {
    Some((pw, ph)) => assert_true(pw == 712 && ph > 600, msg="\{(pw, ph)}")
    None => fail("not a PNG")
  }
  assert_true(t.find("已保存到相册") is Some(_))
  // 取消, beside it at the foot, closes it: gone as a dialog goes
  t.click(Button, label="取消")
  t.run_for(@kit.pop_out_ms)
  assert_true(t.find("部署登录页") is None)
}

///|
test "分享图片: a message unticked fades on the page and is not in the picture" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  t.tap_text("分享图片")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // a box to tick for each message, all ticked; the agent's words (the second) left out
  let ticks = t.all(Checkbox, label="放进图片")
  assert_eq(ticks.length(), 4)
  assert_true(ticks.iter().all(fn(n) { n.check == Some(On) }))
  // in a column of their own before the words (the phone's picture: the pictures inline, at the words' start)
  assert_true(ticks_before_words(t, 0.0), msg=ticks.map(fn(n) { n.rect }).to_string())
  // its attachments not ticked: each has the composer's ✕ on its corner, which takes it out; then a ＋ puts it back
  assert_eq(t.all(Checkbox).length(), 4)
  let outs = t.all(Button, label="移出图片")
  assert_eq(outs.length(), 3)
  let (ox, oy, ow, oh) = outs[1].rect
  t.tap(ox + ow / 2.0, oy + oh / 2.0)
  assert_true(@sfpages.publish_left_out("f1"))
  assert_eq(t.all(Button, label="移出图片").length(), 2)
  let backs = t.all(Button, label="放回图片")
  assert_eq(backs.length(), 1)
  let (bx, by, bw, bh) = backs[0].rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_true(!@sfpages.publish_left_out("f1"))
  let (x, y, w, h) = ticks[1].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(@sfpages.publish_message_left_out(6.0))
  assert_true(!@sfpages.publish_message_left_out(4.0))
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  let words = t.shots()[0].join("|")
  assert_true(words.contains("截图、日志和构建缓存都附上了") && !words.contains("跑了 42 秒"), msg=words)
}

///|
/// Whether the picture's boxes to tick (one for each of fix_preview's four messages) stand in one column of their own
/// before its words, 12 short of where they start (its title's start, less the pictures' `reach` out in the margin
/// before them), not over a message; each on the middle of its message's first line: the viewer's own words, Ana's
/// name over hers.
fn ticks_before_words(t : @ui.Tester, reach : Double) -> Bool {
  let ticks = t.all(Checkbox, label="放进图片")
  guard ticks.length() == 4 &&
    t.rect_of("部署登录页") is Some((title_x, _, _, _)) &&
    t.rect_of("帮我把登录页部署到预发") is Some((_, mine_y, _, mine_h)) else {
    return false
  }
  let (x, _, w, _) = ticks[0].rect
  // (Ana's name on the page: past its boxes, not the chat's list's under it)
  guard t.words().iter().find_first(fn(n) { n.0 == "Ana" && n.1 > x }) is Some((_, _, ana_y, _, ana_h, _)) else {
    return false
  }
  let middle = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
  // (the viewer's own words' first line: however many it wraps to)
  let words_line = t.ctx().style_size(@sf.theme().t.words).1
  ticks.iter().all(fn(n) { n.rect.0 == x }) &&
  x + w + 12.0 <= title_x - reach &&
  (middle(ticks[0].rect) - (mine_y + dmin(mine_h, words_line) / 2.0)).abs() < 0.5 &&
  (middle(ticks[3].rect) - (ana_y + ana_h / 2.0)).abs() < 0.5
}

///|
/// Whether the viewer's message stands further along than someone else's in the picture shown (its bubble at the
/// column's end, as the chat's list has it).
fn picture_mine_at_end(t : @ui.Tester) -> Bool {
  // (where their words start: however wide each wraps to, the viewer's in its bubble further along)
  match (t.rect_of("帮我把登录页部署到预发，token 是 [已隐藏]"), t.rect_of("截图、日志和构建缓存都附上了")) {
    (Some((mx, _, _, _)), Some((ox, _, _, _))) => mx > ox
    _ => false
  }
}

///|
test "分享图片: 撤销 asks first, then revokes that public link" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  t.tap_text("撤销")
  assert_eq(named(calls, "chat.unpublish").length(), 0)
  assert_true(t.find("撤销此链接？") is Some(_))
  tap_last(t, "撤销")
  let revoked = named(calls, "chat.unpublish")
  assert_eq(revoked.length(), 1)
  assert_eq(text(Some(revoked[0].params), "id"), "p2")
  assert_eq(number(Some(revoked[0].params), "thread"), 7.0)
}

///|
/// Taps the last words holding `s` (drawn last: the sheet's, over what is under it).
fn tap_last(t : @ui.Tester, s : String) -> Unit {
  match t.find_last(s) {
    Some((x, y)) => t.tap(x, y)
    None => abort("no text \"\{s}\" on screen")
  }
}

///|
/// Where the chat's sheet's rows are well in view on a phone (844 high): a row under it is brought up to it.
let publish_fold : Double = 600.0
