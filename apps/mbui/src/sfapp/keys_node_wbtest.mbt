// The app's keys taken as they come, by the signed-in shell's node (sfdesk's keys_node), not by an old view under the
// pages as it builds the frame after: ⌘, the settings and ⌘[ back at the key's moment, no frame between; the Mac's
// menu bar's 设置 at its choice.

///|
test "小屏 with a keyboard: ⌘, the settings and ⌘[ back at the key's moment, no frame between; the menu bar's at its choice" {
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  nav_rested(t)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_true(app.nav.top() is Home)
  // (the keymap's Mod: ⌘ where the keys are a Mac's, Ctrl elsewhere)
  let mod = if @ui.keys_system() == 0 { @ui.mod_cmd } else { @ui.mod_ctrl }
  t.key_told(@ui.key_of_char(','), mod, t.time())
  assert_true(app.nav.top() is Settings, msg="⌘, the settings, no frame drawn")
  t.key_told(@ui.key_of_char('['), mod, t.time())
  assert_true(app.nav.top() is Home, msg="⌘[ back, no frame drawn")
  t.run_for(@ui.move_most_ms * 2.0)
  @settings.ask_action("settings")
  assert_true(app.nav.top() is Settings, msg="the menu bar's 设置 at its choice")
}
