// The original read-position and keyboard contracts, kept alongside the newer tests that also cover them.

///|
test "opened short of its end, the core is told the messages shown whole: read up to there, the end not seen" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  // at its end: the end seen, and its newest shown whole
  let (end, newest) = focus_seen(calls)
  assert_true(end)
  assert_true(newest > 0.0)
  // scrolled up from its end, let be: the place it is at
  t.drag(200.0, 300.0, 200.0, 300.0 + seen_drag)
  t.run_for(t.rest_of("a list") - t.time())
  t.frame()
  let told = named(calls, "chat.place")
  let p = told[told.length() - 1].params
  let seq = number(Some(p), "seq")
  let px = number(Some(p), "offset")
  // opened again there (the core's `at`): the messages in view shown whole, the end not
  let again : Array[Made] = []
  let t2 = fake_core(again, over=fn(name, tp) {
    match (name, tp.value) {
      ("chat", Some(Object(m))) => {
        let v = m.copy()
        v["at"] = Json::number(seq)
        v["atOffset"] = Json::number(px)
        { ..tp, value: Some(Json::object(v)) }
      }
      _ => tp
    }
  })
  t2.run_for(@ui.move_most_ms)
  let (end2, seen) = focus_seen(again)
  assert_true(!end2)
  assert_true(seen >= 0.0)
  assert_true(seen < newest)
  ignore(t)
}

///|
test "the cache choice can be changed from the keyboard" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-cache-cold", wide=true)
  let choice = t.get(Button, label="接着聊")
  t.ctx().focus_on(choice.id, visible=true)
  t.draw()
  assert_eq(t.focused().map(fn(n) { n.label }), Some("接着聊"), msg="the choice has keyboard focus")
  t.enter()
  t.draw()
  assert_true(t.query(MenuItemRadio, label="换新上下文") is Some(_), msg="Enter opens the choices")
  assert_eq(t.focused().map(fn(n) { n.role }), Some(MenuItemRadio), msg="the menu focuses an item")
  t.key(@ui.key_code_down)
  assert_eq(t.focused().map(fn(n) { n.label }), Some("换新上下文"), msg="Down moves to the other choice")
  t.enter()
  t.draw()
  let asked = named(calls, "session.settings")
  assert_eq(asked.length(), 1)
  assert_eq(field(Some(asked[0].params), "afresh"), Some(Json::boolean(true)))
}
