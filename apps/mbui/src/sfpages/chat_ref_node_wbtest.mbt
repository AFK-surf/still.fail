///|
fn retained_ref_tester() -> (@ui.Tester, ComposerNode, Array[(String, Json)], Ref[Int]) {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let calls : Array[(String, Json)] = []
  let sent = Ref(0)
  let src = { ..@sfbase.made_source(call=fn(name, params, done) {
    calls.push((name, params))
    if name == "ref.at" {
      let words = text(Some(params), "text")
      let caret = number(Some(params), "caret").to_int()
      match words.find("@") {
        Some(at) if !words.contains("@[") && caret > at => done(Ok({ "at": { "start": Json::number(at.to_double()), "query": Json::string(words.view(start_offset=at + 1, end_offset=caret).to_string()) } }))
        _ => done(Ok({}))
      }
    } else if name == "chat.ref" {
      done(Ok({ "mark": Json::string("@[" + text(Some(params), "title") + "]") }))
    } else { done(Ok({})) }
  }), topic: fn(name, _) {
    if name == "chatSearch" {
      { value: Some({ "items": [
        { "id": "one", "station": "ws/st", "title": "First", "agents": [], "ago": "now" },
        { "id": "two", "station": "ws/st", "title": "Second", "agents": [], "ago": "now" },
      ] }), error: None, version: 1 }
    } else { { value: None, error: None, version: 0 } }
  } }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=0)
  let made : Ref[ComposerNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lies_along(Is(End)) |> ignore
    made.val = Some(composer_node(root, src, "refs", fn() {
      { station: "ws/st", draft: "refs", session: "chat", placeholder: "Write", toolbar: None, toolbar_node: None, note: [], tail: None,
        roomy: false, locked: false, offline: false, warm_agent: false }
    }, fn(_) { sent.val += 1 }, fn() { 900.0 }, fn(_, _, _, _) {  }))
  })
  t.draw()
  let n = made.val.unwrap()
  n.writing.field.focus()
  t.type_text("look @a")
  t.draw()
  (t, n, calls, sent)
}

///|
test "a retained reference menu keeps editing and inserts its keyboard choice once before Enter or Tab" {
  for key in [@ui.key_code_enter, @ui.key_tab] {
    let (t, n, calls, sent) = retained_ref_tester()
    assert_true(t.find("引用对话") is Some(_))
    let id = n.field.id()
    t.key(@ui.key_code_down)
    assert_eq(t.get(Button, label="Second").selected, Some(true))
    t.type_text("b")
    t.key(@ui.key_code_down)
    t.key_told(key, 0, t.time())
    t.key_told(@ui.key_escape, 0, t.time())
    assert_eq(calls.filter(fn(c) { c.0 == "chat.ref" }).length(), 1)
    assert_eq((n.writing.field.text(), sent.val), ("look @[Second] ", 0))
    assert_eq(n.field.id(), id)
    assert_true(n.field.focused())
  }
}

///|
test "a retained reference menu closes at an outside press and an Escape, without consuming the following Enter" {
  for outside in [true, false] {
    let (t, _, calls, sent) = retained_ref_tester()
    if outside { t.touch_at(0, 10.0, 10.0, t.time()); t.touch_at(2, 10.0, 10.0, t.time()) }
    else { t.key_told(@ui.key_escape, 0, t.time()) }
    assert_true(@sfbase.refs_at("refs") is None)
    t.key_told(@ui.key_code_enter, 0, t.time())
    assert_eq(calls.filter(fn(c) { c.0 == "chat.ref" }).length(), 0)
    assert_eq(sent.val, 1)
  }
}
