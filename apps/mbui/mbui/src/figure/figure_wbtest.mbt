///|
test "a panel and its child are placed relative to their parent and keep mbui's corners" {
  let t = @ui.Tester::new(fn(c) {
    canvas(c, 200.0, 120.0, 0xF0F0F0FFL, fn() {
      panel(c, 20.0, 15.0, 150.0, 80.0, 0xFFFFFFFFL, 20.0, fn() {
        panel(c, 10.0, 12.0, 40.0, 25.0, 0x123456FFL, 8.0, fn() { })
      })
    })
  }, w=200.0, h=120.0, corners_held=false)
  let rs = t.drawn_rect_corners()
  let panel_rect = rs.iter().find_first(fn(r) { r.4 == 0xFFFFFFFFL }).unwrap()
  assert_eq((panel_rect.0, panel_rect.1, panel_rect.2, panel_rect.3), (20.0, 15.0, 150.0, 80.0))
  assert_eq(panel_rect.5, (20.0, 20.0, 20.0, 20.0))
  let child = rs.iter().find_first(fn(r) { r.4 == 0x123456FFL }).unwrap()
  assert_eq((child.0, child.1, child.2, child.3), (30.0, 27.0, 40.0, 25.0))
  assert_eq(child.5, (8.0, 8.0, 8.0, 8.0))
}
