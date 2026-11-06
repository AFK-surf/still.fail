///|
fn press_tape_inputs() -> Array[String] {
  match tape.val { Some(lines) => lines.filter(fn(s) { s.has_prefix("INPUT ") }); None => [] }
}

///|
fn press_tape_tester(seen : Array[(Double, Array[String])], then? : () -> Unit = fn() {  }) -> Tester {
  let opened = @signals.signal(false)
  let t = Tester::new(fn(c) {
    if opened.get() {
      c.text("opened") |> ignore
    } else {
      let id = c.id("open")
      let b = c.box(id~, w=Px(100.0), h=Px(40.0), fn() { c.text("open") |> ignore })
      c.focusable(id, node=b)
      c.semantics(b, Button, id~, label="open", actions=[Activate])
      c.on_press(id, fn() {
        seen.push((view_moment(), press_tape_inputs()))
        opened.set(true)
        then()
      })
    }
  }, w=200.0, h=100.0)
  t
}

///|
test "a callback's page change sees its triggering key on the tape and replays once at the same moment" {
  for code in [key_enter, key_space] {
    let seen : Array[(Double, Array[String])] = []
    let t = press_tape_tester(seen)
    let id = t.get(Button, label="open").id
    t.ctx().ask_action(id, Focus)
    t.draw()
    t.start_tape()
    let at = t.time() + 50.0
    // A host may hand the event over late; the tape and callback still use its own moment.
    let delivered_at = at + 50.0
    t.advance(delivered_at - t.time())
    t.key_told(code, 0, at)
    assert_eq(seen.length(), 1)
    assert_eq(seen[0].0, at)
    assert_eq(seen[0].1.length(), 1, msg="the key is recorded before the callback, not after it returns")
    assert_eq(seen[0].1, press_tape_inputs())
    let input = @json.parse(seen[0].1[0].view(start_offset=6).to_owned())
    assert_eq(input, { "k": "key", "t": Json::number(at), "a": [Json::number(code.to_double()), 0] })
    t.draw()
    assert_true(t.find("opened") is Some(_))
    let log = t.tape()
    let replayed : Array[(Double, Array[String])] = []
    let again = press_tape_tester(replayed)
    again.ctx().ask_action(again.get(Button, label="open").id, Focus)
    again.draw()
    again.start_tape()
    let frames = again.replay_frames(log)
    assert_true(frames.all(fn(f) { f.1 == f.2 }), msg="the resulting page replays with the same drawing")
    assert_eq(replayed, seen)
    assert_true(again.find("opened") is Some(_))
  }
}

///|
test "an unaccepted key falls through and is taped once; a callback's nested input has its own single record" {
  let nested = Ref(false)
  let seen : Array[(Double, Array[String])] = []
  let t = press_tape_tester(seen, then=fn() {
    if !nested.val {
      nested.val = true
      on_key(key_of_char('x'), mod_ctrl)
    }
  })
  t.ctx().ask_action(t.get(Button, label="open").id, Focus)
  t.draw()
  t.start_tape()
  t.key_told(key_space, mod_cmd, t.time())
  assert_eq(seen.length(), 0)
  assert_eq(press_tape_inputs().length(), 1)
  t.key_told(key_enter, 0, t.time())
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].1.length(), 2)
  assert_eq(press_tape_inputs().length(), 3)
  t.draw()
  assert_eq(press_tape_inputs().length(), 3)
}
