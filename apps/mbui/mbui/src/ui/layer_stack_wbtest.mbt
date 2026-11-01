// The window's stack of layers, the old frame's and the window's tree's in one order (Ctx::stacked, View::stacked): a
// layer each, modal, the whole window a button of its own; only the topmost takes a press, Enter, Escape, a screen
// reader's Activate, Tab; drawn in that order; closed, the one under it takes them again. What a layer opens in it (a
// menu) at its place.

///|
/// Which layers there are, each at its place, and what each was pressed (by name).
struct StackCase {
  on : Map[String, @signals.Signal[Bool]]
  pressed : Array[String]
  /// each closed, by name, at the moment it is (dismissed: back, Escape)
  closed : Array[String]
}

///|
/// An old view the whole window and, by `layers` (name, place, whether the tree's), a modal layer each the whole window,
/// a button read out by its name: the old frame's in an overlay at its place (Ctx::stacked), the tree's a node the root
/// holds at its place (View::stacked). The old "甲" opens a menu in it (a layer of its own, not modal, 120 by 40 at the
/// top left, a button "甲的菜单") while `menu`.
fn stack_tester(
  layers : Array[(String, Int, Bool)],
  menu? : @signals.Signal[Bool] = @signals.signal(false),
  grouped? : Array[(String, Int)] = [],
) -> (Tester, StackCase) {
  let k : StackCase = { on: Map([]), pressed: [], closed: [] }
  for l in layers {
    k.on[l.0] = @signals.signal(true)
  }
  for l in grouped {
    k.on[l.0] = @signals.signal(true)
  }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        for l in layers {
          let (name, stack, tree) = l
          if tree || !k.on[name].get() {
            continue
          }
          c.stacked(stack, fn() {
            c.with_dismissed(fn(_) { k.closed.push(name) }, fn() {
            let o = c.overlay(name, modal=true, outside=false, fn() {
              let id = c.id(name + " button")
              c.focusable(id)
              if c.interact(id).clicked {
                k.pressed.push(name)
              }
              let b = c.box(id~, w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {  })
              c.semantics(b, Button, id~, label=name, actions=[Activate])
              if name == "甲" && menu.get() {
                ignore(c.overlay("甲的菜单", fn() {
                  let mid = c.id("甲的菜单 button")
                  if c.interact(mid).clicked {
                    k.pressed.push("甲的菜单")
                  }
                  let m = c.box(id=mid, w=Px(120.0), h=Px(40.0), bg=0xFF7F7FFFL, fn() {  })
                  c.semantics(m, Button, id=mid, label="甲的菜单", actions=[Activate])
                }))
              }
            })
            // (back, Escape: closed)
            if o.dismissed is Some(_) {
              k.on[name].set(false)
            }
            })
          })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    // (the tree's layers in one slot of the root's, in `grouped`'s order, each its own place)
    if !grouped.is_empty() {
      root.each(fn() { grouped.filter(fn(g) { k.on[g.0].get() }) }, fn(g) { g.0 }, fn(row, item) {
        let (name, stack) = @signals.untracked(fn() { item.get() })
        let on = k.on[name]
        row
        .over(Is(true))
        .stacked(Is(stack))
        .modal(Is(true))
        .ground(Is(0x7FFF7FFFL))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label=name))))
        .on_press(fn() { k.pressed.push(name) })
        .takes_back(fn() {
          k.closed.push(name)
          on.set(false)
        })
        |> ignore
      })
    }
    for l in layers {
      let (name, stack, tree) = l
      if !tree {
        continue
      }
      let on = k.on[name]
      root.show(fn() { on.get() }, fn(v) {
        v
        .over(Is(true))
        .stacked(Is(stack))
        .modal(Is(true))
        .ground(Is(0x7FFF7FFFL))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label=name))))
        .on_press(fn() { k.pressed.push(name) })
        .takes_back(fn() {
          k.closed.push(name)
          on.set(false)
        })
        |> ignore
      })
    }
  })
  t.draw()
  t.draw()
  (t, k)
}

///|
/// The ids each layer is read out by (its button's), hidden under another or not: kept, so that what is under another,
/// or gone, is asked by them still.
fn stack_ids(t : Tester, names : Array[String]) -> Map[String, Int] {
  let ids : Map[String, Int] = Map([])
  for s in t.semantics() {
    if s.role == Button && names.contains(s.label) {
      ids[s.label] = s.id
    }
  }
  ids
}

///|
/// What a press in the middle, a screen reader's Activate of each by the id it was read out by (`ids`: asked whether it
/// is read out now or not), and Tab take now: the press's and Activate's by name (what was pressed), what has the focus
/// after Tab.
fn stack_takes(t : Tester, k : StackCase, ids : Map[String, Int]) -> (Array[String], Array[String], String?) {
  let from = k.pressed.length()
  t.tap(200.0, 150.0)
  let tapped = k.pressed[from:].to_array()
  let from = k.pressed.length()
  for n in ["甲", "乙", "丙"] {
    match ids.get(n) {
      Some(id) => {
        g().ask_action(id, Activate)
        t.draw()
      }
      None => ()
    }
  }
  let acted = k.pressed[from:].to_array()
  t.tab()
  (tapped, acted, t.focused().map(fn(s) { s.label }))
}

///|
test "old 甲 at 1, the tree's 乙 at 2, old 丙 at 3: 丙 alone takes them; closed, 乙; closed, 甲" {
  let (t, k) = stack_tester([("甲", 1, false), ("乙", 2, true), ("丙", 3, false)])
  let ids = stack_ids(t, ["甲", "乙", "丙"])
  let all = stack_takes(t, k, ids)
  k.on["丙"].set(false)
  t.draw()
  t.draw()
  let two = stack_takes(t, k, ids)
  k.on["乙"].set(false)
  t.draw()
  t.draw()
  let one = stack_takes(t, k, ids)
  assert_eq(
    (all, two, one),
    ((["丙"], ["丙"], Some("丙")), (["乙"], ["乙"], Some("乙")), (["甲"], ["甲"], Some("甲"))),
  )
}

///|
test "the tree's 甲 at 1, old 乙 at 2, the tree's 丙 at 3: 丙 alone takes them; closed, 乙; closed, 甲" {
  let (t, k) = stack_tester([("甲", 1, true), ("乙", 2, false), ("丙", 3, true)])
  let ids = stack_ids(t, ["甲", "乙", "丙"])
  let all = stack_takes(t, k, ids)
  k.on["丙"].set(false)
  t.draw()
  t.draw()
  let two = stack_takes(t, k, ids)
  k.on["乙"].set(false)
  t.draw()
  t.draw()
  let one = stack_takes(t, k, ids)
  assert_eq(
    (all, two, one),
    ((["丙"], ["丙"], Some("丙")), (["乙"], ["乙"], Some("乙")), (["甲"], ["甲"], Some("甲"))),
  )
}

///|
test "old 甲 at 1 with its menu open in it, the tree's 乙 at 2: 乙 over 甲's menu too; 乙 closed, 甲's menu over 甲" {
  let menu = @signals.signal(true)
  let (t, k) = stack_tester([("甲", 1, false), ("乙", 2, true)], menu~)
  t.tap(60.0, 20.0)
  let over = k.pressed.copy()
  k.on["乙"].set(false)
  t.draw()
  t.draw()
  t.tap(60.0, 20.0)
  assert_eq((over, k.pressed), (["乙"], ["乙", "甲的菜单"]))
}

///|
test "drawn in the stack's order: old 甲 at 1, the tree's 乙 at 2, old 丙 at 3; the tree's 甲 at 1, old 乙 at 2" {
  let colours = fn(layers : Array[(String, Int, Bool)]) {
    let (t, _) = stack_tester(layers)
    t.drawn_rects().filter(fn(r) { r.2 == 400.0 && r.3 == 300.0 }).map(fn(r) { r.4 })
  }
  // (an old layer's ground white, a tree's green)
  assert_eq(
    (colours([("甲", 1, false), ("乙", 2, true), ("丙", 3, false)]), colours([("甲", 1, true), ("乙", 2, false)])),
    ([0xFFFFFFFFL, 0x7FFF7FFFL, 0xFFFFFFFFL], [0x7FFF7FFFL, 0xFFFFFFFFL]),
  )
}

///|
test "old 丙 at 3 built before old 甲 at 1, the tree's 乙 at 2: 丙 the topmost still, drawn, pressed, read out; back closes 丙, then 乙, then 甲" {
  let (t, k) = stack_tester([("丙", 3, false), ("甲", 1, false), ("乙", 2, true)])
  let ids = stack_ids(t, ["甲", "乙", "丙"])
  let all = stack_takes(t, k, ids)
  let top = t.drawn_rects().filter(fn(r) { r.2 == 400.0 && r.3 == 300.0 }).map(fn(r) { r.4 })
  let open = fn() { ["甲", "乙", "丙"].filter(fn(n) { k.on[n].get() }) }
  t.back()
  t.draw()
  let after_one = open()
  t.back()
  t.draw()
  let after_two = open()
  t.back()
  t.draw()
  assert_eq(
    (all, top, after_one, after_two, open()),
    ((["丙"], ["丙"], Some("丙")), [0xFFFFFFFFL, 0x7FFF7FFFL, 0xFFFFFFFFL], ["甲", "乙"], ["甲"], []),
  )
}

///|
test "old 丙 at 3 over the tree's 乙 at 2 over old 甲 at 1: Escape closes 丙, pressing nothing under it; no frame drawn, the next Activate of 乙 is 乙's, once; Enter on it, once more" {
  let (t, k) = stack_tester([("甲", 1, false), ("乙", 2, true), ("丙", 3, false)])
  let ids = stack_ids(t, ["甲", "乙", "丙"])
  // (Escape, no frame drawn after it)
  t.key_told(key_escape, 0, t.time())
  // (closed by it at once: its own takes nothing from then, as its view reads at its next build)
  let escaped = k.pressed.copy()
  // (no frame: the next input's own, at once)
  g().ask_action(ids["乙"], Activate)
  let acted = k.pressed.copy()
  g().ask_action(ids["乙"], Focus)
  t.key_told(key_enter, 0, t.time())
  // (甲 under 乙 still: its id asked, nothing)
  g().ask_action(ids["甲"], Activate)
  t.draw()
  assert_eq((escaped, acted, k.pressed, k.on["丙"].get()), ([], ["乙"], ["乙", "乙"], false))
}

///|
test "old 丙 at 3 built before old 甲 at 1, the tree's 乙 at 2: three backs at one moment, no frame between: 丙, 乙, 甲 closed in turn, one each" {
  let (t, k) = stack_tester([("丙", 3, false), ("甲", 1, false), ("乙", 2, true)])
  let each = []
  for _ in 0..<3 {
    on_back(2, 0.0, 1.0, 0)
    each.push(k.closed.copy())
  }
  t.draw()
  assert_eq(each, [["丙"], ["丙", "乙"], ["丙", "乙", "甲"]])
}

///|
test "the tree's 丙 at 3 and 甲 at 1 in one slot of the root's (3 given first), the tree's 乙 at 2 beside it: drawn, pressed and read out 甲, 乙, 丙; 丙 alone takes them" {
  let (t, k) = stack_tester([("乙", 2, true)], grouped=[("丙", 3), ("甲", 1)])
  let ids = stack_ids(t, ["甲", "乙", "丙"])
  let all = stack_takes(t, k, ids)
  let order = t.semantics().filter(fn(s) { s.role == Button }).map(fn(s) { s.label })
  k.on["丙"].set(false)
  t.draw()
  t.draw()
  let two = stack_takes(t, k, ids)
  assert_eq((all, order, two), ((["丙"], ["丙"], Some("丙")), ["甲", "乙", "丙"], (["乙"], ["乙"], Some("乙"))))
}

///|
/// Two old views the whole window, kept apart: the first's layer 丙 at 3 (modal, the whole window a button) and, built
/// after it outside its place, a menu said at no place (丙的菜单, not modal, 120 by 40 at the top left: its node's place
/// -1, kept in `menu_stack`), the first built again as `tick` changes; the second, built after them, saying what takes
/// back of its own (its page's, "乙页"), built again by nothing (kept: what it said said again as kept,
/// Ctx::made_island). What each was pressed and closed (by name), how many
/// times the second was built.
fn kept_stack_tester(tick : @signals.Signal[Int], menu_stack : Ref[Int]) -> (Tester, StackCase, Ref[Int]) {
  let k : StackCase = { on: Map([]), pressed: [], closed: [] }
  for n in ["丙", "丙的菜单"] {
    k.on[n] = @signals.signal(true)
  }
  let builds = Ref(0)
  let layer = fn(c : Ctx, name : String, modal : Bool, w : Double, h : Double) -> Int {
    guard k.on[name].get() else { return -1 }
    let mut node = -1
    c.with_dismissed(fn(_) { k.closed.push(name) }, fn() {
      let o = c.overlay(name, modal~, outside=false, fn() {
        let id = c.id(name + " button")
        if c.interact(id).clicked {
          k.pressed.push(name)
        }
        let b = c.box(id~, w=Px(w), h=Px(h), bg=0xFFFFFFFFL, fn() {  })
        c.semantics(b, Button, id~, label=name, actions=[Activate])
      })
      node = o.node
      if o.dismissed is Some(_) {
        k.on[name].set(false)
      }
    })
    node
  }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(a) {
      a.over(Is(true)) |> ignore
      old(a, fn(c) {
        tick.get() |> ignore
        c.stacked(3, fn() { layer(c, "丙", true, 400.0, 300.0) |> ignore })
        let m = layer(c, "丙的菜单", false, 120.0, 40.0)
        if m >= 0 {
          menu_stack.val = c.nodes[m].stack
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      old(b, fn(c) {
        builds.val = builds.val + 1
        // (no layer of its own: a part that opens one is built every frame, kept_census's "a layer opened"; what it
        // says takes back, its page's, said again as kept)
        c.take_back(fn() { k.closed.push("乙页") })
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, k, builds)
}

///|
test "an old 丙 at 3, a menu at no place built after it, an old view's own back said after them again as kept: back closes the menu, 丙, then the view's own, no frame between" {
  let menu_stack = Ref(-9)
  let tick = @signals.signal(0)
  let (t, k, builds) = kept_stack_tester(tick, menu_stack)
  // (the first built again, its menu with it; the second kept, its layers said again as kept)
  let built = builds.val
  // (the menu built anew with the first: its place said again, -1)
  menu_stack.val = -9
  tick.set(1)
  t.drawn_now()
  let kept = builds.val == built
  let why = rows_unkept()
  let each = []
  for _ in 0..<3 {
    on_back(2, 0.0, 1.0, 0)
    each.push(k.closed.copy())
  }
  t.draw()
  assert_eq((menu_stack.val, kept, each), (-1, true, [["丙的菜单"], ["丙的菜单", "丙"], ["丙的菜单", "丙", "乙页"]]), msg="\{why} \{builds.val - built} \{nodes_run.evented}")
}

///|
test "an old 丙 at 3, a menu at no place built after it, an old view kept beside them: drawn and pressed, the menu over 丙" {
  let menu_stack = Ref(-9)
  let tick = @signals.signal(0)
  let (t, k, builds) = kept_stack_tester(tick, menu_stack)
  let built = builds.val
  // (the menu built anew with the first: its place said again, -1)
  menu_stack.val = -9
  tick.set(1)
  t.drawn_now()
  let kept = builds.val == built
  let fulls = t.drawn_rects().filter(fn(r) { r.2 == 400.0 && r.3 == 300.0 }).length()
  let last = t.drawn_rects().last().map(fn(r) { (r.2, r.3) })
  t.tap(200.0, 150.0)
  t.tap(60.0, 20.0)
  assert_eq((menu_stack.val, kept, fulls, last, k.pressed), (-1, true, 1, Some((120.0, 40.0)), ["丙", "丙的菜单"]))
}

///|
test "old views' own backs, no layer opened: 丙's at 3 said before 甲's at 1, the tree's 乙 at 2: back is 乙's, the tree's later than the old views' (Ctx::stacked places layers, not an old view's own back)" {
  let k : StackCase = { on: Map([]), pressed: [], closed: [] }
  for n in ["丙", "甲", "乙"] {
    k.on[n] = @signals.signal(true)
  }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.grow(Is(1.0)) |> ignore
      old(h, fn(c) {
        for l in [("丙", 3), ("甲", 1)] {
          let (name, stack) = l
          c.stacked(stack, fn() {
            if k.on[name].get() {
              c.take_back(fn() {
                k.closed.push(name)
                k.on[name].set(false)
              })
            }
          })
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    let on = k.on["乙"]
    root.show(fn() { on.get() }, fn(v) {
      v
      .over(Is(true))
      .stacked(Is(2))
      .takes_back(fn() {
        k.closed.push("乙")
        on.set(false)
      })
      |> ignore
    })
  })
  t.draw()
  on_back(2, 0.0, 1.0, 0)
  t.draw()
  assert_eq(k.closed, ["乙"])
}
