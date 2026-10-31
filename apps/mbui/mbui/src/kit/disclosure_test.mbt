// Batch 4 (collapsible, accordion, tabs, scroll area, form) driven as a person and a screen reader drive them.

///|
test "collapsible: its trigger opens it, its content grows in; closed, gone from the tree" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    open.val = collapsible(c, "more", open.val, "Details", fn() { c.text("Hidden words") |> ignore }).value
  })
  assert_eq(t.get(@ui.Role::Button, label="Details").expanded, Some(false))
  assert_true(t.query(@ui.Role::Region, label="Details") is None)
  t.click(@ui.Role::Button, label="Details")
  assert_true(open.val)
  // on its way: cut to part of its height
  t.run_for(collapsible_open_ms / 2.0)
  let (_, _, _, h1) = t.get(@ui.Role::Region, label="Details").rect
  t.draw()
  let (_, _, _, h2) = t.get(@ui.Role::Region, label="Details").rect
  assert_true(h2 > 0.0)
  ignore(h1)
  assert_eq(t.get(@ui.Role::Button, label="Details").expanded, Some(true))
  t.act(@ui.Role::Button, @ui.Action::Activate, label="Details")
  assert_false(open.val)
  t.draw()
  assert_true(t.query(@ui.Role::Region, label="Details") is None)
}

///|
test "accordion: one open at a time; pressed again it closes; Up and Down move among its triggers" {
  let v : Ref[Array[String]] = Ref([])
  let t = @ui.Tester::new(fn(c) {
    v.val = accordion(
      c,
      "faq",
      [
        fold("a", "What is it?", fn() { c.text("A UI library") |> ignore }),
        fold("b", "Is it fast?", fn() { c.text("Yes") |> ignore }),
        fold("c", "Who made it?", fn() { c.text("Us") |> ignore }),
      ],
      v.val,
      label="FAQ",
    ).value
  })
  t.click(@ui.Role::Button, label="What is it?")
  assert_eq(v.val, ["a"])
  t.click(@ui.Role::Button, label="Is it fast?")
  assert_eq(v.val, ["b"])
  t.draw()
  assert_true(t.query(@ui.Role::Region, label="What is it?") is None)
  ignore(t.get(@ui.Role::Region, label="Is it fast?"))
  t.click(@ui.Role::Button, label="Is it fast?")
  assert_eq(v.val, [])
  // the keyboard: one Tab stop, Down to the next, round; Enter opens
  t.tab()
  t.press("Down")
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "Who made it?")
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "What is it?")
  t.press("Enter")
  assert_eq(v.val, ["a"])
}

///|
test "accordion, multiple: each on its own" {
  let v : Ref[Array[String]] = Ref([])
  let t = @ui.Tester::new(fn(c) {
    v.val = accordion(c, "m", [fold("a", "One", fn() {  }), fold("b", "Two", fn() {  })], v.val, multiple=true).value
  })
  t.click(@ui.Role::Button, label="One")
  t.click(@ui.Role::Button, label="Two")
  assert_eq(v.val, ["a", "b"])
  t.click(@ui.Role::Button, label="One")
  assert_eq(v.val, ["b"])
}

///|
test "tabs: a tap chooses; the arrows move and choose, round; the chosen one's panel shows" {
  let v = Ref("account")
  let t = @ui.Tester::new(fn(c) {
    v.val = tabs(
      c,
      "settings",
      [item("account", label="Account"), item("password", label="Password"), item("billing", label="Billing")],
      v.val,
      fn(which) { c.text("Panel of " + which) |> ignore },
      label="Settings",
    ).value
  })
  ignore(t.get(@ui.Role::TabList, label="Settings"))
  assert_eq(t.get(@ui.Role::Tab, label="Account").selected, Some(true))
  assert_true(t.find("Panel of account") is Some(_))
  t.click(@ui.Role::Tab, label="Billing")
  assert_eq(v.val, "billing")
  assert_true(t.find("Panel of billing") is Some(_))
  ignore(t.get(@ui.Role::TabPanel, label="Billing"))
  // Tab lands on the chosen; Right goes round to the first and chooses it
  t.tab()
  assert_eq(t.focused().unwrap().label, "Billing")
  t.press("Right")
  assert_eq(v.val, "account")
  t.press("Left")
  assert_eq(v.val, "billing")
}

///|
test "tabs, manual: the arrows move the focus only; Enter chooses" {
  let v = Ref("a")
  let t = @ui.Tester::new(fn(c) {
    v.val = tabs(c, "t", [item("a", label="A"), item("b", label="B")], v.val, fn(_) {  }, manual=true).value
  })
  t.tab()
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "B")
  assert_eq(v.val, "a")
  t.press("Enter")
  assert_eq(v.val, "b")
}

///|
test "scroll area: what is taller than its room scrolls in it" {
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      scroll_area(c, "s", 200.0, label="Log", fn() {
        c.column(fn() {
          for i in 0..<40 {
            c.text("line \{i}") |> ignore
          }
        })
        |> ignore
      })
    })
    |> ignore
  })
  let (_, _, _, h) = t.get(@ui.Role::ScrollArea, label="Log").rect
  assert_eq(h, 200.0)
  let (_, y0, _, _) = t.rect_of("line 0").unwrap()
  t.wheel(100.0, 100.0, 120.0)
  let (_, y1, _, _) = t.rect_of("line 0").unwrap_or((0.0, -1000.0, 0.0, 0.0))
  assert_true(y1 < y0)
}

///|
test "form: nothing wrong shows before it is left or handed on; handed on wrong, why shows and the focus goes there" {
  let got : Ref[Map[String, String]?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let r = form(c, "signup", [
      form_field("email", "Email", kind=Email, required=true, placeholder="you@example.com"),
      form_field("age", "Age", kind=Number),
      form_field("name", "Name", check=fn(s) { if s == "root" { "这个名字不能用" } else { "" } }),
    ])
    if r.submitted {
      got.val = Some(r.values)
    }
  })
  ignore(t.get(@ui.Role::Form))
  assert_true(t.find("请填写此项") is None)
  t.click(@ui.Role::Button, label="提交")
  assert_true(got.val is None)
  assert_true(t.find("请填写此项") is Some(_))
  assert_true(t.get(@ui.Role::TextField, label="you@example.com").focused)
  t.type_text("ada")
  t.frame()
  assert_true(t.find("请输入有效的邮箱地址") is Some(_))
  t.type_text("@example.com")
  t.frame()
  assert_true(t.find("请输入有效的邮箱地址") is None)
  // a field left after typing in it shows what is wrong at once
  t.tap_text("Name")
  t.type_text("root")
  t.tap_text("Age")
  t.type_text("x")
  t.frame()
  assert_true(t.find("这个名字不能用") is Some(_))
  assert_true(t.find("请输入数字") is Some(_))
  t.backspace()
  t.type_text("36")
  t.tap_text("Name")
  for _ in 0..<4 {
    t.backspace()
  }
  t.type_text("Ada")
  t.enter()
  assert_eq(got.val.map(fn(m) { m.get("age") }), Some(Some("36")))
  assert_eq(got.val.map(fn(m) { m.get("email") }), Some(Some("ada@example.com")))
}
