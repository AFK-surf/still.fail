// A station's 进程 on 大屏, its table 平铺: laid out once by the width the page gives it, whatever its rows hold. As the
// flat table made its way in, its View::by_room was measured in the room offered (760), came to what its rows held
// side by side (586), and was laid out again at that (flex's way in, size_uncached), so told 586 it stacked them, came
// to 760, and so on, twice a frame, every frame, what each pass made drawn never placed (the switches' sweep,
// 2026-11-14: 36 nodes; tester_placed.mbt).

///|
test "a station's 进程 on 大屏, 平铺: its rows laid out once by the page's width, every node drawn as placed" {
  let app = fixture_app("settings-station-processes")
  let src = round_trip_again(@sffixture.round_trip(app, 0.0), 0.0)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=daily_large.w, h=daily_large.h, platform=daily_large.platform)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("平铺")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.placed_faults(), [])
  let was = t.words().filter(fn(w) { w.0 == "stillfail" }).map(fn(w) { (w.1, w.2, w.3) })
  assert_true(was.length() > 0, msg="its rows drawn")
  t.frame()
  assert_eq(t.placed_faults(), [], msg="the frame after")
  assert_eq(t.words().filter(fn(w) { w.0 == "stillfail" }).map(fn(w) { (w.1, w.2, w.3) }), was, msg="where they were")
}
