// A chat's page made with its inside nodes (sfbase's chat_page_nodes on): a picture quoted in words sent from here,
// pressed in their message once the core has taken the row over, opens in the viewer asked of the core by the name
// the core gives that row (`o:<outbox id>/q:<i>`, the core's placed.ts `near`: by any other it finds the picture
// nowhere, and the viewer has no way to the chat's other pictures nor says which of them it is), and goes back to the
// row it was pressed in as it closes; pressed before the core has it, it is asked by that name as the core takes it
// over (the row keeping the key it was sent as: chat_body_rows' `sent_as`, given the viewer by sfbase's rows_sent_as).
// On 小屏 and 大屏.

///|
/// The core's outbox row `out-1` taking over words "." sent from here quoting picture `file` (named `name`), once
/// `has` is on.
fn cnsq_core(has : @signals.Signal[Bool], name : String, file : Json, w : Double, platform : Int) -> (@ui.Tester, Source) {
  let made : Ref[Source?] = Ref(None)
  let calls : Array[Made] = []
  let t = fake_core(calls, made~, platform~, nodes=true, over=fn(topic, tp) {
    match (topic, tp.value) {
      ("chat", Some(Object(m))) if has.get() => {
        let v = m.copy()
        v["outbox"] = [{
          "id": "out-1", "text": ".", "createdAt": 0, "state": "sending",
          "attachments": [file],
          "quotes": [{ "author": "Ana", "text": Json::string(name), "ts": "ts8", "comment": "", "file": Json::string(name) }],
        }]
        { ..tp, value: Some(Json::object(v)), version: tp.version + 1 }
      }
      _ => tp
    }
  })
  if w != 390.0 {
    t.resize(w, 844.0)
    t.run_for(@ui.move_most_ms)
  }
  (t, made.val.unwrap())
}

///|
/// Where the viewer asked the core for the pictures beside the one it shows (imageNear's `at`), since it was last
/// cleared.
fn cnsq_asked() -> Array[String] {
  let asked : Array[String] = []
  @sfbase.near_asked.each(fn(_, p) { asked.push(text(Some(Json::object(p)), "at")) })
  asked
}

///|
/// On a screen `w` wide (`platform`'s): a picture quoted and sent, the core taking the row over before it is pressed
/// (`early` false) or as it shows in the viewer (`early`); asked by the core's name for the row, back to its row.
fn cnsq_check(w : Double, platform : Int, early : Bool) -> Unit raise {
  let has = @signals.signal(false)
  let name = "sent-quote.png"
  let file : Json = { "name": Json::string(name), "path": Json::string("/w/uploads/" + name), "size": 120, "width": 1600, "height": 900, "owner": "s-c1" }
  let (t, src) = cnsq_core(has, name, file, w, platform)
  let wr = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, wr, { "author": "Ana", "text": Json::string(name), "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  t.tap_text("发消息")
  t.type_text(".")
  tap_send(t)
  t.run_for(@sfbase.flight_len(true) * 2.0 + @sf.hint_back_ms + @ui.move_most_ms)
  if !early {
    has.set(true)
    t.run_for(@ui.move_most_ms)
  }
  let pictures = t.locate("img:" + name)
  assert_eq(pictures.length(), 1, msg="the quoted picture in its message: \{Repr(pictures)}")
  @sfbase.near_asked.clear()
  t.tap(pictures[0].0, pictures[0].1)
  t.frame()
  if early {
    has.set(true)
    t.frame()
  }
  let asked = cnsq_asked()
  assert_true(
    asked.last() == Some("o:out-1/q:0"),
    msg="\{w}, taken over \{if early { "as it shows" } else { "before" }}: the viewer asked the core by \{Repr(asked)}, not by its row's name there",
  )
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  let back = t.locate("img:" + name)
  assert_true(back.length() == 1 && back[0] == pictures[0], msg="\{w}: closed, not back in its row: \{Repr(back)}")
}

///|
test "a picture quoted in words sent from here opens asked of the core by its row's name there, and goes back to that row" {
  for screen in [(390.0, 2), (1280.0, 0)] {
    cnsq_check(screen.0, screen.1, false)
    cnsq_check(screen.0, screen.1, true)
  }
}
