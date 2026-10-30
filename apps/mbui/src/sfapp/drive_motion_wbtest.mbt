// The files' rows as the folder changes (rows_view by their keys, docs/list-motion.md): a file made comes where it is,
// its room opening; one taken out goes where it was, its room closing; none at once.

///|
test "files: a file made comes where it is, one taken out goes where it was, neither in one frame" {
  // (drive_tester's, the clock set after reset, which puts the fixture's own back, and before the fixture's steps
  // are said)
  reset()
  let clock = Ref::new(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("drive-motion")
  open_drive_fixture("drive-motion")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  let shown = fn(words : String) -> Double {
    match t.words().filter(fn(w) { w.0 == words }) {
      [w, ..] => w.5
      [] => -1.0
    }
  }
  assert_eq(shown("新建的笔记.md"), -1.0)
  // made (the fixture's first step): in the list, as far shown as its room is open
  clock.val = 2001.0
  t.frame()
  t.run_for(@ui.row_size_ms / 4.0)
  let half = shown("新建的笔记.md")
  assert_true(half > 0.0 && half < 1.0, msg="\{half}")
  t.run_for(@ui.row_size_ms)
  assert_eq(shown("新建的笔记.md"), 1.0)
  // taken out (its second): still there as its room closes, then gone
  clock.val = 3601.0
  t.frame()
  // (seen only while it is less than half closed: out of sight by then, row_held_look)
  t.run_for(@ui.row_size_ms / 10.0)
  let going = shown("发布清单.md")
  assert_true(going > 0.0 && going < 1.0, msg="\{going}")
  t.run_for(@ui.row_size_ms)
  assert_eq(shown("发布清单.md"), -1.0)
  fix_clock.val = None
}
