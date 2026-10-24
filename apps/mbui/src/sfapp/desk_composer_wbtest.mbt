// The desk's composer (sfdesk's composer.mbt, the web's Chat.tsx ComposerView) over the fixture core's composers
// (compose_fixture.mbt), drawn on its own in a desktop's window.

///|
/// The desk's composer for chat s-c1, over the chat fixture; what the core was asked kept in `calls`.
fn desk_composer_tester(
  calls : Array[Made],
  spec_of? : (ComposerFor) -> @sfpages.ComposerSpec = default_spec,
  pointing? : @ui.Pointing = Mouse,
  platform? : Int = 0,
) -> (@ui.Tester, Source) {
  reset()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
    call_bytes: fn(name, params, bytes, done) {
      calls.push({ name, params, bytes: Some(bytes), done, heard: None })
      (base.call_bytes)(name, params, bytes, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(
    fn(c) {
      // (the library's words as the app's view says them: without, the composer said its keys, and passed only after
      // another test had drawn the app, 2026-10-24)
      @sf.set_words(fill)
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      c.box(style=@ui.css("w=Full h=Full p=S4 justify=JEnd"), fn() {
        @sfpages.composer(c, src, ws, spec_of({ station: r.station, key: "ws1/st1:s-c1" }), fn(w) {
          match (src.topic)("chat", chat_params(r)).value {
            Some(v) => @sfpages.send_in_chat(c, src, r, chat_view(v), w)
            None => ()
          }
        })
      })
      |> ignore
      // what the presenters show (＋'s sheet with a finger), over it as the shell has it
      @sf.presented(c)
    },
    w=900.0,
    h=500.0,
    platform~,
    pointing~,
  )
  (t, src)
}

///|
priv struct ComposerFor {
  station : String
  key : String
}

///|
fn default_spec(f : ComposerFor) -> @sfpages.ComposerSpec {
  {
    station: f.station,
    draft: f.key,
    session: "",
    placeholder: "发消息",
    toolbar: None,
    roomy: false,
    locked: false,
    offline: false,
  }
}

///|
test "desk composer: typed words are the core's draft (composer.text); Enter sends them, in the list and empty at once (sent_local, composer.take, chat.send)" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  t.draw()
  // (with a mouse and nothing focused it says which key brings the cursor there: pressed in its middle)
  t.tap(450.0, 500.0 - 16.0 - 22.0)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  t.type_text("先看第三项")
  t.frame()
  assert_true(named(calls, "composer.text").length() > 0)
  t.enter()
  t.frame()
  let sends = named(calls, "chat.send")
  assert_eq(sends.length(), 1)
  assert_eq(text(Some(sends[0].params), "text"), "先看第三项")
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").text, "")
}

///|
test "desk composer: a quote waiting is its card over the words, its comment told to the core, ✕ lets it go" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  t.draw()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Claude", "text": "其余的行按估计的高度占位" })
  t.frame()
  t.frame()
  assert_true(t.find("其余的行按估计的高度占位") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  let (x, y, bw, bh) = t.query(Button, label="移除引用").unwrap().rect
  t.tap(x + bw / 2.0, y + bh / 2.0)
  t.frame()
  assert_true(named(calls, "composer.unquote").length() > 0)
}

///|
test "desk composer: Enter in a quote's comment keeps the comment and goes back to the words" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  t.draw()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Claude", "text": "其余的行按估计的高度占位" })
  t.frame()
  t.frame()
  t.type_text("这里要对齐")
  t.frame()
  t.enter()
  t.frame()
  t.frame()
  // (the core has what its line holds, told every frame it differs: emptied, it would say "")
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  assert_eq(w.quotes.length(), 1)
  assert_eq(text(Some(w.quotes[0]), "comment"), "这里要对齐")
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  assert_eq(named(calls, "chat.send").length(), 0)
}

///|
/// What draft s-c1's field holds now.
fn desk_words(src : Source) -> String {
  @sfbase.writing(src, "ws1/st1:s-c1").field.text()
}

///|
/// The desk's composer focused (tapped in its middle).
fn desk_focus(t : @ui.Tester) -> Unit raise {
  t.draw()
  t.tap(450.0, 500.0 - 16.0 - 22.0)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
}

///|
test "desk composer: `@` and words offer the chats they find over it (ChatRefMenu); ↓ and Enter put the one chosen in as its mark, not sending; a Backspace after it takes it whole" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("看 @首页")
  t.frame()
  assert_true(t.find("引用对话") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  // (↓ goes round the chats found, not the field's lines)
  t.key(@ui.key_code_down)
  t.key(@ui.key_code_up)
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").field.selection(), (5, 5))
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  assert_true(t.find("引用对话") is Some(_))
  t.enter()
  t.frame()
  assert_eq(named(calls, "chat.send").length(), 0)
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "into"), "ws1")
  assert_eq(desk_words(src), "看 @[首页的列表改成按天分组] ")
  assert_true(t.find("引用对话") is None)
  // drawn as the mark: `[@…]`, its brackets clear
  t.backspace()
  t.frame()
  assert_eq(desk_words(src), "看 @[首页的列表改成按天分组]")
  t.backspace()
  t.frame()
  assert_eq(desk_words(src), "看 ")
}

///|
test "desk composer: Escape closes the `@` menu for that `@`; the words stay, Enter sends them" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("问 @发版")
  t.frame()
  assert_true(t.find("引用对话") is Some(_))
  t.key(@ui.key_escape)
  t.frame()
  assert_true(t.find("引用对话") is None)
  t.enter()
  t.frame()
  let sends = named(calls, "chat.send")
  assert_eq(sends.length(), 1)
  assert_eq(text(Some(sends[0].params), "text"), "问 @发版")
}

///|
test "desk composer: a chat's link pasted as it is copied goes in as its mark" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.paste("先看 [首页](https://app.still.fail/w/ws1/s/st1/chats/s-c2) 再说")
  t.frame()
  t.frame()
  let made = named(calls, "chat.ref")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "id"), "s-c2")
  assert_eq(desk_words(src), "先看 @[首页] 再说")
}

///|
/// Words past the core's bound for a paste (what the core says of them kept: src/sfkept).
fn long_paste() -> String {
  let long = StringBuilder()
  long.write_string("发布前要核对的条目\n")
  for i in 0..<1000 {
    long.write_string("第\{i}条，")
  }
  long.to_string()
}

///|
test "desk composer: words pasted at once past the core's bound go as a file of their own, what they begin with kept with it" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  // (the bound asked of the core once the field is drawn)
  t.frame()
  assert_true(long_paste().length() >= 5000)
  t.paste(long_paste())
  t.frame()
  t.frame()
  assert_eq(desk_words(src), "")
  // (waiting with the draft: composer.add, its bytes beside it)
  let files = @sfbase.writing(src, "ws1/st1:s-c1").files
  assert_eq(files.length(), 1)
  let one = files[0]
  assert_true(text(Some(one), "name").has_prefix("pasted-text-"))
  assert_eq(text(field(Some(one), "pasted"), "preview"), "发布前要核对的条目")
  // its card: what they begin with and how many, not the file's name
  t.frame()
  assert_true(t.find("发布前要核对的条目") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(t.find("pasted-text-") is None)
}

///|
test "desk composer: a file waiting and no words, Enter sends it (as send does)" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.frame()
  t.paste(long_paste())
  t.frame()
  t.frame()
  assert_eq(desk_words(src), "")
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.length(), 1)
  t.enter()
  t.frame()
  assert_eq(named(calls, "chat.send").length(), 1)
}

///|
test "desk composer: a reference to another workspace's chat is asked about first (OutsideShare.tsx), Enter again shares it and it goes" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("先看 @[季度路线图] 再定")
  t.frame()
  t.enter()
  t.frame()
  // not sent: the core asked what it refers to, the dialog saying whose
  assert_eq(named(calls, "chat.outsideRefs").length(), 1)
  assert_eq(named(calls, "chat.send").length(), 0)
  assert_true(t.find("分享对话") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(t.find("来自 个人") is Some(_))
  assert_true(t.find("分享并发送") is Some(_))
  // Enter again: shared by the core (which of them, with which workspace: its), then it goes
  t.enter()
  t.frame()
  t.frame()
  let shared = named(calls, "chat.outsideShare")
  assert_eq(shared.length(), 1)
  assert_eq(text(Some(shared[0].params), "station"), "ws1/st1")
  assert_eq(named(calls, "chat.send").length(), 1)
  assert_eq(text(Some(named(calls, "chat.send")[0].params), "text"), "先看 @[季度路线图] 再定")
  assert_true(fix_xshared.contains("s-p1"))
  ignore(src)
}

///|
test "desk composer: words with no reference go at once, the core not asked what they refer to" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("没有引用的话")
  t.enter()
  t.frame()
  assert_eq(named(calls, "chat.outsideRefs").length(), 0)
  assert_eq(named(calls, "chat.send").length(), 1)
}

///|
test "a phone's ＋: the sheet of what can go in (Attach.kt); 照片 asks the system, held, and what it picks goes up (composer.add)" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls, pointing=Finger, platform=2)
  t.draw()
  t.click(Button, label=@sf.t("web-main.composer.attach"))
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("照片") is Some(_))
  assert_true(t.find("Station 文件") is Some(_))
  // (what the system's picker answers, said before it is asked; the tile, not the strip's last, which asks for the
  // gallery's 最近照片)
  t.picks([("photo.jpg", b"abcd")])
  let (x, y) = t.locate("=照片")[0]
  t.tap(x, y)
  assert_eq(t.pick_asks().length(), 1)
  assert_true(t.pick_asks()[0] == Photos)
  t.draw()
  t.draw()
  let added = named(calls, "composer.add")
  assert_eq(added.length(), 1)
  assert_eq(text(Some(items(Some(added[0].params), "files")[0]), "name"), "photo.jpg")
}

///|
test "on a phone, a finger down outside the composer lets go of the keyboard once lifted (Keyboard.kt letsGoOfKeyboard)" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls, pointing=Finger, platform=2)
  t.draw()
  t.tap(450.0, 500.0 - 16.0 - 22.0)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  t.tap(450.0, 60.0)
  t.draw()
  assert_true(!t.ctx().editor_focused(@sfpages.composer_field_key))
}
