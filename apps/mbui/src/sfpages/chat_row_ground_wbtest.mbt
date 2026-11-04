///|
test "a retained chat row shows selection from its first frame and follows it without being rebuilt" {
  for platform in [0, 2] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let selected = @signals.signal(true)
    let made = Ref(0)
    let item = { ..sample_chat(0), title: "A chat", ago: "5 minutes ago", full: "A moment ago" }
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      made.val += 1
      chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { selected.get() }, Side, fn() { 0 }) |> ignore
    })
    t.draw()
    let lit = fn() {
      t.drawn_rects().filter(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.4 == @sf.theme().p.selected }).length()
    }
    assert_eq(lit(), 1, msg="selected when made, platform \{platform}")
    selected.set(false)
    t.run_for(left_lit_ms + left_fade_ms + @sf.dur_ms)
    assert_eq(lit(), 0, msg="selection left, platform \{platform}")
    selected.set(true)
    t.run_for(@sf.dur_ms)
    assert_eq(lit(), 1, msg="selected again, platform \{platform}")
    assert_eq(made.val, 1)
  }
}

///|
test "a mouse entering a retained chat row shows its background and time with its archive action" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let item = { ..sample_chat(0), title: "A chat", ago: "5 minutes ago", full: "A moment ago" }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=320.0, h=200.0, platform=0, pointing=Mouse)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
    let tips = @sf.TipLayer::new(fn() { Some(popup) })
    chat_row_node(root, @sfbase.sample_source, tips, fn() { item }, "agents", fn() { false }, Side, fn() { 0 }) |> ignore
  })
  t.draw()
  assert_true(t.find(item.ago) is None)
  let (x, y, w, h) = t.get(Link, label=item.title).rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(@sf.dur_ms)
  assert_true(t.find(item.ago) is Some(_), msg="the row says when while pointed at")
  assert_true(t.query(Button, label=@sf.t("web-main.chat.archiveNamed", args=[("title", item.title)])) is Some(_))
  assert_true(t.drawn_rects().iter().any(fn(r) { r.2 > 100.0 && r.3 > 30.0 && r.4 == @sf.theme().p.hover }), msg="the row's hover background")
  t.move(319.0, 199.0)
  t.run_for(@sf.dur_ms)
  assert_true(t.find(item.ago) is None)
  t.assert_idle()
}
