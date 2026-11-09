// A field of an old view with the focus and, over it, a modal layer of the tree's that leaves what is typed to the
// field (View::leaves_typing: a small panel opened beside it that takes no focus). The keys the field does not take
// as its own (Escape) the layer's, before what holds the field and before a layer of the old frame's under the
// tree's (a menu the old view opened by the field, Escape dismissing it): the layer's first, the menu's after it goes.

///|
/// What modal_over_field_tester has: whether the tree's layer is open, whether the old view's menu is, and Escape taken
/// by the layer.
priv struct ModalOverField {
  t : Tester
  open : @signals.Signal[Bool]
  menu : @signals.Signal[Bool]
  layer_escapes : Ref[Int]
}

///|
/// An old view the whole window with a field "页字段" given the focus as it is first built and, while `menu`, a menu by
/// it (Escape and a press away dismiss it); while `open`, a modal layer of the tree's over all of it that leaves what is
/// typed to the field, taking Escape.
fn modal_over_field_tester(menu : Bool) -> ModalOverField {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let m = { t, open: @signals.signal(false), menu: @signals.signal(menu), layer_escapes: Ref(0) }
  let asked = Ref(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if !asked.val {
          asked.val = true
          c.focus_editor("页/字段")
        }
        if m.menu.get() {
          c.with_dismissed(fn(_) { m.menu.set(false) }, fn() {
            c.overlay("页/菜单", fn() { c.text("菜单项") |> ignore }) |> ignore
          })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.show(fn() { m.open.get() }, fn(l) {
      l
      .over(Is(true))
      .stacked(Is(5))
      .modal(Is(true))
      .presses(Is(true))
      .leaves_typing()
      .on_key(fn(k) {
        if k.code == key_escape {
          m.layer_escapes.val = m.layer_escapes.val + 1
          true
        } else {
          false
        }
      })
      |> ignore
      l.box(fn(x) { x.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
    })
  })
  m
}

///|
test "a modal layer of the tree's over a field with the focus that leaves it what is typed: Escape the layer's, not what holds the field" {
  let m = modal_over_field_tester(false)
  let t = m.t
  t.draw()
  t.draw()
  m.open.set(true)
  t.draw()
  t.key_told(key_escape, 0, t.time())
  t.draw()
  assert_eq(m.layer_escapes.val, 1)
}

///|
test "a modal layer of the tree's over a field with the focus and a menu of the old frame's by it: Escape the layer's first, the menu kept; the layer gone, the menu's" {
  let m = modal_over_field_tester(true)
  let t = m.t
  t.draw()
  t.draw()
  assert_true(t.find("菜单项") is Some(_))
  m.open.set(true)
  t.draw()
  t.key_told(key_escape, 0, t.time())
  t.draw()
  assert_eq((m.layer_escapes.val, m.menu.get()), (1, true), msg="the layer's first")
  m.open.set(false)
  t.draw()
  t.key_told(key_escape, 0, t.time())
  t.draw()
  assert_eq((m.layer_escapes.val, m.menu.get()), (1, false), msg="the layer gone: the menu's")
}
