// The title keeps its place while a request is pending and moves only when that request answers.

///|
test "title generation paints a moving light and its answer slides into the same line" {
  title_motions.clear()
  title_motions["test"] = { old: "Old title", next: "", at: 0.0, waiting: true }
  let t = @ui.Tester::new(fn(c) {
    row_title(c, "test", "Old title", @ui.text_style(size=Ui, leading=L6, wrap=false))
  })
  t.draw()
  let first = t.drawn_glyphs()
  t.run_for(title_shine_ms / 4.0)
  let later = t.drawn_glyphs()
  assert_true(first != later)
  let at = t.time()
  title_motions["test"] = { old: "Old title", next: "New title", at, waiting: false }
  t.frame()
  let start = t.drawn_glyphs()
  t.run_for(title_swap_ms / 2.0)
  let middle = t.drawn_glyphs()
  assert_true(start != middle)
  t.run_for(title_swap_ms)
  assert_true(t.find("New title") is Some(_))
  title_motions.clear()
}

///|
test "title request waits, ignores a duplicate, and clears on failure or an unchanged answer" {
  title_motions.clear()
  let base = @sffixture.fixture("home")
  let calls : Ref[Int] = Ref(0)
  let answer : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    call: fn(_, _, done) { calls.val += 1; answer.val = Some(done) },
  }
  let t = @ui.Tester::new(fn(c) { row_title(c, "test", "Old", @ui.text_style(size=Ui)) })
  t.draw()
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  assert_true(title_motions.get("test") is Some({ waiting: true, .. }))
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  assert_eq(calls.val, 1)
  (answer.val.unwrap())(Err({ "message": "failed" }))
  assert_true(title_motions.get("test") is None)
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  (answer.val.unwrap())(Ok({ "autoTitle": "Old" }))
  assert_true(title_motions.get("test") is None)
  regenerate_row_title(src, "test", "station", 8.0, "Old")
  (answer.val.unwrap())(Ok({ "autoTitle": "New" }))
  assert_true(title_motions.get("test") is Some({ old: "Old", next: "New", waiting: false, .. }))
  title_motions.clear()
}

///|
test "reduced motion keeps waiting words still and shows the new title at once" {
  title_motions.clear()
  title_motions["test"] = { old: "Old", next: "", at: 0.0, waiting: true }
  let t = @ui.Tester::new(fn(c) { row_title(c, "test", "Old", @ui.text_style(size=Ui, leading=L6)) })
  t.set_reduce_motion(true)
  t.draw()
  let first = t.drawn_glyphs()
  t.run_for(title_shine_ms / 4.0)
  assert_eq(t.drawn_glyphs(), first)
  title_motions["test"] = { old: "Old", next: "New", at: t.time(), waiting: false }
  t.frame()
  assert_true(t.find("New") is Some(_))
  t.set_reduce_motion(false)
  title_motions.clear()
}

///|
test "retained chat rows animate the request and release it after both the answer and core title arrive" {
  let places : Array[@sf.ListAt] = [Side, Whole]
  for at in places {
    for core_first in [true, false] {
      @sfbase.reset()
      @sf.set_words(@sfbase.fill)
      title_motions.clear()
      let title = @signals.signal("Old title")
      let item = { ..sample_chat(0), title: "Old title" }
      let key = @sfbase.row_name(item)
      let base = @sffixture.fixture("home")
      let answer : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
      let src : Source = { ..base, call: fn(_, _, done) { answer.val = Some(done) } }
      let made = Ref(0)
      let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform=0)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
        let tips = @sf.TipLayer::new(fn() { Some(popup) })
        made.val += 1
        chat_row_node(root, src, tips, fn() { { ..item, title: title.get() } }, "agents", fn() { false }, at, fn() { 0 }) |> ignore
      })
      t.draw()
      regenerate_row_title(src, key, "station", 8.0, "Old title")
      t.frame()
      let first = t.drawn_glyphs()
      t.run_for(title_shine_ms / 4.0)
      let later = t.drawn_glyphs()
      assert_true(first != later, msg="the retained row paints the waiting light: first \{first}, later \{later}, state \{title_motions.get(key) is Some({ waiting: true, .. })}")
      assert_eq(made.val, 1, msg="the list is not rebuilt for the light")
      (answer.val.unwrap())(Ok({ "autoTitle": "New title" }))
      if core_first { title.set("New title") }
      t.frame()
      let start = t.drawn_glyphs()
      t.run_for(title_swap_ms / 2.0)
      assert_true(start != t.drawn_glyphs(), msg="the title moves through its line")
      t.run_for(title_swap_ms)
      if !core_first {
        assert_true(title_motions.get(key) is Some(_), msg="keep the answer until the core publishes it")
        title.set("New title")
        t.frame()
      }
      assert_true(title_motions.get(key) is None, msg="the title motion is released")
      assert_true(t.find("New title") is Some(_))
      assert_eq(made.val, 1)
      title_motions.clear()
    }
  }
}

///|
test "a retained chat row respects reduced motion for the generated title" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  title_motions.clear()
  let title = @signals.signal("Old title")
  let item = { ..sample_chat(0), title: "Old title" }
  let key = @sfbase.row_name(item)
  title_motions[key] = { old: "Old title", next: "", at: 0.0, waiting: true }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform=0)
  t.set_reduce_motion(true)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
    let tips = @sf.TipLayer::new(fn() { Some(popup) })
    chat_row_node(root, @sfbase.sample_source, tips, fn() { { ..item, title: title.get() } }, "agents", fn() { false }, Side, fn() { 0 }) |> ignore
  })
  t.draw()
  let first = t.drawn_glyphs()
  t.run_for(title_shine_ms / 4.0)
  assert_eq(first, t.drawn_glyphs())
  title_motions[key] = { old: "Old title", next: "New title", at: t.time(), waiting: false }
  t.frame()
  assert_true(t.find("New title") is Some(_))
  title.set("New title")
  t.frame()
  assert_true(title_motions.get(key) is None)
  t.set_reduce_motion(false)
  title_motions.clear()
}
