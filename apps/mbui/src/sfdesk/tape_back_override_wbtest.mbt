// A page's outside-bar back: the frame owns visibility, the page owns an optional live override, and system back is
// still taken by the page's own node before the shell's. Exercise the real bar and its accessibility and input paths.

///|
fn override_tester(
  under : Page,
  platform : Int,
) -> (@ui.Tester, TapeBar, @signals.Signal[String?], @signals.Signal[Bool], Ref[Int], Ref[Int]) {
  @sfbase.reset()
  tape_bars.clear()
  app.nav.push(under)
  app.nav.push(Setting(@settings.Route::About))
  let tb = tape_bar_of(app.nav.top_stay().0)
  let label : @signals.Signal[String?] = @signals.signal(None, same=fn(a, b) { a == b })
  let mounted = @signals.signal(true)
  let page_backs = Ref(0)
  let shell_backs = Ref(0)
  let go = fn() {
    page_backs.val += 1
    label.set(None)
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=700.0, h=900.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(shell) {
      shell.over(Is(true)).takes_back(fn() {
        shell_backs.val += 1
        app.nav.pop() |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(frame) {
      frame.width(Is(Some(700.0))).height(Is(Some(900.0))) |> ignore
      tape_lend_page_back(frame, tb)
      let tips = @sf.TipLayer::new(fn() { None })
      pane_bar_node(
        frame,
        fn() {
          Some(tape_made_bar(Some(under), false, Some({ title: "Run settings", about: "" }), tape_made_back_label(tb)))
        },
        fn() { tape_made_back(tb) },
        fn() { @sf.tape_corners(left=true, right=true) },
        fn() { @sf.theme().p.bg },
        tips,
        fn() { 700.0 },
        fn() { false },
      )
      |> ignore
      frame.show(fn() { mounted.get() }, fn(page) {
        @sf.page_bar_back(page, fn() { label.get() }, go)
        page.show(fn() { label.get() is Some(_) }, fn(back) {
          back.over(Is(true)).takes_back(go) |> ignore
        })
      })
    })
    |> ignore
  })
  t.draw()
  (t, tb, label, mounted, page_backs, shell_backs)
}

///|
fn override_buttons(t : @ui.Tester, label : String) -> Array[@ui.SemNode] {
  t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == label && !s.hidden })
}

///|
fn override_tap(t : @ui.Tester, label : String) -> Unit raise {
  guard override_buttons(t, label) is [b] else { fail("no unique back: \{label}") }
  let (x, y, w, h) = b.rect
  t.tap(x + w / 2.0, y + h / 2.0)
}

///|
test "outside bar back: a setting keeps its button, changes its accessible label as the page changes, and restores the default action" {
  let under = Setting(@settings.Route::Archiving)
  for platform in [1, 2] {
    let (t, _, label, _, page_backs, _) = override_tester(under, platform)
    let original = @sfbase.back_label(under)
    let depth = app.nav.depth()
    assert_eq(override_buttons(t, original).length(), 1)
    label.set(Some("Run settings"))
    t.draw()
    assert_eq(override_buttons(t, original).length(), 0)
    assert_eq(override_buttons(t, "Run settings").length(), 1)
    label.set(Some("Changed label"))
    t.draw()
    assert_eq(override_buttons(t, "Run settings").length(), 0)
    assert_eq(override_buttons(t, "Changed label").length(), 1)
    override_tap(t, "Changed label")
    t.draw()
    assert_eq(page_backs.val, 1)
    assert_eq(app.nav.depth(), depth, msg="the list closed, the route stayed")
    assert_eq(override_buttons(t, original).length(), 1)
    override_tap(t, original)
    assert_eq(page_backs.val, 1)
    assert_eq(app.nav.depth(), depth - 1, msg="the default action popped the page")
  }
}

///|
test "outside bar back: a focused button keeps focus as its label changes and Enter uses the page's action" {
  let (t, _, label, _, page_backs, _) = override_tester(Setting(@settings.Route::Archiving), 0)
  label.set(Some("Run settings"))
  t.draw()
  t.act(Button, Focus, label="Run settings")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Run settings"))
  label.set(Some("Changed label"))
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Changed label"))
  let depth = app.nav.depth()
  t.enter()
  assert_eq(page_backs.val, 1)
  assert_eq(app.nav.depth(), depth)
}

///|
test "outside bar back: a chat or history does not gain a button, while system back first closes the page's list" {
  let chat = { station: "ws1/st1", session: "s1", title: "Chat", station_name: "Willow" }
  for under in [Chat(chat), History(chat, "history", None)] {
    let (t, _, label, _, page_backs, shell_backs) = override_tester(under, 2)
    let depth = app.nav.depth()
    label.set(Some("Run settings"))
    t.draw()
    assert_eq(override_buttons(t, "Run settings").length(), 0)
    assert_eq(t.semantics().filter(fn(s) { s.role == @ui.Role::Button && !s.hidden }).length(), 0)
    t.back()
    assert_eq(page_backs.val, 1)
    assert_eq(shell_backs.val, 0)
    assert_eq(app.nav.depth(), depth)
    t.back()
    assert_eq(shell_backs.val, 1)
    assert_eq(app.nav.depth(), depth - 1)
  }
}

///|
test "outside bar back: releasing the page clears its override and leaves the frame's default back" {
  let under = Setting(@settings.Route::Archiving)
  let (t, tb, label, mounted, page_backs, _) = override_tester(under, 2)
  label.set(Some("Run settings"))
  t.draw()
  assert_eq(override_buttons(t, "Run settings").length(), 1)
  mounted.set(false)
  t.draw()
  assert_true(tape_made_back_label(tb) is None)
  let original = @sfbase.back_label(under)
  assert_eq(override_buttons(t, original).length(), 1)
  let depth = app.nav.depth()
  override_tap(t, original)
  assert_eq(page_backs.val, 0)
  assert_eq(app.nav.depth(), depth - 1)
}

///|
test "outside bar back: an old page released after its replacement cannot clear the replacement's override" {
  tape_bars.clear()
  let tb = tape_bar_of(123)
  let first = @signals.signal(true)
  let second = @signals.signal(false)
  let tree = @view.Tree::new(fn(root) {
    tape_lend_page_back(root, tb)
    root.show(fn() { first.get() }, fn(page) {
      @sf.page_bar_back(page, fn() { Some("First") }, fn() {  })
    })
    root.show(fn() { second.get() }, fn(page) {
      @sf.page_bar_back(page, fn() { Some("Second") }, fn() {  })
    })
  }, time=fn() { 0.0 })
  tree.frame(700.0, 900.0) |> ignore
  assert_eq(tape_made_back_label(tb), Some("First"))
  second.set(true)
  tree.frame(700.0, 900.0) |> ignore
  assert_eq(tape_made_back_label(tb), Some("Second"))
  first.set(false)
  tree.frame(700.0, 900.0) |> ignore
  assert_eq(tape_made_back_label(tb), Some("Second"))
  tape_bars.remove(123) |> ignore
  second.set(false)
  tree.frame(700.0, 900.0) |> ignore
  assert_true(tape_made_back_label(tb) is None)
  assert_false(tape_bars.contains(123), msg="a released entry was not recreated")
}
