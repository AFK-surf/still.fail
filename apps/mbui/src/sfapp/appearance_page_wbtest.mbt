// 外观, one page in every frame (src/sfdesk appearance.mbt): at a width of each tier, on a touch device and on a
// computer; the faces a row opening 字体 on every screen; laid out wide the rail changed in place; the files dragged
// into a chat a computer's alone. 字体 and 下方栏 one page each on every screen too.

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
    // the faces a row, saying the app's own
    assert_true(t.find("默认") is Some(_), msg=at)
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
    // back up, the faces' row opens 字体's page
    t.wheel(w / 2.0, 450.0, -3000.0)
    t.run_for(@ui.nav_push_ms)
    tap_in_page(t, "字体")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::Fonts), msg=at)
  }
}

///|
test "字体, at each width on either screen: the places' choice, a chat as they set it, the faces a row each" {
  for case in one_page_cases {
    let (w, platform, regular, narrow) = case
    let t = one_page_tester(@settings.Route::Fonts, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    for words in ["界面", "正文", "代码"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    assert_true(t.find("默认") is Some(_), msg=at)
    if narrow {
      // back to 外观 (the page under it: settings here), the faces a row each
      assert_true(t.find("字体") is Some(_), msg=at)
    }
  }
}

///|
test "下方栏, at each width on either screen: its bars a card each, the one in view said, a new one to make" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::BarSettings, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("下方栏") is Some(_), msg=at)
    assert_true(t.find("第 1 栏") is Some(_), msg=at)
    assert_true(t.find("当前") is Some(_), msg=at)
    // a place's "−" takes it off its bar
    assert_true(t.query(Button, label="从此栏移除Station") is Some(_), msg=at)
    t.click(Button, label="从此栏移除Station")
    t.frame()
    assert_true(t.query(Button, label="从此栏移除Station") is None, msg=at)
  }
}
