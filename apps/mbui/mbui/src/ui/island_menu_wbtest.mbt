// A menu an old view opens (Ctx::overlay) where that old view is in a modal layer of the window's tree (a dialog's
// body, a field in it with the focus): at the layer's place in the window's stack of layers, as it is now, over it, as
// one a layer of the old frame's opens is at its: a press on it its own, Escape and back closing it, not the layer;
// the next Escape or back the layer's. The layer put at another place while the menu is kept as it was (nothing it
// reads changed): the menu with it.

///|
/// What island_menu_tester has: whether the layer is open, its place, whether the menu is, how many times the menu was
/// pressed, and Escape and back taken by the layer.
priv struct IslandMenu {
  t : Tester
  open : @signals.Signal[Bool]
  place : @signals.Signal[Int]
  menu : @signals.Signal[Bool]
  picked : Ref[Int]
  layer_escapes : Ref[Int]
  layer_backs : Ref[Int]
}

///|
/// A window whose tree holds an old view, and while `open` a modal layer of the tree's at `place` (2 at first) over it,
/// taking Escape and back, holding an old view with a field (the focus given it as the layer opens) and, under it, a
/// menu (not modal: Escape, back and a press away dismiss it) with a button "选这个".
fn island_menu_tester() -> IslandMenu {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  let m = {
    t,
    open: @signals.signal(false),
    place: @signals.signal(2),
    menu: @signals.signal(true),
    picked: Ref(0),
    layer_escapes: Ref(0),
    layer_backs: Ref(0),
  }
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) { c.text("页") |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.show(fn() { m.open.get() }, fn(l) {
      l
      .over(Is(true))
      .stacked(By(fn() { m.place.get() }))
      .modal(Is(true))
      .presses(Is(true))
      .focusable(Is(true), keys=0, tab=false)
      .on_key(fn(k) {
        if k.code == key_escape {
          m.layer_escapes.val = m.layer_escapes.val + 1
          true
        } else {
          false
        }
      })
      .takes_back(fn() { m.layer_backs.val = m.layer_backs.val + 1 })
      |> ignore
      old(l, fn(c) {
        c.editor("层/字段", placeholder="层里的字段") |> ignore
        if m.menu.get() {
          c.with_dismissed(fn(_) { m.menu.set(false) }, fn() {
            c.overlay("层/菜单", fn() {
              c.button("选这个", on_press=fn() {
                m.picked.val = m.picked.val + 1
              })
            })
            |> ignore
          })
        }
      }).height(Is(Some(200.0))).width(Is(Some(300.0)))
      |> ignore
      l.focus_opens_first() |> ignore
    })
  })
  m
}

///|
fn island_menu_frames(t : Tester, n : Int) -> Unit {
  for _ in 0..<n {
    t.frame_at(t.next_frame_time())
  }
}

///|
test "a menu an old view opens in a modal layer of the tree's: over it as it is put elsewhere, pressed, Escape closing it before the layer" {
  let m = island_menu_tester()
  let t = m.t
  t.draw()
  m.open.set(true)
  island_menu_frames(t, 3)
  let focused = t.focused().map(fn(s) { s.label }).unwrap_or("none")
  t.tap_text("选这个")
  island_menu_frames(t, 1)
  let first = m.picked.val
  // (put at another place, the topmost still, the menu kept as it was)
  m.place.set(3)
  island_menu_frames(t, 3)
  // (found where it is drawn, over the layer: else not pressed)
  match t.find("选这个") {
    Some((x, y)) => t.tap(x, y)
    None => ()
  }
  island_menu_frames(t, 1)
  t.key_told(key_escape, 0, t.time())
  island_menu_frames(t, 3)
  let after_one = (m.picked.val, m.menu.get(), m.layer_escapes.val, t.find("层里的字段") is Some(_))
  t.key_told(key_escape, 0, t.time())
  island_menu_frames(t, 1)
  assert_eq((focused, first, after_one, m.layer_escapes.val), ("层里的字段", 1, (2, false, 0, true), 1))
}

///|
test "a menu an old view opens in a modal layer of the tree's, the layer put elsewhere: back closes the menu before the layer" {
  let m = island_menu_tester()
  let t = m.t
  t.draw()
  m.open.set(true)
  island_menu_frames(t, 3)
  // (put at another place, the topmost still, the menu kept as it was; nothing pressed or keyed since)
  m.place.set(3)
  island_menu_frames(t, 3)
  t.back_raw(2, 0.0, t.time())
  island_menu_frames(t, 3)
  let after_one = (m.menu.get(), m.layer_backs.val, t.find("层里的字段") is Some(_))
  t.back_raw(2, 0.0, t.time())
  island_menu_frames(t, 1)
  assert_eq((after_one, m.layer_backs.val), ((false, 0, true), 1))
}

///|
/// Two modal layers of the tree's, "甲" at 2 and "乙" at 3, each holding an old view with a field and its menu (as
/// island_menu_tester's), each taking Escape and back (counted by layer); `places` where each is, `menus` whether each
/// menu is.
fn island_menus_tester(
  places : Array[@signals.Signal[Int]],
  menus : Array[@signals.Signal[Bool]],
  layer_took : Array[Int],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) { c.text("页") |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    for k, name in ["甲", "乙"] {
      root.box(fn(l) {
        l
        .over(Is(true))
        .stacked(By(fn() { places[k].get() }))
        .modal(Is(true))
        .presses(Is(true))
        .focusable(Is(true), keys=0, tab=false)
        .on_key(fn(e) {
          if e.code == key_escape {
            layer_took[k] = layer_took[k] + 1
            true
          } else {
            false
          }
        })
        .takes_back(fn() { layer_took[k] = layer_took[k] + 1 })
        |> ignore
        old(l, fn(c) {
          c.editor("层/\{name}字段", placeholder="\{name}字段") |> ignore
          if menus[k].get() {
            c.with_dismissed(fn(_) { menus[k].set(false) }, fn() {
              c.overlay("层/\{name}菜单", fn() { c.text("\{name}菜单") |> ignore }) |> ignore
            })
          }
        }).height(Is(Some(200.0))).width(Is(Some(300.0)))
        |> ignore
        l.focus_opens_first() |> ignore
      })
      |> ignore
    }
  })
  t
}

///|
/// Which menus are open, and Escape or back taken by each layer, after "甲" (under "乙", each menu kept as it was built)
/// is put over it, then one Escape (`back`: one back).
fn island_menus_crossed(back : Bool) -> (Array[Bool], Array[Int]) {
  let places = [@signals.signal(2), @signals.signal(3)]
  let menus = [@signals.signal(true), @signals.signal(true)]
  let layer_took = [0, 0]
  let t = island_menus_tester(places, menus, layer_took)
  t.draw()
  island_menu_frames(t, 3)
  places[0].set(4)
  island_menu_frames(t, 3)
  if back {
    t.back_raw(2, 0.0, t.time())
  } else {
    t.key_told(key_escape, 0, t.time())
  }
  island_menu_frames(t, 3)
  (menus.map(fn(m) { m.get() }), layer_took)
}

///|
test "two layers of the tree's, each with an old view's menu, put the other way over: Escape and back close the menu of the one now over" {
  assert_eq((island_menus_crossed(false), island_menus_crossed(true)), (([false, true], [0, 0]), ([false, true], [0, 0])))
}

///|
/// One modal layer of the tree's at `place`, its old view's field with two menus kept as they were built: "随层菜单" at
/// the layer's place (none said), "定层菜单" at 3 (said: Ctx::stacked); the layer put from 2 to 4, nothing else of it
/// changed (where its old view is, how big, in what order), then one Escape (`back`: one back). Which menus are open
/// then, and Escape or back taken by the layer. `whole`: each frame drawn whole after it as well and compared
/// (Tester::check_looks), else as a host draws it.
fn island_menus_one(back : Bool, whole : Bool) -> (Bool, Bool, Int) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(whole)
  let place = @signals.signal(2)
  let (with_layer, said) = (@signals.signal(true), @signals.signal(true))
  let took = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) { c.text("页") |> ignore }).grow(Is(1.0)) |> ignore
    })
    |> ignore
    root.show(fn() { true }, fn(l) {
      l
      .over(Is(true))
      .stacked(By(fn() { place.get() }))
      .modal(Is(true))
      .presses(Is(true))
      .focusable(Is(true), keys=0, tab=false)
      .on_key(fn(e) {
        if e.code == key_escape {
          took.val = took.val + 1
          true
        } else {
          false
        }
      })
      .takes_back(fn() { took.val = took.val + 1 })
      |> ignore
      old(l, fn(c) {
        c.editor("层/字段", placeholder="层里的字段") |> ignore
        if with_layer.get() {
          c.with_dismissed(fn(_) { with_layer.set(false) }, fn() {
            c.overlay("层/随层菜单", fn() { c.text("随层菜单") |> ignore }) |> ignore
          })
        }
        if said.get() {
          c.stacked(3, fn() {
            c.with_dismissed(fn(_) { said.set(false) }, fn() {
              c.overlay("层/定层菜单", fn() { c.text("定层菜单") |> ignore }) |> ignore
            })
          })
        }
      }).height(Is(Some(200.0))).width(Is(Some(300.0)))
      |> ignore
      l.focus_opens_first() |> ignore
    })
  })
  t.draw()
  island_menu_frames(t, 3)
  place.set(4)
  island_menu_frames(t, 3)
  if back {
    t.back_raw(2, 0.0, t.time())
  } else {
    t.key_told(key_escape, 0, t.time())
  }
  island_menu_frames(t, 3)
  t.check_looks(true)
  (with_layer.get(), said.get(), took.val)
}

///|
test "one old view's two menus, one at its layer's place, one at a place said, the layer put over the one said: Escape and back close the one at the layer's place" {
  let want = (false, true, 0)
  assert_eq(
    [island_menus_one(false, true), island_menus_one(true, true), island_menus_one(false, false), island_menus_one(true, false)],
    [want, want, want, want],
  )
}
