// 外观, 字体 and 下方栏 (appearance.mbt, font_setting.mbt, bars.mbt) alone, at each width, with a finger and with a
// mouse: 字体 a section, the faces chosen a row opening its page; laid out wide the rail changed in place; the files
// dragged into a chat keyboard and mouse's alone.
///|
test "外观, at each width on either screen: 主题, 字体, 动画, 语言; 拖入 chat 的文件 on a computer; the rail's laid out wide; 提示归档 is 归档's" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Appearance, w, platform~)
    let at = "\{w} platform \{platform}"
    for words in ["主题", "字体", "动画"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    assert_true(t.find("提示归档") is None, msg=at)
    // the faces a row, saying the app's own
    assert_true(t.find("默认") is Some(_), msg=at)
    // (its last sections: the page scrolled to its end)
    t.wheel(w - 200.0, 450.0, 3000.0)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("语言") is Some(_), msg=at)
    assert_eq(t.find("拖入 chat 的文件") is Some(_), platform == 0, msg=at)
    // the rail changed where it is: laid out wide alone, asked of the shell
    assert_eq(t.find("自定义侧边条") is Some(_), laid_wide(w), msg=at)
    if laid_wide(w) {
      let asked = Ref(0)
      @sfbase.shell.val = { ..@sfbase.bare_shell(), edit_rail: fn() { asked.val += 1 } }
      t.click(Button, label="自定义侧边条")
      t.draw()
      assert_eq(asked.val, 1, msg=at)
    }
    // the faces' row (字体, the faces chosen, after 主题: the page scrolled back to its top) opens 字体's page (its
    // words whole: 拖入 chat 的文件's note says 默认 too)
    t.wheel(w - 200.0, 450.0, -3000.0)
    t.run_for(@ui.move_most_ms)
    tap_words(t, "默认")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(Fonts), msg=at)
  }
}

///|
test "外观: a setting opening another page has the same title weight as a setting changed here" {
  for platform in [0, 2] {
    let plain = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.setting(c, "主题", fn() {  })
    }, w=900.0, platform~)
    plain.draw()
    let weight = plain.census().weight
    let link = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.setting_link(c, "fonts", "字体", "") |> ignore
    }, w=900.0, platform~)
    link.draw()
    assert_eq(link.census().weight, weight)
  }
}

///|
test "字体, at each width on either screen: the places' choice, a chat as they set it, the faces a row each" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Fonts, w, platform~)
    let at = "\{w} platform \{platform}"
    for words in ["界面", "正文", "代码"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    assert_true(t.find("默认") is Some(_), msg=at)
  }
}

///|
test "下方栏, at each width on either screen: what a bar's title has at its end on the title's line, in its middle" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(BarSettings, w, platform~)
    let at = "\{w} platform \{platform}"
    // the middles of the words drawn so, top to bottom
    let middles = fn(words : String) -> Array[Double] {
      let m = t.words().filter(fn(x) { x.0 == words && x.5 > 0.5 }).map(fn(x) { x.2 + x.4 / 2.0 })
      m.sort()
      m
    }
    let (titles, deletes) = (middles("第 1 栏") + middles("第 2 栏"), middles("删除"))
    let (current, make) = (middles("当前"), middles("设为当前"))
    guard titles.length() == 2 && deletes.length() == 2 && current.length() == 1 && make.length() == 1 else {
      fail("\{at}: \{titles} \{deletes} \{current} \{make}")
    }
    // 第 1 栏 with 当前 and 删除, 第 2 栏 with 设为当前 and 删除 (2026-10-26: 删除 4 over 当前 and the title)
    for pair in [(titles[0], current[0]), (titles[0], deletes[0]), (titles[1], make[0]), (titles[1], deletes[1])] {
      assert_true((pair.0 - pair.1).abs() < 0.5, msg="\{at}: \{pair}")
    }
  }
}

///|
test "下方栏, at each width on either screen: its bars a card each, the one in view said, a new one to make" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(BarSettings, w, platform~)
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
