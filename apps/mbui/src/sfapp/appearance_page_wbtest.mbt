// 外观, one page in every frame (src/sfdesk appearance.mbt): at a width of each tier, on a touch device and on a
// computer; laid out narrow as the web's phone page (the faces a row opening 字体), wide as its desktop page (the faces
// chosen in place, the rail changed in place); the files dragged into a chat a computer's alone.

///|
test "外观, at each width on either screen: 主题, 字体, 动画, 语言; 拖入 chat 的文件 on a computer; the rail's laid out wide; 提示归档 is 归档's" {
  for case in one_page_cases {
    let (w, platform, regular, narrow) = case
    let t = one_page_tester(@settings.Route::Appearance, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    for words in ["主题", "字体", "动画"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    assert_true(t.find("提示归档") is None, msg=at)
    if narrow {
      // the faces a row, saying the app's own
      assert_true(t.find("默认") is Some(_), msg=at)
    }
    // (its last sections: the page scrolled to its end)
    t.wheel(w - 200.0, 450.0, 3000.0)
    t.run_for(@ui.nav_push_ms)
    assert_true(t.find("语言") is Some(_), msg=at)
    assert_eq(t.find("拖入 chat 的文件") is Some(_), platform == 0, msg=at)
    if narrow {
      assert_true(t.find("自定义侧边条") is None, msg=at)
    } else if w >= 1100.0 {
      assert_true(t.find("自定义侧边条") is Some(_), msg=at)
    }
    if narrow {
      // back up, the faces' row opens 字体's page
      t.wheel(w / 2.0, 450.0, -3000.0)
      t.run_for(@ui.nav_push_ms)
      tap_in_page(t, "字体")
      t.run_for(@ui.nav_push_ms)
      assert_true(app.nav.top() == Setting(@settings.Route::Fonts), msg=at)
    }
  }
}
