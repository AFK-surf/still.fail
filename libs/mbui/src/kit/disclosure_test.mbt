// Batch 4 (collapsible, accordion, tabs, scroll area, form) driven as a person and a screen reader drive them.

///|
test "collapsible: its trigger opens it, its content grows in; closed, gone from the tree" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    open.val = @kit.collapsible(c, "more", open.val, "Details", fn() { c.text("Hidden words") |> ignore }).value
  })
  assert_eq(t.get(@ui.Role::Button, label="Details").expanded, Some(false))
  assert_true(t.query(@ui.Role::Region, label="Details") is None)
  t.click(@ui.Role::Button, label="Details")
  assert_true(open.val)
  // on its way: cut to part of its height
  t.run_for(@kit.collapsible_open_ms / 2.0)
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
    v.val = @kit.accordion(
      c,
      "faq",
      [
        @kit.fold("a", "What is it?", fn() { c.text("A UI library") |> ignore }),
        @kit.fold("b", "Is it fast?", fn() { c.text("Yes") |> ignore }),
        @kit.fold("c", "Who made it?", fn() { c.text("Us") |> ignore }),
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
    v.val = @kit.accordion(c, "m", [@kit.fold("a", "One", fn() {  }), @kit.fold("b", "Two", fn() {  })], v.val, multiple=true).value
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
    v.val = @kit.tabs(
      c,
      "settings",
      [@kit.item("account", label="Account"), @kit.item("password", label="Password"), @kit.item("billing", label="Billing")],
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
    v.val = @kit.tabs(c, "t", [@kit.item("a", label="A"), @kit.item("b", label="B")], v.val, fn(_) {  }, manual=true).value
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
      @kit.scroll_area(c, "s", 200.0, label="Log", fn() {
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
    let r = @kit.form(c, "signup", [
      @kit.form_field("email", "Email", kind=Email, required=true, placeholder="you@example.com"),
      @kit.form_field("age", "Age", kind=Number),
      @kit.form_field("name", "Name", check=fn(s) { if s == "root" { "这个名字不能用" } else { "" } }),
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

///|
/// An accordion of two folds, each trigger 40 high on its own colour (A's green, B's blue), A holding a red box 80
/// high: what is open as `v` says.
fn two_folds(v : Ref[Array[String]]) -> @ui.Tester {
  let look = fn(c : @ui.Ctx, s : @kit.TriggerState) {
    c.box(w=Fill(1.0), h=Px(40.0), bg=if s.label == "B" { 0x0000FFFFL } else { 0x00FF00FFL }, fn() {  }) |> ignore
  }
  let t = @ui.Tester::new(
    fn(c) {
      v.val = @kit.accordion(
        c,
        "two",
        [
          @kit.fold("a", "A", fn() { c.box(w=Px(100.0), h=Px(80.0), bg=0xFF0000FFL, fn() {  }) |> ignore }),
          @kit.fold("b", "B", fn() {  }),
        ],
        v.val,
        look~,
      ).value
    },
    w=400.0,
    h=400.0,
  )
  t.check_looks(false)
  t.draw()
  t
}

///|
/// How far down A's red (40 down to 120) is seen with what cuts it ending `at`.
fn red_shown(at : Double) -> Double {
  if at > 120.0 {
    120.0
  } else {
    at
  }
}

///|
/// Frames from now to the declared end of a fold's way, `ms` long (each the next one a motion asks for): at each, where
/// B's trigger is drawn (its top) and how far down A's red is drawn (the bottom of what cuts it, none where it is not
/// drawn); and each frame built for the clock (its why: "the clock read at" a motion as it was built).
fn fold_frames(t : @ui.Tester, ms : Double) -> (Array[(Double, Double?)], Array[String]) {
  let seen : Array[(Double, Double?)] = []
  let built : Array[String] = []
  let until = t.time() + ms
  while t.time() < until {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    t.frame_at(if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) })
    if t.built_why().has_prefix("the clock read at") {
      built.push("\{t.time()}: \{t.built_why()}")
    }
    let b = t.drawn_rects().filter(fn(r) { r.4 == 0x0000FFFFL }).map(fn(r) { r.1 })
    let red = t.drawn_cut().filter(fn(i) { i.0 == 0 && i.3 == 100.0 && i.4 == 80.0 }).map(fn(i) { i.5.3 })
    seen.push((b[0], red.get(0)))
  }
  (seen, built)
}

///|
test "accordion: a fold opening is laid out open at once, what is under it drawn from where it was going down with it, what it holds shown down to there; closing, the same back; nothing built for the clock" {
  let v : Ref[Array[String]] = Ref([])
  let t = two_folds(v)
  let b_at = fn() { t.drawn_rects().filter(fn(r) { r.4 == 0x0000FFFFL }).map(fn(r) { r.1 }) }
  // (B's trigger under A's, and the line between them)
  let shut = b_at()
  assert_eq(shut, [41.0])
  t.act(@ui.Role::Button, @ui.Action::Activate, label="A")
  assert_eq(v.val, ["a"])
  // laid out open at once: B's trigger there for a press, drawn where it was as it sets off
  assert_eq(t.get(@ui.Role::Button, label="B").rect.1, 133.0)
  assert_eq(b_at(), shut)
  let (opening, built) = fold_frames(t, @kit.collapsible_open_ms)
  // (it goes down through more than a few places to where it is laid out, never back up, and A's red is shown down to
  // the line over B's trigger all the way: what is under it neither left as a gap nor drawn over)
  let places = opening.map(fn(s) { s.0 })
  assert_true(places.filter(fn(y) { y > 41.0 && y < 133.0 }).length() > 3, msg="\{Repr(places)}")
  assert_eq(places[places.length() - 1], 133.0)
  for k, s in opening {
    if k > 0 {
      assert_true(s.0 >= opening[k - 1].0, msg="\{Repr(places)}")
    }
    match s.1 {
      // (shown down to the line over B's trigger: the whole of it once that is past its foot, 120 down)
      Some(cut) => assert_true((red_shown(cut) - red_shown(s.0 - 1.0)).abs() <= 0.5, msg="\{Repr(s)}")
      None => fail("A's red not drawn as it opens: \{Repr(opening)}")
    }
  }
  assert_eq(built, [], msg="built for the clock: \{Repr(built)}")
  // closing: laid out shut at once, B's trigger going up from where it was, A's red going in under it
  t.act(@ui.Role::Button, @ui.Action::Activate, label="A")
  assert_eq(v.val, [])
  assert_eq(t.get(@ui.Role::Button, label="B").rect.1, 41.0)
  let (closing, built) = fold_frames(t, @kit.collapsible_close_ms)
  let places = closing.map(fn(s) { s.0 })
  assert_true(places.filter(fn(y) { y > 41.0 && y < 133.0 }).length() > 3, msg="\{Repr(places)}")
  for k, s in closing {
    if k > 0 {
      assert_true(s.0 <= closing[k - 1].0, msg="\{Repr(places)}")
    }
    match s.1 {
      // (shown down to the line over B's trigger: the whole of it once that is past its foot, 120 down)
      Some(cut) => assert_true((red_shown(cut) - red_shown(s.0 - 1.0)).abs() <= 0.5, msg="\{Repr(s)}")
      None => assert_eq(s.0, 41.0, msg="A's red gone before B's trigger is up: \{Repr(closing)}")
    }
  }
  assert_eq(b_at(), shut)
  assert_eq(built, [], msg="built for the clock: \{Repr(built)}")
  t.assert_idle()
}
