// What the library keeps across runs is each run's own (mbui's on_reset, as presented_each_run_wbtest has the
// presenters): a run that leaves a menu open, a mark tapped open, a group's or a page's rows as drawn, a text read and
// the reader's layout changed, the system's bars said, has none of it as the next run begins. Each failed before these
// were put back as a run begins: only the app's reset (sfapp's) put them back, so a run without the app (a Tester of
// sfpages' or of this library's) was given what the run before it left.

///|
/// A run of its own: a window with nothing in it.
fn ker_run() -> @ui.Tester {
  set_words(fn(key, _) { key })
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  t.draw()
  t
}

///|
test "a run begins with no menu open, none going, no submenu pointed at, no mark tapped open, no menu's hold felt: what the run before left is not the next one's" {
  ker_run() |> ignore
  menu_set("甲")
  menu_open_at.val = (10.0, 20.0)
  menu_going.set(["乙"])
  submenu_hover.val = "丙"
  about_open.val = "丁"
  held_felt["戊"] = 3
  ker_run() |> ignore
  assert_eq(menu_open.untracked(), "")
  assert_false(menu_open_by.peek("甲"))
  assert_eq(menu_going.count(), 0)
  assert_eq(menu_open_at.val, (0.0, 0.0))
  assert_eq(submenu_hover.val, "")
  assert_eq(about_open.val, "")
  assert_true(held_felt.is_empty())
}

///|
test "a run begins with no group's rows as the run before drew them" {
  ker_run() |> ignore
  group_rows_of["甲"] = { order: [("a", fn() {  })] }
  ker_run() |> ignore
  assert_true(group_rows_of.is_empty())
}

///|
test "a run begins with no page's blocks as the run before made them, no page's keys left said" {
  ker_run() |> ignore
  page_lists["甲"] = @ui.ListRows::new()
  page_keyed.val = Some([("a", "b")])
  ker_run() |> ignore
  assert_true(page_lists.is_empty())
  assert_true(page_keyed.val is None)
}

///|
test "a run begins with no text read, the reader's layout as at first and its panel shut, whatever the run before left" {
  ker_run() |> ignore
  reading_for("甲") |> ignore
  layout_open.set(Some("甲"))
  style_here.set({ ..reader_style_default, size: reader_style_default.size + 2 })
  ker_run() |> ignore
  assert_true(readings.is_empty())
  assert_true(layout_open.untracked() is None)
  assert_true(style_here.untracked() == reader_style_default, msg="the reader's layout as at first")
}

///|
test "a run begins with none of the system's bars said, nothing said over the window, whatever the run before said" {
  ker_run() |> ignore
  native_bars.on.set(true)
  native_bars.side.set(30.0)
  native_foot_made.set(Some(12.0))
  native_foot_rest.val = Some(12.0)
  native_over_up("屏幕", alive=fn() { true }) |> ignore
  ker_run() |> ignore
  assert_false(native_bars.on.untracked())
  assert_eq(native_bars.side.untracked(), 0.0)
  assert_true(native_foot_made.untracked() is None)
  assert_true(native_foot_rest.val is None)
  assert_false(native_over.up)
  assert_true(native_claims.is_empty())
}
