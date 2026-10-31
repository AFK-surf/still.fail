// What is read out of the window where it is a tree (Ctx::semantics_spliced): its nodes that say what they are, in its
// order, each old view's widgets at its node, a node's press done as a screen reader asks it, one taking no presses
// read out and done nothing.

///|
/// A tree button ("前一个") before an old view with a button of its own ("旧的"), a separator, another tree button
/// ("后一个") taking presses as `on` says: how many times each tree button was pressed.
fn said_tester(on : @signals.Signal[Bool], before : Ref[Int], after : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() { before.val = before.val + 1 })
      .says(Is(Some(@view.said(Button, label="前一个"))))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(120.0))) |> ignore
      old(v, fn(c) {
        let id = c.id("old")
        c.clicked(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, label="旧的", fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(s) { s.width(Is(Some(1.0))).height(Is(Some(40.0))).says(Is(Some(@view.said(Separator)))) |> ignore })
    |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { on.get() }))
      .on_press(fn() { after.val = after.val + 1 })
      .says(Is(Some(@view.said(Button, label="后一个"))))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "read out of the window's tree: its nodes in its order, an old view's widgets at its node, a separator said so" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = said_tester(on, Ref(0), Ref(0))
  let read = t.semantics().filter(fn(s) { !s.hidden }).map(fn(s) { (s.role, s.label) })
  assert_eq(read, [(Button, "前一个"), (Button, "旧的"), (Separator, ""), (Button, "后一个")])
}

///|
test "a node of the tree's pressed as a screen reader asks it: its press, once; taking no presses, read out disabled, done nothing" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let before = Ref(0)
  let after = Ref(0)
  let t = said_tester(on, before, after)
  t.act(Button, Activate, label="前一个")
  assert_eq(before.val, 1)
  on.set(false)
  t.draw()
  let s = t.get(Button, label="后一个")
  assert_eq((s.disabled, s.actions), (true, []))
  t.act(Button, Activate, label="后一个")
  assert_eq(after.val, 0)
  on.set(true)
  t.draw()
  t.act(Button, Activate, label="后一个")
  assert_eq(after.val, 1)
}

///|
/// One node, read out as `label` while `says` holds, shown while `shown` holds, pressed counting `presses`.
fn one_said(
  shown : @signals.Signal[Bool],
  says : Bool,
  label : String,
  presses : Ref[Int],
) -> (@view.View) -> Unit {
  fn(root) {
    root.show(fn() { shown.get() }, fn(b) {
      b.width(Is(Some(80.0))).height(Is(Some(40.0))).on_press(fn() { presses.val = presses.val + 1 }) |> ignore
      if says {
        b.says(Is(Some(@view.said(Button, label~)))) |> ignore
      }
    })
  }
}

///|
test "a node let go, its index made another's: the other read out as itself, by an id of its own; the first's id asked, the other not pressed" {
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let b_on = @signals.signal(false, same=fn(a, b) { a == b })
  let a_pressed = Ref(0)
  let b_pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    one_said(a_on, true, "甲", a_pressed)(root)
    one_said(b_on, true, "乙", b_pressed)(root)
  })
  t.draw()
  let a_id = t.get(Button, label="甲").id
  a_on.set(false)
  b_on.set(true)
  t.draw()
  assert_eq(t.semantics().filter(fn(s) { s.role == Button }).map(fn(s) { s.label }), ["乙"])
  assert_true(t.get(Button, label="乙").id != a_id)
  // (asked by its id as the host has it: none of the other's)
  t.post(@hostapi.a11y_channel, "{\"id\":\{a_id},\"action\":\"activate\"}")
  t.draw()
  assert_eq((a_pressed.val, b_pressed.val), (0, 0))
}

///|
/// A button of the tree's taking presses as `on` says, flipped at `flip_ms` by a moment of its own, no frame drawn
/// between; asked to be pressed as a screen reader asks at `ask_ms`: whether it was.
fn asked_after_flip(on_first : Bool) -> Int {
  let on = @signals.signal(on_first, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  let t0 = t.time()
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { on.get() }))
      .on_press(fn() { pressed.val = pressed.val + 1 })
      .says(Is(Some(@view.said(Button, label="按钮"))))
      |> ignore
      b.at_moment(t0 + flip_ms, fn() { on.set(!on_first) }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let id = t.semantics().filter(fn(s) { s.label == "按钮" })[0].id
  t.advance(t0 + ask_ms - t.time())
  g().ask_action(id, Activate)
  pressed.val
}

///|
let flip_ms : Double = 50.0

///|
let ask_ms : Double = 100.0

///|
test "a screen reader's press asked at its moment, the button's taking presses changed by then, no frame between: as it is then, both ways" {
  assert_eq(asked_after_flip(true), 0)
  assert_eq(asked_after_flip(false), 1)
}

///|
test "a layer of the old frame's over everything, modal: the tree's buttons under it read out hidden and pressed by nothing; closed, again" {
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() { pressed.val = pressed.val + 1 })
      .says(Is(Some(@view.said(Button, label="树的"))))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, fn(c) {
        if open.get() {
          c.overlay("menu", modal=true, fn() {
            let id = c.id("item")
            c.clicked(id) |> ignore
            c.box(w=Px(80.0), h=Px(40.0), id~, label="菜单项", fn() {  }) |> ignore
          })
          |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree_button = t.semantics().filter(fn(s) { s.label == "树的" })
  assert_true(tree_button.length() == 1 && tree_button[0].hidden, msg="\{tree_button}")
  g().ask_action(tree_button[0].id, Activate)
  t.draw()
  assert_eq(pressed.val, 0)
  open.set(false)
  t.draw()
  let s = t.get(Button, label="树的")
  t.act(Button, Activate, label="树的")
  assert_eq((s.hidden, pressed.val), (false, 1))
}

///|
test "what can be done to a node of the tree's: Activate where a press does something, none of a separator; as the host is told it" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = said_tester(on, Ref(0), Ref(0))
  t.set_a11y(true)
  t.draw()
  let sep = t.get(Separator)
  assert_eq(sep.actions, [])
  let said = t.a11y_said()
  let line = fn(role : String, label : String) {
    for l in said.split("\n") {
      let f = l.split("\u{1F}").map(fn(v) { v.to_string() }).to_array()
      if f.length() == 16 && f[3] == role && f[9] == label {
        return Some(f)
      }
    }
    None
  }
  assert_eq(line("Button", "前一个").map(fn(f) { f[15] }), Some("a"))
  assert_eq(line("Separator", "").map(fn(f) { f[15] }), Some(""))
}

///|
/// A button read out, then (no frame drawn) kept from being read out by `how` at `flip_ms` (0 its own hides by a
/// signal, 1 what holds it hidden by a moment of its own, 2 its saying none): whether a screen reader's press of the id
/// it was read out by at `ask_ms` pressed it, and whether one did once it is read out again.
fn asked_unsaid(how : Int) -> (Int, Int) raise {
  let hidden = @signals.signal(false, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  let t0 = t.time()
  set_view_app(fn(root) {
    root.box(fn(holder) {
      holder.hides(By(fn() { how == 1 && hidden.get() })) |> ignore
      if how == 1 {
        holder.at_moment(t0 + flip_ms, fn() { hidden.set(true) }) |> ignore
      }
      holder.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() { pressed.val = pressed.val + 1 })
        .hides(By(fn() { how == 0 && hidden.get() }))
        .says(By(fn() { if how == 2 && hidden.get() { None } else { Some(@view.said(Button, label="按钮")) } }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let id = t.get(Button, label="按钮").id
  if how != 1 {
    hidden.set(true)
  }
  t.advance(t0 + ask_ms - t.time())
  g().ask_action(id, Activate)
  let then = pressed.val
  hidden.set(false)
  t.draw()
  t.act(Button, Activate, label="按钮")
  (then, pressed.val)
}

///|
test "a button read out, then kept from it (its own hiding, what holds it hidden at a moment, its saying none), no frame drawn: a screen reader's press of its id presses nothing; read out again, one does" {
  assert_eq(asked_unsaid(0), (0, 1))
  assert_eq(asked_unsaid(1), (0, 1))
  assert_eq(asked_unsaid(2), (0, 1))
}

///|
test "the window's tree made anew, a node in the same place saying what it is: the first tree's button's id asked, the new one not pressed" {
  let first = Ref(0)
  let second = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  let button = fn(label : String, pressed : Ref[Int]) {
    fn(root : @view.View) {
      root.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() { pressed.val = pressed.val + 1 })
        .says(Is(Some(@view.said(Button, label~))))
        |> ignore
      })
      |> ignore
    }
  }
  set_view_app(button("甲", first))
  t.draw()
  let a_id = t.get(Button, label="甲").id
  set_view_app(button("乙", second))
  t.draw()
  assert_true(t.get(Button, label="乙").id != a_id)
  t.post(@hostapi.a11y_channel, "{\"id\":\{a_id},\"action\":\"activate\"}")
  t.draw()
  assert_eq((first.val, second.val), (0, 0))
}

///|
/// An old view's button (its id as the host was told it), its view in a node hidden from what is read out as `hidden`
/// says, a modal layer of the tree's over it as `modal` says: how many times it was clicked.
fn old_said(hidden : @signals.Signal[Bool], modal : @signals.Signal[Bool], clicks : Ref[Int], id : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.grow(Is(1.0)).hides(By(fn() { hidden.get() })) |> ignore
      old(v, fn(c) {
        let b = c.id("old")
        id.val = b
        if c.clicked(b) {
          clicks.val = clicks.val + 1
        }
        c.box(w=Px(80.0), h=Px(40.0), id=b, label="旧的", fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { modal.get() }, fn(m) {
      m.over(Is(true)).modal(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
    })
  })
  t.draw()
  t
}

///|
test "an old view's button its id told the host, then its view hidden by the tree or under a modal layer of its: a late Activate does nothing; shown again, it is clicked" {
  for how in [0, 1] {
    let hidden = @signals.signal(false, same=fn(a, b) { a == b })
    let modal = @signals.signal(false, same=fn(a, b) { a == b })
    let clicks = Ref(0)
    let id = Ref(0)
    let t = old_said(hidden, modal, clicks, id)
    if how == 0 {
      hidden.set(true)
    } else {
      modal.set(true)
    }
    t.post(@hostapi.a11y_channel, "{\"id\":\{id.val},\"action\":\"activate\"}")
    t.draw()
    assert_eq(clicks.val, 0, msg="kept from it (\{how})")
    hidden.set(false)
    modal.set(false)
    t.draw()
    t.post(@hostapi.a11y_channel, "{\"id\":\{id.val},\"action\":\"activate\"}")
    t.draw()
    assert_eq(clicks.val, 1, msg="again (\{how})")
  }
}

///|
/// An old view's button in a node of the tree's taking presses as `on` says, shown while `shown` holds (leaving
/// `leave_ms` as it goes); its id as the host was told it; how many times it was clicked.
fn old_in_node(
  on : @signals.Signal[Bool],
  shown : @signals.Signal[Bool],
  clicks : Ref[Int],
  id : Ref[Int],
  host : Ref[@view.View?],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.set_a11y(true)
  set_view_app(fn(root) {
    root.show(
      fn() { shown.get() },
      fn(v) {
        host.val = Some(v)
        v.grow(Is(1.0)).presses(By(fn() { on.get() })) |> ignore
        old(v, fn(c) {
          let b = c.id("old")
          id.val = b
          if c.clicked(b) {
            clicks.val = clicks.val + 1
          }
          c.box(w=Px(80.0), h=Px(40.0), id=b, label="旧的", fn() {  }) |> ignore
        }).grow(Is(1.0))
        |> ignore
      },
      leave=leave_ms,
    )
  })
  t.draw()
  t
}

///|
let leave_ms : Double = 200.0

///|
test "an old view's button in a node taking no presses: read out disabled, nothing done by a screen reader; taking them again, clicked; its node leaving, nothing" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let id = Ref(0)
  let t = old_in_node(on, shown, clicks, id, Ref(None))
  let activate = fn() {
    t.post(@hostapi.a11y_channel, "{\"id\":\{id.val},\"action\":\"activate\"}")
    t.draw()
  }
  on.set(false)
  t.draw()
  let s = t.get(Button, label="旧的")
  assert_eq((s.disabled, s.actions), (true, []))
  activate()
  assert_eq(clicks.val, 0, msg="taking no presses")
  on.set(true)
  t.draw()
  activate()
  assert_eq(clicks.val, 1, msg="taking them again")
  // (going: leaving a while, alive meanwhile)
  shown.set(false)
  activate()
  assert_eq(clicks.val, 1, msg="leaving")
}

///|
test "a screen reader's press asked inside an event of the tree's: nothing due at that moment done ahead of the rest of it; asked alone, what was due before done first" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let id = Ref(0)
  let host : Ref[@view.View?] = Ref(None)
  let t = old_in_node(on, shown, clicks, id, host)
  let tree = view_tree().unwrap()
  let step = Ref(0)
  let seen = Ref(-1)
  let at = t.time() + flip_ms
  t.advance(flip_ms)
  tree.event(at, fn() {
    step.val = 1
    host.val.unwrap().at_moment(at, fn() { seen.val = step.val }) |> ignore
    g().ask_action(id.val, Activate)
    step.val = 2
  })
  assert_true(seen.val != 1, msg="done in the middle of the event: \{seen.val}")
  // (that one taken as asked: clicked as the old view is built next)
  t.draw()
  let before = clicks.val
  // (alone: its node taking presses no more at a moment before it, that done first)
  let t0 = t.time()
  host.val.unwrap().at_moment(t0 + flip_ms, fn() { on.set(false) }) |> ignore
  t.advance(ask_ms)
  g().ask_action(id.val, Activate)
  t.draw()
  assert_eq(clicks.val, before, msg="taking presses no more by then")
}
