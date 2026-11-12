// A row that opens a panel (link_row_opens_node), on a narrow page and a wide one: the panel stands by the row
// itself (Node(row)), and as it closes the focus is the row's, whether a pointer or the keyboard opened it (#5181).

///|
/// A page `w` wide (its look by its width) holding a node taking the focus ("别处") and a row "账号" that opens a panel
/// "面板" from itself (link_row_opens_node), the times it opened counted in `opened`; on a window `w` × 800 pointed at as `platform`
/// says.
fn opens_row_tester(platform : Int, w : Double, opened : Ref[Int]) -> @ui.Tester {
  presenters_reset()
  let t = @ui.Tester::new(fn(_) {  }, w~, h=800.0, platform~)
  @ui.set_view_app(
    fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(p) {
        p.grow(Is(1.0)).pad(Is(40.0)) |> ignore
        look_lent(p, look_for(w))
        p.box(fn(e) {
          e
          .width(Is(Some(50.0)))
          .height(Is(Some(50.0)))
          .presses(Is(true))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label="别处"))))
          .on_press(fn() {  })
          |> ignore
        })
        |> ignore
        link_row_opens_node(p, fn() { "账号" }, fn(row) {
          opened.val += 1
          panel_nodes("面板", fn(v, _) { words_node(v, fn() { "面板里的字" }, fn() { desk_muted }) |> ignore }, from=Node(row))
        })
      })
      |> ignore
      // (what of the presented the tree draws, over the page: as the app's tree has it)
      presented_nodes(root)
    },
    around=fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        @ui.old_views_here(c)
        presented(c)
      })
    },
  )
  t.draw()
  t.draw()
  t
}

///|
/// The windows it is tried on: a phone's with a finger (a sheet), a narrow one with a mouse, a wide one (beside the
/// row).
let opens_row_ways : Array[(Int, Double)] = [(2, 390.0), (0, 390.0), (0, 1200.0)]

///|
test "a row that opens a panel from itself (link_row_opens_node): pressed by the pointer, the panel by the row; Escape closes it, the focus on the row" {
  for way in opens_row_ways {
    let (platform, w) = way
    let at = "platform \{platform} \{w} wide"
    let opened = Ref(0)
    let t = opens_row_tester(platform, w, opened)
    let rows = t.all(Link, label="账号")
    guard rows.length() == 1 else { fail("\{at}: \{rows.length()} rows") }
    let r = rows[0].rect
    t.tap(r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(opened.val, 1, msg="\{at}: opened \{opened.val} times, row at \{Repr(r)}")
    assert_true(presenter_visible(), msg="\{at}: open")
    match t.find("面板里的字") {
      // (beside the row on a wide window: under it)
      Some((_, y)) => if w > 1000.0 { assert_true(y > r.1 + r.3, msg="\{at}: under the row") }
      None => fail("\{at}: nothing in it")
    }
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    assert_false(presenter_visible(), msg="\{at}: closed")
    assert_eq(t.focused().map(fn(s) { s.label }), Some("账号"), msg="\{at}: \{t.focus_said()}")
    assert_eq(t.audit(), [], msg=at)
  }
}

///|
test "a row that opens a panel from itself (link_row_opens_node), by the keyboard: Enter opens it, Escape closes it, the focus still on the row, Enter opens it again" {
  for way in opens_row_ways.filter(fn(w) { w.0 == 0 }) {
    let (platform, w) = way
    let at = "\{w} wide"
    let opened = Ref(0)
    let t = opens_row_tester(platform, w, opened)
    t.act(Button, Focus, label="别处")
    t.tab()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("账号"), msg=at)
    for round in 0..<2 {
      t.enter()
      t.run_for(@ui.move_most_ms)
      assert_eq(opened.val, round + 1, msg="\{at}: round \{round}")
      assert_true(presenter_visible(), msg="\{at}: round \{round}: open")
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_false(presenter_visible(), msg="\{at}: round \{round}: closed")
      assert_eq(t.focused().map(fn(s) { s.label }), Some("账号"), msg="\{at}: round \{round}: \{t.focus_said()}")
    }
    assert_eq(t.audit(), [], msg=at)
  }
}
