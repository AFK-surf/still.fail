// A part of the window not in use (View::in_use): the keyboard's focus none of it (Tree::takes_keys). All it holds, a
// node and an old view's widget, gone to by no Tab and read out as taking no focus, the focus in it let go of at the
// moment it stops being in use; the hand's as ever (a press, a hold its cover hands through); in use again, all of it
// as before from that moment.

///|
/// A node "甲" beside a part in use while `on` holds, a node "乙" and an old view's button "丙" in it, each 80 by 40 in
/// a row; a cover over "丙" alone, its hold going through. What each was told, in order.
fn in_use_tester(on : @signals.Signal[Bool]) -> (Tester, Array[String]) {
  let said : Array[String] = []
  let note = fn(s : String) {
    if said.last() != Some(s) {
      said.push(s)
    }
  }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=2)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(a) {
      a
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .says(Is(Some(@view.said(Button, label="甲"))))
      .focusable(Is(true))
      .on_press(fn() { note("甲 pressed") })
      |> ignore
    })
    |> ignore
    root.box(fn(part) {
      part.row(Is(true)).in_use(By(fn() { on.get() })) |> ignore
      part.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .says(Is(Some(@view.said(Button, label="乙"))))
        .focusable(Is(true))
        .on_press(fn() { note("乙 pressed") })
        |> ignore
      })
      |> ignore
      part.box(fn(h) {
        h.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
        old(h, fn(c) {
          let id = c.id("丙")
          c.interact(id) |> ignore
          c.on_press(id, fn() { note("丙 clicked") })
          if c.held_long(id) {
            note("丙 held")
          }
          let i = c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  })
          c.semantics(i, Button, id~, label="丙", actions=[Activate])
        })
        .grow(Is(1.0))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // (the cover, over "丙" alone)
    root.box(fn(cv) {
      cv
      .over(Is(true))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .offset(Is((160.0, 0.0)))
      .gesture(touch_slop(), tap=fn(_) { note("cover tap") }, through=long_press_ms)
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, said)
}

///|
/// The names Tab goes to, from what has the focus round to it again (8 at most).
fn in_use_round(t : Tester) -> Array[String] {
  let first = t.focus_said()
  let out = []
  for _ in 0..<8 {
    t.tab()
    if t.focus_said() == first {
      break
    }
    out.push(t.focused().map(fn(s) { s.label }).unwrap_or(""))
  }
  out
}

///|
/// Whether what is called `label` is read out as able to take the focus.
fn in_use_focusable(t : Tester, label : String) -> Bool {
  t.semantics().iter().any(fn(s) { s.label == label && (s.actions.contains(Focus) || s.focused) })
}

///|
/// Whether what is called `label` is read out.
fn in_use_read(t : Tester, label : String) -> Bool {
  t.semantics().iter().any(fn(s) { s.label == label && !s.hidden })
}

///|
test "a part in use: Tab goes to the node and the old view's widget in it, both read out" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, _) = in_use_tester(on)
  t.act(Button, Focus, label="甲")
  assert_eq(in_use_round(t), ["乙", "丙"])
  assert_true(in_use_read(t, "乙") && in_use_read(t, "丙"))
}

///|
test "a part not in use: the focus in it let go of at that moment; Tab goes to none of it, nothing of it read out as taking the focus; pressed as ever; in use again, all of it at that moment" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, said) = in_use_tester(on)
  t.act(Button, Focus, label="乙")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("乙"))
  // (said between frames: at once, no frame drawn)
  on.set(false)
  assert_eq(view_app.val.unwrap().focused_now().0, None, msg="the focus kept in what is not in use")
  t.draw()
  t.act(Button, Focus, label="甲")
  assert_eq(in_use_round(t), [], msg="Tab went into what is not in use")
  assert_false(in_use_focusable(t, "乙"), msg="乙 read out as taking the focus")
  assert_true(in_use_read(t, "乙") && in_use_read(t, "丙"), msg="read out as before")
  // (the hand's as ever: a tap on it presses it, a finger held on its cover past a long press is handed through)
  t.tap(120.0, 20.0)
  assert_true(said.contains("乙 pressed"), msg="\{Repr(said)}")
  t.touch(0, 180.0, 20.0)
  t.draw()
  t.run_for(long_press_ms + through_later_ms)
  t.touch(2, 180.0, 20.0)
  t.draw()
  assert_true(said.contains("丙 held"), msg="\{Repr(said)}")
  // in use again: at that moment, no frame drawn
  on.set(true)
  assert_true(in_use_focusable(t, "乙"), msg="乙 may take the focus at that moment")
  t.draw()
  t.act(Button, Focus, label="甲")
  assert_eq(in_use_round(t), ["乙", "丙"])
}

///|
/// An old view the whole window, in a part in use while `in_use` holds, holding a button "旧按钮"; while `open`, a
/// modal layer of the tree's over it holding "取消", giving the focus to it as it opens, leaving over
/// layer_focus_leave_ms (layer_focus_wbtest's layer_page_tester, the part not in use in the place of its page put away).
fn in_use_layer_tester(open : @signals.Signal[Bool], in_use : @signals.Signal[Bool]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)).in_use(By(fn() { in_use.get() })) |> ignore
      old(h, fn(c) {
        let id = c.id("旧按钮")
        c.focusable(id)
        let b = c.box(id~, w=Px(120.0), h=Px(40.0), top=100.0, left=0.0, fn() {  })
        c.semantics(b, Button, id~, label="旧按钮", actions=[Activate])
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)).modal(By(fn() { !l.leaving() })) |> ignore
      let no = l.box(fn(x) {
        x
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="取消"))))
        .on_press(fn() {  })
        |> ignore
      })
      l.focus_opens(no) |> ignore
    }, leave=layer_focus_leave_ms)
  })
  t.draw()
  t
}

///|
test "a layer of the tree's opened from an old view's button with the focus, its part put out of use while it is open: closed, the focus given back to none of it; its part in use still, back on the button" {
  for behind in [false, true] {
    let open = @signals.signal(false)
    let in_use = @signals.signal(true)
    let t = in_use_layer_tester(open, in_use)
    t.act(Button, Focus, label="旧按钮")
    open.set(true)
    t.draw()
    let opened = layer_focused(t)
    // (the part put out of use as the layer stays open: 中屏's page, the sidebar brought over under a menu of its)
    if behind {
      in_use.set(false)
      t.draw()
    }
    open.set(false)
    let closed = layer_focused(t)
    t.run_for(layer_focus_leave_ms)
    let want = if behind { None } else { Some("旧按钮") }
    assert_eq((opened, closed, layer_focused(t)), (Some("取消"), want, want), msg="out of use: \{behind}")
  }
}
