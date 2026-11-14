// A station's terminals (the user, 2026-11-14/15): among its screens and its browser on its page, not a part of their
// own; one's page over the whole window, a viewer's bar on a wide one and a phone's on a narrow one, 接管 there while
// someone else types, its ⋯ holding 复制工作目录 and 结束会话.

///|
/// A phone's window and a wide one (corner_windows').
let terminal_windows : Array[(String, Double, Double, Int, String)] = [corner_windows[0], corner_windows[5]]

///|
test "a station's terminals are rows among its screens, 打开终端 after them; no part of their own" {
  for win in terminal_windows {
    let t = screen_in("settings-station-terminals", win, "zh")
    for title in ["station", "still.fail"] {
      assert_true(t.find(title) is Some(_), msg="\{win.0}: no row \{title}")
    }
    assert_true(t.query(Radio, label="终端") is None, msg="\{win.0}: a part 终端")
    assert_true(t.query(Radio, label="概览") is Some(_), msg="\{win.0}: no 概览")
    assert_true(t.find(tr("web-pages.terminal.openRow")) is Some(_) || t.all(Link, label=tr("web-pages.terminal.openRow")).length() == 1, msg="\{win.0}: no 打开终端")
  }
}

///|
test "a terminal typed into by someone else: who, and 接管, on a wide window's bar and on a phone's" {
  for win in terminal_windows {
    let t = screen_in("terminal-taken", win, "zh")
    assert_true(t.find("左子健 正在控制") is Some(_), msg="\{win.0}: who types not said")
    t.get(Button, label=tr("android-misc.screen.takeOver")) |> ignore
    // (its screen: what the station gave, drawn)
    assert_true(t.find("import { Effect }") is Some(_), msg="\{win.0}: the screen not drawn")
    assert_true(t.query(Radio, label=tr("web-pages.screen.control")) is None, msg="\{win.0}: 只看/控制 left")
  }
}

///|
test "a terminal typed into here: no 控制 nor 接管; its ⋯ holds 复制工作目录 and 结束会话" {
  for win in terminal_windows {
    let t = screen_in("terminal", win, "zh")
    assert_true(t.query(Button, label=tr("android-misc.screen.takeOver")) is None, msg="\{win.0}: 接管 while typing")
    assert_true(t.query(Button, label=tr("web-pages.screen.control")) is None, msg="\{win.0}: 控制 while typing")
    t.click(Button, label=tr("common.more"))
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(tr("web-pages.terminal.copyCwd")) is Some(_), msg="\{win.0}: no 复制工作目录")
    assert_true(t.find(tr("web-pages.terminal.end")) is Some(_), msg="\{win.0}: no 结束会话")
  }
}
