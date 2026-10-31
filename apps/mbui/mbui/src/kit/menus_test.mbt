// The menus (batch 3) driven by the pointer and the keyboard, what is open and chosen kept by the test (the view's).

///|
fn file_menu() -> Array[Entry] {
  [
    menu_item("new", label="New tab", shortcut="⌘T"),
    menu_item("window", label="New window"),
    menu_item("private", label="Private window", disabled=true),
    menu_separator(),
    menu_sub("Share", [menu_item("mail", label="Email link"), menu_item("copy", label="Copy link")]),
    menu_check("bar", true, label="Show bookmarks"),
  ]
}

///|
test "dropdown menu: opened by the keyboard at its first item; the arrows skip what is disabled; Enter chooses" {
  let open = Ref(false)
  let chosen : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "File", key="file")
    if tr.clicked {
      open.val = !open.val
    }
    let m = dropdown_menu(c, "menu", open.val, tr.id, file_menu(), label="File")
    open.val = m.open
    if m.chosen is Some(_) {
      chosen.val = m.chosen
    }
  })
  t.tab()
  t.press("Enter")
  assert_true(open.val)
  ignore(t.get(@ui.Role::Menu, label="File"))
  // the page under it is out of the tree
  assert_true(t.query(@ui.Role::Button, label="File") is None)
  assert_eq(t.focused().unwrap().label, "New tab")
  t.press("Down")
  t.press("Down")
  // past the disabled one and the line: the submenu's item
  assert_eq(t.focused().unwrap().label, "Share")
  t.press("Up")
  t.press("Enter")
  assert_eq(chosen.val, Some("window"))
  assert_false(open.val)
  t.draw()
  // the focus back on its trigger
  assert_eq(t.focused().unwrap().label, "File")
}

///|
test "dropdown menu: opened by a click, nothing lit until a key; Down on the trigger opens it; Escape closes it" {
  let open = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "File", key="file")
    if tr.clicked {
      open.val = !open.val
    }
    open.val = dropdown_menu(c, "menu", open.val, tr.id, file_menu(), label="File").open
  })
  t.click(@ui.Role::Button, label="File")
  assert_true(open.val)
  // the focus on the panel: no item lit
  assert_eq(t.focused().map(fn(s) { s.role }), Some(@ui.Role::Menu))
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "New tab")
  t.press("End")
  assert_eq(t.focused().unwrap().label, "Show bookmarks")
  t.press("Escape")
  assert_false(open.val)
  t.draw()
  t.tab()
  t.press("Down")
  assert_true(open.val)
  assert_eq(t.focused().unwrap().label, "New tab")
}

///|
test "menu: letters typed go to the item they start; a press outside closes it; a click chooses" {
  let open = Ref(true)
  let chosen : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "File", key="file")
    let m = dropdown_menu(c, "menu", open.val, tr.id, file_menu(), label="File")
    open.val = m.open
    if m.chosen is Some(_) {
      chosen.val = m.chosen
    }
  })
  t.draw()
  t.press("s")
  assert_eq(t.focused().unwrap().label, "Share")
  t.press("s")
  assert_eq(t.focused().unwrap().label, "Show bookmarks")
  // what was typed forgotten: a word from the start
  t.run_for(typeahead_ms)
  t.press("n")
  t.press("e")
  t.press("w")
  assert_eq(t.focused().unwrap().label, "New tab")
  t.click(@ui.Role::MenuItemCheckbox, label="Show bookmarks")
  assert_eq(chosen.val, Some("bar"))
  assert_false(open.val)
  open.val = true
  t.frame()
  t.draw()
  t.tap(380.0, 800.0)
  assert_false(open.val)
}

///|
test "submenu: Right opens it at its first item, Left closes it alone; the pointer opens it; a choice in it closes all" {
  let open = Ref(true)
  let chosen : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let tr = button(c, "File", key="file")
    let m = dropdown_menu(c, "menu", open.val, tr.id, file_menu(), label="File")
    open.val = m.open
    if m.chosen is Some(_) {
      chosen.val = m.chosen
    }
  })
  t.draw()
  t.press("End")
  t.press("Up")
  assert_eq(t.focused().unwrap().label, "Share")
  t.press("Right")
  assert_eq(t.get(@ui.Role::MenuItem, label="Share").expanded, Some(true))
  assert_eq(t.focused().unwrap().label, "Email link")
  t.press("Left")
  assert_eq(t.focused().unwrap().label, "Share")
  assert_eq(t.get(@ui.Role::MenuItem, label="Share").expanded, Some(false))
  assert_true(open.val)
  // Escape in the submenu closes it alone
  t.press("Right")
  t.press("Escape")
  assert_true(open.val)
  assert_eq(t.focused().unwrap().label, "Share")
  // the pointer onto it opens it; a choice in it closes everything
  let (x, y, w, h) = t.get(@ui.Role::MenuItem, label="Share").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.click(@ui.Role::MenuItem, label="Copy link")
  assert_eq(chosen.val, Some("copy"))
  assert_false(open.val)
}

///|
test "context menu: opened at the pointer by a right click, at its press by a long one" {
  let chosen : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let area = c.id("area")
    c.box(id=area, w=Fill(1.0), h=Px(300.0), fn() { c.text("Right click here") |> ignore }) |> ignore
    let m = context_menu(c, "ctx", area, [menu_item("cut", label="Cut"), menu_item("paste", label="Paste")], label="Edit")
    if m.chosen is Some(_) {
      chosen.val = m.chosen
    }
  })
  t.right_click(100.0, 120.0)
  // come in (its panel grows in from where it opened)
  t.run_for(pop_ms)
  let (x, y, _, _) = t.get(@ui.Role::Menu, label="Edit").rect
  assert_true(x >= 100.0 && x < 110.0 && y >= 120.0 && y < 130.0)
  t.click(@ui.Role::MenuItem, label="Paste")
  assert_eq(chosen.val, Some("paste"))
  // gone at once
  t.draw()
  assert_true(t.query(@ui.Role::Menu) is None)
  // a finger held still
  t.touch(0, 50.0, 200.0)
  t.draw()
  t.run_for(@ui.long_press_ms)
  t.touch(2, 50.0, 200.0)
  t.draw()
  ignore(t.get(@ui.Role::Menu, label="Edit"))
}

///|
test "menubar: a click opens a menu, the pointer moves among them, Left and Right too; a choice closes it" {
  let chosen : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    let v = menubar(
      c,
      "bar",
      [
        ("File", [menu_item("new", label="New"), menu_item("open", label="Open…")]),
        ("Edit", [menu_item("undo", label="Undo"), menu_item("redo", label="Redo")]),
        ("View", [menu_check("side", false, label="Sidebar")]),
      ],
      label="Main",
    )
    if v is Some(_) {
      chosen.val = v
    }
  })
  ignore(t.get(@ui.Role::MenuBar, label="Main"))
  t.click(@ui.Role::MenuItem, label="File")
  t.draw()
  ignore(t.get(@ui.Role::Menu, label="File"))
  let (x, y, w, h) = t.get(@ui.Role::MenuItem, label="Edit").rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.draw()
  ignore(t.get(@ui.Role::Menu, label="Edit"))
  assert_true(t.query(@ui.Role::Menu, label="File") is None)
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "Undo")
  t.press("Right")
  t.draw()
  ignore(t.get(@ui.Role::Menu, label="View"))
  assert_eq(t.focused().unwrap().label, "Sidebar")
  t.press("Right")
  t.draw()
  ignore(t.get(@ui.Role::Menu, label="File"))
  t.press("Enter")
  assert_eq(chosen.val, Some("new"))
  t.draw()
  assert_true(t.query(@ui.Role::Menu) is None)
}

///|
test "select: opens on the chosen option; Enter chooses; letters on the trigger choose; a click outside leaves it" {
  let v = Ref("b")
  let t = @ui.Tester::new(fn(c) {
    v.val = select(
      c,
      "fruit",
      v.val,
      [item("a", label="Apple"), item("b", label="Banana"), item("c", label="Cherry"), item("d", label="Date", disabled=true)],
      placeholder="Pick a fruit",
      label="Fruit",
    ).value
  })
  assert_eq(t.get(@ui.Role::Combobox, label="Fruit").value, "Banana")
  t.tab()
  t.press("Enter")
  t.draw()
  // (the page under it, its trigger too, out of the tree while it is open)
  ignore(t.get(@ui.Role::Listbox, label="Fruit"))
  assert_eq(t.focused().unwrap().label, "Banana")
  assert_eq(t.get(@ui.Role::Option, label="Banana").selected, Some(true))
  t.press("Down")
  t.press("Down")
  // past the disabled one: nothing further
  t.press("Down")
  assert_eq(t.focused().unwrap().label, "Cherry")
  t.press("Enter")
  assert_eq(v.val, "c")
  t.draw()
  assert_eq(t.focused().unwrap().label, "Fruit")
  // a letter on the closed trigger
  t.press("a")
  assert_eq(v.val, "a")
  assert_eq(t.focused().unwrap().label, "Fruit")
  // opened and left by a press outside: unchanged
  t.click(@ui.Role::Combobox, label="Fruit")
  t.draw()
  t.tap(380.0, 800.0)
  t.draw()
  assert_eq(v.val, "a")
  assert_true(t.query(@ui.Role::Listbox) is None)
}

///|
test "toolbar: one Tab stop, the arrows along it" {
  let t = @ui.Tester::new(fn(c) {
    c.column(gap=8.0, fn() {
      toolbar(c, "tools", label="Format", fn() {
        button(c, "Bold", key="b", variant=Ghost) |> ignore
        button(c, "Italic", key="i", variant=Ghost) |> ignore
        button(c, "Link", key="l", variant=Ghost) |> ignore
      })
      button(c, "After") |> ignore
    })
    |> ignore
  })
  ignore(t.get(@ui.Role::Toolbar, label="Format"))
  t.tab()
  assert_eq(t.focused().unwrap().label, "Bold")
  t.press("Right")
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "Link")
  t.press("Right")
  assert_eq(t.focused().unwrap().label, "Bold")
  t.tab()
  assert_eq(t.focused().unwrap().label, "After")
  // back in: where it was left
  t.tab(back=true)
  assert_eq(t.focused().unwrap().label, "Bold")
}

///|
test "navigation menu: a trigger's content shown once the pointer rests on it, at once on another; links followed" {
  let followed : Ref[String?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    c.column(pad=20.0, fn() {
      let f = navigation_menu(
        c,
        "nav",
        [
          nav_trigger("Learn", fn() { c.text("Guides and tutorials") |> ignore }),
          nav_trigger("Overview", fn() { c.text("What it is") |> ignore }),
          nav_link("github", label="GitHub"),
        ],
        label="Site",
      )
      if f is Some(_) {
        followed.val = f
      }
    })
    |> ignore
  })
  ignore(t.get(@ui.Role::Navigation, label="Site"))
  let (x, y, w, h) = t.get(@ui.Role::Button, label="Learn").rect
  // (taken at its moment)
  let moved = t.time()
  t.move(x + w / 2.0, y + h / 2.0)
  let due = moved + nav_menu_open_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_true(t.find("Guides and tutorials") is None)
  t.run_for(due - t.time())
  t.draw()
  assert_true(t.find("Guides and tutorials") is Some(_))
  let (x2, y2, w2, h2) = t.get(@ui.Role::Button, label="Overview").rect
  t.move(x2 + w2 / 2.0, y2 + h2 / 2.0)
  t.draw()
  assert_true(t.find("What it is") is Some(_))
  assert_true(t.find("Guides and tutorials") is None)
  // away from both: closed after a moment
  // (taken at its moment)
  let moved = t.time()
  t.move(380.0, 800.0)
  let due = moved + nav_menu_close_ms
  // (a millisecond before it)
  t.run_for(due - 1.0 - t.time())
  assert_true(t.find("What it is") is Some(_))
  t.run_for(due - t.time())
  t.draw()
  assert_true(t.find("What it is") is None)
  // by the keyboard: Down opens it, Escape closes it
  t.tab()
  t.press("Down")
  t.draw()
  assert_true(t.find("Guides and tutorials") is Some(_))
  t.press("Escape")
  t.draw()
  assert_true(t.find("Guides and tutorials") is None)
  t.click(@ui.Role::Link, label="GitHub")
  assert_eq(followed.val, Some("github"))
}

///|
test "dropdown menu: put by a rectangle, its own motion and a scrim; gone once its motion has played" {
  // its motion's length, in and out (ms): the test's own
  let motion_ms = 300.0
  let open = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    open.val = dropdown_menu(
      c,
      "menu",
      open.val,
      0,
      [menu_item("a", label="One"), menu_item("b", label="Two")],
      label="Filter",
      at=(200.0, 60.0, 40.0, 40.0),
      along=End,
      offset=6.0,
      scrim=0x00000047L,
      enter=@motion.trans(fade=0.0, scale=0.9, ox=0.0, oy=0.0, spec=@motion.tween(motion_ms, ease=Out)),
      exit=@motion.trans(fade=0.0, scale=0.9, ox=0.0, oy=0.0, spec=@motion.tween(motion_ms, ease=Out)),
    ).open
  })
  // (put by its rectangle once laid out: a layout read back, drawn now)
  t.draw()
  let (x, y, w, _) = t.get(@ui.Role::Menu, label="Filter").rect
  assert_true((x + w - 240.0).abs() < 0.5)
  assert_true((y - 106.0).abs() < 0.5)
  t.press("Escape")
  assert_false(open.val)
  // its own motion played out: gone
  t.run_for(motion_ms)
  assert_true(t.find("One") is None)
  t.assert_idle()
}

///|
/// Where `words` are drawn now (their top and bottom, moved as what holds them scrolls), or a failure.
fn words_span(t : @ui.Tester, words : String) -> (Double, Double) raise {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some((_, _, y, _, h, _)) => (y, y + h)
    None => fail("\{words} not drawn")
  }
}

///|
test "dropdown menu: taller than the window, as tall as it lets it, its items scrolled to" {
  let open = Ref(true)
  let entries = Array::makei(40, fn(i) { menu_item("i\{i}", label="Item \{i + 1}") })
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, justify=JEnd, fn() {
        let tr = button(c, "More", key="more")
        if tr.clicked {
          open.val = !open.val
        }
        open.val = dropdown_menu(c, "menu", open.val, tr.id, entries, label="More").open
      })
      |> ignore
    },
    w=600.0,
    h=400.0,
  )
  t.run_for(presence_in_ms)
  // its first item in the window, its last past it until scrolled to
  let (first, _) = words_span(t, "Item 1")
  assert_true(first > 0.0, msg="its first item out of the window")
  assert_true(words_span(t, "Item 40").0 > 400.0, msg="its last item not past what it shows")
  let (x, y) = t.find("Item 1").unwrap()
  t.wheel(x, y, 5000.0)
  assert_true(words_span(t, "Item 40").1 < 400.0, msg="its items not scrolled to their end")
  assert_true(words_span(t, "Item 1").0 < 0.0)
  assert_true(open.val)
}
