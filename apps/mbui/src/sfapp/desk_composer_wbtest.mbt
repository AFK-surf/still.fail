// The desk's composer (sfdesk's composer.mbt, the web's Chat.tsx ComposerView) over the fixture core's composers
// (compose_fixture.mbt), drawn on its own in a desktop's window.

///|
/// The desk's composer for chat s-c1, over the chat fixture; what the core was asked kept in `calls`.
fn desk_composer_tester(
  calls : Array[Made],
  spec_of? : (ComposerFor) -> @sfpages.ComposerSpec = default_spec,
  pointing? : @ui.Pointing = Mouse,
  platform? : Int = 0,
  over? : (String, Topic) -> Topic = fn(_, t) { t },
  kept? : ((String, String) -> String)? = None,
) -> (@ui.Tester, Source) {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    draft_picture: kept.unwrap_or(base.draft_picture),
    topic: fn(name, params) { over(name, (base.topic)(name, params)) },
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
          match view_of_chat(src, r).0 {
            Some(v) => @sfpages.send_in_chat(c, src, r, v, w)
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
    note: [],
    tail: None,
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
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").text.get(), "")
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
test "desk composer: the `@` menu offers the workspace's other stations' chats too, each with its station after its title; this one's with none" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls)
  desk_focus(t)
  // written in Studio's (ws1/st1); 夜里的构建又失败了 is MBA's (ws1/st2)
  t.type_text("@的")
  t.frame()
  // (then when it was last active)
  assert_true(after_on_its_row(t, "夜里的构建又失败了") == ["MBA", "15 分钟前"], msg=about_its_row(t, "夜里的构建又失败了"))
  assert_true(after_on_its_row(t, "首页的列表改成按天分组") == ["8 分钟前"], msg=about_its_row(t, "首页的列表改成按天分组"))
  // keyboard and mouse's row: a menu's 34 (a finger's 44: chat_refs_wbtest)
  let (_, _, _, high) = t.get(Button, label="夜里的构建又失败了").rect
  assert_true(high >= 34.0 && high < 44.0, msg="\{high}")
}

///|
test "desk composer: the pointer moving over the `@` menu's chats chooses them; resting, ↑ / ↓ still move the choice away from under it" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls)
  desk_focus(t)
  t.type_text("@的")
  t.frame()
  let b = "首页的列表改成按天分组"
  let chosen = fn() raise { t.get(Button, label=b).selected }
  // moved onto it: chosen
  let (x, y, w, h) = t.get(Button, label=b).rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame()
  assert_eq(chosen(), Some(true))
  // the keys move the choice to another, the pointer resting where it was
  t.key(@ui.key_code_up)
  t.frame()
  t.frame()
  assert_eq(chosen(), Some(false))
  // moved again over it: chosen again
  t.move(x + w / 2.0 + 4.0, y + h / 2.0)
  t.frame()
  assert_eq(chosen(), Some(true))
}

///|
test "desk composer: while the core looks up the `@` menu's next words, the chats the last ones found stay, not a line saying it is reading" {
  let calls : Array[Made] = []
  // (from when it is set, the core answers no `chatSearch` yet)
  let held = Ref(false)
  let (t, _) = desk_composer_tester(calls, over=fn(name, topic) {
    if name == "chatSearch" && held.val {
      { value: None, error: None, version: 0 }
    } else {
      topic
    }
  })
  desk_focus(t)
  t.type_text("@首页")
  t.frame()
  assert_true(t.find("首页的列表改成按天分组") is Some(_))
  held.val = true
  t.type_text("的")
  t.frame()
  assert_true(t.find("引用对话") is Some(_))
  assert_true(t.find("首页的列表改成按天分组") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
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
test "desk composer: words dragged in from another app go into its field: let go on the field where they were let go, on ＋ beside it at its caret" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  t.draw()
  // on the field, nothing in it and not focused: in, the field focused
  let (fx, fy, _, fh) = t.rect_of("发消息").unwrap()
  t.drop_words(fx + 4.0, fy + fh / 2.0, "对话 ID：c1")
  t.frame()
  t.frame()
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  assert_eq(desk_words(src), "对话 ID：c1")
  // on ＋ (the composer opened now), beside the field: at its caret, after them
  let (px, py, pw, ph) = t.query(Button, label=@sf.t("web-main.composer.attach")).unwrap().rect
  t.drop_words(px + pw / 2.0, py + ph / 2.0, "，消息 ID：m9")
  t.frame()
  t.frame()
  assert_eq(desk_words(src), "对话 ID：c1，消息 ID：m9")
  // the core keeps them as typed words (composer.text)
  let kept = named(calls, "composer.text")
  assert_eq(text(Some(kept[kept.length() - 1].params), "text"), "对话 ID：c1，消息 ID：m9")
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
test "desk composer: a file up after the page last heard of it goes once as Enter sends it: as the core took it (composer.take), not as the page drew it" {
  let calls : Array[Made] = []
  // the draft as the page last heard of it, its file going up, while the core's word that it is up is on its way
  let heard : Ref[Topic?] = Ref(None)
  let (t, src) = desk_composer_tester(calls, over=fn(name, now) {
    match heard.val {
      Some(before) if name == "composer" => before
      _ => now
    }
  })
  desk_focus(t)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "notes.txt", b"abc")
  t.frame()
  // (the fixture's core has it up at once)
  let now = (src.topic)("composer", { "key": Json::string("ws1/st1:s-c1") })
  let going = items(now.value, "files").map(fn(f) {
    guard f is Object(m) else { f }
    let g = m.copy()
    g.remove("done")
    g["sent"] = Json::number(0.0)
    Json::object(g)
  })
  guard now.value is Some(Object(v)) else { abort("no draft") }
  let before = v.copy()
  before["files"] = Json::array(going)
  before["uploading"] = Json::boolean(true)
  heard.val = Some({ value: Some(Json::object(before)), error: None, version: now.version + 1 })
  t.frame()
  let drawn = @sfbase.writing(src, "ws1/st1:s-c1").files
  assert_eq(drawn.length(), 1)
  assert_true(field(Some(drawn[0]), "done") is None)
  t.enter()
  t.frame()
  let sends = named(calls, "chat.send")
  assert_eq(sends.length(), 1)
  let p = Some(sends[0].params)
  assert_eq(items(p, "attachments").map(fn(a) { text(Some(a), "name") }), ["notes.txt"])
  assert_eq(items(p, "uploads").length(), 0)
}

///|
test "desk composer: the same file picked or pasted again while it is in the draft is one file, going up once; taken out, it goes in again" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  let clip : @hostapi.Picked = { name: "录屏.mov", bytes: b"", held: 7, size: 3.0e9, src: "file:///clips/录屏.mov" }
  @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
  @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
  @sfbase.writing_add_picked(src, w, "ws1/st1", clip)
  @sfbase.writing_add_picked(src, w, "ws1/st1", clip)
  // another file: of another name, or of other bytes
  @sfbase.writing_add(src, w, "ws1/st1", "照片2.png", png_head())
  @sfbase.writing_add(src, w, "ws1/st1", "build.log", b"abc")
  @sfbase.writing_add(src, w, "ws1/st1", "build.log", b"abcd")
  t.frame()
  let names = fn() { @sfbase.writing(src, "ws1/st1:s-c1").files.map(fn(f) { text(Some(f), "name") }) }
  assert_eq(names(), ["照片.png", "录屏.mov", "照片2.png", "build.log", "build.log"])
  assert_eq(named(calls, "composer.add").length(), 5)
  // taken out, the same goes in again
  let photo = text(Some(@sfbase.writing(src, "ws1/st1:s-c1").files[0]), "id")
  @sfbase.writing_remove(src, @sfbase.writing(src, "ws1/st1:s-c1"), photo)
  t.frame()
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "照片.png", png_head())
  t.frame()
  assert_eq(names(), ["录屏.mov", "照片2.png", "build.log", "build.log", "照片.png"])
  assert_eq(named(calls, "composer.add").length(), 6)
}

///|
test "desk composer: an image sent while it goes up is among its message's files at once, its picture from here, a file of another kind a card saying how far" {
  let calls : Array[Made] = []
  // the draft as the page heard of it while its files went up (the fixture's core has them up at once)
  let heard : Ref[Topic?] = Ref(None)
  let (t, src) = desk_composer_tester(calls, over=fn(name, now) {
    match heard.val {
      Some(before) if name == "composer" => before
      _ => now
    }
  })
  desk_focus(t)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
  @sfbase.writing_add(src, w, "ws1/st1", "build.log", b"abc")
  t.frame()
  let now = (src.topic)("composer", { "key": Json::string("ws1/st1:s-c1") })
  let going = items(now.value, "files").map(fn(f) {
    guard f is Object(m) else { f }
    let g = m.copy()
    g.remove("done")
    g["sent"] = Json::number(1.0)
    Json::object(g)
  })
  guard now.value is Some(Object(v)) else { abort("no draft") }
  let before = v.copy()
  before["files"] = Json::array(going)
  before["uploading"] = Json::boolean(true)
  heard.val = Some({ value: Some(Json::object(before)), error: None, version: now.version + 1 })
  t.frame()
  let id = text(Some(@sfbase.writing(src, "ws1/st1:s-c1").files[0]), "id")
  t.enter()
  t.frame()
  // in the list from the frame it is sent (sent_local), as the core's outbox will have it (views.ts goingUp)
  let sent = sending_of("ws1/st1\u{1}s-c1")
  assert_eq(sent.length(), 1)
  let row = sent[0].row
  assert_eq(row.attachments.map(fn(a) { (a.name, a.path, a.upload) }), [("照片.png", "upload:" + id, id)])
  assert_true(sent_picture("ws1/st1", row.attachments[0]) is Some(_))
  assert_eq(row.uploads.map(fn(u) { u.0 }), ["build.log"])
  // it flies there as the upload it is (file_key: its path the station's once it is up), drawn where its tile was as
  // its tile, a picture, until it sets off; not a card
  let flying = match send_flight.get() {
    Some(f) => f.files
    None => fail("nothing flies")
  }
  assert_eq(flying.map(fn(ff) { ff.key }), ["upload:" + id])
  assert_true(flying[0].picture != "")
  let face = @ui.Tester::new(fn(_) { (flying[0].face)() }, w=200.0, h=200.0)
  // (its bytes again: a tester of its own starts with none)
  @ui.add_image(flying[0].picture, png_head())
  face.draw()
  assert_true(face.find("照片.png") is None)
  assert_eq(loaded_sources(face), 1)
  send_flight.set(None)
}

///|
/// How many pictures a tester decoded (each at as many sizes as it was drawn at: a picture covering its tile, once its
/// proportions are known, again at the size it is drawn).
fn loaded_sources(t : @ui.Tester) -> Int {
  let seen : Map[String, Bool] = {}
  for l in t.image_loads() {
    seen[l.0] = true
  }
  seen.length()
}

///|
/// A picture in the desk composer's draft, as the core says it (`as`: its file's fields put or taken off), sent: whether
/// a spinner turned over its tile as it waited there, and over what is drawn where its tile was till it sets off.
fn spun_tile_and_face(as_ : (Map[String, Json]) -> Unit) -> (Bool, Bool) raise {
  let calls : Array[Made] = []
  let heard : Ref[Topic?] = Ref(None)
  let (t, src) = desk_composer_tester(calls, over=fn(name, now) {
    match heard.val {
      Some(before) if name == "composer" => before
      _ => now
    }
  })
  desk_focus(t)
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
  t.frame()
  let now = (src.topic)("composer", { "key": Json::string("ws1/st1:s-c1") })
  let files = items(now.value, "files").map(fn(f) {
    guard f is Object(m) else { f }
    let g = m.copy()
    as_(g)
    Json::object(g)
  })
  guard now.value is Some(Object(v)) else { abort("no draft") }
  let before = v.copy()
  before["files"] = Json::array(files)
  heard.val = Some({ value: Some(Json::object(before)), error: None, version: now.version + 1 })
  t.frame()
  let lines = t.drawn_lines()
  t.enter()
  t.frame()
  let flying = match send_flight.get() {
    Some(f) => f.files
    None => fail("nothing flies")
  }
  assert_eq(flying.length(), 1)
  let (x, y, fw, fh) = flying[0].from
  let tile = lines.iter().any(fn(l) { l.0 >= x && l.0 <= x + fw && l.1 >= y && l.1 <= y + fh })
  let face = @ui.Tester::new(fn(_) { (flying[0].face)() }, w=200.0, h=200.0)
  // (its bytes again: a tester of its own starts with none)
  @ui.add_image(flying[0].picture, png_head())
  face.draw()
  assert_eq(loaded_sources(face), 1)
  let spun = face.drawn_lines().length() > 0
  send_flight.set(None)
  (tile, spun)
}

///|
test "desk composer: a draft kept, read again as the app starts, shows its pictures as the device keeps them (composer.picture), any other file as its card" {
  let calls : Array[Made] = []
  let asked : Array[String] = []
  let file = fn(id : String, name : String) -> Json {
    { "id": id, "name": name, "size": 120, "done": { "name": name, "path": "/w/uploads/" + name, "size": 120 } }
  }
  let (t, _) = desk_composer_tester(
    calls,
    over=fn(name, now) {
      if name != "composer" {
        return now
      }
      let m = match now.value {
        Some(Object(v)) => v.copy()
        _ => {}
      }
      m["files"] = [file("kept-1", "照片.png"), file("kept-2", "说明.txt")]
      { value: Some(Json::object(m)), error: now.error, version: now.version }
    },
    kept=Some(fn(key, id) {
      asked.push(key + " " + id)
      @ui.add_image("mem:test/kept", png_head())
      "mem:test/kept"
    }),
  )
  t.frame()
  assert_true(asked.length() > 0 && asked.iter().all(fn(a) { a == "ws1/st1:s-c1 kept-1" }), msg="\{asked}")
  // (its picture, the one image drawn)
  assert_eq(loaded_sources(t), 1)
  // a tile, not a card naming it; the other file a card
  let words = t.words().map(fn(w) { w.0 })
  assert_true(!words.iter().any(fn(w) { w.contains("照片") }), msg="\{words}")
  assert_true(words.iter().any(fn(w) { w.contains("说明") }), msg="\{words}")
}

///|
test "desk composer: a picture sent is drawn where its tile was as the composer drew it till it sets off: a spinner over it while it goes up, none over a new chat's waiting for its message" {
  // going up: a spinner over its tile, and over it till it sets off
  assert_eq(
    spun_tile_and_face(fn(g) {
      g.remove("done")
      g["sent"] = Json::number(1.0)
    }),
    (true, true),
  )
  // a new chat's, waiting for its message (composer.ts `waits`): nothing going up, no spinner over either
  assert_eq(
    spun_tile_and_face(fn(g) {
      g.remove("done")
      g["waits"] = Json::boolean(true)
    }),
    (false, false),
  )
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
  // whose: 来自, then that workspace's mark (its letter, 个, where it has none) and its name
  assert_true(t.find("来自 ") is Some(_) && t.find("个") is Some(_) && t.find("个人") is Some(_))
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
test "a phone's ＋: the sheet of what can go in (Attach.kt); 照片和视频 asks the system, held, and what it picks goes up (composer.add)" {
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
  let (x, y) = t.locate("=照片和视频")[0]
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
test "a phone's ＋ opened again shows the gallery as it is then: a screenshot taken since it was last up comes first in its strip" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls, pointing=Finger, platform=2)
  let shot = fn(id : Int64, added : Int64) -> @hostapi.GalleryPhoto {
    { id, src: "content://media/external/images/media/\{id}", added, modified: added, taken: -1L, video: false }
  }
  let earlier = shot(1L, 1_792_200_000L)
  let taken = shot(2L, 1_792_200_060L)
  for p in [earlier, taken] {
    t.add_image(p.src, 1080, 2400)
  }
  t.gallery([earlier])
  t.draw()
  t.click(Button, label=@sf.t("web-main.composer.attach"))
  // (the gallery read, its photos' pictures decoded and faded in)
  t.run_for(@ui.image_fade_ms)
  assert_eq(strip_photos(t), [earlier.src])
  // put away by one of its tiles (照片, the system's picker called off), as a photo or the camera puts it away too
  t.picks([])
  let (x, y) = t.locate("=照片和视频")[0]
  t.tap(x, y)
  t.draw()
  // a screenshot taken meanwhile, ＋ again
  t.gallery([earlier, taken])
  t.click(Button, label=@sf.t("web-main.composer.attach"))
  t.run_for(@ui.image_fade_ms)
  assert_eq(strip_photos(t), [taken.src, earlier.src])
}

///|
/// The gallery's photos ＋'s strip draws, in its order (the draw list's images, as first drawn).
fn strip_photos(t : @ui.Tester) -> Array[String] {
  let out = []
  for line in t.drawlist().split("\n") {
    // image N PX "SOURCE"
    let parts = line.split("\"").to_array()
    if line.has_prefix("image ") && parts.length() >= 2 && parts[1].has_prefix("content://") {
      out.push(parts[1].to_string())
    }
  }
  out
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

///|
test "the room a list keeps for the composer opened with one line is as tall as it lays out (composer_open_room), on a computer and on a phone" {
  for screen in [(@ui.Pointing::Mouse, 0), (@ui.Pointing::Finger, 2)] {
    let (pointing, platform) = screen
    let calls : Array[Made] = []
    let (t, _) = desk_composer_tester(calls, pointing~, platform~)
    t.draw()
    t.tap(450.0, 500.0 - 16.0 - 22.0)
    assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
    // (its box come to its opened shape)
    let opened = t.rest_of("composer")
    if opened > t.time() && opened < @double.infinity {
      t.run_for(opened - t.time())
    }
    t.draw()
    // (12 over the box and its foot's room under it, as a chat's foot has it)
    let pane = t.ctx().width
    assert_eq(
      @motion.measured(t.ctx(), "composer/content"),
      Some(@sfpages.composer_open_room(pane) - 12.0 - @sfpages.composer_foot_in(pane)),
    )
  }
}

///|
test "the composer growing a line as it is typed in draws none of its words over the row of ＋ and send on its way, on a phone and on a computer" {
  for screen in [(@ui.Pointing::Finger, 2), (@ui.Pointing::Mouse, 0)] {
    let (pointing, platform) = screen
    let calls : Array[Made] = []
    let (t, _) = desk_composer_tester(calls, pointing~, platform~)
    t.draw()
    t.tap(450.0, 500.0 - 16.0 - 22.0)
    t.type_text("先看第三项")
    t.run_for(2.0 * @ui.move_most_ms)
    t.draw()
    let (cx, cy) = t.locate("icon:arrow-up")[0]
    let half = @sf.theme().round.side / 2.0
    let over = fn() {
      t
      .glyphs_shown()
      .filter(fn(g) { g.1 < cy + half && g.3 > cy - half })
      .length()
    }
    assert_eq(over(), 0, msg="at rest, platform \{platform}")
    let lines = t.text_runs().length()
    // (words enough for a line more)
    t.type_text("，然后把第四项里每一个还没有人认领的条目都分给明天值班的同事，再把结果写进发布清单的最后一节里面")
    t.frame()
    assert_true(t.text_runs().length() > lines, msg="no line more: \{t.text_runs()}")
    assert_eq(over(), 0, msg="as it sets off, platform \{platform}")
    t.run_for(@ui.move_most_ms / 2.0)
    assert_eq(over(), 0, msg="half way, platform \{platform}")
  }
}

///|
test "a chat's composer growing a line as it is typed in keeps its send whole on its way, nothing of it faded or cut" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=400.0, h=800.0, platform=2, pointing=Finger)
  t.run_for(@ui.move_most_ms)
  let (px, py) = t.locate("icon:plus")[0]
  t.tap(px + 120.0, py)
  t.type_text("先看第三项")
  t.run_for(2.0 * @ui.move_most_ms)
  t.draw()
  let (cx, cy) = t.locate("icon:arrow-up")[0]
  let side = @sf.theme().round.side
  // (its round ground: the rect drawn as big as it, round its middle)
  let send = fn() {
    t
    .drawn_order()
    .filter(fn(d) {
      d.0 == 0 && (d.3 - side).abs() < 1.0 && (d.4 - side).abs() < 1.0 && d.1 <= cx && d.1 + d.3 >= cx && d.2 <= cy && d.2 + d.4 >= cy
    })
    .map(fn(d) { d.5 })
  }
  assert_eq(send(), [1.0], msg="at rest")
  t.type_text("，然后把第四项里每一个还没有人认领的条目都分给明天值班的同事，再把结果写进发布清单的最后一节里面")
  t.frame()
  assert_eq(send(), [1.0], msg="as it sets off")
  t.run_for(@ui.move_most_ms / 4.0)
  assert_eq(send(), [1.0], msg="a quarter of the way")
}

///|
test "a composer growing a line as it is typed in fades none of its words on its way: its last lines neither dim nor come back (the user, 2026-10-30: 「换行的时候最后两行会闪烁」)" {
  for screen in [(@ui.Pointing::Finger, 2), (@ui.Pointing::Mouse, 0)] {
    let (pointing, platform) = screen
    let calls : Array[Made] = []
    let (t, _) = desk_composer_tester(calls, pointing~, platform~)
    t.draw()
    t.tap(450.0, 500.0 - 16.0 - 22.0)
    t.type_text("先看第三项")
    t.run_for(2.0 * @ui.move_most_ms)
    t.draw()
    // (its words: the glyphs drawn in its field (focused) as laid out, to a line under its foot)
    let faded = fn() {
      let (ex, ey, ew, eh) = t.focused().unwrap().rect
      let line = @sf.theme().round.side
      t
      .drawn_order()
      .filter(fn(d) {
        d.0 == 1 && d.1 >= ex - 1.0 && d.1 <= ex + ew && d.2 + d.4 / 2.0 >= ey - 1.0 && d.2 <= ey + eh + line &&
        d.5 > 0.0 && d.5 < 0.99
      })
      .length()
    }
    assert_eq(faded(), 0, msg="at rest, platform \{platform}")
    t.type_text("，然后把第四项里每一个还没有人认领的条目都分给明天值班的同事，再把结果写进发布清单的最后一节里面")
    t.frame()
    assert_eq(faded(), 0, msg="as it sets off, platform \{platform}")
    t.run_for(@ui.move_most_ms / 4.0)
    assert_eq(faded(), 0, msg="a quarter of the way, platform \{platform}")
    t.run_for(@ui.move_most_ms / 2.0)
    assert_eq(faded(), 0, msg="three quarters of the way, platform \{platform}")
  }
}

///|
test "the line a composer grows by comes out fading to its foot pixel by pixel, what showed before untouched on its way, nothing fading once it is there (the user, 2026-10-30: 「带渐隐，但不是整行渐隐」)" {
  for screen in [(@ui.Pointing::Finger, 2), (@ui.Pointing::Mouse, 0)] {
    let (pointing, platform) = screen
    let calls : Array[Made] = []
    let (t, _) = desk_composer_tester(calls, pointing~, platform~)
    t.draw()
    t.tap(450.0, 500.0 - 16.0 - 22.0)
    t.type_text("先看第三项")
    t.run_for(2.0 * @ui.move_most_ms)
    t.draw()
    // (its glyphs: in its field, as laid out, to a line under its foot; each its top, height and how it fades to its
    // foot: where 0, over how far)
    let glyphs = fn() {
      let (_, ey, _, eh) = t.focused().unwrap().rect
      let line = @sf.theme().round.side
      t
      .drawn_fades()
      .filter(fn(d) { d.0 == 1 && d.1 + d.2 / 2.0 >= ey - 1.0 && d.1 <= ey + eh + line })
      .map(fn(d) { (d.1, d.2, d.5, d.6) })
    }
    // (none of the lines over the lowest, the new one, touched by its fading: each wholly above where it starts)
    let untouched = fn(at : String) raise {
      let gs = glyphs()
      let lowest = gs.fold(init=-1.0e9, fn(m, g) { if g.0 > m { g.0 } else { m } })
      for g in gs {
        if g.0 < lowest - 1.0 {
          assert_true(g.3 <= 0.0 || g.0 + g.1 <= g.2 - g.3 + 0.001, msg="\{at}: a line that showed faded \{g}, platform \{platform}")
        }
      }
      gs.iter().any(fn(g) { g.0 == lowest && g.3 > 0.0 })
    }
    t.type_text("，然后把第四项里每一个还没有人认领的条目都分给明天值班的同事，再把结果写进发布清单的最后一节里面")
    t.frame()
    untouched("as it sets off") |> ignore
    t.run_for(@ui.move_most_ms / 4.0)
    assert_true(untouched("a quarter of the way"), msg="the new line not fading on its way, platform \{platform}")
    t.run_for(@ui.move_most_ms / 2.0)
    untouched("three quarters of the way") |> ignore
    t.run_for(2.0 * @ui.move_most_ms)
    assert_eq(glyphs().filter(fn(g) { g.3 > 0.0 }).length(), 0, msg="once it is there, platform \{platform}")
  }
}

///|
test "on a phone a finger 3 off the send button, beside it or over it, sends: the button's reach over the composer's own (its field, its box)" {
  for off in [(1.0, 0.0), (0.0, -1.0), (-1.0, 0.0)] {
    let calls : Array[Made] = []
    let (t, _) = desk_composer_tester(calls, pointing=Finger, platform=2)
    t.draw()
    t.tap(450.0, 500.0 - 16.0 - 22.0)
    t.type_text("先看第三项")
    t.frame()
    let opened = t.rest_of("composer")
    if opened > t.time() && opened < @double.infinity {
      t.run_for(opened - t.time())
    }
    t.draw()
    let (cx, cy) = t.locate("icon:arrow-up")[0]
    let half = @sf.theme().round.side / 2.0
    t.tap(cx + off.0 * (half + 3.0), cy + off.1 * (half + 3.0))
    t.frame()
    assert_eq(named(calls, "chat.send").length(), 1, msg="pressed \{off}")
  }
}

///|
test "desk composer: 抄送 opens a menu of the chat's Slack and Feishu threads; several stay open to tick, ticked ones said beside 抄送 (chat.cc)" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let on = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.set_words(fill)
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      let v = chat_view_made({
        "title": "整理发布清单",
        "thread": { "id": 7 },
        "cc": [
          { "thread": 21, "place": "#still-fail", "via": "slack", "on": Json::boolean(on.val) },
          { "thread": 22, "place": "产品讨论", "via": "feishu", "on": false },
        ],
      })
      @sfpages.chat_composer(c, src, ws, r, Some(v))
      @sf.presented(c)
    },
    w=900.0,
    h=500.0,
    pointing=Mouse,
  )
  t.draw()
  let cc = @sf.t("web-main.composer.ccLabel")
  t.click(Button, label=cc)
  t.click(MenuItemCheckbox, label="#still-fail")
  on.val = true
  t.draw()
  // still open: the other can be ticked next
  t.click(MenuItemCheckbox, label="产品讨论")
  let asked = calls.filter(fn(m) { m.name == "chat.cc" }).map(fn(m) { m.params })
  assert_eq(asked, [
    { "station": "ws1/st1", "thread": 7, "to": 21, "on": true },
    { "station": "ws1/st1", "thread": 7, "to": 22, "on": true },
  ])
  // what is ticked is said beside 抄送
  assert_true(t.find("#still-fail") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
}

///|
test "desk composer: where 抄送 copies to is said just before send in either shape, staying where it is as the composer opens and shuts, 抄送 beside it once opened (chat.cc)" {
  new_run()
  let src = fixture("chat-cc")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, pointing=Mouse)
  t.run_for(@ui.move_most_ms)
  let (send_x, _) = t.locate("icon:arrow-up")[0]
  let xs : Array[Double] = []
  let watch = fn(ms : Double) raise {
    let until = t.time() + ms
    while t.time() < until {
      match t.drawn_of("#still-fail") {
        Some((x, _)) => xs.push(x)
        None => fail("where it copies to not drawn at \{t.time()}")
      }
      t.frame()
    }
  }
  // opened: where it copies to just before send, 抄送 just before that, not at the row's start
  let (cc_x, _) = t.locate("=抄送")[0]
  assert_true(cc_x > send_x - 200.0, msg="抄送 at \{cc_x}, send at \{send_x}")
  watch(@ui.move_most_ms)
  // let go of (one line): the place said just before send, where it was; nothing to press
  t.ctx().blur()
  // (its shape changing once it is let go of, and as long again after)
  watch(@sfpages.let_go_ms + 2.0 * @ui.move_most_ms)
  assert_true(t.locate("=抄送") is [], msg="抄送 only once opened")
  // opened again
  let (px, py) = t.locate("icon:plus")[0]
  t.tap(px + 200.0, py)
  watch(2.0 * @ui.move_most_ms)
  // (going with send, which stands a pixel further in on one line)
  let moved = xs.filter(fn(x) { (x - xs[0]).abs() > 1.5 })
  assert_true(moved.is_empty(), msg="went across: \{xs}")
}

///|
test "desk composer: 抄送's menu has each thread's platform mark before its place, its check only at its end (chat.cc)" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(
    fn(c) {
      @sf.set_words(fill)
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      let v = chat_view_made({
        "title": "整理发布清单",
        "thread": { "id": 7 },
        "cc": [
          { "thread": 21, "place": "产品讨论", "via": "feishu", "on": true },
          { "thread": 22, "place": "#still-fail", "via": "slack", "on": false },
        ],
      })
      @sfpages.chat_composer(c, src, ws, r, Some(v))
      @sf.presented(c)
    },
    w=900.0,
    h=500.0,
    pointing=Mouse,
  )
  t.draw()
  // (named with what is ticked)
  t.click(Button, label=@sf.t("web-main.composer.ccLabel") + " 产品讨论")
  let bs = t.boxes()
  // whether it or what is in it draws a picture (a mark, an icon)
  let draws = fn(i : Int) {
    bs.iter().any(fn(b) {
      let mut at = b.index
      while at >= 0 && at != i {
        at = bs[at].parent
      }
      at == i && b.draws
    })
  }
  for place in ["产品讨论", "#still-fail"] {
    // (the menu's, made by 抄送 before what is said by send: a ticked one's place is said there too)
    let w = bs.iter().find_first(fn(b) { b.text == place }).unwrap()
    let row = bs.filter(fn(b) { b.parent == w.parent })
    let before = row.filter(fn(b) { b.index < w.index })
    let after = row.filter(fn(b) { b.index > w.index })
    // one column before its words, its mark's: none empty where a check would go
    assert_true(before.length() == 1 && draws(before[0].index), msg="\{place}: \{before.map(fn(b) { (b.kind, b.x, b.w) })}")
    // a ticked one's check at its end, only there
    assert_eq(after.iter().any(fn(b) { draws(b.index) }), place == "产品讨论", msg=place)
  }
}
