// A link row follows the panel's row line without changing its identity or its ordinary page and card insets.

///|
test "link row follows changing panel reach and word insets on both page widths" {
  for look in [Narrow, Wide] {
    let context : @signals.Signal[PanelRowContext] = @signals.signal({ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
    let pressed = Ref(0)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      root.padding(Is((20.0, 0.0, 20.0, 0.0))) |> ignore
      panel_rows_lent(root, fn() { context.get() })
      link_row_node(root, fn() { "Account" }, fn() { pressed.val += 1 })
    })
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let id = t.get(Link, label="Account").id
    let row = fn() { t.query(Link, label="Account").unwrap().rect }
    let title = fn() { tree.drawn().iter().find_first(fn(d) { d.words == "Account" }).unwrap() }
    let arrow = fn() { tree.drawn().iter().find_first(fn(d) { tree.drawn_name(d.id) == "/icon/chevron-right/" }).unwrap() }
    assert_eq((row().0, row().2, title().x, arrow().x + arrow().w), (12.0, 296.0, 20.0, 300.0), msg="\{look}: panel reach")
    t.tap(row().0 + 1.0, row().1 + row().3 / 2.0)
    t.act(Link, Focus, label="Account")
    context.set({ sides_in: 24.0, rows_out: 8.0, words_in: 20.0, small: false })
    t.draw()
    assert_eq((row().0, row().2, title().x, arrow().x + arrow().w), (20.0, 280.0, 40.0, 280.0), msg="\{look}: word inset")
    assert_eq((t.get(Link, label="Account").id, t.focused().map(fn(s) { s.label })), (id, Some("Account")))
    context.set({ sides_in: 24.0, rows_out: 0.0, words_in: 0.0, small: true })
    t.draw()
    assert_eq((row().0, row().2, title().x, arrow().x + arrow().w), (20.0, 280.0, 36.0, 284.0), msg="\{look}: small panel")
    assert_true(tree.drawn().iter().any(fn(d) {
      (d.x, d.y, d.w, d.h) == row() && d.radius == small_panel_inner(r_menu)
    }), msg="\{look}: small-panel corner")
    t.enter()
    assert_eq(pressed.val, 2)
  }
}

///|
test "link row keeps page and card insets when a panel changes" {
  for look in [Narrow, Wide] {
    let page = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      root.padding(Is((20.0, 0.0, 20.0, 0.0))) |> ignore
      link_row_node(root, fn() { "Page row" }, fn() {  })
    })
    page.draw()
    let tree = @ui.view_tree().unwrap()
    let title = tree.drawn().iter().find_first(fn(d) { d.words == "Page row" }).unwrap()
    let arrow = tree.drawn().iter().find_first(fn(d) { tree.drawn_name(d.id) == "/icon/chevron-right/" }).unwrap()
    assert_eq((title.x, arrow.x + arrow.w), (36.0, 284.0), msg="\{look}: ordinary page")
    for card in [false, true] {
      let context : @signals.Signal[PanelRowContext] = @signals.signal({ sides_in: 24.0, rows_out: 8.0, words_in: 20.0, small: false })
      let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=300.0, platform=2)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        look_lent(root, look)
        panel_rows_lent(root, fn() { context.get() })
        group_node(root, fn(g) { link_row_node(g, fn() { "Card row" }, fn() {  }) }, card~)
      })
      let inset = fn() {
        let tree = @ui.view_tree().unwrap()
        let row = t.query(Link, label="Card row").unwrap().rect
        let title = tree.drawn().iter().find_first(fn(d) { d.words == "Card row" }).unwrap()
        title.x - row.0
      }
      t.draw()
      assert_eq(inset(), text_in, msg="\{look}, card=\{card}: card inset")
      context.set({ sides_in: 32.0, rows_out: 8.0, words_in: 30.0, small: false })
      t.draw()
      assert_eq(inset(), text_in, msg="\{look}, card=\{card}: changing panel inset")
    }
  }
}
