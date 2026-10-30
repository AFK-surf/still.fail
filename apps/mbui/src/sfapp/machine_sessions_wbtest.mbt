// The sessions a station's machine kept, their dialog over a new chat (settings run_more.mbt open_machine_sessions):
// found by runtime and folder, still.fail's own apart from the terminal's.

///|
fn machine_dialog() -> @ui.Tester {
  let src = fixture_app("newchat-machine")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "machine sessions: the terminal's under their days, still.fail's own apart; a runtime and a folder choose among them" {
  let t = machine_dialog()
  // the terminal's, under their days' headings, each when at its end; still.fail's own not among them
  assert_true(t.find("检查线程并操作应用内浏览器") is Some(_))
  assert_true(t.find("3 分钟前") is Some(_))
  assert_true(t.find("Use your image generation tool to make the app icon") is None, msg="still.fail's own among the terminal's")
  // the runtimes of those shown, each with how many
  assert_true(t.find("全部 7") is Some(_), msg="all of the terminal's counted")
  t.tap_text("Claude Code 3")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理构建脚本，把 Windows 的打包也接进 CI") is Some(_))
  assert_true(t.find("检查线程并操作应用内浏览器") is None, msg="a Codex session under Claude Code")
  // still.fail's own, chosen as a folder: they alone, all their runtimes (the one chosen not among them)
  t.tap_text("所有目录")
  t.run_for(@ui.move_most_ms)
  t.tap_text("still.fail 运行的")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Use your image generation tool to make the app icon") is Some(_), msg="still.fail's own chosen")
  assert_true(t.find("整理构建脚本，把 Windows 的打包也接进 CI") is None, msg="a terminal's among still.fail's own")
}
