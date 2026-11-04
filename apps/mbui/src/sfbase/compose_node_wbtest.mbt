// The same retained editor follows core drafts and optimistic actions without rebuilding its page or losing the
// selection. A call's answer and its topic may arrive in either order.

///|
test "a retained draft follows core changes, preserves its field, and stops reading when its owner leaves" {
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0)
  writings_reset()
  let topic = @signals.signal((0, Json::object({
    "text": "first words",
    "rev": 1,
    "version": 1,
    "files": [],
    "quotes": [],
  })))
  let src : Source = {
    ..made_source(),
    topic: fn(_, _) {
      let (version, value) = topic.get()
      { value: Some(value), error: None, version }
    },
  }
  let shown = @signals.signal(true)
  let builds = Ref(0)
  let draft : Ref[Writing?] = Ref(None)
  @ui.set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(p) {
      builds.val += 1
      let w = writing_in(p, src, "retained-draft")
      draft.val = Some(w)
      @ui.field(p, w.field) |> ignore
    })
  })
  t.draw()
  let w = draft.val.unwrap()
  w.field.pick(2, 6)
  // Upload progress and readiness change; no new text revision means neither selection nor editor is replaced.
  topic.set((1, {
    "text": "first words",
    "rev": 1,
    "version": 2,
    "files": [{ "id": "f1", "loaded": 12, "size": 40 }],
    "quotes": [{ "id": "q1", "text": "a quotation" }],
    "ready": true,
    "uploading": true,
  }))
  t.draw()
  assert_eq(builds.val, 1)
  assert_eq((w.field.text(), w.field.selection()), ("first words", (2, 6)))
  assert_eq((w.files.get().length(), w.quotes.get().length(), w.ready.get(), w.uploading.get()), (1, 1, true, true))
  shown.set(false)
  t.draw()
  topic.set((2, { "text": "a later draft", "rev": 2, "version": 3 }))
  t.draw()
  assert_eq(w.text.get(), "first words")
  shown.set(true)
  t.draw()
  assert_eq(builds.val, 2)
  assert_eq(w.field.text(), "a later draft")
  assert_eq(draft.val.unwrap().text.get(), "a later draft")
}

///|
test "a retained draft never adopts a stale topic over an optimistic edit when its acknowledgement arrives first" {
  let t = @ui.Tester::new(fn(_) {  }, w=300.0, h=200.0)
  writings_reset()
  let topic = @signals.signal((0, Json::object({ "text": "before", "rev": 1, "version": 1 })))
  let replies : Array[(Result[Json, Json]) -> Unit] = []
  let src : Source = {
    ..made_source(call=fn(_, _, done) { replies.push(done) }),
    topic: fn(_, _) {
      let (version, value) = topic.get()
      { value: Some(value), error: None, version }
    },
  }
  let draft : Ref[Writing?] = Ref(None)
  @ui.set_view_app(fn(root) { draft.val = Some(writing_in(root, src, "retained-draft")) })
  t.draw()
  let w = draft.val.unwrap()
  let seen : Array[String] = []
  let stop = @signals.effect(fn() { seen.push(w.text.get()) })
  w.field.set("typed now")
  writing_text(src, w, "typed now")
  // A late topic with a new subscription version, but an older core version, must wait for the edit.
  topic.set((1, { "text": "late old words", "rev": 2, "version": 1 }))
  t.draw()
  assert_eq(w.text.get(), "typed now")
  (replies[0])(Ok({ "version": 3 }))
  t.draw()
  assert_eq((w.text.get(), w.field.text()), ("typed now", "typed now"))
  assert_eq(seen, ["before", "typed now"])
  topic.set((2, { "text": "typed now", "rev": 3, "version": 3, "ready": true }))
  t.draw()
  assert_eq((w.text.get(), w.ready.get(), w.pending.get()), ("typed now", true, 0))
  stop()
}
