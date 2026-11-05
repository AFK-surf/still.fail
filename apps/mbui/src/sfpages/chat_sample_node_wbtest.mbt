///|
test "a chat's first read is a retained sample on every width: no sample words, actions or picture requests escape its bones" {
  for platform in [0, 2] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let error : @signals.Signal[Json?] = @signals.signal(None)
    let loading = @signals.signal(true, same=fn(a, b) { a == b })
    let src = { ..@sfbase.made_source(), topic: fn(_, _) { { value: None, error: error.get(), version: 0 } } }
    let r : ChatRef = { station: "sample/st", session: "chat", title: "Chat", station_name: "Studio" }
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=844.0, platform~)
    let built = Ref(0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.show(fn() { loading.get() }, fn(sample) {
        built.val += 1
        sample.grow(Is(1.0)) |> ignore
        chat_waiting_node(sample, src, r, fn() { sample.window().0 }, fn() { 74.0 }, fn() { 60.0 })
      })
    })
    for width in [390.0, 740.0, 1280.0, 390.0] {
      t.resize(width, 844.0)
      assert_true(t.drawn_instances().length() > 0, msg="the loading sample is drawn at \{width}")
      assert_true(!t.words().iter().any(fn(w) { w.0.contains("字") }), msg="sample words at \{width}: \{t.words()}")
      assert_true(!t.semantics_dump().contains("字"), msg="sample read out at \{width}")
      assert_eq(t.image_loads().length(), 0)
      assert_eq(built.val, 1)
    }
    error.set(Some({ "message": "读取失败" }))
    t.draw()
    let note = @sf.t("android-chat.chat.unreadable", args=[("error", "读取失败")])
    assert_true(t.find(note) is Some(_), msg=t.semantics_dump())
    for word in t.words() {
      if word.0.contains("读取失败") { assert_true(word.2 >= 60.0, msg="the error is below the bar: \{word}") }
    }
    t.assert_idle()
    loading.set(false)
    t.draw()
    assert_true(t.find(note) is None)
    t.assert_idle()
  }
}
