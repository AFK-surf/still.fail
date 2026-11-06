// A settings page's fixed wide head: its own nodes follow the page's state and width, while its content scrolls.

///|
priv struct FixedHeadRig {
  t : @ui.Tester
  title : @signals.Signal[String]
  back : @signals.Signal[String]
  deep : @signals.Signal[Bool]
  named : @signals.Signal[Bool]
  shown : @signals.Signal[Bool]
  presses : Ref[Int]
}

///|
fn fixed_head_rig(pane : Bool, platform : Int) -> FixedHeadRig {
  let title = @signals.signal("Run settings")
  let back = @signals.signal("Settings")
  let deep = @signals.signal(false)
  let named = @signals.signal(false)
  let shown = @signals.signal(true)
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=1000.0, h=500.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      page.grow(Is(1.0)).min_height(Is(Some(0.0))).lends(pane_lent, pane) |> ignore
      page.show(fn() { shown.get() }, fn(head) {
        fixed_wide_head_node(
          head,
          fn() { title.get() },
          fn() { back.get() },
          fn() { presses.val += 1 },
          frame=fn() {
            { back: if deep.get() { Some("under") } else { None }, top: 0.0, foot: 0.0, named: named.get() }
          },
        )
      })
      page.box(fn(body) {
        body.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        body.scrolls(@view.Scroll::list(), fn(content) {
          for i in 0..<30 {
            content.box(fn(row) {
              row.height(Is(Some(70.0))) |> ignore
              words_node(row, fn() { "Body \{i}" }, fn() { desk_muted }) |> ignore
            }) |> ignore
          }
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  { t, title, back, deep, named, shown, presses }
}

///|
test "fixed wide head: its centred column follows the page width and its title stays put when the body scrolls" {
  for pane in [false, true] {
    let r = fixed_head_rig(pane, 0)
    let t = r.t
    let first = t.rect_of("Run settings").unwrap()
    let inset = if pane { panel_words } else { desk_column_in }
    assert_eq(first.0, (1000.0 - desk_lane_most) / 2.0 + inset)
    let body = t.rect_of("Body 0")
    t.wheel(500.0, 400.0, 300.0)
    t.draw()
    assert_eq(t.rect_of("Run settings"), Some(first))
    assert_true(t.rect_of("Body 0") != body)
    t.resize(700.0, 500.0)
    let resized = t.rect_of("Run settings").unwrap()
    assert_eq(resized.0, if pane { panel_words } else { desk_lane_in + desk_column_in })
  }
}

///|
test "fixed wide head: title and back change with the page, and a frame's own name hides and restores it" {
  let r = fixed_head_rig(false, 0)
  let t = r.t
  assert_true(t.rect_of("Settings") is None)
  r.deep.set(true)
  r.title.set("Models")
  r.back.set("Run settings")
  t.draw()
  assert_true(t.rect_of("Models") is Some(_))
  assert_true(t.rect_of("Run settings") is Some(_))
  assert_true(t.rect_of("Run settings").unwrap().1 < t.rect_of("Models").unwrap().1)
  assert_true(t.query(Link, label="Run settings") is Some(_))
  r.named.set(true)
  t.draw()
  assert_true(t.rect_of("Models") is None)
  assert_true(t.query(Link, label="Run settings") is None)
  r.title.set("Accounts")
  r.named.set(false)
  t.draw()
  assert_true(t.rect_of("Accounts") is Some(_))
  assert_true(t.query(Link, label="Run settings") is Some(_))
  r.deep.set(false)
  t.draw()
  assert_true(t.query(Link, label="Run settings") is None)
}

///|
test "fixed wide head: back by touch, keyboard and accessibility; removing the head removes its action" {
  for platform in [0, 2] {
    let r = fixed_head_rig(false, platform)
    let t = r.t
    r.deep.set(true)
    t.draw()
    t.click(Link, label="Settings")
    assert_eq(r.presses.val, 1)
    let (x, y, w, h) = t.query(Link, label="Settings").unwrap().rect
    let (_, _, _, text_h) = t.rect_of("Settings").unwrap()
    assert_true(h >= text_h + desk_back_foot)
    t.tap(x + w / 2.0, y + h - 1.0)
    assert_eq(r.presses.val, 2)
    t.act(Link, Activate, label="Settings")
    assert_eq(r.presses.val, 3)
    t.act(Link, Focus, label="Settings")
    t.enter()
    assert_eq(r.presses.val, 4)
    r.shown.set(false)
    t.draw()
    assert_true(t.query(Link, label="Settings") is None)
    assert_true(t.focused().map(fn(s) { s.label }) != Some("Settings"))
  }
}
