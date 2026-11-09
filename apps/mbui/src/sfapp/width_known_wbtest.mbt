// The app's window tree made before its window has a size (app_tree: shell_is reads a width of 0: nothing picked for
// it), then the frames the Tester draws as it is made and as it asks for them: the size given at the first one's start
// (Tree::frame sets the room before what follows it is worked out), the shell picked by it.

///|
/// The fixture's Home signed in, `w` wide on `platform`'s screen: whether the workspace's Home is drawn once the Tester
/// has drawn the frames it asks for (`home`, words of it).
fn width_known_case(w : Double, platform : Int, home : String) -> Bool {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  t.draw()
  t.find(home) is Some(_)
}

///|
test "the window tree made with no width yet, then its frames: Home drawn by the shell for the width given (a phone's and a desktop's)" {
  // (Home as each draws it: the phone's its workspace's name at its top; the desktop's 新建对话 beside the sidebar)
  assert_eq((width_known_case(390.0, 2, "星火工作室"), width_known_case(1280.0, 0, "新建对话")), (true, true))
}

///|
/// The fixture's Home signed in, its window 0 wide at first (its frames drawn so), then `w` wide on `platform`'s
/// screen: whether Home is drawn while it is 0 wide, and after it has a width (`home`, words of it).
fn width_none_case(w : Double, platform : Int, home : String) -> (Bool, Bool) {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=0.0, h=844.0, platform~)
  t.draw()
  let none = t.find(home) is Some(_)
  t.resize(w, 844.0)
  t.draw()
  (none, t.find(home) is Some(_))
}

///|
test "a window 0 wide, its frames drawn so, then made as wide as a phone's or a desktop's: Home drawn once it has a width" {
  assert_eq(
    (width_none_case(390.0, 2, "星火工作室"), width_none_case(1280.0, 0, "新建对话")),
    ((false, true), (false, true)),
  )
}
