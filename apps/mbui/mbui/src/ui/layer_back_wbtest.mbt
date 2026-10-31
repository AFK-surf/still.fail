// Back to a layer (Ctx::overlay) as this opening of it: a gesture held by it as it was open before, gone through after it
// closed and a layer of the same key opened again, takes nothing of the one open now.

///|
test "a layer's back gesture held, the layer closed and opened again under the same key, the gesture gone through: the one open now not dismissed" {
  let open = Ref(true)
  let dismissed : Array[String] = []
  let t = Tester::new(
    fn(c) {
      if open.val {
        let o = c.overlay("menu", fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore })
        match o.dismissed {
          Some(why) => {
            dismissed.push("\{why}")
            open.val = false
          }
          None => ()
        }
      }
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t.draw()
  t.back_raw(0, 0.0, t.time())
  t.back_raw(1, 60.0, t.time())
  // (closed meanwhile, its back's gesture still held: opened again under the same key)
  open.val = false
  t.draw()
  t.draw()
  open.val = true
  t.draw()
  t.draw()
  t.back_raw(2, 60.0, t.time())
  t.draw()
  t.draw()
  assert_eq((open.val, dismissed), (true, []))
}

///|
test "a layer in a stack's top page, in an old view over a node of the tree's taking back: back taken by the layer, then back with no frame between: the stack's (a page off), the node's none" {
  let tree_backs = Ref(0)
  let menu = Ref(true)
  let nav : Nav[String] = Nav::new("a")
  nav.push("b")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(n) { n.over(Is(true)).takes_back(fn() { tree_backs.val += 1 }) |> ignore }) |> ignore
    old(root, fn(c) {
      c.nav(nav, fn(p) {
        c.box(w=Px(400.0), h=Px(300.0), fn() {  }) |> ignore
        if p == "b" && menu.val {
          let o = c.overlay("menu", fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore })
          if o.dismissed is Some(_) {
            menu.val = false
          }
        }
      })
      |> ignore
    })
    .over(Is(true))
    |> ignore
  })
  t.draw()
  t.draw()
  assert_eq(nav.depth(), 2)
  t.back_raw(2, 0.0, t.time())
  t.back_raw(2, 0.0, t.time())
  t.run_for(move_most_ms)
  assert_eq((menu.val, nav.depth(), tree_backs.val), (false, 1, 0))
}

///|
/// A layer said as `key` while `open` holds (Ctx::overlay), its dismissal (`why`) put down in `said` and closing it.
fn layer_while(c : Ctx, key : String, open : Ref[Bool], said : Array[String], ids? : Map[String, Int] = Map::new()) -> Unit {
  if !open.val {
    return
  }
  let o = c.overlay(key, fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore })
  ids[key] = o.id
  if o.dismissed is Some(_) {
    said.push(key)
    open.val = false
  }
}

///|
test "two layers in a stack's top page, in an old view over a node of the tree's taking back: back three times with no frame between: the layer over first, the one under it, then the stack's; the node's none" {
  let tree_backs = Ref(0)
  let a = Ref(true)
  let b = Ref(true)
  let ids : Map[String, Int] = Map::new()
  let said : Array[String] = []
  let nav : Nav[String] = Nav::new("a")
  nav.push("b")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(n) { n.over(Is(true)).takes_back(fn() { tree_backs.val += 1 }) |> ignore }) |> ignore
    old(root, fn(c) {
      c.nav(nav, fn(p) {
        c.box(w=Px(400.0), h=Px(300.0), fn() {  }) |> ignore
        if p == "b" {
          layer_while(c, "a", a, said, ids~)
          layer_while(c, "b", b, said, ids~)
        }
      })
      |> ignore
    })
    .over(Is(true))
    |> ignore
  })
  t.draw()
  t.draw()
  let at = t.time()
  // (who took each back as it came, no frame between: the one said over first)
  let asked = fn() { (g().dismissals.get(ids["a"]), g().dismissals.get(ids["b"])) }
  t.back_raw(2, 0.0, at)
  assert_eq(asked(), (None, Some(Back)), msg="the first back")
  t.back_raw(2, 0.0, at)
  assert_eq(asked(), (Some(Back), Some(Back)), msg="the second")
  let after_two = nav.depth()
  t.back_raw(2, 0.0, at)
  t.run_for(move_most_ms)
  // (both closed by the two backs before the stack's, each read as it is built next: in the order they are built)
  assert_eq((said, after_two, nav.depth(), tree_backs.val), (["a", "b"], 2, 1, 0))
}

///|
test "a layer in an inner stack's top page, that stack in an outer one's top page: back with no frame between: the layer's, then the inner stack's (the outer's after, a frame between)" {
  let menu = Ref(true)
  let said : Array[String] = []
  let outer : Nav[String] = Nav::new("o1")
  outer.push("o2")
  let inner : Nav[String] = Nav::new("i1")
  inner.push("i2")
  let t = Tester::new(
    fn(c) {
      c.nav(outer, fn(p) {
        if p == "o2" {
          c.nav(inner, fn(q) {
            c.box(w=Px(400.0), h=Px(300.0), fn() {  }) |> ignore
            if q == "i2" {
              layer_while(c, "menu", menu, said)
            }
          })
          |> ignore
        } else {
          c.box(w=Px(400.0), h=Px(300.0), fn() {  }) |> ignore
        }
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t.draw()
  let at = t.time()
  t.back_raw(2, 0.0, at)
  t.back_raw(2, 0.0, at)
  let after_two = (inner.depth(), outer.depth())
  t.run_for(move_most_ms)
  t.back_raw(2, 0.0, t.time())
  t.run_for(move_most_ms)
  assert_eq((said, after_two, inner.depth(), outer.depth()), (["menu"], (1, 2), 1, 1))
}

///|
test "a stack in a part kept as drawn, a layer after it: the part's nodes moved since it was built (more before it), back taken by the layer: what takes it next the part's stack, of its nodes where they are now (as the frame built whole has it)" {
  let stack_node = Ref(-1)
  let builds = Ref(0)
  let shift = @signals.signal(0.0)
  let before = @signals.signal(0)
  let menu = Ref(true)
  let said : Array[String] = []
  let nav : Nav[String] = Nav::new("a")
  nav.push("b")
  let t = Tester::new(
    fn(c) {
      c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(shift.get()), h=Px(10.0), fn() {  }) |> ignore
        for _ in 0..<before.get() {
          c.box(w=Px(0.0), h=Px(0.0), fn() {  }) |> ignore
        }
        // (in a box of the row's, put on past what is before it; the part fills it, out of the flow: built from its key
        // and what it reads alone, as an island's page is, Ctx::kept_part's `own`)
        c.box(w=Px(200.0), h=Px(300.0), fn() {
          c.kept_part(c.id("part"), "k", own=true, fn() {
            builds.val = builds.val + 1
            stack_node.val = c.nav(nav, fn(_p) { c.box(w=Px(200.0), h=Px(300.0), fn() {  }) |> ignore })
          })
        })
        |> ignore
      })
      |> ignore
      layer_while(c, "menu", menu, said)
    },
    w=500.0,
    h=300.0,
    platform=2,
  )
  // (no frame built again whole to check what was kept: its builds counted as the part's own)
  t.check_looks(false)
  t.keep_parts(true)
  t.draw()
  t.draw()
  t.clock_frame()
  let built = builds.val
  shift.set(50.0)
  before.set(3)
  // (the display's next frame, as a host draws it: no test's step, which builds every part again)
  t.clock_frame()
  // (the part kept as drawn, the boxes before it built again: its nodes further on, the part further right)
  assert_eq((builds.val, t.parts_kept()), (built, 1))
  t.back_raw(2, 0.0, t.time())
  // (what takes it next, as the kept part said it again: its stack, of the part's nodes where they are now, there)
  let next = (g().back_node, g().back_taker().map(fn(h) { h.left }))
  assert_eq((said, menu.val), ([], true))
  // (the frame built whole, the layer closed: the stack's node as built there, the same, where the part is put)
  t.draw()
  assert_eq((said, next), (["menu"], (stack_node.val, Some(50.0))))
}

///|
/// A layer said as "menu" while `shown` is not 0: open (1) or leaving (2: inert, its exit drawn), never let go between;
/// its dismissals put down in `said`, its id in `id`. A gesture of back begun as it is open, then it leaving for a frame
/// and open again (`reopen`) or left leaving, then the gesture gone through: what was said of it, and whether a
/// dismissal was written for it as the gesture went through.
fn layer_left_and_back(reopen : Bool) -> (Array[String], Bool) {
  let shown = Ref(1)
  let said : Array[String] = []
  let id = Ref(0)
  let t = Tester::new(
    fn(c) {
      if shown.val != 0 {
        let o = c.overlay("menu", inert=shown.val == 2, fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore })
        id.val = o.id
        if o.dismissed is Some(_) {
          said.push("dismissed while \{shown.val}")
        }
      }
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t.draw()
  t.back_raw(0, 0.0, t.time())
  t.back_raw(1, 60.0, t.time())
  // (leaving, its exit drawn, never let go)
  shown.val = 2
  t.draw()
  if reopen {
    shown.val = 1
    t.draw()
  }
  t.back_raw(2, 60.0, t.time())
  let written = g().dismissals.get(id.val) is Some(_)
  t.draw()
  t.draw()
  (said, written)
}

///|
test "a layer's back gesture held, the layer leaving (inert, drawn going) and open again under the same key, never let go: the gesture gone through takes nothing of the one open now" {
  assert_eq(layer_left_and_back(true), ([], false))
}

///|
test "a layer's back gesture held, the layer leaving (inert, drawn going): the gesture gone through as it leaves writes no dismissal" {
  assert_eq(layer_left_and_back(false), ([], false))
}
