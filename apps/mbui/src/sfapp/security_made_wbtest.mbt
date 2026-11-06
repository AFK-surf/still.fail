// Security is made in the window's tree in each screen's shell, not hosted as one old view.

///|
test "security's state and explanation are the tree's own on each screen with either input" {
  for (platform, w) in [(2, 390.0), (0, 390.0), (2, 700.0), (0, 700.0), (2, 1280.0), (0, 1280.0)] {
    let t = if w < 600.0 {
      settings_home_tester(true, platform, h=900.0, mode="settings-security").0
    } else {
      large_about_tester(true, platform, w~, mode="settings-security")
    }
    assert_true(app.nav.top() == Setting(@settings.Route::Security), msg="\{w} platform \{platform}")
    let own = tree_words_drawn()
    for word in [@sf.t("web-pages.security.on"), @sf.t("web-pages.security.onLead")] {
      assert_true(own.iter().any(fn(s) { s.contains(word) }), msg="\{word} at \{w} platform \{platform}: \{own}")
    }
    assert_true(t.find(@sf.t("web-pages.security.on")) is Some(_))
  }
}
