// The app's window tree made before its window has a size (app_tree: shell_is reads a width of 0: nothing picked for
// it), then the frames the Tester draws as it is made and as it asks for them: the size given at the first one's start
// (Tree::frame sets the room before what follows it is worked out), the shell picked by it. The old view whole
// (app_state_island's body: what it says of the frame, state_node) built at no point of it.

///|
/// The fixture's Home signed in, `w` wide on `platform`'s screen: whether the old view whole's body ran as the Tester was
/// made (its own frames) or in the frames asked for after (state_node set), and whether the workspace's Home is drawn by
/// then (`home`, words of it).
fn width_known_case(w : Double, platform : Int, home : String) -> (Bool, Bool) {
  new_run()
  let src = fixture("home")
  state_node.val = -2
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  let first = state_node.val != -2
  // (and on, its frames drawn as it asks for them: still never built)
  t.draw()
  (first || state_node.val != -2, t.find(home) is Some(_))
}

///|
test "the window tree made with no width yet, then its frames: the old view whole never built, Home drawn by the shell for the width given (a phone's and a desktop's)" {
  // (Home as each draws it: the phone's its workspace's name at its top; the desktop's 新建对话 beside the sidebar)
  assert_eq((width_known_case(390.0, 2, "星火工作室"), width_known_case(1280.0, 0, "新建对话")), ((false, true), (false, true)))
}

///|
/// The fixture's Home signed in, its window 0 wide at first (its frames drawn so), then `w` wide on `platform`'s
/// screen: whether the old view whole's body ran while it was 0 wide (state_node set), and after, whether Home is drawn
/// (`home`, words of it) and nothing of the old view whole built.
fn width_none_case(w : Double, platform : Int, home : String) -> (Bool, Bool, Bool) {
  new_run()
  let src = fixture("home")
  state_node.val = -2
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=0.0, h=844.0, platform~)
  t.draw()
  let none = state_node.val != -2
  t.resize(w, 844.0)
  t.draw()
  (none, t.find(home) is Some(_), state_node.val != -2)
}

///|
test "a window 0 wide, its frames drawn so, then made as wide as a phone's or a desktop's: nothing built while it is 0 wide (no old view whole), Home drawn once it has a width, nothing of the old view whole after" {
  assert_eq(
    (width_none_case(390.0, 2, "星火工作室"), width_none_case(1280.0, 0, "新建对话")),
    ((false, true, false), (false, true, false)),
  )
}
