// The sessions a station's machine kept, their dialog over a new chat (settings run_more.mbt open_machine_sessions):
// found by runtime and folder, still.fail's own apart from the terminal's.

///|
fn machine_dialog() -> @ui.Tester {
  let src = fixture_app("newchat-machine")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
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

///|
test "machine sessions: one looked at is a step of the same dialog, back from it back to the list as it was left; at 大屏 and at 小屏" {
  for win in [(1280.0, 800.0, 0), (390.0, 844.0, 2)] {
    let at = "\{win.0}"
    let src = fixture_app("newchat-machine")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=win.0, h=win.1, platform=win.2)
    t.run_for(@ui.move_most_ms)
    t.tap_text("Claude Code 3")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("检查线程并操作应用内浏览器") is None, msg=at)
    t.tap_text("整理构建脚本，把 Windows 的打包也接进 CI")
    t.run_for(@ui.move_most_ms)
    // the look: its own foot, the list's filters gone, the same presenter
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("继续此会话") is Some(_), msg=at)
    assert_true(t.find("Claude Code 3") is None, msg=at)
    // back (its head's back key; the system's back): the list, the runtime chosen in it still chosen
    if win.2 == 0 {
      t.click(Button, label="返回")
    } else {
      t.back()
    }
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("继续此会话") is None, msg=at)
    assert_true(t.find("Claude Code 3") is Some(_), msg=at)
    assert_true(t.find("检查线程并操作应用内浏览器") is None, msg="\{at}: the runtime chosen forgotten")
    // back from the list: closed
    t.back()
    t.run_for(@ui.move_most_ms * 2.0)
    assert_true(!@sf.presenting(), msg=at)
  }
}

///|
/// Whether the machine's sessions' dialog is up (its runtimes' filter), and its folders' pick over it (a choice of it).
fn dialog_and_pick(t : @ui.Tester) -> (Bool, Bool) {
  (t.find("Claude Code 3") is Some(_), t.find("still.fail 运行的") is Some(_))
}

///|
test "machine sessions at 大屏 with a mouse: the folders' pick over the dialog; a press outside both, Escape: the pick alone goes, the dialog stays" {
  let steps = ["outside", "escape"]
  let seen = []
  for step in steps {
    let t = machine_dialog()
    t.tap_text("所有目录")
    t.run_for(@ui.move_most_ms)
    let up = dialog_and_pick(t)
    match step {
      "outside" => t.tap(40.0, 40.0)
      _ => t.key_named("esc") |> ignore
    }
    t.run_for(@ui.move_most_ms)
    seen.push((step, up, dialog_and_pick(t)))
  }
  assert_eq(seen, steps.map(fn(s) { (s, (true, true), (true, false)) }))
}
