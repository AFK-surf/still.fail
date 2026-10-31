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

///|
test "a layer of the old frame's over a node of the tree's taking presses: Escape with no frame after, then a press there: the node's at once" {
  let pressed = Ref(0)
  let menu = Ref(true)
  let said : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))).on_press(fn() { pressed.val += 1 }) |> ignore
    })
    |> ignore
    old(root, fn(c) {
      if menu.val {
        // (a modal one: its ground takes the presses it does not, over the node)
        let o = c.overlay("menu", modal=true, fn() {
          let id = c.id("item")
          c.interact(id) |> ignore
          c.box(id~, w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore
        })
        if o.dismissed is Some(_) {
          said.push("menu")
          menu.val = false
        }
      }
    })
    .over(Is(true))
    // (taking presses where it draws them alone, as the shell's over all of it: tape_shell.mbt)
    |> old_takes_own
    |> ignore
  })
  t.draw()
  t.draw()
  let at = t.time()
  t.key_told(key_escape, 0, at)
  t.touch_raw(0, 1, 50.0, 50.0, at)
  t.touch_raw(2, 1, 50.0, 50.0, at)
  let at_once = pressed.val
  t.draw()
  assert_eq((at_once, said), (1, ["menu"]))
}

///|
test "a layer opened from a button with the focus, the focus in it: Escape with no frame after, the focus back on the button at once, and after frames" {
  let open = Ref(false)
  let button = Ref(0)
  let t = Tester::new(
    fn(c) {
      let id = c.id("opener")
      button.val = id
      c.focusable(id)
      c.box(id~, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      if open.val {
        let o = c.overlay("menu", modal=true, fn() {
          let item = c.id("item")
          c.focusable(item)
          c.box(id=item, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
        })
        if o.dismissed is Some(_) {
          open.val = false
        }
      }
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  g().focus_moved(button.val)
  open.val = true
  t.draw()
  t.draw()
  let inside = g().focused_id() != button.val
  t.key_told(key_escape, 0, t.time())
  let at_once = g().focused_id() == button.val
  t.draw()
  t.draw()
  assert_eq((inside, at_once, g().focused_id() == button.val), (true, true, true))
}

///|
test "a layer's back gesture held, the layer dismissed by Escape and built open again under the same key the frame after (never leaving): the gesture gone through takes nothing of that opening" {
  let dismissed : Array[String] = []
  let t = Tester::new(
    fn(c) {
      // (its view keeps it open whatever dismisses it)
      let o = c.overlay("menu", fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore })
      match o.dismissed {
        Some(why) => dismissed.push("\{why}")
        None => ()
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
  t.key_told(key_escape, 0, t.time())
  t.draw()
  t.draw()
  t.back_raw(2, 60.0, t.time())
  t.draw()
  t.draw()
  assert_eq(dismissed, ["Escape"])
}

///|
test "two layers, neither modal, a press outside both with no frame after: both dismissed at once, the topmost told first, each once" {
  let told : Array[String] = []
  let open = [true, true]
  let t = Tester::new(
    fn(c) {
      for k in 0..<2 {
        if open[k] {
          c.with_dismissed(fn(_) { told.push("layer \{k}") }, fn() {
            let o = c.overlay("layer \{k}", fn() {
              c.box(tx=10.0 + 120.0 * k.to_double(), ty=10.0, w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore
            })
            if o.dismissed is Some(_) {
              open[k] = false
            }
          })
        }
      }
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t.draw()
  let at = t.time()
  t.touch_raw(0, 1, 300.0, 250.0, at)
  t.touch_raw(2, 1, 300.0, 250.0, at)
  let at_once = told.copy()
  t.draw()
  t.draw()
  assert_eq((at_once, told, open), (["layer 1", "layer 0"], ["layer 1", "layer 0"], [false, false]))
}

///|
/// A modal layer of the old frame's opened (`open`) as the focus is on `from`'s, holding a stop that takes it or none
/// (`stops`); then Escape with no frame after: whether the focus went into it, is on `from` at once, and after frames.
fn focus_given_back(tree_opener : Bool, stops : Bool) -> (Bool, Bool, Bool) {
  let open = Ref(false)
  let opener = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    if tree_opener {
      root.box(fn(n) {
        n.width(Is(Some(80.0))).height(Is(Some(30.0))).focusable(Is(true)).on_press(fn() {  }) |> ignore
        opener.val = tree_said_id(n.id())
      })
      |> ignore
    }
    old(root, fn(c) {
      if !tree_opener {
        let id = c.id("opener")
        opener.val = id
        c.focusable(id)
        c.box(id~, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      }
      if open.val {
        let o = c.overlay("menu", modal=true, fn() {
          if stops {
            let item = c.id("item")
            c.focusable(item)
            c.box(id=item, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
          } else {
            c.box(w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
          }
        })
        if o.dismissed is Some(_) {
          open.val = false
        }
      }
    })
    .over(Is(true))
    |> old_takes_own
    |> ignore
  })
  t.draw()
  g().focus_moved(opener.val)
  t.draw()
  open.val = true
  t.draw()
  t.draw()
  let inside = g().focused_id() != opener.val
  t.key_told(key_escape, 0, t.time())
  let at_once = g().focused_id() == opener.val
  t.draw()
  t.draw()
  (inside, at_once, g().focused_id() == opener.val)
}

///|
test "a modal layer opened from a node of the tree's with the focus: Escape with no frame after, the focus back on that node at once, and after frames" {
  assert_eq(focus_given_back(true, true), (true, true, true))
}

///|
test "a modal layer holding nothing that takes the focus (its own ground has it): Escape with no frame after, the focus back on what opened it at once, and after frames" {
  assert_eq(focus_given_back(false, false), (true, true, true))
}

///|
test "a layer of the old frame's, not modal, a node of the tree's taking presses outside it: a finger down and up there, no frame between: the layer dismissed as it went down, the node pressed once" {
  let pressed = Ref(0)
  let told : Array[String] = []
  let open = Ref(true)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((300.0, 250.0))).width(Is(Some(80.0))).height(Is(Some(40.0))).on_press(fn() {
        pressed.val += 1
      })
      |> ignore
    })
    |> ignore
    old(root, fn(c) {
      if open.val {
        c.with_dismissed(fn(_) { told.push("menu") }, fn() {
          let o = c.overlay("menu", fn() {
            let id = c.id("item")
            c.interact(id) |> ignore
            c.box(id~, tx=10.0, ty=10.0, w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore
          })
          if o.dismissed is Some(_) {
            open.val = false
          }
        })
      }
    })
    .over(Is(true))
    |> old_takes_own
    |> ignore
  })
  t.draw()
  t.draw()
  let at = t.time()
  t.touch_raw(0, 1, 320.0, 260.0, at)
  let down = told.copy()
  t.touch_raw(2, 1, 320.0, 260.0, at)
  let up = pressed.val
  t.draw()
  t.draw()
  assert_eq((down, up, pressed.val, open.val), (["menu"], 1, 1, false))
}

///|
test "a modal layer over a list, closed by Escape with no frame after, then the wheel over the list: the list scrolls" {
  let open = Ref(true)
  let t = Tester::new(
    fn(c) {
      c.list("rows", 100, 40.0, fn(i) { c.text("row \{i}") |> ignore }) |> ignore
      if open.val {
        let o = c.overlay("m", modal=true, fn() {
          c.box(tx=20.0, ty=20.0, w=Px(100.0), h=Px(100.0), bg=0xFFFFFFFFL, id=c.id("p"), fn() {  }) |> ignore
        })
        if o.dismissed is Some(_) {
          open.val = false
        }
      }
    },
  )
  t.draw()
  t.draw()
  t.key_told(key_escape, 0, t.time())
  finger_wheel(200.0, 400.0, 0.0, 300.0, 0)
  t.draw()
  assert_true(t.list_offset() > 0.0)
}

///|
test "the same layer opened from one button, closed by Escape, then from another: closed by Escape again, the focus back on the second" {
  let open = Ref(false)
  let ids = [0, 0]
  let t = Tester::new(
    fn(c) {
      for k in 0..<2 {
        let id = c.id("opener \{k}")
        ids[k] = id
        c.focusable(id)
        c.box(id~, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      }
      if open.val {
        let o = c.overlay("menu", modal=true, fn() {
          let item = c.id("item")
          c.focusable(item)
          c.box(id=item, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
        })
        if o.dismissed is Some(_) {
          open.val = false
        }
      }
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  let from = fn(k : Int) {
    g().focus_moved(ids[k])
    t.draw()
    open.val = true
    t.draw()
    t.draw()
    t.key_told(key_escape, 0, t.time())
    t.draw()
    t.draw()
    g().focused_id() == ids[k]
  }
  let first = from(0)
  let second = from(1)
  assert_eq((first, second), (true, true))
}

///|
/// A layer over a page that counts the Escapes it sees, the layer stepping back within itself once on Escape
/// (on_escape) before one dismisses it: what it was told, as each of two Escapes is handed on (a frame drawn between
/// them where `frames`), and how many the page saw.
fn escape_steps(frames : Bool) -> (Array[String], Array[String], Int) {
  let steps = Ref(1)
  let told : Array[String] = []
  let page_saw = Ref(0)
  let t = Tester::new(
    fn(c) {
      if c.key_pressed(key_escape) {
        page_saw.val = page_saw.val + 1
      }
      c.with_dismissed(fn(why) { told.push("\{why} with \{steps.val} left") }, fn() {
        c.overlay(
          "menu",
          modal=true,
          on_escape=fn() {
            if steps.val > 0 {
              steps.val = steps.val - 1
              told.push("stepped back")
              true
            } else {
              false
            }
          },
          fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore },
        )
        |> ignore
      })
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  t.draw()
  t.key_told(key_escape, 0, t.time())
  let first = told.copy()
  if frames {
    t.draw()
  }
  t.key_told(key_escape, 0, t.time())
  let second = told.copy()
  t.draw()
  t.draw()
  (first, second, page_saw.val)
}

///|
test "a layer that steps back within itself on Escape (on_escape): the first Escape its own, as it comes, not dismissing it nor reaching the page; the next, with nothing left to step back, dismissing it; a frame between or none" {
  for frames in [true, false] {
    assert_eq(
      escape_steps(frames),
      (["stepped back"], ["stepped back", "Escape with 0 left"], 0),
      msg="frames between: \{frames}",
    )
  }
}

///|
/// A page that takes back and sees Escapes, under a modal layer that stays open while `busy` (stays), its one item
/// focused as it opens and pressed in it counted: `hand` twice while busy (no frame between), a frame; then the item
/// pressed; then busy no more, `hand` once, a frame, `hand` again. What the layer was told as it was dismissed, what
/// the page saw, how often the item was pressed, and whether the item has the focus, after each of those.
fn stays_seen(hand : (Tester) -> Unit) -> Array[(Array[String], Array[String], Int, Bool)] {
  let busy = Ref(true)
  let told : Array[String] = []
  let page : Array[String] = []
  let pressed = Ref(0)
  let item = Ref(0)
  let open = Ref(true)
  let t = Tester::new(
    fn(c) {
      c.take_back(fn() { page.push("back") })
      if c.key_pressed(key_escape) {
        page.push("Escape")
      }
      if open.val {
        c.with_dismissed(fn(why) {
          told.push("\{why}")
          open.val = false
        }, fn() {
          c.overlay("busy", modal=true, stays=fn() { busy.val }, initial_focus=-1, fn() {
            let id = c.id("item")
            item.val = id
            c.focusable(id)
            c.box(id~, w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore
            if c.clicked(id) {
              pressed.val = pressed.val + 1
            }
          })
          |> ignore
        })
      }
    },
    w=400.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t.draw()
  let seen = []
  let look = fn() { seen.push((told.copy(), page.copy(), pressed.val, g().focused_id() == item.val && item.val != 0)) }
  hand(t)
  hand(t)
  look()
  t.draw()
  look()
  // (it still takes presses, as this opening of it)
  t.tap(50.0, 50.0)
  look()
  busy.val = false
  hand(t)
  look()
  t.draw()
  hand(t)
  t.draw()
  look()
  seen
}

///|
test "a layer that stays open while what it does may not be left (stays): back twice, no frame between, dismisses nothing and reaches nothing under it, the layer's focus and presses its own still; once it may be left, back dismisses it at once, told once, the next back the page's" {
  let seen = stays_seen(fn(t) { t.back_raw(2, 0.0, t.time()) })
  assert_eq(seen, [
    ([], [], 0, true),
    ([], [], 0, true),
    ([], [], 1, true),
    (["Back"], [], 1, false),
    (["Back"], ["back"], 1, false),
  ])
}

///|
test "a layer that stays open while what it does may not be left (stays): Escape twice, no frame between, dismisses nothing and reaches nothing under it, the layer's focus and presses its own still; once it may be left, Escape dismisses it at once, told once, the next Escape the page's" {
  let seen = stays_seen(fn(t) { t.key_told(key_escape, 0, t.time()) })
  assert_eq(seen, [
    ([], [], 0, true),
    ([], [], 0, true),
    ([], [], 1, true),
    (["Escape"], [], 1, false),
    (["Escape"], ["Escape"], 1, false),
  ])
}

///|
test "a layer anchored to a box with presses of its own in it: a press on one of them dismisses nothing (it is on the anchor), one past the box dismisses it as it goes down" {
  let told : Array[String] = []
  let pressed = Ref(0)
  let t = Tester::new(
    fn(c) {
      let anchor = c.id("anchor")
      c.box(id=anchor, w=Px(60.0), h=Px(300.0), fn() {
        c.box(w=Px(60.0), h=Px(200.0), fn() {  }) |> ignore
        let inner = c.id("inner")
        c.box(id=inner, w=Px(60.0), h=Px(40.0), fn() {  }) |> ignore
        if c.clicked(inner) {
          pressed.val = pressed.val + 1
        }
      })
      |> ignore
      c.with_dismissed(fn(why) { told.push("\{why}") }, fn() {
        c.overlay("beside", anchor~, fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore }) |> ignore
      })
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  t.draw()
  // (under the layer's own 100 square, on the anchor's own press)
  t.touch_at(0, 30.0, 220.0, t.time())
  let on_inner = told.copy()
  t.touch_at(2, 30.0, 220.0, t.time())
  t.draw()
  let after = (told.copy(), pressed.val)
  t.touch_at(0, 300.0, 250.0, t.time())
  let past = told.copy()
  assert_eq((on_inner, after, past), ([], ([], 1), ["Outside"]))
}

///|
/// A layer anchored to a box 60 by 300 at the window's left, its own press 40 high 200 down in it; the box in one that
/// cuts it at `cut` high, where given; and, where `cover`, a press of its own drawn over the anchor's foot (200 to 260
/// down, in a layer of the page's: no part of the anchor). What the layer was told as a press goes down at (30, 220) and
/// whether the cover took it.
fn anchor_pressed(cut? : Double, cover? : Bool = false) -> (Array[String], Int) {
  let told : Array[String] = []
  let covered = Ref(0)
  let t = Tester::new(
    fn(c) {
      let anchor = c.id("anchor")
      let body = fn() {
        c.box(id=anchor, w=Px(60.0), h=Px(300.0), fn() {
          c.box(w=Px(60.0), h=Px(200.0), fn() {  }) |> ignore
          c.box(id=c.id("inner"), w=Px(60.0), h=Px(40.0), fn() {  }) |> ignore
        })
        |> ignore
      }
      match cut {
        Some(h) => c.box(w=Px(60.0), h=Px(h), clip=true, body) |> ignore
        None => body()
      }
      if cover {
        c.layer(fn() {
          c.box(w=Px(60.0), h=Px(200.0), fn() {  }) |> ignore
          let k = c.id("cover")
          c.box(id=k, w=Px(60.0), h=Px(60.0), fn() {  }) |> ignore
          if c.pressed(k) {
            covered.val = covered.val + 1
          }
        })
        |> ignore
      }
      c.with_dismissed(fn(why) { told.push("\{why}") }, fn() {
        c.overlay("beside", anchor~, fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore }) |> ignore
      })
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  t.draw()
  t.touch_at(0, 30.0, 220.0, t.time())
  let at_down = told.copy()
  t.frame()
  (at_down, covered.val)
}

///|
test "a layer's anchor cut short by what holds it: a press where its box is laid out but cut away is outside it, the layer dismissed as it goes down" {
  assert_eq(anchor_pressed(cut=150.0).0, ["Outside"])
}

///|
test "a layer's anchor with a press of another's drawn over it there (no part of it): a press there is that one's, outside the anchor, the layer dismissed as it goes down" {
  let (told, covered) = anchor_pressed(cover=true)
  assert_eq((told, covered > 0), (["Outside"], true))
}

///|
test "a layer's anchor, a press of its own in it: on the anchor, nothing dismissed" {
  assert_eq(anchor_pressed().0, [])
}

///|
test "the same layer opened from one button, ended by what it is for (Ctx::layer_ended), opened at once from another with no frame closing it: the new opening takes presses and Escape, told its own closing once, the focus back on the second" {
  let open = Ref(false)
  let told = Ref(0)
  let pressed = Ref(0)
  let ids = [0, 0]
  let menu = Ref(0)
  let item_id = Ref(0)
  let t = Tester::new(
    fn(c) {
      for k in 0..<2 {
        let id = c.id("opener \{k}")
        ids[k] = id
        c.focusable(id)
        c.box(id~, w=Px(80.0), h=Px(30.0), fn() {  }) |> ignore
      }
      if open.val {
        c.with_dismissed(
          fn(_) {
            told.val += 1
            open.val = false
          },
          fn() {
            menu.val = c.id("menu")
            c.overlay("menu", modal=true, fn() {
              let item = c.id("item")
              item_id.val = item
              c.focusable(item)
              if c.clicked(item) {
                pressed.val += 1
              }
              c.box(id=item, w=Px(100.0), h=Px(40.0), fn() {  }) |> ignore
            })
            |> ignore
          },
        )
      }
    },
    w=400.0,
    h=300.0,
    platform=0,
  )
  t.draw()
  g().focus_moved(ids[0])
  t.draw()
  open.val = true
  t.draw()
  t.draw()
  // ended by what it is for, then opened from the second at once: no frame between
  g().layer_ended(menu.val)
  g().focus_moved(ids[1])
  t.draw()
  t.draw()
  // the new opening: a press in it its own, Escape dismissing it, told once, the focus back on the second
  let (x, y, w, h) = g().rect_of(item_id.val).unwrap()
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.key_told(key_escape, 0, t.time())
  let at_once = open.val
  t.draw()
  t.draw()
  assert_eq((pressed.val, told.val, at_once, open.val, g().focused_id() == ids[1]), (1, 1, false, false, true))
}
