// The small agent card's figures as retained nodes: the core's answers can arrive and change while they are shown,
// and its context's entry can become available, busy, or unavailable without making the other figures again.

///|
fn agent_figures_tester(
  card : () -> Json?,
  entry : () -> ContextTile?,
  shown : @signals.Signal[Bool],
  platform : Int,
) -> @ui.Tester {
  new_run()
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=360.0, h=180.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(column) {
      column.width(Is(Some(320.0))) |> ignore
      column.show(fn() { shown.get() }, fn(at) { agent_tiles_node(at, card, top=14.0, entry~) })
      @sf.words_node(column, fn() { "after figures" }, fn() { tile_name }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "agent figures follow the card as figures arrive, change and disappear" {
  let value : Ref[Json?] = Ref(None)
  let version = @signals.signal(0)
  let shown = @signals.signal(true)
  let card = fn() { version.get() |> ignore; value.val }
  let t = agent_figures_tester(card, fn() { None }, shown, 0)
  let after = fn() { t.semantics().filter(fn(s) { s.label == "after figures" })[0].rect.1 }
  let empty_y = after()
  assert_true(t.semantics().filter(fn(s) { s.label.has_prefix(tr("android-chat.agent.cost")) }).is_empty())
  value.val = Some({ "cost": "$1.25", "cache": { "text": "80%" }, "context": { "percent": 72.6, "level": "amber" } })
  version.set(1)
  t.draw()
  let cost = tr("android-chat.agent.cost") + " $1.25"
  let cache = tr("android-chat.agent.cache") + " 80%"
  let context = tr("android-chat.agent.context") + " 73%"
  let figures = t.semantics().filter(fn(s) { s.label == cost || s.label == cache || s.label == context })
  assert_eq(figures.map(fn(s) { s.label }), [cost, cache, context])
  assert_true(figures.iter().all(fn(s) { s.role == Text }), msg="history has no context action")
  assert_true(after() > empty_y, msg="known figures occupy their row and top padding")
  let cost_id = figures[0].id
  value.val = Some({ "cost": "$12.3456", "context": { "unknown": true, "text": "?", "level": "red" } })
  version.set(2)
  t.draw()
  let revised = t.semantics().filter(fn(s) { s.label == tr("android-chat.agent.cost") + " $12.3456" })
  assert_eq(revised.length(), 1)
  assert_eq(revised[0].id, cost_id, msg="the cost node is retained as its words change")
  assert_true(t.semantics().any(fn(s) { s.label == tr("android-chat.agent.context") + " ?" }))
  assert_true(t.semantics().all(fn(s) { s.label != cache }))
  value.val = None
  version.set(3)
  t.draw()
  assert_eq(after(), empty_y, msg="no known figures leave no padding")
}

///|
test "agent context figure follows its action state and accepts touch, keys and accessibility" {
  for platform in [0, 2] {
    let shown = @signals.signal(true)
    let available = @signals.signal(true)
    let busy = @signals.signal(false)
    let failed = @signals.signal(false)
    let compacts = @signals.signal(true)
    let opened : Array[Int] = []
    let card : Json? = Some({ "context": { "percent": 88.0, "level": "red" } })
    let entry = fn() -> ContextTile? {
      if available.get() {
        Some({ open: fn() { opened.push(1) }, busy: busy.get(), failed: failed.get(), compacts: compacts.get() })
      } else { None }
    }
    let t = agent_figures_tester(fn() { card }, entry, shown, platform)
    let label = tr("web-mobile.agent.contextCompactable") + " 88%"
    let button = t.all(Button, label~)[0]
    let (x, y, w, h) = button.rect
    assert_true(w >= 44.0 && h >= 44.0, msg="the context has a full touch target")
    t.key(@ui.key_tab)
    t.draw()
    assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
    t.key(@ui.key_code_enter)
    t.draw()
    assert_eq(opened.length(), 1, msg="keyboard activation")
    t.tap(x + w / 2.0, y + h / 2.0)
    t.draw()
    assert_eq(opened.length(), 2)
    busy.set(true)
    t.draw()
    t.tap(x + w / 2.0, y + h / 2.0)
    t.draw()
    assert_eq(opened.length(), 2, msg="a busy context does not open")
    busy.set(false)
    failed.set(true)
    t.draw()
    let tree = @ui.view_tree().unwrap()
    assert_true(tree.drawn().any(fn(d) { tree.drawn_name(d.id) == "/icon/info/" }), msg="failure shown beside the name")
    compacts.set(false)
    t.draw()
    let normal = tr("android-chat.agent.context") + " 88%"
    assert_eq(t.all(Button, label=normal).length(), 1)
    t.act(Button, Activate, label=normal)
    t.draw()
    assert_eq(opened.length(), 3, msg="semantic activation")
    available.set(false)
    t.draw()
    assert_true(t.all(Button, label=normal).is_empty())
    assert_true(t.semantics().any(fn(s) { s.role == Text && s.label == normal }))
    shown.set(false)
    t.draw()
    assert_true(t.semantics().all(fn(s) { s.label != normal }), msg="the node is released with its owner")
  }
}
