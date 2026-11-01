// Long names in choices and headings stay readable; list summaries stay compact where their content may be shortened.

///|
fn whole_long_words(t : @ui.Tester, fragment : String) -> Unit raise {
  let lines = t.lines_of(fragment)
  assert_true(lines.length() > 1, msg="\{fragment}: \{lines}")
  assert_true(lines.iter().all(fn(s) { !s.has_suffix("…") }), msg="\{fragment}: \{lines}")
  assert_true(lines.last().unwrap_or("").contains("wide"), msg="\{fragment}: \{lines}")
}

///|
test "a long model name can be read when choosing a model" {
  let t = screen_in("settings-run-models", corner_windows[1], "zh", said=true)
  whole_long_words(t, "Opus 5.5")
}

///|
test "a choice keeps the badges beside its short name" {
  for win in [corner_windows[1], corner_windows[4]] {
    let t = screen_in("settings-run-accounts", win, "zh")
    assert_eq(t.corner_faults(), [], msg=win.0)
  }
}

///|
test "a long station name can be read at the top of its sheet" {
  let t = screen_in("chat-peek", corner_windows[0], "zh", said=true)
  whole_long_words(t, "Studio — 后面")
}

///|
test "a transfer's long name remains a compact one-line summary" {
  let t = screen_in("files-transfers", corner_windows[1], "zh", said=true)
  let lines = t.lines_of("演示录屏.mp4 — 后面")
  assert_eq(lines.length(), 1, msg="\{lines}")
  assert_true(lines[0].has_suffix("…"), msg="\{lines}")
}

///|
test "a station card's long name remains a one-line summary" {
  let t = screen_in("settings-stations", corner_windows[0], "zh", said=true)
  let lines = t.lines_of("Studio — 后面")
  assert_eq(lines.length(), 1, msg="\{lines}")
  assert_true(lines[0].has_suffix("…"), msg="\{lines}")
}

///|
test "a long selected model remains a one-line setting" {
  let t = screen_in("settings-run", corner_windows[1], "zh", said=true)
  let lines = t.lines_of("Opus 5.5 — 后面")
  assert_eq(lines.length(), 1, msg="\{lines}")
  assert_true(lines[0].has_suffix("…"), msg="\{lines}")
}

///|
test "a long connect owner can be read" {
  let t = screen_in("settings-connect", corner_windows[1], "zh", said=true)
  whole_long_words(t, "林 — 后面")
}

///|
test "a long station name fits the account section heading" {
  let t = screen_in("settings-profiles", corner_windows[1], "zh", said=true)
  let lines = t.lines_of("已在 Studio — 后面")
  assert_true(lines.length() > 1, msg="\{lines}")
  assert_true(lines.last().unwrap_or("").contains("上登录"), msg="\{lines}")
}

///|
test "a long destination can be read in the history" {
  let t = screen_in("history", corner_windows[0], "zh", said=true)
  whole_long_words(t, "整理发布清单 — 后面")
}

///|
test "a connect in a profile keeps its long name as a one-line summary" {
  let t = screen_in("settings-profile", corner_windows[1], "zh", said=true)
  let lines = t.lines_of("星火助手 — 后面")
  assert_eq(lines.length(), 1, msg="\{lines}")
  assert_true(lines[0].has_suffix("…"), msg="\{lines}")
}

///|
test "a long profile check keeps its refresh button beside it" {
  for long in [false, true] {
    let t = screen_in("settings-profile", corner_windows[1], "zh", said=long)
    let (x, y, w, h) = t.rect_of("订阅有效").unwrap()
    let (bx, by, _, bh) = t.get(Button, label="重新检查").rect
    assert_true(bx >= x + w - 0.5 && by < y + h && by + bh > y, msg="long=\{long}: \{(x, y, w, h)}, \{(bx, by, bh)}")
  }
}

///|
test "a long chat and activity time both have room on their row" {
  let t = screen_in("settings-connect", corner_windows[1], "zh", said=true)
  let chat = t.lines_of("Slack 里问的报销流程 — 后面")
  let time = t.lines_of("昨天 — 后面")
  assert_eq(chat.length(), 1, msg="\{chat}")
  assert_eq(time.length(), 1, msg="\{time}")
  assert_true(chat[0].starts_with("Slack") && chat[0].has_suffix("…"), msg="\{chat}")
  assert_true(time[0].starts_with("昨天") && time[0].has_suffix("…"), msg="\{time}")
}

///|
test "a long completion message can be read in the history" {
  let t = screen_in("history", corner_windows[0], "zh", said=true)
  whole_long_words(t, "标记为做完了：截图已更新")
}

///|
test "a short status stays on one line beside a chat title" {
  for (lang, status) in [("zh", "已拒绝"), ("en", "Denied")] {
    let t = screen_in("settings-vault-item", corner_windows[0], lang)
    assert_eq(t.lines_of(status), [status], msg=lang)
  }
}
