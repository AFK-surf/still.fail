// Making a chat public on a phone (sfpages' publish.mbt, the same as a computer's; publish.mbt the info's links) over
// the fixture's chat: its sheet's links, the publishing over the screen with what a snapshot would hold, the attachments ticked, and a link revoked once asked.

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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  open_fixture("chat-info")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "公开分享: the chat's sheet lists its link, 复制 copies it" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  assert_true(t.find("公开分享") is Some(_))
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
test "公开分享: the sheet shows what a snapshot would hold; 发布 takes the attachments ticked, then its link" {
  let calls : Array[Made] = []
  let t = publish_core(calls)
  t.tap_text("公开分享")
  // the chat's sheet put down (to where it rests, gone), the publishing over the whole screen (the pages', as on a
  // computer)
  t.frame()
  t.run_for(@kit.sheet_rest("decide-sheet") - t.time())
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  assert_true(t.find("持有链接的任何人都可查看这些消息") is Some(_))
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
  // (the button, under the chat's name 整理发布清单)
  tap_last(t, "发布")
  let made = named(calls, "chat.publish")
  assert_eq(made.length(), 1)
  assert_eq(number(Some(made[0].params), "upto"), 9.0)
  match field(Some(made[0].params), "files") {
    Some(Array(fs)) => assert_eq(fs, [Json::string("f0")])
    _ => fail("no files said")
  }
  // published: the publishing gone, its link in the presenters' sheet
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("已发布") is Some(_))
  assert_true(t.find("https://share.still.fail/#st1key.p3.k3") is Some(_))
  t.tap_text("复制链接")
  assert_eq(t.clipboard(), "https://share.still.fail/#st1key.p3.k3")
}

///|
test "公开分享: 撤销 asks first, then revokes that link" {
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
