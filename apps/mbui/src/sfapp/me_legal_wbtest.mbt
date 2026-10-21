// The account's foot and the settings' legal rows (settings/home.mbt; Me.kt, SettingsHome.kt Legal).

///|
test "the account: 注销账号 at its foot asks first, saying what goes" {
  let t = settings_tester("me")
  shown_on_page(t, "注销账号")
  assert_true(!@settings.sheet_up())
  t.tap_text("注销账号")
  t.frame()
  assert_true(@settings.sheet_up(), msg="asked first")
  assert_true(t.find("注销后无法恢复") is Some(_))
}

///|
test "settings: 服务条款 and 隐私政策 open still.fail's pages" {
  let t = settings_tester("home")
  shown_on_page(t, "隐私政策")
  t.tap_text("服务条款")
  assert_true(t.opened().contains("https://still.fail/terms"))
  t.tap_text("隐私政策")
  assert_true(t.opened().contains("https://still.fail/privacy"))
}

///|
/// The page scrolled down until `words` are well inside the window (the list builds rows a little past its foot too).
fn shown_on_page(t : @ui.Tester, words : String) -> Unit {
  t.move(195.0, 400.0)
  for _ in 0..<10 {
    match t.find(words) {
      Some((_, y)) if y < 700.0 => break
      _ => t.wheel(195.0, 400.0, 300.0)
    }
  }
}
