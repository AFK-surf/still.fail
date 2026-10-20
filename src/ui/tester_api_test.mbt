///|
test "a test finds words as a scripted run does, reads and pastes into the focused field, presses keys by name" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.text("Send it", wrap=false) |> ignore
      c.text("Send", wrap=false) |> ignore
      c.editor("field", placeholder="words") |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.locate("Send").length(), 2)
  assert_eq(t.locate("=Send").length(), 1)
  assert_eq(t.locate("nowhere"), [])
  assert_eq(t.size(), (390.0, 844.0))
  assert_eq(t.field_words(), "")
  t.tap_text("words")
  t.paste("pasted words")
  assert_eq(t.field_words(), "pasted words")
  assert_true(t.key_named("shift+enter"))
  assert_true(t.key_named("cmd+a"))
  assert_false(t.key_named("hyper+q"))
}

///|
test "a test sees the notifications the app shows, and taps one: what it opens is the app's, once" {
  let shown = Ref(false)
  let opened : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    if !shown.val {
      shown.val = true
      @ui.notice_show(channel="chats", tag="c1", title="Ana", body="the build is green", opens="chat:c1")
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="a question", opens="chat:c2")
      // the same tag again: the one before replaced
      @ui.notice_show(channel="chats", tag="c2", title="Lin", body="two questions", opens="chat:c2")
    }
    let o = @ui.notice_opened()
    if o != "" {
      opened.push(o)
    }
    c.text("app", wrap=false) |> ignore
  })
  t.draw()
  assert_eq(t.notices().map(fn(n) { n.body }), ["the build is green", "two questions"])
  assert_true(t.tap_notice("green"))
  assert_eq(opened, ["chat:c1"])
  assert_eq(t.notices().length(), 1)
  assert_false(t.tap_notice("green"))
  @ui.notice_cancel("c2")
  assert_eq(t.notices(), [])
}

///|
test "idle but for what never ends while shown: a cycle read is said, not a failure; a field cleared" {
  let spin = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    if spin.val {
      // (a declared period, a spinner's)
      let turn_ms = 1000.0
      ignore(c.cycle(turn_ms))
    }
    c.editor("field", placeholder="words") |> ignore
  })
  t.draw()
  t.assert_idle()
  assert_eq(t.cycles().length(), 1)
  assert_true(t.cycles()[0].has_prefix("1000 ms by "))
  spin.val = false
  t.draw()
  t.assert_idle()
  assert_eq(t.cycles(), [])
  t.tap_text("words")
  t.type_text("some words")
  assert_eq(t.field_words(), "some words")
  t.clear()
  assert_eq(t.field_words(), "")
}

///|
/// A box whose words are placed by where they were last laid out: `step` px further in each frame (`step` 0: placed
/// once by them, then where they are).
fn reading_back(step : Double) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let x = match c.words_of("w") {
        Some(w) if w.pieces.length() > 0 => if step > 0.0 { w.pieces[0].x + step } else { 20.0 }
        _ => 0.0
      }
      c.box(padx=x, fn() {
        let b = c.column(w=Px(100.0), fn() { c.rich([@ui.plain("hello")], size=10.0) |> ignore })
        c.words(b, "w")
      })
      |> ignore
    },
    w=300.0,
    h=100.0,
  )
}

///|
test "draw: a layout read back that moves once is placed again at the same moment, and then is still" {
  let t = reading_back(0.0)
  let at = t.time()
  t.draw()
  assert_eq(t.time(), at)
  assert_eq(t.ctx().words_of("w").unwrap().pieces[0].x, 20.0)
  t.assert_idle()
}

///|
test "panic draw: a layout read back that moves at every frame does not converge, and says whose" {
  let t = reading_back(1.0)
  t.draw()
}
