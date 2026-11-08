///|
fn width_known_case(w : Double, platform : Int, home : String) -> Bool {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  t.draw()
  t.find(home) is Some(_)
}

///|
test "the window tree draws Home using the first supplied width" {
  assert_true(width_known_case(390.0, 2, "星火工作室"))
  assert_true(width_known_case(1280.0, 0, "新建对话"))
}

///|
fn width_none_case(w : Double, platform : Int, home : String) -> (Bool, Bool) {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=0.0, h=844.0, platform~)
  t.draw()
  let before = t.find(home) is Some(_)
  t.resize(w, 844.0)
  t.draw()
  (before, t.find(home) is Some(_))
}

///|
test "a window with no width draws Home only after its width is supplied" {
  assert_eq(width_none_case(390.0, 2, "星火工作室"), (false, true))
  assert_eq(width_none_case(1280.0, 0, "新建对话"), (false, true))
}
