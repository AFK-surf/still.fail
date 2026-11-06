// A retained composer consumes input and asynchronous answers without asking a page to rebuild it.

///|
test "a retained composer receives picked files and completes a delayed send once, with the same editor" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=0)
  let offline = @signals.signal(false)
  let calls : Array[String] = []
  let answer : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
  let sent : Array[String] = []
  let src = @sfbase.made_source(call=fn(name, _, done) {
    calls.push(name)
    if name == "chat.outsideRefs" { answer.val = Some(done) }
    else if name == "ref.marks" { done(Ok({ "marks": [{ "start": 0, "end": 7 }] })) }
    else if name == "paste.info" { done(Ok({ "threshold": 800 })) }
    else { done(Ok({})) }
  })
  let node : Ref[ComposerNode?] = Ref(None)
  let built = Ref(0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    built.val += 1
    node.val = Some(composer_node(root, src, "node-draft", fn() {
      { station: "workspace/station", draft: "node-draft", session: "chat", placeholder: "Write",
        toolbar: None, toolbar_node: None, note: [], tail: None, roomy: false, locked: false, offline: offline.get(), warm_agent: true }
    }, fn(w) { sent.push(w.text.get()) }, (root, fn(_, _) { 900.0 }), fn(_, _, _, _) {  }))
  })
  t.draw()
  let n = node.val.unwrap()
  let w = n.writing
  let field_id = n.field.id()
  w.field.focus()
  t.type_text("@[chat] a message")
  t.draw()
  assert_eq(w.text.get(), "@[chat] a message")
  assert_true((n.opened)())
  assert_eq(calls.filter(fn(s) { s == "session.warm" }).length(), 1)
  w.field.pick(1, 4)
  offline.set(true)
  t.draw()
  offline.set(false)
  t.draw()
  assert_eq((node.val.unwrap().field.id(), w.field.selection(), built.val), (field_id, (1, 4), 1))
  t.picks([("notes.txt", b"picked once")])
  t.click(Button, label=@sf.t("web-main.composer.attach"))
  t.draw()
  t.draw()
  assert_eq(calls.filter(fn(s) { s == "composer.add" }).length(), 1)
  assert_eq(w.files.get().length(), 1)
  // The core's delayed answer resumes this send through the composer's effect, with no old build polling it.
  let tree = @ui.view_tree().unwrap()
  let send_label = @sf.t("web-main.composer.send")
  let send_said = t.get(Button, label=send_label)
  let send_id = tree.said_order().filter(fn(s) { s.said is Some({ label, .. }) && label == send_label })[0].id
  let (sx, sy, sw, sh) = send_said.rect
  assert_eq(tree.target_at(sx + sw / 2.0, sy + sh / 2.0), @view.Pressed(send_id),
    msg="send=\{send_said.describe()}, areas=\{tree.finger_areas(send_id)}, all=\{t.semantics_dump()}")
  t.click(Button, label=@sf.t("web-main.composer.send"))
  assert_eq(sent.length(), 0)
  assert_eq(calls.filter(fn(s) { s == "chat.outsideRefs" }).length(), 1,
    msg="calls=\{calls}, words=\{w.text.get()}, ready=\{w.ready.get()}, starting=\{w.starting.get()}, field=\{n.field.rect()}, cap=\{n.cap.rect()}")
  (answer.val.unwrap())(Ok({ "chats": [] }))
  t.draw()
  t.draw()
  assert_eq(sent, ["@[chat] a message"])
  assert_eq(calls.filter(fn(s) { s == "composer.add" }).length(), 1)
  assert_eq((node.val.unwrap().field.id(), built.val), (field_id, 1))
}

///|
test "a composer made after its new chat sends keeps the source box until that send lets it go" {
  @sfbase.reset()
  composing_reset()
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=2, stable=false)
  let tall = 145.119
  composer_hold("carried", 0.0, tall, @sfbase.flight_wait_ms)
  let node : Ref[ComposerNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    node.val = Some(composer_node(root, src, "carried", fn() {
      { station: "ws/st", draft: "carried", session: "chat", placeholder: "Write",
        toolbar: None, toolbar_node: None, note: [], tail: None, roomy: false, locked: false, offline: false, warm_agent: true }
    }, fn(_) { }, (root, fn(_, _) { 900.0 }), fn(_, _, _, _) { }))
  })
  t.draw()
  let n = node.val.unwrap()
  assert_eq(n.cap.laid_size().1, tall)
  let field = n.field.id()
  // The real row is placed: the same source height now has the flight's release deadline, in either page.
  composer_hold("carried", 0.0, tall, @sfbase.flight_carry_after_ms)
  t.draw()
  t.run_for(@sfbase.flight_carry_after_ms / 2.0)
  assert_eq(n.cap.laid_size().1, tall)
  assert_eq(composer_held_box(t.ctx(), "carried"), tall)
  t.run_for(@sfbase.flight_carry_after_ms / 2.0)
  assert_true(n.cap.laid_size().1 < tall)
  assert_eq(composer_held_box(t.ctx(), "carried"), 0.0)
  assert_eq(n.field.id(), field)
}
