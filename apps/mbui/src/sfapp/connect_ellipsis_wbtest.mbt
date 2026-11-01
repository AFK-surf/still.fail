// The two ways of adding a Slack workspace must remain readable where the dialog is narrow.

///|
test "the manual setup action is whole in a narrow new-connect dialog" {
  for (lang, action) in [
    ("zh", "不使用配置 token，手动创建 app"),
    ("en", "Create the app yourself"),
  ] {
    let t = screen_in("settings-new-connect", corner_windows[0], lang)
    assert_eq(t.lines_of(action), [action], msg=lang)
  }
}
