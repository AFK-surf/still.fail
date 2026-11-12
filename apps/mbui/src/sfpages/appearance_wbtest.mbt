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
test "外观's 震动 switch is at the end of its row and turns haptics off and on at each width" {
  for (w, platform) in page_cases + [(390.0, 1)] {
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Appearance, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) {
          calls.push((name, params))
          (s.call)(name, params, done)
        } }
    })
    let at = "\{w} platform \{platform}"
    let titles = t.boxes_held().filter(fn(b) { b.text == "震动" })
    assert_eq(titles.length(), 1, msg="\{at}: \{Repr(titles.map(fn(b) { (b.x, b.y, b.w, b.h, b.weight) }))}")
    let (sx, y, sw, sh) = t.get(Switch, label="震动").rect
    // (where the switch is drawn: its track, the widest round ground in what is read out. What is read out is its
    // press's room, which may be wider than the track drawn in it: a small switch's, 9 more each side with a finger)
    let mut track : (Double, Double)? = None
    for b in t.boxes_held() {
      if b.bg != 0L &&
        b.h > 0.0 &&
        (b.radius * 2.0 - b.h).abs() < 0.5 &&
        b.x >= sx - 0.5 &&
        b.x + b.w <= sx + sw + 0.5 &&
        b.y >= y - 0.5 &&
        b.y + b.h <= y + sh + 0.5 &&
        (match track {
          Some((_, tw)) => b.w > tw
          None => true
        }) {
        track = Some((b.x, b.w))
      }
    }
    guard track is Some((x, _)) else { fail("\{at}: no track drawn in the switch") }
    // (the title's words as they are drawn: where they end, their line's middle)
    guard t.rect_of("震动") is Some((tx, ty, tw, th)) else { fail("\{at}: no 震动 drawn") }
    assert_true(x >= tx + tw, msg="\{at}: switch follows its title: title ends \{tx + tw}, switch \{x}")
    if !laid_wide(w) {
      let title_mid = ty + th / 2.0
      assert_true((y + sh / 2.0 - title_mid).abs() < 2.0, msg="\{at}: switch is on the title's line: title \{Repr((ty, th))}, switch \{Repr((y, sh))}")
    }
    assert_eq(t.get(Switch, label="震动").check, Some(On), msg=at)
    t.tap_text("震动")
    t.draw()
    assert_true(calls.filter(fn(call) { call.0 == "prefs.set" }).is_empty(), msg="\{at}: only the switch answers")
    // A press just outside the small switch still reaches it.
    t.tap(x - 4.0, y + sh / 2.0)
    t.frame()
    t.frame()
    let off = calls.filter(fn(call) { call.0 == "prefs.set" })
    assert_eq(text(Some(off[off.length() - 1].1), "haptics"), "off", msg=at)
    t.click(Switch, label="震动")
    t.frame()
    t.frame()
    let on = calls.filter(fn(call) { call.0 == "prefs.set" })
    assert_true(field(Some(on[on.length() - 1].1), "haptics") is Some(Null), msg=at)
  }
}

///|
test "外观: wide setting titles have the same weight as the rows in 自动决策" {
  for platform in [0, 2] {
    let decision = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.link_row(c, "decision", "结束时") |> ignore
    }, w=900.0, platform~)
    decision.draw()
    let weight = decision.census().weight
    assert_eq(weight, ["500"])
    let plain = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.setting(c, "主题", fn() {  })
    }, w=900.0, platform~)
    plain.draw()
    assert_eq(plain.census().weight, weight)
    // 外观's settings laid out wide (主题's choice, 字体's row going to its page): their titles as strong
    let page = setting_tester(Appearance, 1280.0, platform~)
    for title in ["主题", "字体", "震动"] {
      let found = page.boxes_held().filter(fn(b) { b.text == title })
      assert_eq(found.map(fn(b) { b.weight }), [500], msg="\{platform}: \{title} \{Repr(found.map(fn(b) { (b.x, b.y, b.w, b.h) }))}")
    }
    // a switch's row in a group (分享给其他 station over 可用的 station): its title no lighter than the rows by it
    let switch = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.group(c, fn() { @sf.switch_row(c, "share", "分享给其他 station", true) |> ignore })
    }, w=900.0, platform~)
    switch.draw()
    assert_eq(switch.census().weight, weight)
  }
}

///|
test "setting rows keep their title prominent at every width and with either input" {
  for (w, platform) in page_cases {
    let t = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      @sf.group(c, fn() {
        @sf.link_row(c, "plain", "Plain title") |> ignore
        @sf.link_row(c, "value", "Title with value", value="Current") |> ignore
        @sf.link_row(c, "note", "Title with note", note="More detail") |> ignore
        @sf.link_row(c, "summary", "Summary title", value="Selected", note="Explanation") |> ignore
        @sf.link_row(c, "custom", "Custom title", title_style=@sf.desk_list_title.then(@ui.text_style(weight=Normal))) |> ignore
        @sf.switch_row(c, "switch", "Switch title", false) |> ignore
        @sf.link_row(c, "strong", "Strong title", strong=true) |> ignore
        @sf.setting(c, "Setting title", fn() {  })
      })
      @sf.switch_row(c, "outside", "Standalone switch", false) |> ignore
    }, w~, platform~)
    t.draw()
    let boxes = t.boxes()
    let at = "\{w} platform \{platform}"
    for title in ["Plain title", "Title with value", "Title with note", "Summary title", "Custom title", "Switch title", "Setting title", "Standalone switch"] {
      let found = boxes.filter(fn(b) { b.text == title })
      assert_eq(found.length(), 1, msg="\{at}: \{title}")
      assert_eq(found[0].weight, 500, msg="\{at}: \{title}")
      assert_eq(found[0].color, boxes.filter(fn(b) { b.text == "Strong title" })[0].color, msg="\{at}: \{title} ink")
    }
    assert_eq(boxes.filter(fn(b) { b.text == "Strong title" })[0].weight, 700, msg=at)
    assert_eq(boxes.filter(fn(b) { b.text == "Explanation" })[0].weight, 400, msg=at)
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
      fail("\{at}: \{Repr(titles)} \{Repr(deletes)} \{Repr(current)} \{Repr(make)}")
    }
    // 第 1 栏 with 当前 and 删除, 第 2 栏 with 设为当前 and 删除 (2026-10-26: 删除 4 over 当前 and the title)
    for pair in [(titles[0], current[0]), (titles[0], deletes[0]), (titles[1], make[0]), (titles[1], deletes[1])] {
      assert_true((pair.0 - pair.1).abs() < 0.5, msg="\{at}: \{Repr(pair)}")
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
