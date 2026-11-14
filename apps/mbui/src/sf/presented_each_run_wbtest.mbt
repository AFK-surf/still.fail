// What is presented is each run's own (run_begins.mbt: as a run begins, mbui's on_reset or what runs the app): a menu one
// run leaves open is not drawn by the next, which begins with nothing presented, as the app's reset (parts_reset) has
// it; where what runs the app began the run before its Tester, what was opened then is that run's, not closed again as
// the Tester is made. A Tester without the app
// (sfpages', this library's) was given what the one before it left open: viz_mermaid_node_wbtest, run after
// vault_wbtest (its last test leaves a menu open), drew that menu over its chart.

///|
/// A wide window (a keyboard and mouse's) whose tree holds a button 开 that opens a menu of 一 at a point; the
/// presenters drawn over it.
fn pe_tester() -> @ui.Tester {
  set_words(fn(key, _) { key })
  let t = @ui.Tester::new(fn(_c) {  }, w=1200.0, h=800.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(col) {
      col.padding(Is((100.0, 100.0, 0.0, 0.0))) |> ignore
      button_node(col, fn() { "开" }, fn() {
        menu([Some(menu_item_of("一", fn() {  }))], from=at_point(300.0, 300.0))
      })
      |> ignore
    })
    |> ignore
    presented_nodes(root)
  })
  t.draw()
  t
}

///|
test "a run begins with nothing presented: a menu the run before left open is not drawn by the next" {
  let first = pe_tester()
  first.tap_text("开")
  first.run_for(@ui.move_most_ms)
  assert_true(presenting(), msg="open in the first run")
  assert_true(first.find("一") is Some(_))
  // (the first run ends with it open)
  let next = pe_tester()
  next.run_for(@ui.move_most_ms)
  assert_false(presenting(), msg="nothing presented as the next begins")
  assert_true(next.find("一") is None, msg="the menu the first left open not drawn")
  assert_true(next.find("开") is Some(_))
  let faults = next.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "a run begun by what runs the app before its Tester: what it opened then is shown by that Tester, not closed again as it is made" {
  // (the first run leaves a menu open)
  let first = pe_tester()
  first.tap_text("开")
  first.run_for(@ui.move_most_ms)
  assert_true(presenting())
  // (the next run begun by the app, as sfapp's new_run begins one: nothing presented; then a menu opened before its Tester)
  let begun = Ref(true)
  run_begun_by_app.val = fn() { begun.val }
  run_begin()
  assert_false(presenting(), msg="the run before's menu gone as the app begins the next")
  menu([Some(menu_item_of("二", fn() {  }))], from=at_point(300.0, 300.0))
  let next = pe_tester()
  begun.val = false
  run_begun_by_app.val = fn() { false }
  next.run_for(@ui.move_most_ms)
  assert_true(presenting(), msg="what the run opened before its Tester still presented")
  assert_true(next.find("二") is Some(_), msg="and drawn")
  assert_true(next.find("一") is None)
}
