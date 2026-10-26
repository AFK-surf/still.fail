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
  assert_true(t.find("10 分钟前 · Alice") is Some(_))
  assert_true(t.find("2 天前 · Bob") is Some(_))
  // Bob's only copied: the viewer did not publish it (the one 撤销 is on the viewer's own row)
  let (_, mine) = t.find("10 分钟前 · Alice").unwrap()
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
test "分享图片: the page shows the picture as it would be; 保存到相册 keeps it in the album, without what was left out" {
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
  assert_true(t.find("部署登录页") is Some(_))
  assert_true(t.find("截图、日志和构建缓存都附上了") is Some(_))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  assert_true(t.find("共隐藏 1 处疑似机密") is Some(_))
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
  // kept in the photo album, a PNG as wide as the screen at its scale, said once it is
  assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
  match png_size(t.kept()[0].2) {
    Some((pw, ph)) => assert_true(pw == 780 && ph > 600, msg="\{(pw, ph)}")
    None => fail("not a PNG")
  }
  assert_true(t.find("已保存到相册") is Some(_))
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
