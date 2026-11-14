// The app in a browser started with a finger (a phone's Safari or Chrome): its fields a finger's, as on a phone, so a
// field held offers 粘贴 (the web's host's text menu), as nothing else in a browser offers it to a finger.

///|
/// The fixture's chat on a phone's screen in a browser (4), started with `native` and pointed at with it, after the
/// app's host_setup, its composer held: whether the text menu is up, and what it offers.
fn web_composer_held(native : @ui.Pointing) -> (Bool, Int) raise {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(
    fn(c) { view(c, src) },
    tree=app_tree(src),
    w=390.0,
    h=844.0,
    platform=4,
    pointing=native,
    native~,
  )
  host_setup()
  let log = t.drive("until 发消息\nhold 700 发消息\n")
  t.draw()
  let (shown, _, _, _, _, can) = t.text_menu()
  // (the feel said for the whole run: put back for the tests after this one)
  @ui.feel_as(-1)
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  (shown, can)
}

///|
test "a browser started with a finger: the composer, empty, held: its menu up offering 粘贴" {
  let (shown, can) = web_composer_held(Finger)
  assert_true(shown, msg="no text menu over the field held")
  assert_true((can & @hostapi.text_menu_paste) != 0, msg="its menu offers \{can}, no paste")
}

///|
test "a browser started with a mouse: the composer as a desktop's, no finger's menu" {
  let (shown, _) = web_composer_held(Mouse)
  assert_false(shown)
}
