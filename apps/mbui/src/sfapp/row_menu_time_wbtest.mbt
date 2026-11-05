// 大屏 with keyboard and mouse: a chat's row right clicked, its menu open beside it: the row stays as pointed at, its
// time where it shows (1 小时前), as main's (row_menu_open: its menu said to the rows as it opens, read by each row's
// node as it changes).

///|
test "大屏 by mouse: a row's menu open, the row says its time as when pointed at" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  // (a row's middle: its title over its last words, the second of the list's day)
  let (x, y) = (150.0, 330.0)
  // (its time "…前", in the row's band of the side column: none while nothing points at it)
  let times = fn() {
    t.words().filter(fn(wd) { wd.0.has_suffix("前") && wd.1 < 296.0 && wd.2 > y - 25.0 && wd.2 < y + 25.0 }).length()
  }
  let before = times()
  t.right_click(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq((before, times()), (0, 1), msg="no time in the row with its menu open")
}
