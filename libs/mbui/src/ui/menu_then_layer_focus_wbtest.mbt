// A field with the focus; a menu opened over it by a pointer; its item pressed, its handler closing the menu and
// opening a modal layer whose field is given the focus once as it opens: once all of it has come and gone, the
// focus is in the new layer's field and what is typed goes into it. The menu closing gives the focus back to what had
// it as it opened only where the focus is still in it or nowhere: the layer opened at the same cause has it already.
// The four ways it is made: an old frame's menu or the tree's, an old frame's layer or the tree's.

///|
/// What menu_layer_tester has: the menu and the layer open, and the layer's field (the tree's).
priv struct MenuLayer {
  t : Tester
  menu : @signals.Signal[Bool]
  layer : @signals.Signal[Bool]
  field : Field
}

///|
/// An old view the whole window: its field "页字段", given the focus as it is first built, and an old button "旧菜单"
/// at 100 down; the tree's button "树菜单" at the top right. While `menu`, a modal menu (the old frame's where
/// `old_menu`, else the tree's) holding "打开层", 200 down, its press closing the menu and opening the layer; while
/// `layer`, a modal layer (the old frame's where `old_layer`, else the tree's) holding the field "层字段" 150 down,
/// given the focus once as it opens. A menu is opened by "旧菜单" where it is the old frame's, else by "树菜单".
fn menu_layer_tester(old_menu : Bool, old_layer : Bool, chosen_in_build? : Bool = false, old_on_top? : Bool = false) -> MenuLayer {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let m = { t, menu: @signals.signal(false), layer: @signals.signal(false), field: Field::new() }
  let page_asked = Ref(false)
  let layer_asked = Ref(false)
  // (an old menu chosen from as it is built, as kit's menu says what was chosen: drawn on, inert, the frames its way
  // out takes)
  let menu_leaving = Ref(0)
  let open_layer = fn() {
    m.menu.set(false)
    m.layer.set(true)
  }
  let tree_button = fn(v : @view.View, label : String, press : () -> Unit) {
    v.box(fn(x) {
      x
      .width(Is(Some(120.0)))
      .height(Is(Some(40.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label~))))
      .on_press(press)
      |> ignore
    })
  }
  // (the old view where `old_on_top`: over all of the tree's, as the frame's old layers are over what it presents)
  let page = fn(root : @view.View) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      if old_on_top {
        h.over(Is(true)).width_share(Is(1.0)).height(Is(Some(300.0))) |> ignore
      }
      old(h, fn(c) {
        c.editor("页/字段", placeholder="页字段") |> ignore
        if !page_asked.val {
          page_asked.val = true
          c.focus_editor("页/字段")
        }
        let id = c.id("旧菜单")
        c.focusable(id)
        let b = c.box(id~, w=Px(120.0), h=Px(40.0), top=100.0, left=0.0, fn() {  })
        c.semantics(b, Button, id~, label="旧菜单", actions=[Activate])
        c.on_press(id, fn() { m.menu.set(true) })
        if old_menu && (m.menu.get() || menu_leaving.val > 0) {
          let now = m.menu.get()
          if !now {
            menu_leaving.val -= 1
          }
          c.with_dismissed(fn(_) { m.menu.set(false) }, fn() {
            c.overlay("菜单", modal=true, inert=!now, fn() {
              let item = c.id("打开层")
              c.focusable(item)
              let i = c.box(id=item, w=Px(120.0), h=Px(40.0), top=200.0, left=0.0, fn() {  })
              c.semantics(i, Button, id=item, label="打开层", actions=[Activate])
              if chosen_in_build {
                if now && c.interact(item).clicked {
                  menu_leaving.val = 2
                  open_layer()
                }
              } else {
                c.on_press(item, open_layer)
              }
            })
            |> ignore
          })
        }
        if old_layer && m.layer.get() {
          c.overlay("层", modal=true, initial_focus=0, fn() {
            c.box(top=150.0, left=0.0, w=Px(200.0), fn() { c.editor("层/字段", placeholder="层字段") |> ignore }) |> ignore
            if !layer_asked.val {
              layer_asked.val = true
              c.focus_editor("层/字段")
            }
          })
          |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  }
  set_view_app(fn(root) {
    if !old_on_top {
      page(root)
    }
    root.box(fn(b) {
      b.over(Is(true)).offset(Is((280.0, 0.0))) |> ignore
      tree_button(b, "树菜单", fn() { m.menu.set(true) }) |> ignore
    })
    |> ignore
    if !old_menu {
      root.show(fn() { m.menu.get() }, fn(l) {
        l.over(Is(true)).stacked(Is(2)).modal(Is(true)) |> ignore
        l.box(fn(gap) { gap.height(Is(Some(200.0))) |> ignore }) |> ignore
        l.focus_opens(tree_button(l, "打开层", open_layer)) |> ignore
      })
    }
    if !old_layer {
      root.show(fn() { m.layer.get() }, fn(l) {
        l.over(Is(true)).stacked(Is(3)).modal(Is(true)) |> ignore
        l.box(fn(gap) { gap.height(Is(Some(150.0))) |> ignore }) |> ignore
        l.box(fn(b) {
          b.width(Is(Some(200.0))) |> ignore
          l.focus_opens(field(b, m.field, placeholder="层字段")) |> ignore
        })
        |> ignore
      })
    }
    if old_on_top {
      page(root)
    }
  })
  t.draw()
  t.draw()
  m
}

///|
/// How long the run is let go on once the item is pressed: what comes and goes there over in it.
let menu_layer_ms : Double = 300.0

///|
/// The four ways, each: the focus on the page's field first; the menu opened by a pointer's tap on what opens it; its
/// 打开层 tapped; then where the focus is and what typing does.
fn menu_then_layer(old_menu : Bool, old_layer : Bool, chosen_in_build? : Bool = false, old_on_top? : Bool = false) -> (String, String, String) {
  let m = menu_layer_tester(old_menu, old_layer, chosen_in_build~, old_on_top~)
  let t = m.t
  let first = t.focus_said()
  let opener = t.get_or_none(Button, if old_menu { "旧菜单" } else { "树菜单" })
  match opener {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
  t.draw()
  match t.get_or_none(Button, "打开层") {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => ()
  }
  t.run_for(menu_layer_ms)
  let after = t.focus_said()
  t.type_text("层里打的字")
  t.draw()
  let typed = if old_layer { t.ime().1 } else { m.field.text() }
  (first, after, typed)
}

///|
/// Where node `label` of `role` is, if it is up (the first so named).
fn Tester::get_or_none(self : Tester, role : Role, label : String) -> (Double, Double, Double, Double)? {
  self.query(role, label~).map(fn(s) { s.rect })
}

///|
test "an old menu's item opening an old layer: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "an old menu's item opening a layer of the tree's: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, false)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "a menu of the tree's item opening an old layer: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(false, true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "a menu of the tree's item opening a layer of the tree's: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(false, false)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "an old menu chosen from as it is built (kit's menu's way), drawn on inert as it goes, opening a layer of the tree's: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, false, chosen_in_build=true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "an old menu chosen from as it is built, drawn on inert as it goes, opening an old layer: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, true, chosen_in_build=true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "the old view over the tree's layers: an old menu chosen from as it is built opening a layer of the tree's: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, false, chosen_in_build=true, old_on_top=true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}

///|
test "the old view over the tree's layers: an old menu's item opening a layer of the tree's in its handler: the focus in the layer's field, typing goes in it" {
  let (first, after, typed) = menu_then_layer(true, false, old_on_top=true)
  assert_true(first.has_prefix("TextField \"页字段\""), msg=first)
  assert_true(after.has_prefix("TextField \"层字段\""), msg=after)
  assert_eq(typed, "层里打的字")
}
