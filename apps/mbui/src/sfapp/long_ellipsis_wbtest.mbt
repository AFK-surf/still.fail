// Names in choices and station cards, and a transfer's status, must remain readable when the source makes them long.

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
test "a long station name can be read on its card" {
  let t = screen_in("settings-stations", corner_windows[0], "zh", said=true)
  whole_long_words(t, "Studio — 后面")
}

///|
test "a long station name can be read at the top of its sheet" {
  let t = screen_in("chat-peek", corner_windows[0], "zh", said=true)
  whole_long_words(t, "Studio — 后面")
}

///|
test "a long transfer status can be read in the list" {
  let t = screen_in("files-transfers", corner_windows[1], "zh", said=true)
  whole_long_words(t, "18.3 MB / 48.2 MB — 后面")
}

///|
test "a long transfer name can be read in the list" {
  let t = screen_in("files-transfers", corner_windows[1], "zh", said=true)
  whole_long_words(t, "演示录屏.mp4 — 后面")
}

///|
test "a long selected model can be read in its setting" {
  let t = screen_in("settings-run", corner_windows[1], "zh", said=true)
  whole_long_words(t, "Opus 5.5 — 后面")
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
test "a long model value can be read alongside its connect" {
  let t = screen_in("settings-profile", corner_windows[1], "zh", said=true)
  whole_long_words(t, "星火助手 — 后面")
  whole_long_words(t, "Opus 5.5 — 后面")
}

///|
test "a long activity time can be read alongside its chat" {
  let t = screen_in("settings-connect", corner_windows[1], "zh", said=true)
  whole_long_words(t, "Slack 里问的报销流程 — 后面")
  whole_long_words(t, "昨天 — 后面")
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
