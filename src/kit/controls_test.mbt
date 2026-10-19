// Batch 1's controls driven as a person and a screen reader drive them, the values kept by the test (the view's),
// read back through the semantics tree.

///|
test "switch: a tap turns it, the view keeps it; Activate too; disabled, nothing does" {
  let on = Ref(false)
  let off = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      on.val = switch(c, "wifi", on.val, label="Wi-Fi").value
      ignore(switch(c, "air", off.val, label="Airplane", disabled=true))
    })
    |> ignore
  })
  t.click(@ui.Switch, label="Wi-Fi")
  assert_true(on.val)
  assert_eq(t.get(@ui.Switch, label="Wi-Fi").check, Some(@ui.On))
  t.act(@ui.Switch, @ui.Activate, label="Wi-Fi")
  assert_false(on.val)
  t.click(@ui.Switch, label="Airplane")
  assert_false(off.val)
}

///|
test "checkbox: a click checks it; Space with the focus unchecks it; neither (mixed) goes to checked" {
  let v : Ref[@ui.Check] = Ref(@ui.Off)
  let t = @ui.Tester::new(fn(c) { v.val = checkbox(c, "terms", v.val, label="Terms").value })
  t.click(@ui.Checkbox, label="Terms")
  assert_eq(v.val, @ui.On)
  t.key(@ui.key_tab)
  t.key(@ui.key_space)
  assert_eq(v.val, @ui.Off)
  v.val = @ui.Mixed
  t.frame()
  t.click(@ui.Checkbox, label="Terms")
  assert_eq(v.val, @ui.On)
}

///|
test "radio group: a tap checks one; the arrows move the focus along it and check what they reach, wrapping" {
  let v = Ref("a")
  let t = @ui.Tester::new(fn(c) {
    v.val = radio_group(c, "size", [item("a", label="Small"), item("b", label="Medium"), item("c", label="Large")], v.val, label="Size").value
  })
  t.click(@ui.Radio, label="Large")
  assert_eq(v.val, "c")
  // Tab lands on the checked one; Down from the last wraps to the first
  t.key(@ui.key_tab)
  t.key(@ui.key_code_down)
  assert_eq(v.val, "a")
  t.key(@ui.key_code_down)
  assert_eq(v.val, "b")
  assert_eq(t.get(@ui.Radio, label="Medium").check, Some(@ui.On))
  assert_eq(t.get(@ui.Radio, label="Small").check, Some(@ui.Off))
}

///|
test "toggle group: single, a tap picks one and a second tap lets it go; multiple, each on its own" {
  let one : Ref[Array[String]] = Ref([])
  let many : Ref[Array[String]] = Ref([])
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      one.val = toggle_group(c, "align", [item("l", label="Left"), item("r", label="Right")], one.val, label="Align").value
      many.val = toggle_group(
        c,
        "fmt",
        [item("b", label="Bold"), item("i", label="Italic")],
        many.val,
        multiple=true,
        label="Format",
      ).value
    })
    |> ignore
  })
  t.click(@ui.Radio, label="Left")
  assert_eq(one.val, ["l"])
  t.click(@ui.Radio, label="Right")
  assert_eq(one.val, ["r"])
  t.click(@ui.Radio, label="Right")
  assert_eq(one.val, [])
  t.click(@ui.Button, label="Bold")
  t.click(@ui.Button, label="Italic")
  assert_eq(many.val, ["b", "i"])
}

///|
test "slider: the arrows a step, Page keys ten, Home and End the ends; Increment and Decrement; held in range" {
  let v = Ref(50.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "vol", v.val, min=0.0, max=100.0, step=5.0, label="Volume").value
  })
  t.key(@ui.key_tab)
  t.key(@ui.key_code_right)
  assert_eq(v.val, 55.0)
  t.key(@ui.key_code_down)
  assert_eq(v.val, 50.0)
  t.key(@ui.key_code_page_up)
  assert_eq(v.val, 100.0)
  t.key(@ui.key_code_right)
  assert_eq(v.val, 100.0)
  t.key(@ui.key_code_home)
  assert_eq(v.val, 0.0)
  t.act(@ui.Slider, @ui.Increment, label="Volume")
  assert_eq(v.val, 5.0)
  t.act(@ui.Slider, @ui.Decrement, label="Volume")
  t.act(@ui.Slider, @ui.Decrement, label="Volume")
  assert_eq(v.val, 0.0)
  let s = t.get(@ui.Slider, label="Volume")
  assert_eq(s.value, "0")
  assert_eq(s.range, Some((0.0, 100.0, 0.0)))
}

///|
test "slider: dragged along its track, it follows the pointer to the nearest step; right to left, mirrored" {
  let v = Ref(0.0)
  let t = @ui.Tester::new(fn(c) {
    v.val = slider(c, "s", v.val, min=0.0, max=10.0, step=1.0, w=200.0, label="S").value
  })
  let (x, y, w, h) = t.get(@ui.Slider, label="S").rect
  t.drag(x + 1.0, y + h / 2.0, x + w * 0.7, y + h / 2.0)
  assert_eq(v.val, 7.0)
  t.drag(x + w * 0.7, y + h / 2.0, x + w * 0.2, y + h / 2.0)
  assert_eq(v.val, 2.0)
}

///|
test "snap: in range, on the step from min" {
  assert_eq(snap(7.4, 0.0, 10.0, 1.0), 7.0)
  assert_eq(snap(-3.0, 0.0, 10.0, 1.0), 0.0)
  assert_eq(snap(12.0, 0.0, 10.0, 1.0), 10.0)
  assert_eq(snap(0.26, 0.0, 1.0, 0.25), 0.25)
  assert_eq(snap(3.3, 1.0, 10.0, 2.0), 3.0)
}

///|
test "progress: its value as a percentage and its range; not known, neither, and it keeps asking for frames" {
  let v : Ref[Double?] = Ref(Some(30.0))
  let t = @ui.Tester::new(fn(c) { progress(c, v.val, max=60.0, label="Upload") })
  let p = t.get(@ui.ProgressBar, label="Upload")
  assert_eq(p.value, "50%")
  assert_eq(p.range, Some((0.0, 60.0, 30.0)))
  v.val = None
  t.frame()
  assert_eq(t.get(@ui.ProgressBar, label="Upload").range, None)
  assert_eq(t.settle(max=5), 5)
}

///|
test "avatar: named by its person, their initials while it has no picture" {
  assert_eq(initials("Ada Lovelace"), "AL")
  assert_eq(initials("ada"), "A")
  assert_eq(initials("林 子 健"), "林子")
  let t = @ui.Tester::new(fn(c) { avatar(c, "", "Ada Lovelace") })
  ignore(t.get(@ui.Image, label="Ada Lovelace"))
  assert_true(t.find("AL") is Some(_))
}

///|
test "password field: hidden, its words are not read out; the button shows them, named for what it does next" {
  let shown = Ref(false)
  let words = Ref("")
  let t = @ui.Tester::new(fn(c) {
    let p = password_field(c, "pw", shown.val, placeholder="Password")
    shown.val = p.visible
    words.val = p.text
  })
  t.tap_text("Password")
  t.type_text("hunter2")
  assert_eq(words.val, "hunter2")
  assert_eq(t.get(@ui.TextField).value, "")
  t.click(@ui.Button, label="显示")
  assert_true(shown.val)
  assert_eq(t.get(@ui.TextField).value, "hunter2")
  assert_eq(t.get(@ui.Button, label="隐藏").pressed, Some(true))
  t.click(@ui.Button, label="隐藏")
  assert_false(shown.val)
  assert_eq(t.get(@ui.TextField).value, "")
}

///|
test "toggle: a tap presses it, Activate lets it go; said pressed or not" {
  let on = Ref(false)
  let t = @ui.Tester::new(fn(c) { on.val = toggle(c, "Bold", on.val).value })
  t.click(@ui.Button, label="Bold")
  assert_true(on.val)
  assert_eq(t.get(@ui.Button, label="Bold").pressed, Some(true))
  t.act(@ui.Button, @ui.Activate, label="Bold")
  assert_false(on.val)
  assert_eq(t.get(@ui.Button, label="Bold").pressed, Some(false))
}

///|
test "label: a tap on it turns its control, or gives its field the focus" {
  let v : Ref[@ui.Check] = Ref(@ui.Off)
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      c.row(gap=8.0, fn() {
        v.val = checkbox(c, "terms", v.val, label="Terms").value
        label(c, "Accept the terms", for_id=c.id("terms")) |> ignore
      })
      |> ignore
      label(c, "Name", for_id=c.id("name"), field=true) |> ignore
      c.editor("name", placeholder="Your name") |> ignore
    })
    |> ignore
  })
  t.tap_text("Accept the terms")
  assert_eq(v.val, @ui.On)
  t.tap_text("Name")
  assert_true(t.get(@ui.TextField, label="Your name").focused)
  t.type_text("Ada")
  assert_eq(t.get(@ui.TextField, label="Your name").value, "Ada")
}

///|
test "separator, aspect ratio, accessible icon, visually hidden: what the tree says, and the shape kept" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      separator(c)
      separator(c, decorative=true)
      c.box(w=Px(160.0), fn() {
        let i = aspect_ratio(c, 16.0 / 9.0, fn() {  })
        c.semantics(i, Group, label="Picture")
      })
      |> ignore
      accessible_icon(c, "Favourite", fn() { c.text("★") |> ignore })
      visually_hidden(c, "3 unread")
    })
    |> ignore
  })
  inspect(
    t.semantics_dump(),
    content=(
      #|Separator value="horizontal"
      #|Group "Picture"
      #|Image "Favourite"
      #|Text "3 unread"
      #|
    ),
  )
  let (_, _, w, h) = t.get(@ui.Group, label="Picture").rect
  assert_eq(w, 160.0)
  assert_eq(h, 90.0)
}

///|
test "text field: typed in, its words the view's to read; Enter hands them on" {
  let got = Ref("")
  let sent = Ref(0)
  let t = @ui.Tester::new(fn(c) {
    let f = text_field(c, "name", placeholder="Name")
    got.val = f.text
    if f.submitted {
      sent.val += 1
    }
  })
  t.tap_text("Name")
  t.type_text("Ada")
  assert_eq(got.val, "Ada")
  assert_eq(t.get(@ui.TextField, label="Name").value, "Ada")
  t.enter()
  assert_eq(sent.val, 1)
}
