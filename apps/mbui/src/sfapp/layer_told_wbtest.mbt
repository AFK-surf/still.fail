// What the frame opens over the pages as an old view's layer (⌘K's panel, sfdesk's switcher.mbt; sharing a chat as a
// picture, sfpages' publish.mbt) dismissed by the hand (Escape, back, a press outside it): closed as the input is taken,
// as that input's own moment, no frame after it; the frame after closing nothing more, the next opening its own.

///|
/// 大屏 (1280 wide, a mouse's), ⌘K opened and `words` typed.
fn switcher_typed(words : String) -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.draw()
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  if words != "" {
    t.type_text(words)
    t.frame()
  }
  t
}

///|
/// ⌘K open with words typed, dismissed by `how` (as the host hands it on, no frame after it): whether it is open and
/// what it holds typed then, once a frame is drawn after, and as ⌘K opens it again and a frame after that.
fn switcher_dismissed(how : (@ui.Tester) -> Unit) -> Array[(Bool, String)] {
  let t = switcher_typed("签名")
  let seen = [(@sfdesk.switcher_open(), @sfpages.finder_query())]
  how(t)
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_query()))
  t.draw()
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_query()))
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_query()))
  t.frame()
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_query()))
  seen
}

///|
let switcher_closed_seen : Array[(Bool, String)] = [
  (true, "签名"),
  (false, ""),
  (false, ""),
  (true, ""),
  (true, ""),
]

///|
test "⌘K dismissed by Escape: closed as the key is taken, what was typed let go; the frame after closes nothing more, ⌘K again its own" {
  let seen = switcher_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) })
  assert_eq(seen, switcher_closed_seen)
}

///|
test "⌘K dismissed by back: closed as back is taken; the frame after closes nothing more, ⌘K again its own" {
  let seen = switcher_dismissed(fn(t) { t.back_raw(2, 0.0, t.time()) })
  assert_eq(seen, switcher_closed_seen)
}

///|
test "⌘K dismissed by a press outside its panel: closed as the press goes down; the frame after closes nothing more, ⌘K again its own" {
  let down : Array[(Bool, String)] = []
  let seen = switcher_dismissed(fn(t) {
    t.touch_at(0, 20.0, 780.0, t.time())
    // (as the press goes down, before it is let go)
    down.push((@sfdesk.switcher_open(), @sfpages.finder_query()))
    t.touch_at(2, 20.0, 780.0, t.time())
  })
  assert_eq((down, seen), ([(false, "")], switcher_closed_seen))
}

///|
test "⌘K in one kind's list, Escape: back to all of them, still open, as the key is taken; a second Escape closes it" {
  let t = switcher_typed("签名")
  guard t.find_last("查看更多") is Some((x, y)) else { fail("no 查看更多: \{t.words().map(fn(w) { w.0 }).join("|")}") }
  t.tap(x, y)
  t.frame()
  let kind = @sfpages.finder_kind()
  assert_true(kind != "", msg="one kind's list")
  let seen = []
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_kind()))
  t.draw()
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_kind()))
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_kind()))
  t.draw()
  seen.push((@sfdesk.switcher_open(), @sfpages.finder_kind()))
  assert_eq(seen, [(true, ""), (true, ""), (false, ""), (false, "")])
}

///|
/// The fixture's chat on a phone, its picture's page open (分享图片 on the chat's sheet), at rest; `preview` and
/// `finish` as publish_core's.
fn publish_shown(preview? : () -> Json = fix_preview, finish? : Bool = true) -> @ui.Tester {
  let t = publish_core([], preview~, finish~)
  t.tap_text("分享图片")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "分享图片's page dismissed by back: closed as back is taken; the frame after closes nothing more, opened again its own" {
  let t = publish_shown()
  let seen = [@sfpages.publish_open()]
  t.back_raw(2, 0.0, t.time())
  seen.push(@sfpages.publish_open())
  t.draw()
  seen.push(@sfpages.publish_open())
  t.run_for(@kit.pop_out_ms)
  // (opened again as it was: the chat's sheet from its bar, 分享图片 on it)
  t.click(Button, label="对话信息")
  t.run_for(@ui.move_most_ms)
  t.tap_text("分享图片")
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  seen.push(@sfpages.publish_open())
  t.run_for(@ui.move_most_ms)
  seen.push(@sfpages.publish_open())
  assert_eq(seen, [true, false, false, true, true])
}

///|
test "分享图片's page dismissed by Escape: closed as the key is taken; the frame after closes nothing more" {
  let t = publish_shown()
  let seen = [@sfpages.publish_open()]
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(@sfpages.publish_open())
  t.draw()
  seen.push(@sfpages.publish_open())
  assert_eq(seen, [true, false, false])
}


///|
/// The fixture's preview (fix_preview), Ana's message with a screen recording among its files too: its still in the
/// picture as the chat draws a video's (its poster, the station's).
fn preview_with_video() -> Json {
  let p = fix_preview()
  match p {
    Object(m) =>
      match m.get("list") {
        Some(Array(list)) =>
          for item in list {
            match item {
              Object(msg) =>
                match msg.get("attachments") {
                  Some(Array(files)) if files.length() > 0 =>
                    files.push({ "name": "演示录屏.mp4", "path": "/w/uploads/演示录屏.mp4", "size": 1048576 })
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  p
}

///|
/// 分享图片's page with a video's still in its picture not decoded yet (preview_with_video, nothing decoded till the
/// test says), 保存到相册 pressed as the host hands it on and two frames drawn: its picture being taken, waiting on the
/// still, nothing out yet.
fn publish_busy() -> @ui.Tester raise {
  let t = publish_shown(preview=preview_with_video, finish=false)
  let (bx, by, bw, bh) = t.get(Button, label="保存到相册").rect
  t.touch_at(0, bx + bw / 2.0, by + bh / 2.0, t.time())
  t.touch_at(2, bx + bw / 2.0, by + bh / 2.0, t.time())
  t.frame()
  t.frame()
  assert_true(
    t.ctx().taking_shot(publish_shot_key) && t.shots().length() == 0,
    msg="being taken: \{t.ctx().taking_shot(publish_shot_key)}, shots \{t.shots().length()}, pending \{t.pending()}",
  )
  t
}

///|
/// publish_busy's page, `hand` twice (as the host hands each on, no frame between), a frame; then the still decoded and
/// the picture taken, `hand` once more and a frame: whether the page is open and the stack under it as it was, at each.
fn publish_busy_seen(hand : (@ui.Tester) -> Unit) -> Array[(Bool, Bool)] raise {
  let t = publish_busy()
  let depth = app.nav.depth()
  let seen = []
  let look = fn() { (@sfpages.publish_open(), app.nav.depth() == depth) }
  hand(t)
  seen.push(look())
  hand(t)
  seen.push(look())
  t.frame()
  seen.push(look())
  // (the still decoded: the picture taken, out, once)
  t.finish_all()
  t.frame()
  t.frame()
  assert_true(!t.ctx().taking_shot(publish_shot_key) && t.shots().length() == 1, msg="taken: \{t.shots().length()}")
  hand(t)
  seen.push(look())
  t.draw()
  seen.push(look())
  seen
}

///|
let publish_busy_want : Array[(Bool, Bool)] = [(true, true), (true, true), (true, true), (false, true), (false, true)]

///|
test "分享图片's page while its picture is being taken (a video's still in it not decoded yet): back twice, no frame between, closes nothing and reaches nothing under it; once it is taken, back closes it at once" {
  assert_eq(publish_busy_seen(fn(t) { t.back_raw(2, 0.0, t.time()) }), publish_busy_want)
}

///|
test "分享图片's page while its picture is being taken (a video's still in it not decoded yet): Escape twice, no frame between, closes nothing and reaches nothing under it; once it is taken, Escape closes it at once" {
  assert_eq(publish_busy_seen(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), publish_busy_want)
}

///|
/// The picture's shot (sfpages' publish.mbt publish_shot).
let publish_shot_key : String = "publish/picture"
