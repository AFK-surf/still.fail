// The window's tree's room a press has (rooms.mbt, Tester::tree_room_faults) is what its hit test gives
// (Tree::press_room_found, Tree::target_at): what is drawn over another and within it is not parted from it as a
// neighbour, nor said to be drawn over it; what reaches past what holds it is measured so; and what is crowded as a
// press finds it is said as before.

///|
/// A Tester by a keyboard and mouse (platform 0, a room 36 across) or a finger (2, 44), 400 by 400, drawing what `make`
/// makes from (16, 40) on; the tree.
fn rr_tester(platform : Int, make : (@view.View) -> Unit) -> (Tester, @view.Tree) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform~)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.padding(Is((16.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      make(b)
    })
    |> ignore
  })
  t.draw()
  (t, view_app.val.unwrap())
}

///|
/// A button `w` by `h` named `name` made in `v`, pressed for nothing; what it holds made by `inside`.
fn rr_key(
  v : @view.View,
  w : Double,
  h : Double,
  name : String,
  inside? : (@view.View) -> Unit = fn(_) {  },
) -> Unit {
  v.box(fn(k) {
    k
    .width(Is(Some(w)))
    .height(Is(Some(h)))
    .presses(Is(true))
    .says(Is(Some(@view.said(Button, label=name))))
    .on_press(fn() {  })
    |> ignore
    inside(k)
  })
  |> ignore
}

///|
/// A block 358 by `h` whose ground scrolls (held: on_drag, as a code block's code is) and over it, `key_y` down its
/// top and 326 in, a key 24 by 24 (as a code block's 复制 is on its code).
fn rr_key_on_scroller(v : @view.View, h : Double, key_y : Double) -> Unit {
  v.box(fn(blk) {
    blk.width(Is(Some(358.0))).height(Is(Some(h))) |> ignore
    blk.box(fn(s) {
      s.grow(Is(1.0)).says(Is(Some(@view.said(Region, label="代码")))).on_drag(fn(_) {  }) |> ignore
    })
    |> ignore
    blk.box(fn(o) {
      o.over(Is(true)).padding(Is((326.0, key_y, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
      rr_key(o, 24.0, 24.0, "复制")
    })
    |> ignore
  })
  |> ignore
}

///|
/// A pill `w` by `h` that takes presses (opening a notice) holding, `pad` in from its foot, a key `kw` by 22 (· 安装 at
/// its end, 复制 across its foot).
fn rr_pill(v : @view.View, w : Double, h : Double, kw : Double, pad : Double) -> Unit {
  rr_key(v, w, h, "通知", inside=fn(p) {
    p.padding(Is((w - kw - 14.0, h - 22.0 - pad, 0.0, 0.0))) |> ignore
    rr_key(p, kw, 22.0, "安装")
  })
}

///|
/// The id of the node of `tree` named `name` that takes presses, and its box.
fn rr_box(tree : @view.Tree, name : String) -> (@view.NodeId, (Double, Double, Double, Double)) {
  let found = tree
    .press_boxes()
    .filter(fn(b) {
      match tree.said_of(b.0) {
        Some(s) => s.label == name
        None => false
      }
    })
  guard found is [b] else { @halt.saying("\{found.length()} take presses named \{name}") }
  (b.0, b.1)
}

///|
/// Whether a press at (x, y) of `tree` is on `id`, as the hit test says (Tree::target_at).
fn rr_on(tree : @view.Tree, id : @view.NodeId, x : Double, y : Double) -> Bool {
  match tree.target_at(x, y) {
    Pressed(t) | Dragged(t) => t == id
    _ => false
  }
}

///|
/// The faults of the rule of a press's room `t` says (Tester::tree_room_faults), each but where what it names was
/// made (its line in this file, which moves as it is written: from ", made at " to the ")" closing it).
fn rr_faults(t : Tester) -> Array[String] {
  t
  .tree_room_faults()
  .map(fn(f) {
    let parts = f.split(", made at ").map(fn(v) { v.to_owned() }).to_array()
    let sb = StringBuilder()
    sb.write_string(parts[0])
    for i in 1..<parts.length() {
      // (what follows the place: from the ")" closing it)
      let after = parts[i].split(")").map(fn(v) { v.to_owned() }).to_array()
      for k in 1..<after.length() {
        sb.write_string(")" + after[k])
      }
    }
    sb.to_string()
  })
}

///|
test "rooms: a key drawn over what scrolls and within it is pressed there first and as far round it as its room, no neighbour parting the room with it nor drawn over it" {
  for platform in [0, 2] {
    let (t, tree) = rr_tester(platform, fn(b) { rr_key_on_scroller(b, 60.0, 2.0) })
    assert_eq(rr_faults(t), [], msg="platform \{platform}")
    // (its room past the block's top, where nothing is under the press, and down into the code: the key's)
    let (key, (x0, y0, x1, y1)) = rr_box(tree, "复制")
    let mx = (x0 + x1) / 2.0
    assert_true(rr_on(tree, key, mx, y0 - 3.0), msg="platform \{platform}: past the block's top")
    assert_true(rr_on(tree, key, mx, y1 + 5.0), msg="platform \{platform}: over the code under it")
    let (code, _) = rr_box(tree, "代码")
    assert_true(rr_on(tree, code, mx, y1 + 20.0), msg="platform \{platform}: the code past its room")
  }
}

///|
test "rooms: a key in what takes presses, as big as its room down only past its edge, has that room: what the press lands in past it is not what holds it" {
  // (复制 across a notice's foot, 6 from it, 22 high: its room 36 by a keyboard and mouse, one past the pill's edge;
  // the pill as tall as a room, reached nowhere round it)
  let (t, tree) = rr_tester(0, fn(b) { rr_pill(b, 260.0, 100.0, 231.0, 6.0) })
  assert_eq(rr_faults(t), [])
  let (key, (x0, _, x1, y1)) = rr_box(tree, "安装")
  let (_, pill) = rr_box(tree, "通知")
  assert_eq(pill.3 - y1, 6.0)
  assert_true(rr_on(tree, key, (x0 + x1) / 2.0, pill.3 + 0.5), msg="past the pill's foot")
  assert_true(!rr_on(tree, key, (x0 + x1) / 2.0, pill.3 + 1.5), msg="past its room")
}

///|
test "rooms: what is crowded as a press finds it is said: a key in a pill a room's least, rows 2 apart, a time under a pill" {
  // (· 安装 in a pill 34 high that takes presses: the pill's own room, nearer, past its edge; 36 by 34)
  let (t, _) = rr_tester(0, fn(b) { rr_pill(b, 298.0, 34.0, 24.0, 6.0) })
  assert_eq(rr_faults(t), [
    "room: a box (a node of the window's tree's at 276,46 24×22) has 36×34 to be pressed in, under 36",
  ])
  let (t, _) = rr_tester(2, fn(b) { rr_pill(b, 298.0, 34.0, 24.0, 6.0) })
  assert_eq(rr_faults(t), [
    "room: a box (a node of the window's tree's at 276,46 24×22) has 44×34 to be pressed in, under 44",
  ])
  // (an agent's card's last three lines, 274 by 18, 2 apart: each the half of the gap nearer it)
  let (t, _) = rr_tester(0, fn(b) {
    b.gap(Is(2.0)) |> ignore
    for k in 0..<3 {
      rr_key(b, 274.0, 18.0, "行\{k}")
    }
  })
  assert_eq(rr_faults(t), [
    "room: a box (a node of the window's tree's at 16,40 274×18) has 274×28 to be pressed in, under 36",
    "room: a box (a node of the window's tree's at 16,60 274×18) has 274×20 to be pressed in, under 36",
    "room: a box (a node of the window's tree's at 16,80 274×18) has 274×28 to be pressed in, under 36",
  ])
  // (a notice's time 44 by 18, 4 under its pill 34 high that takes presses: the pill's room ends 1 past it, the time's
  // from there)
  let (t, _) = rr_tester(0, fn(b) {
    b.gap(Is(4.0)) |> ignore
    rr_key(b, 260.0, 34.0, "通知")
    rr_key(b, 44.0, 18.0, "时间")
  })
  assert_eq(rr_faults(t), [
    "room: a box (a node of the window's tree's at 16,78 44×18) has 44×30 to be pressed in, under 36",
  ])
}

///|
test "rooms: drawn over another and not within it, two are still drawn over each other" {
  let (t, _) = rr_tester(0, fn(b) {
    b.box(fn(blk) {
      blk.width(Is(Some(200.0))).height(Is(Some(40.0))) |> ignore
      rr_key(blk, 200.0, 40.0, "底")
      blk.box(fn(o) {
        o.over(Is(true)).padding(Is((180.0, 10.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
        rr_key(o, 40.0, 20.0, "半")
      })
      |> ignore
    })
    |> ignore
  })
  assert_eq(rr_faults(t), [
    "apart: a box (a node of the window's tree's at 16,40 200×40) and a box (a node of the window's tree's at 196,50 40×20) are drawn over each other by 20×30",
  ])
}

///|
test "rooms: every point of the room the rule measures is the hit test's for it, the point a quarter past each end not" {
  let scenes : Array[(Int, (@view.View) -> Unit)] = [
    (0, fn(b) { rr_key_on_scroller(b, 60.0, 2.0) }),
    (2, fn(b) { rr_key_on_scroller(b, 40.0, 8.0) }),
    (0, fn(b) { rr_pill(b, 260.0, 100.0, 231.0, 6.0) }),
    (2, fn(b) { rr_pill(b, 298.0, 34.0, 24.0, 6.0) }),
    (
      0,
      fn(b) {
        b.gap(Is(2.0)) |> ignore
        for k in 0..<3 {
          rr_key(b, 274.0, 18.0, "行\{k}")
        }
      },
    ),
    (
      2,
      fn(b) {
        b.row(Is(true)).gap(Is(4.0)) |> ignore
        for k in 0..<4 {
          rr_key(b, 24.0 + 3.0 * k.to_double(), 24.0, "键\{k}")
        }
      },
    ),
  ]
  for s, scene in scenes {
    let (_, tree) = rr_tester(scene.0, scene.1)
    let boxes = tree.press_boxes()
    let rooms = boxes.map(fn(b) { tree.press_room_found(b.0, b.1) })
    for j, b in boxes {
      let (id, (x0, y0, x1, y1), _, _) = b
      let (rx0, ry0, rx1, ry1) = rooms[j]
      let (mx, my) = ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
      // (each point a quarter apart on the lines it is measured on, an eighth in from its ends: where two meet, the
      // point between them is the one drawn first's; where one drawn after it and within it reaches, as the rule
      // measures it, that one's: a key's on what scrolls)
      let over = fn(x : Double, y : Double) {
        for k in (j + 1)..<boxes.length() {
          let (ox0, oy0, ox1, oy1) = rooms[k]
          if x >= ox0 && x < ox1 && y >= oy0 && y < oy1 {
            return true
          }
        }
        false
      }
      let at = "scene \{s}, target \{j} at \{x0},\{y0}"
      let mut x = rx0 + 0.125
      while x < rx1 {
        if !over(x, my) {
          assert_true(rr_on(tree, id, x, my), msg="\{at}: across at \{x} of \{rx0}–\{rx1}")
        }
        x += 0.25
      }
      let mut y = ry0 + 0.125
      while y < ry1 {
        if !over(mx, y) {
          assert_true(rr_on(tree, id, mx, y), msg="\{at}: down at \{y} of \{ry0}–\{ry1}")
        }
        y += 0.25
      }
      assert_true(!rr_on(tree, id, rx0 - 0.25, my), msg="\{at}: before \{rx0}")
      assert_true(!rr_on(tree, id, rx1 + 0.25, my), msg="\{at}: past \{rx1}")
      assert_true(!rr_on(tree, id, mx, ry0 - 0.25), msg="\{at}: over \{ry0}")
      assert_true(!rr_on(tree, id, mx, ry1 + 0.25), msg="\{at}: under \{ry1}")
    }
  }
}

///|
test "rooms: a column's edge is pressed only where it is drawn, its room as wide as it, and the rule says nothing of it" {
  // (the user, 2026-10-28: 左右各 6px, 同 web: a pane's edge 12 across, a panel's 7)
  for platform in [0, 2] {
    for w in [12.0, 7.0] {
      let (t, tree) = rr_tester(platform, fn(b) {
        b.box(fn(e) {
          e
          .width(Is(Some(w)))
          .height(Is(Some(300.0)))
          .presses(Is(true))
          .cursor(Is(Some(@view.Cursor::ResizeX)))
          .says(Is(Some(@view.said(Separator, label="边"))))
          .on_drag(fn(_) {  })
          |> ignore
        })
        |> ignore
      })
      let at = "platform \{platform}, \{w} across"
      let (edge, (x0, y0, x1, y1)) = rr_box(tree, "边")
      assert_true(tree.pressed_as_drawn(edge), msg=at)
      assert_eq(tree.press_room_found(edge, (x0, y0, x1, y1)), (x0, y0, x1, y1), msg=at)
      assert_eq(x1 - x0, w, msg=at)
      let my = (y0 + y1) / 2.0
      assert_true(rr_on(tree, edge, x0 + 0.25, my), msg="\{at}: in its left edge")
      assert_true(rr_on(tree, edge, x1 - 0.25, my), msg="\{at}: in its right edge")
      assert_true(!rr_on(tree, edge, x0 - 0.25, my), msg="\{at}: before it")
      assert_true(!rr_on(tree, edge, x1 + 0.25, my), msg="\{at}: past it")
      assert_eq(rr_faults(t), [], msg=at)
    }
  }
}

///|
/// A Tester by a finger (a room 44 across), 400 by 400: a trigger 60 by 20 at (100, 100) that takes presses, and, 6
/// under its foot, a card 200 by 120 that takes presses, in a layer over all else of the window (View::over_all, as a
/// hover card's) where `presented`, else drawn after the trigger as any; in the card at (20, 40) a key 30 by 20, and
/// where `crowded` another 4 under it.
fn rr_presented(presented : Bool, crowded : Bool) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=400.0, platform=2)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(k) {
      k.over(Is(true)).offset(Is((100.0, 100.0))) |> ignore
      rr_key(k, 60.0, 20.0, "触发点")
    })
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)).over_all(Is(presented)) |> ignore
      l.box(fn(c) {
        c.over(Is(true)).offset(Is((80.0, 126.0))) |> ignore
        rr_key(c, 200.0, 120.0, "卡", inside=fn(card) {
          card.padding(Is((20.0, 40.0, 0.0, 0.0))).lines_up(Is(Some(Start))) |> ignore
          rr_key(card, 30.0, 20.0, "卡里的键")
          if crowded {
            card.box(fn(g) { g.height(Is(Some(4.0))) |> ignore }) |> ignore
            rr_key(card, 30.0, 20.0, "卡里的邻居")
          }
        })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a layer presented over all else (a hover card under its trigger) covering what is under it takes the press there, no room that lacks; a node merely drawn over it does not; what is in the layer is held to its room" {
  // (a) presented: the trigger's room under it the card's, no fault
  let t = rr_presented(true, false)
  let faults = t.tree_room_faults()
  assert_true(faults.is_empty(), msg="presented: \{Repr(faults)}")
  // (b) the same drawn after it as any: the trigger has 6 under it, 12 over it
  let t = rr_presented(false, false)
  let faults = t.tree_room_faults()
  assert_true(
    faults.length() == 1 && faults[0].has_prefix("room: ") && faults[0].contains("60×20") && faults[0].contains("has 60×38"),
    msg="drawn over: \{Repr(faults)}",
  )
  // (c) in the layer: its key 4 over another, each 34 high (12 on its far side, 2 on the near)
  let t = rr_presented(true, true)
  let faults = t.tree_room_faults()
  assert_true(
    faults.length() == 2 && faults.iter().all(fn(f) { f.has_prefix("room: ") && f.contains("30×20") && f.contains("has 44×34") }),
    msg="in the layer: \{Repr(faults)}",
  )
}
