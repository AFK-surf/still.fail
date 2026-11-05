///|
test "the retained find bar keeps its field while typing, looks after the last key, moves both ways and cancels on close" {
  @sfbase.reset()
  find_close()
  @sf.set_words(@sfbase.fill)
  let calls : Array[(String, Json)] = []
  let gone = Ref(0)
  let moved : Array[(Double, Array[String])] = []
  let position = Ref(1)
  let src = @sfbase.made_source(call=fn(name, params, done) {
    calls.push((name, params))
    if name == "chat.find" {
      done(Ok({ "words": [Json::string(text(Some(params), "query"))],
        "hits": [{ "seq": 7, "count": 2 }], "held": 1, "of": 1, "whole": true }))
    } else if name == "chat.find.go" {
      let by = number(Some(params), "by").to_int()
      if by != 0 { position.val = if position.val == 1 { 2 } else { 1 } }
      done(Ok({ "at": { "seq": 7, "k": Json::number((position.val - 1).to_double()) },
        "position": Json::number(position.val.to_double()), "total": 2 }))
    } else { done(Ok({})) }
  })
  let r : ChatRef = { station: "ws/st", session: "chat", title: "核对一下", station_name: "Studio" }
  let key = chat_key(r)
  let list : FindList = { showing: fn() { (7.0, 7.0) }, go: fn(seq, words) { moved.push((seq, words)) },
    forget: fn() { gone.val += 1 } }
  let input : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=640.0, h=400.0, platform=0, stable=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lines_up(Is(Some(Start))) |> ignore
    let tips = @sf.TipLayer::new(fn() { Some(root) })
    root.show(fn() { find_chat() == key }, fn(bar) {
      input.val = Some(find_bar_node(bar, src, r, 1.0, list, tips))
    })
  })
  find_open(t.ctx(), key)
  t.draw()
  let id = input.val.unwrap().id()
  assert_eq(t.focused().map(fn(s) { s.role }), Some(TextField))
  t.type_text("查")
  t.run_for(find_typing_ms / 2.0)
  t.type_text("找")
  t.run_for(find_typing_ms / 2.0)
  assert_eq(calls.filter(fn(c) { c.0 == "chat.find" }).length(), 0, msg="the last key starts its own typing interval")
  t.run_for(find_typing_ms / 2.0)
  assert_eq(calls.filter(fn(c) { c.0 == "chat.find" }).map(fn(c) { text(Some(c.1), "query") }), ["查找"])
  assert_eq(find_query(), "查找")
  assert_true(input.val.unwrap().id() == id)
  assert_eq(find_position(), (1, 2))
  t.enter()
  assert_eq(find_position(), (2, 2))
  t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  assert_eq(find_position(), (1, 2))
  assert_eq(finding.field.text(), "查找", msg="both forms of Enter keep the query")
  assert_true(t.find("1/2") is Some(_))
  t.type_text("还没问")
  t.click(Button, label=@sf.t("web-main.find.close"))
  t.run_for(find_typing_ms)
  assert_eq(gone.val, 1)
  assert_eq(find_chat(), "")
  assert_eq(calls.filter(fn(c) { c.0 == "chat.find" }).length(), 1, msg="the cancelled key never asks the core")
  find_open(t.ctx(), key)
  t.draw()
  assert_eq(finding.field.text(), "")
  assert_eq(t.focused().map(fn(s) { s.role }), Some(TextField))
  t.key(@ui.key_escape)
  t.draw()
  assert_eq(find_chat(), "")
  assert_eq(gone.val, 2)
  t.assert_idle()
}
