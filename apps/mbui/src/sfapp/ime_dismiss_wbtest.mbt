// The soft keyboard while a draft is being written: ordinary chat actions keep it, leaving to view a picture does not.

///|
test "tapping explanatory text beside a field keeps the soft keyboard" {
  for platform in [1, 2] {
    new_run()
    let field = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) {
      c.column(gap=12.0, fn() {
        c.editor("example/field", placeholder="输入文字", field~) |> ignore
        c.text("这里是说明文字") |> ignore
      }) |> ignore
    }, w=360.0, h=740.0, platform~)
    t.tap_text("输入文字")
    t.type_text("写到一半")
    assert_true(t.ime().0)
    t.tap_text("这里是说明文字")
    assert_true(t.ime().0, msg="the keyboard stays after tapping an explanation (platform \{platform})")
    t.type_text("继续")
    assert_eq(field.text(), "写到一半继续")
  }
}

///|
test "a touch menu keeps an active field's soft keyboard until a choice is made" {
  for platform in [1, 2] {
    new_run()
    let field = @ui.Field::new()
    let open = Ref(false)
    let chosen : Ref[String?] = Ref(None)
    let t = @ui.Tester::new(fn(c) {
      c.column(gap=12.0, fn() {
        c.editor("example/field", placeholder="输入文字", field~) |> ignore
        let trigger = @kit.button(c, "选择", key="example/choose")
        if trigger.clicked { open.val = !open.val }
        let menu = @kit.dropdown_menu(c, "example/menu", open.val, trigger.id, [@kit.menu_item("one", label="一个选项")])
        open.val = menu.open
        if menu.chosen is Some(_) { chosen.val = menu.chosen }
      }) |> ignore
    }, w=360.0, h=740.0, platform~)
    t.tap_text("输入文字")
    t.type_text("写到一半")
    assert_true(t.ime().0)
    t.click(Button, label="选择")
    assert_true(open.val)
    assert_true(t.ime().0, msg="the keyboard stays while the menu is open (platform \{platform})")
    t.type_text("再写")
    assert_eq(field.text(), "写到一半再写", msg="the open menu does not swallow the input method")
    t.click(MenuItem, label="一个选项")
    assert_eq(chosen.val, Some("one"))
    assert_true(t.ime().0, msg="the keyboard stays after the choice (platform \{platform})")
    t.type_text("继续")
    assert_eq(field.text(), "写到一半再写继续")
  }
}

///|
test "putting the keyboard away while a touch menu is open does not reopen it" {
  for platform in [1, 2] {
    new_run()
    let open = Ref(false)
    let t = @ui.Tester::new(fn(c) {
      c.column(gap=12.0, fn() {
        c.editor("example/field", placeholder="输入文字") |> ignore
        let trigger = @kit.button(c, "选择", key="example/choose")
        if trigger.clicked { open.val = !open.val }
        open.val = @kit.dropdown_menu(c, "example/menu", open.val, trigger.id, [@kit.menu_item("one", label="一个选项")]).open
      }) |> ignore
    }, w=360.0, h=740.0, platform~)
    t.tap_text("输入文字")
    t.click(Button, label="选择")
    assert_true(t.ime().0)
    t.keyboard_gone()
    assert_false(t.ime().0)
    t.click(MenuItem, label="一个选项")
    assert_false(t.ime().0, msg="closing the menu does not reopen the keyboard")
  }
}

///|
test "another field takes the keyboard, and putting it away leaves both values" {
  for platform in [1, 2] {
    new_run()
    let first = @ui.Field::new()
    let second = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) {
      c.column(gap=12.0, fn() {
        c.editor("example/first", placeholder="第一个", field=first) |> ignore
        c.editor("example/second", placeholder="第二个", field=second) |> ignore
      }) |> ignore
    }, w=360.0, h=740.0, platform~)
    t.tap_text("第一个")
    t.type_text("甲")
    t.tap_text("第二个")
    t.type_text("乙")
    assert_eq(first.text(), "甲")
    assert_eq(second.text(), "乙")
    assert_true(t.ime().0)
    t.keyboard_gone()
    assert_false(t.ime().0)
    assert_eq((first.text(), second.text()), ("甲", "乙"))
  }
}

///|
test "tapping a message while writing keeps the keyboard and the draft" {
  for platform in [1, 2] {
    let calls : Array[Made] = []
    let t = fake_core(calls, platform~)
    t.tap_text("发消息")
    t.type_text("签名")
    assert_true(t.ime().0, msg="the keyboard is up (platform \{platform})")
    t.tap_text("推送截图前要先登录 gh。")
    assert_true(t.ime().0, msg="the keyboard stays after tapping the message (platform \{platform})")
    t.type_text("权限")
    assert_eq(t.ime().1, "签名权限", msg="typing continues in the draft (platform \{platform})")
  }
}

///|
test "answering a chat card while writing keeps the keyboard" {
  for platform in [1, 2] {
    let calls : Array[Made] = []
    let t = cards_core(calls, platform~)
    scroll_to_words(t, "忽略")
    t.tap_text("发消息")
    t.type_text("签名")
    assert_true(t.ime().0)
    tap_now(t, "忽略")
    assert_eq(named(calls, "decision.dismiss").length(), 1)
    assert_true(t.ime().0, msg="the keyboard stays after the card action (platform \{platform})")
    t.type_text("权限")
    assert_eq(t.ime().1, "签名权限")
  }
}

///|
test "opening a draft picture for viewing puts the keyboard away" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let writing = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_add(src, writing, "ws1/st1", "照片.png", png_head())
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("写到一半")
  assert_true(t.ime().0)
  let id = text(Some(writing.files[0]), "id")
  let tile = thumb_of(t.ctx(), "ws1/st1//draft:" + id).unwrap()
  t.tap(tile.x + tile.w / 2.0, tile.y + tile.h / 2.0)
  assert_true(viewer.get() is Some(_), msg="the picture viewer opened")
  assert_false(t.ime().0, msg="the viewer takes the whole screen")
}

///|
test "touching a slider while writing keeps the soft keyboard" {
  for platform in [1, 2] {
    new_run()
    let field = @ui.Field::new()
    let value = Ref(20.0)
    let t = @ui.Tester::new(fn(c) {
      c.column(gap=12.0, fn() {
        c.editor("example/field", placeholder="输入文字", field~) |> ignore
        value.val = @kit.slider(c, "example/slider", value.val, label="音量").value
      }) |> ignore
    }, w=360.0, h=740.0, platform~)
    t.tap_text("输入文字")
    t.type_text("写到一半")
    let (x, y, w, h) = t.get(Slider, label="音量").rect
    t.tap(x + w * 0.75, y + h / 2.0)
    assert_true(t.ime().0, msg="the slider leaves the keyboard up (platform \{platform})")
    assert_true(value.val > 20.0)
    t.type_text("继续")
    assert_eq(field.text(), "写到一半继续")
  }
}

///|
test "a mouse pressing a slider still gives it keyboard focus" {
  new_run()
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=12.0, fn() {
      c.editor("example/field", placeholder="输入文字") |> ignore
      @kit.slider(c, "example/slider", 20.0, label="音量") |> ignore
    }) |> ignore
  }, w=360.0, h=740.0, platform=0)
  t.tap_text("输入文字")
  t.click(Slider, label="音量")
  assert_eq(t.focused().map(fn(n) { n.label }), Some("音量"))
}
