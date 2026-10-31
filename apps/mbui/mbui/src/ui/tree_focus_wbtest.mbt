// The keyboard's focus where the window is a tree: one focus, an old widget's or a node's (Ctx::focus_moved, Tree::
// focus_to), Tab among both in the tree's order at the key's moment (Ctx::focus_spliced), Enter on a node with it its
// press then; a node let go with it, none's, its id nobody's.

///|
/// A focusable node "A" (pressed: `a` counted), an old view with a button of its own, a focusable node "B", in a row; "A"
/// there while `a_on`, a node "C" in its place while `c_on`; the old view's holder taking presses while `old_on`. The
/// old button's id, and the nodes as made (by name, the last made). Last, a node "D" read out as a button, hidden from
/// what is read out while `d_hidden`, taking the focus while `d_focus`, saying what it is
/// while `d_says`.
fn focus_tester(
  a_on : @signals.Signal[Bool],
  c_on : @signals.Signal[Bool],
  old_on : @signals.Signal[Bool],
  a : Ref[Int],
  c : Ref[Int],
  d_hidden? : @signals.Signal[Bool] = @signals.signal(false),
  d_focus? : @signals.Signal[Bool] = @signals.signal(true),
  d_says? : @signals.Signal[Bool] = @signals.signal(true),
) -> (Tester, Ref[Int], Map[String, @view.NodeId]) {
  let ob = Ref(0)
  let ids : Map[String, @view.NodeId] = {}
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { a_on.get() }, fn(v) {
      ids["A"] = v.id()
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .focusable(Is(true))
      .on_press(fn() { a.val = a.val + 1 })
      |> ignore
    })
    root.show(fn() { c_on.get() }, fn(v) {
      ids["C"] = v.id()
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .focusable(Is(true))
      .on_press(fn() { c.val = c.val + 1 })
      |> ignore
    })
    root.box(fn(h) {
      h.width(Is(Some(120.0))).presses(By(fn() { old_on.get() })) |> ignore
      old(h, fn(c) {
        let id = c.id("old button")
        ob.val = id
        c.interact(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      ids["B"] = b.id()
      b.width(Is(Some(80.0))).height(Is(Some(40.0))).focusable(Is(true)) |> ignore
    })
    |> ignore
    // (one read out as a screen reader would give it the focus, kept from what is read out while `d_hidden`)
    root.box(fn(d) {
      ids["D"] = d.id()
      d
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .focusable(By(fn() { d_focus.get() }))
      .says(By(fn() { if d_says.get() { Some(@view.said(Button, label="D")) } else { None } }))
      .hides(By(fn() { d_hidden.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, ob, ids)
}

///|
/// Where the focus is, as either side has it: the old one's id, or the node's name; whether the tree shows it.
fn focus_at(ob : Int, ids : Map[String, @view.NodeId]) -> (String, Bool) {
  let tree = view_app.val.unwrap()
  let (n, shown) = tree.focused_now()
  let c = g()
  match n {
    Some(id) => {
      let mut name = "?"
      for k, v in ids {
        if v == id {
          name = k
        }
      }
      // (one focus: the old side has the node's id)
      if c.focus != tree_said_id(id) {
        name = name + " (old side: \{c.focus})"
      }
      (name, shown)
    }
    None => (if c.focus == ob { "old" } else if c.focus == 0 { "none" } else { "other \{c.focus}" }, false)
  }
}

///|
test "Tab and Shift+Tab among a node, an old view's widget and another node, in the tree's order, each at the key's moment: no frame drawn between them, nothing read out before" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let (_t, ob, ids) = focus_tester(on(true), on(false), on(true), Ref(0), Ref(0))
  // (keys only, no frame drawn after any of them)
  on_key(key_tab, 0)
  assert_eq(focus_at(ob.val, ids), ("A", true), msg="the first Tab")
  on_key(key_tab, 0)
  assert_eq(focus_at(ob.val, ids), ("old", false), msg="the second")
  on_key(key_tab, 0)
  assert_eq(focus_at(ob.val, ids), ("B", true), msg="the third")
  on_key(key_tab, mod_shift_key)
  assert_eq(focus_at(ob.val, ids), ("old", false), msg="Shift+Tab back")
  on_key(key_tab, mod_shift_key)
  assert_eq(focus_at(ob.val, ids), ("A", true), msg="and again")
}

///|
test "Enter on a node with the focus: its press at the key's moment, no frame drawn; a press with the pointer on a node lets the focus go" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let a = Ref(0)
  let (t, ob, ids) = focus_tester(on(true), on(false), on(true), a, Ref(0))
  on_key(key_tab, 0)
  on_key(key_enter, 0)
  assert_eq(a.val, 1, msg="pressed as Enter came")
  assert_eq(focus_at(ob.val, ids), ("A", true))
  // (B pressed with the pointer: the focus nobody's)
  t.press_at(240.0, 20.0)
  t.release(240.0, 20.0)
  assert_eq(focus_at(ob.val, ids), ("none", false), msg="let go as a press came")
}

///|
test "the focus on a node let go of with it, and a node made in its place in the same change: none's, the new one given nothing of it; a late Enter or a screen reader's Focus by the old id, nothing" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let a_on = on(true)
  let c_on = on(false)
  let c_pressed = Ref(0)
  let (_t, ob, ids) = focus_tester(a_on, c_on, on(true), Ref(0), c_pressed)
  on_key(key_tab, 0)
  let a_id = tree_said_id(ids["A"])
  assert_eq(focus_at(ob.val, ids), ("A", true))
  // (A let go and C made where it was, in one change, no frame drawn)
  let tree = view_app.val.unwrap()
  tree.event(view_moment(), fn() {
    a_on.set(false)
    c_on.set(true)
  })
  assert_eq(focus_at(ob.val, ids), ("none", false), msg="let go with its node")
  on_key(key_enter, 0)
  assert_eq(c_pressed.val, 0, msg="a late Enter: not the new one's")
  tree_said_action(a_id, Focus) |> ignore
  assert_eq(focus_at(ob.val, ids), ("none", false), msg="a screen reader's Focus by the old id: still none's")
}

///|
test "an old view's holder said to take no press, no frame drawn: its widgets none of Tab's from then; said to again, theirs" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let old_on = on(true)
  let (_t, ob, ids) = focus_tester(on(true), on(false), old_on, Ref(0), Ref(0))
  let tree = view_app.val.unwrap()
  tree.event(view_moment(), fn() { old_on.set(false) })
  on_key(key_tab, 0)
  on_key(key_tab, 0)
  assert_eq(focus_at(ob.val, ids), ("B", true), msg="past the old view taking no press")
  tree.event(view_moment(), fn() { old_on.set(true) })
  on_key(key_tab, mod_shift_key)
  assert_eq(focus_at(ob.val, ids), ("old", false), msg="back to it once it takes presses again")
}

///|
test "a screen reader's Focus on a node as it may give it then: kept from what is read out, or saying nothing, refused, the focus left where it was; read out again, given" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let d_hidden = on(false)
  let d_says = on(true)
  let (_t, ob, ids) = focus_tester(on(true), on(false), on(true), Ref(0), Ref(0), d_hidden~, d_says~)
  on_key(key_tab, 0)
  assert_eq(focus_at(ob.val, ids), ("A", true))
  let d = tree_said_id(ids["D"])
  let tree = view_app.val.unwrap()
  tree.event(view_moment(), fn() { d_hidden.set(true) })
  tree_said_action(d, Focus) |> ignore
  assert_eq(focus_at(ob.val, ids), ("A", true), msg="hidden from what is read out: refused, A keeps it")
  tree.event(view_moment(), fn() {
    d_hidden.set(false)
    d_says.set(false)
  })
  tree_said_action(d, Focus) |> ignore
  assert_eq(focus_at(ob.val, ids), ("A", true), msg="saying nothing: refused, A keeps it")
  tree.event(view_moment(), fn() { d_says.set(true) })
  tree_said_action(d, Focus) |> ignore
  assert_eq(focus_at(ob.val, ids), ("D", true), msg="read out again: given")
}

///|
test "Tab between two nodes builds none of the old views again; Tab to an old view's widget builds that one again, its ring shown, not the other" {
  let built = [0, 0]
  let ring = Ref(false)
  let ids : Map[String, @view.NodeId] = {}
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    for k in ["A", "B"] {
      root.box(fn(v) {
        ids[k] = v.id()
        v.width(Is(Some(60.0))).height(Is(Some(40.0))).focusable(Is(true)) |> ignore
      })
      |> ignore
    }
    for k in 0..<2 {
      root.box(fn(h) {
        h.width(Is(Some(100.0))) |> ignore
        old(h, fn(c) {
          built[k] = built[k] + 1
          let id = c.id("button \{k}")
          if k == 0 {
            c.interact(id) |> ignore
            ring.val = c.focus_shown(id)
          }
          c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
        }).grow(Is(1.0))
        |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  let at_rest = built.copy()
  // (frames as a host draws them, none of a test's change: Tester::draw builds every old view anew)
  t.frame_now()
  assert_eq(built.copy(), at_rest, msg="a frame with nothing changed builds none again")
  on_key(key_tab, 0)
  t.frames_owed()
  on_key(key_tab, 0)
  t.frames_owed()
  assert_eq(built.copy(), at_rest, msg="Tab from A to B: none built again")
  on_key(key_tab, 0)
  t.frames_owed()
  assert_true(built[0] > at_rest[0], msg="Tab to the first old view's button: that one built again")
  assert_eq(built[1], at_rest[1], msg="the other not")
  assert_true(ring.val, msg="its ring shown")
}

///|
/// The line a host is told of a node read out as `role` labelled `label` (a11y.mbt's fields), if one.
fn told_line(t : Tester, role : String, label : String) -> Array[String]? {
  for l in t.a11y_said().split("\n") {
    let f = l.split("\u{1F}").map(fn(v) { v.to_string() }).to_array()
    if f.length() == 16 && f[3] == role && f[9] == label {
      return Some(f)
    }
  }
  None
}

///|
test "a node said to take the focus, not having it: the host told it can be given the focus, by the frame that change is owed; said not to, told so" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let d_focus = on(false)
  let (t, _ob, _ids) = focus_tester(on(true), on(false), on(true), Ref(0), Ref(0), d_focus~)
  t.set_a11y(true)
  t.draw()
  assert_eq(told_line(t, "Button", "D").map(fn(f) { f[15] }), Some(""), msg="taking no focus: none to be given")
  // (as what comes from outside says it, in no event of the tree's; only the frames it owes: none of a test's change)
  d_focus.set(true)
  t.frames_owed()
  assert_eq(told_line(t, "Button", "D").map(fn(f) { f[15] }), Some("f"), msg="told it can be given it")
  d_focus.set(false)
  t.frames_owed()
  assert_eq(told_line(t, "Button", "D").map(fn(f) { f[15] }), Some(""), msg="and told it no more can")
}

///|
/// A focusable node "A" (pressed: counted in `a`) there while `a_on`, a node "D" read out as a button, focusable, and an
/// old view with a field of its own and, while `layer_on`, a modal layer of the old frame's with a button: the field's
/// and the layer's button's ids, the nodes by name, and whether the field's focus showed as its view was last built.
fn layered_tester(
  a_on : @signals.Signal[Bool],
  layer_on : @signals.Signal[Bool],
  a : Ref[Int],
) -> (Tester, Ref[Int], Ref[Int], Map[String, @view.NodeId], Ref[Bool]) {
  let field_id = Ref(0)
  let layer_id = Ref(0)
  let ring = Ref(false)
  let ids : Map[String, @view.NodeId] = {}
  let field = Field::new()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { a_on.get() }, fn(v) {
      ids["A"] = v.id()
      v
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .focusable(Is(true))
      .on_press(fn() { a.val = a.val + 1 })
      |> ignore
    })
    root.box(fn(d) {
      ids["D"] = d.id()
      d.width(Is(Some(40.0))).height(Is(Some(40.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label="D"))))
      |> ignore
    })
    |> ignore
    root.box(fn(h) {
      h.width(Is(Some(200.0))) |> ignore
      old(h, fn(c) {
        c.editor("field", field~, font_size=10.0) |> ignore
        field_id.val = c.id("field")
        ring.val = c.focus_shown(field_id.val)
        if layer_on.get() {
          c.overlay("dialog", modal=true, fn() {
            let id = c.id("layer button")
            layer_id.val = id
            c.interact(id) |> ignore
            c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
          })
          |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, field_id, layer_id, ids, ring)
}

///|
/// Where the focus is: "A" or "D" (the node's, both sides saying so), "field", "layer", "none"; and whether either side
/// shows it.
fn layered_at(field : Int, layer : Int, ids : Map[String, @view.NodeId]) -> (String, Bool) {
  let tree = view_app.val.unwrap()
  let c = g()
  match tree.focused_now() {
    (Some(n), shown) => {
      let mut name = "?"
      for k, v in ids {
        if v == n {
          name = k
        }
      }
      if c.focus != tree_said_id(n) {
        name = name + " (old side: \{c.focus})"
      }
      (name, shown)
    }
    (None, _) => {
      let name = if c.focus == field {
        "field"
      } else if c.focus == layer {
        "layer"
      } else if c.focus == 0 {
        "none"
      } else {
        "other"
      }
      (name, c.focus != 0 && c.focus_visible)
    }
  }
}

///|
test "a field's focus shown, a node pressed beside it: the field keeps the focus, unshown, by the frame the press owes" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let (t, field, layer, ids, ring) = layered_tester(on(true), on(false), Ref(0))
  // (A, D, then the field)
  on_key(key_tab, 0)
  on_key(key_tab, 0)
  on_key(key_tab, 0)
  t.frames_owed()
  assert_eq(layered_at(field.val, layer.val, ids), ("field", true))
  assert_true(ring.val, msg="its ring shown as its view was built")
  // (the finger as a host gives it, the frames it owes drawn: none of a test's change)
  finger(0, 40.0, 20.0)
  finger(2, 40.0, 20.0)
  t.frames_owed()
  assert_eq(layered_at(field.val, layer.val, ids), ("field", false), msg="kept, unshown")
  assert_false(ring.val, msg="its ring gone as its view was built again")
}

///|
test "the focus on a node, a modal layer of the old frame's opening over it and closing: in the layer as it is open (the node's shown no more), back on the node as it closes; the node let go meanwhile, nobody's" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  for gone in [false, true] {
    let a_on = on(true)
    let layer_on = on(false)
    let (t, field, layer, ids, _ring) = layered_tester(a_on, layer_on, Ref(0))
    on_key(key_tab, 0)
    assert_eq(layered_at(field.val, layer.val, ids), ("A", true))
    layer_on.set(true)
    t.draw()
    assert_eq(layered_at(field.val, layer.val, ids).0, "layer", msg="in the layer as it opens")
    // (a screen reader's Focus on a node under it: refused, the layer's button keeping it)
    tree_said_action(tree_said_id(ids["D"]), Focus) |> ignore
    assert_eq(layered_at(field.val, layer.val, ids).0, "layer", msg="a node under the modal layer: refused")
    if gone {
      let tree = view_app.val.unwrap()
      tree.event(view_moment(), fn() { a_on.set(false) })
    }
    layer_on.set(false)
    t.draw()
    let want = if gone { "none" } else { "A" }
    assert_eq(layered_at(field.val, layer.val, ids).0, want, msg="as it closes (A let go meanwhile: \{gone})")
    on_key(key_enter, 0)
  }
}

///|
test "a key catcher's focus shown, a node pressed beside it: the catcher keeps the focus, its ring gone by the frame the press owes" {
  let a = Ref(0)
  let give = Ref(true)
  let ring = Ref(false)
  let catcher = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(Is(Some(80.0))).height(Is(Some(40.0))).focusable(Is(true)).on_press(fn() { a.val = a.val + 1 }) |> ignore
    })
    |> ignore
    root.box(fn(h) {
      h.width(Is(Some(200.0))) |> ignore
      old(h, fn(c) {
        let k = c.key_catcher("keys")
        catcher.val = k.id
        if give.val {
          give.val = false
          c.focus_on(k.id, visible=true)
        }
        ring.val = c.focus_shown(k.id)
        c.box(w=Px(80.0), h=Px(40.0), fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  assert_eq((g().focus == catcher.val, ring.val), (true, true), msg="given it, shown")
  // (the finger as a host gives it, the frames it owes drawn: none of a test's change)
  finger(0, 40.0, 20.0)
  finger(2, 40.0, 20.0)
  t.frames_owed()
  assert_eq(a.val, 1, msg="the node pressed")
  assert_eq((g().focus == catcher.val, ring.val), (true, false), msg="the catcher keeps it, its ring gone")
}

///|
test "a node read out, said anew to take the focus by another saying, between frames: the host told it can be given it by the frame that owes; the saying before let go of then" {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  let first = on(false)
  let second = on(true)
  let e : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(v) {
      e.val = Some(v)
      v
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .focusable(By(fn() { first.get() }))
      .says(Is(Some(@view.said(Button, label="E"))))
      |> ignore
    })
    |> ignore
  })
  t.set_a11y(true)
  t.draw()
  let actions = fn() { told_line(t, "Button", "E").map(fn(f) { f[15] }) }
  assert_eq(actions(), Some(""), msg="taking no focus")
  assert_true(first.watched(), msg="its saying followed")
  let v = e.val.unwrap()
  // (said anew as a value, then by another saying, each between frames, only the frames owed drawn)
  v.focusable(Is(true)) |> ignore
  assert_false(first.watched(), msg="said anew as a value: the saying before let go of then")
  t.frames_owed()
  assert_eq(actions(), Some("f"), msg="said anew as a value: told")
  v.focusable(Is(false)) |> ignore
  t.frames_owed()
  assert_eq(actions(), Some(""), msg="and back")
  v.focusable(By(fn() { second.get() })) |> ignore
  assert_true(second.watched(), msg="the new saying followed")
  t.frames_owed()
  assert_eq(actions(), Some("f"), msg="by another saying, true as first read: told")
  // (the saying before let go of: what it read changing changes nothing)
  first.set(true)
  second.set(false)
  t.frames_owed()
  assert_eq(actions(), Some(""), msg="the one said last followed, the one before not")
  v.focusable(Is(false)) |> ignore
  assert_false(second.watched(), msg="said anew as a value: let go of then")
}
