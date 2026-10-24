// The desk's composer (sfdesk's composer.mbt, the web's Chat.tsx ComposerView) over the fixture core's composers
// (compose_fixture.mbt), drawn on its own in a desktop's window.

///|
/// The desk's composer for chat s-c1, over the chat fixture; what the core was asked kept in `calls`.
fn desk_composer_tester(
  calls : Array[Made],
  spec_of? : (ComposerFor) -> @sfdesk.ComposerSpec = default_spec,
) -> (@ui.Tester, Source) {
  reset()
  wide_on.val = true
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let t = @ui.Tester::new(
    fn(c) {
      let _ = @sf.begin(c)
      let ws : Workspace = { id: "ws1", name: "Acme", emoji: "", icon: "", email: "" }
      c.box(style=@ui.css("w=Full h=Full p=S4 justify=JEnd"), fn() {
        @sfdesk.composer(c, src, ws, desk_pages(), spec_of({ station: r.station, key: "ws1/st1:s-c1" }), fn(w) {
          match (src.topic)("chat", chat_params(r)).value {
            Some(v) => @sfdesk.send_in_chat(c, src, desk_pages(), r, chat_view(v), w)
            None => ()
          }
        })
      })
      |> ignore
    },
    w=900.0,
    h=500.0,
    platform=0,
  )
  (t, src)
}

///|
priv struct ComposerFor {
  station : String
  key : String
}

///|
fn default_spec(f : ComposerFor) -> @sfdesk.ComposerSpec {
  {
    station: f.station,
    draft: f.key,
    warm: "",
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
  assert_true(t.ctx().editor_focused(@sfdesk.composer_field_key))
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
