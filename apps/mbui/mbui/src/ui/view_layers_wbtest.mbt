// Old views one over another, each the whole window (the narrow shell's shape: what is under the pages, a page, what
// floats over them): a press is the old view's whose hit target the old frame finds there, whatever boxes lie over it
// (one drawing nothing there passes it on), held so till it is let go; the others, reading nothing that changed, are
// not built for it.

///|
priv struct Layers {
  t : Tester
  builds : Array[Int]
  taps : Array[Int]
}

///|
/// Under (no button), a page (a button at its top left, 100 by 100) and over it (a button at (200, 600), 100 by 100;
/// nothing elsewhere), each the whole window; their builds and their buttons' presses counted, in that order.
fn layers() -> Layers {
  let builds = [0, 0, 0]
  let taps = [0, 0, 0]
  let layer = fn(k : Int, button : (Double, Double)?) {
    fn(c : Ctx) {
      builds[k] = builds[k] + 1
      match button {
        Some((x, y)) => {
          let id = c.id("button \{k}")
          if c.clicked(id) {
            taps[k] = taps[k] + 1
          }
          c.box(left=x, top=y, w=Px(100.0), h=Px(100.0), bg=0x3366CCFFL, id~, fn() {  }) |> ignore
        }
        None => ()
      }
    }
  }
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, layer(0, None)).over(Is(true)) |> ignore
    old(root, layer(1, Some((0.0, 0.0)))).over(Is(true)) |> ignore
    old(root, layer(2, Some((200.0, 600.0)))).over(Is(true)) |> ignore
  })
  t.draw()
  t.drawn_now()
  { t, builds, taps }
}

///|
test "window tree: old views one over another: a press on the page's button builds the page alone" {
  let w = layers()
  let b0 = w.builds.copy()
  tree_tap(w.t, 50.0, 50.0)
  assert_eq(w.taps, [0, 1, 0])
  assert_true(w.builds[1] > b0[1])
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}

///|
test "window tree: old views one over another: a press on the top one's button builds that one alone" {
  let w = layers()
  let b0 = w.builds.copy()
  tree_tap(w.t, 250.0, 650.0)
  assert_eq(w.taps, [0, 0, 1])
  assert_true(w.builds[2] > b0[2])
  assert_eq((w.builds[0], w.builds[1]), (b0[0], b0[1]))
}

///|
test "window tree: old views one over another: held on the page's button, let go over the top one's: the page's alone" {
  let w = layers()
  let b0 = w.builds.copy()
  finger(0, 50.0, 50.0)
  w.t.drawn_now()
  finger(1, 250.0, 650.0)
  w.t.drawn_now()
  finger(2, 250.0, 650.0)
  w.t.drawn_now()
  // (let go off it: no press of the page's; none of the top one's, which it was never held by)
  assert_eq(w.taps, [0, 0, 0])
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}

///|
/// Under (no button), a page (a button at its top left, `w` by `w`) and over it a box only pointed at over that button
/// (hovered, never pressed), each the whole window; their builds and the page's presses counted.
fn pointed_over(w : Double) -> Layers {
  let builds = [0, 0, 0]
  let taps = [0, 0, 0]
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(_c) { builds[0] = builds[0] + 1 }).over(Is(true)) |> ignore
    old(root, fn(c) {
      builds[1] = builds[1] + 1
      let id = c.id("page button")
      if c.clicked(id) {
        taps[1] = taps[1] + 1
      }
      c.box(left=100.0, top=100.0, w=Px(w), h=Px(w), bg=0x3366CCFFL, id~, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    old(root, fn(c) {
      builds[2] = builds[2] + 1
      c.box(left=50.0, top=50.0, w=Px(200.0), h=Px(200.0), id=c.id("pointed"), points=true, taps=false, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
  })
  t.draw()
  t.drawn_now()
  { t, builds, taps }
}

///|
test "window tree: old views one over another: a press through what is only pointed at is the page's, built alone" {
  let w = pointed_over(100.0)
  let b0 = w.builds.copy()
  tree_tap(w.t, 150.0, 150.0)
  assert_eq(w.taps[1], 1)
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}

///|
test "window tree: old views one over another: a press just off a small button, reached as a press is, the page's alone" {
  let w = pointed_over(20.0)
  let b0 = w.builds.copy()
  // (4 off its right edge: within the room a press reaches it by)
  tree_tap(w.t, 124.0, 110.0)
  assert_eq(w.taps[1], 1)
  assert_eq((w.builds[0], w.builds[2]), (b0[0], b0[2]))
}

///|
test "window tree: an old view alone, then beside another, then alone: its widgets the same ones throughout" {
  let other = @signals.signal(false, same=fn(a, b) { a == b })
  let ids : Array[Int] = []
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      // (read: built again as the other comes and goes)
      other.get() |> ignore
      ids.push(c.id("field"))
      c.text("page", size=12.0) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.show(fn() { other.get() }, fn(v) {
      v.over(Is(true)) |> ignore
      old(v, fn(_c) {  }).grow(Is(1.0)) |> ignore
    })
  })
  t.draw()
  let alone = ids.last().unwrap()
  other.set(true)
  t.drawn_now()
  // (built again where it now is one of two: the same widget)
  let beside = ids.last().unwrap()
  other.set(false)
  t.drawn_now()
  let again = ids.last().unwrap()
  assert_true(ids.length() >= 3, msg="\{ids.length()}")
  assert_eq((beside, again), (alone, alone))
}

///|
/// A node of the tree's, a button at (0, 0) 100 by 100, and over the window two old views, the second opening (while
/// `open`) an overlay at the old frame's root: a button `over_w` wide at (0, 0) over a modal ground, or (`ground`
/// false) the button alone. The tree's button's presses and the overlay's counted.
fn under_overlay(open : @signals.Signal[Bool], ground : Bool) -> (Tester, Ref[Int], Ref[Int]) {
  let node_taps = Ref(0)
  let over_taps = Ref(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(_c) {  }).over(Is(true)) |> ignore
    old(root, fn(c) {
      if open.get() {
        c.overlay("over", modal=ground, scrim=if ground { 0x00000040L } else { 0L }, fn() {
          let id = c.id("over button")
          if c.clicked(id) {
            over_taps.val = over_taps.val + 1
          }
          c.box(w=Px(60.0), h=Px(60.0), bg=0x3366CCFFL, id~, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    .over(Is(true))
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(100.0))).on_press(fn() { node_taps.val = node_taps.val + 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  (t, node_taps, over_taps)
}

///|
test "window tree: an overlay of the old frame's over a node's button: the overlay's press; let go, the node's again" {
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, node_taps, over_taps) = under_overlay(open, false)
  tree_tap(t, 30.0, 30.0)
  assert_eq((node_taps.val, over_taps.val), (0, 1))
  open.set(false)
  t.drawn_now()
  tree_tap(t, 30.0, 30.0)
  assert_eq((node_taps.val, over_taps.val), (1, 1))
}

///|
test "window tree: a modal overlay's ground over a node's button: the press stopped there, the node's not" {
  let open = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, node_taps, over_taps) = under_overlay(open, true)
  // (on the ground, off the overlay's button, over the node's)
  tree_tap(t, 80.0, 80.0)
  assert_eq((node_taps.val, over_taps.val), (0, 0))
}

///|
test "window tree: old views each built in its own room: what they read of the window's size theirs, one resized alone" {
  let wide = @signals.signal(195.0, same=fn(a, b) { a == b })
  let seen_a : Array[(Double, Double)] = []
  let seen_b : Array[(Double, Double)] = []
  let t = Tester::new(fn(_c) {  })
  t.keep_parts(true)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(v) {
      v.width(By(fn() { Some(wide.get()) })) |> ignore
      old(v, fn(c) {
        seen_a.push((c.width, c.height))
        c.box(w=Fill(1.0), h=Px(20.0), fn() { c.text("a", size=12.0) |> ignore }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(195.0))) |> ignore
      old(v, fn(c) {
        seen_b.push((c.width, c.height))
        c.box(w=Fill(1.0), h=Px(20.0), fn() { c.text("b", size=12.0) |> ignore }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  assert_eq((seen_a.last(), seen_b.last()), (Some((195.0, 844.0)), Some((195.0, 844.0))))
  let b_builds = seen_b.length()
  wide.set(95.0)
  t.drawn_now()
  // (a resized: built for its room; b moved over, its room the same: not built again)
  assert_eq(seen_a.last(), Some((95.0, 844.0)))
  assert_eq(seen_b.length(), b_builds)
}
