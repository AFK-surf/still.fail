// A wheel asked of the topmost node there, then of what holds it, till one takes it (Tree::wheel_at): what moves by it
// and is at its end that way (View::on_wheel_moves; an old view's box kept to a height hosted in it, Ctx::capped) leaves
// it to what holds it; what takes all of it (View::on_wheel) keeps it. What of an old view's is asked is of the one hosted
// there alone, none of another's drawn under it.

///|
/// A node of the tree's 300 tall the whole window wide taking the wheel, as `inner_moves` says how: moving what it
/// counts (`outer`, the way down, as far as 1000) where it can; in it, 200 tall at its top, an old view hosted in it
/// whose box is kept to a height of 100 ("inner": rows 400 tall in all), or, `tree_inner`, a node of the tree's of its
/// own moving `inner` as far as 200 and no further (View::on_wheel_moves), or taking all of it (`all`: View::on_wheel).
struct WheelChain {
  outer : Ref[Double]
  inner : Ref[Double]
}

///|
fn wheel_chain_tester(tree_inner? : Bool = false, all? : Bool = false) -> (Tester, WheelChain) {
  let k : WheelChain = { outer: Ref(0.0), inner: Ref(0.0) }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let moves = fn(r : Ref[Double], most : Double) {
    fn(w : @view.Wheel) {
      let to = dclamp(r.val + w.dy, 0.0, most)
      let moved = to != r.val
      r.val = to
      moved
    }
  }
  set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(400.0))).height(Is(Some(300.0))).on_wheel_moves(moves(k.outer, 1000.0)) |> ignore
      if tree_inner {
        o.box(fn(i) {
          i.width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
          if all {
            i.on_wheel(fn(w) { k.inner.val = k.inner.val + w.dy }) |> ignore
          } else {
            i.on_wheel_moves(moves(k.inner, 200.0)) |> ignore
          }
        })
        |> ignore
      } else {
        old(o, fn(c) {
          c.capped("body", 100.0, fn() {
            for i in 0..<10 {
              c.box(w=Px(160.0), h=Px(40.0), fn() { c.text("第\{i}行") |> ignore }) |> ignore
            }
          })
          |> ignore
        })
        .height(Is(Some(200.0)))
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  (t, k)
}

///|
test "an old view's box kept to a height hosted in a node of the tree's that takes the wheel: it scrolls first; at its end, what holds it moves; turned back, it scrolls up first" {
  let (t, k) = wheel_chain_tester()
  t.wheel(80.0, 50.0, 40.0)
  let first = (capped_at() > 0.0, k.outer.val)
  for _ in 0..<20 {
    t.wheel(80.0, 50.0, 40.0)
  }
  let end = capped_at()
  let outer_at_end = k.outer.val
  t.wheel(80.0, 50.0, -40.0)
  let back = (capped_at() < end, k.outer.val)
  assert_eq((first, end > 0.0, outer_at_end > 0.0, back), ((true, 0.0), true, true, (true, outer_at_end)), msg="\{end}")
}

///|
test "a node of the tree's moving by the wheel in one that does too: it first, as far as it goes; then what holds it; turned back, it first again" {
  let (t, k) = wheel_chain_tester(tree_inner=true)
  for _ in 0..<5 {
    t.wheel(80.0, 50.0, 40.0)
  }
  let first = (k.inner.val, k.outer.val)
  for _ in 0..<5 {
    t.wheel(80.0, 50.0, 40.0)
  }
  let then = (k.inner.val, k.outer.val)
  t.wheel(80.0, 50.0, -40.0)
  assert_eq((first, then, (k.inner.val, k.outer.val)), ((200.0, 0.0), (200.0, 200.0), (160.0, 200.0)))
}

///|
test "a node of the tree's taking all of the wheel (View::on_wheel) in one that moves by it: it keeps it, what holds it never moves" {
  let (t, k) = wheel_chain_tester(tree_inner=true, all=true)
  for _ in 0..<10 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq((k.inner.val, k.outer.val), (400.0, 0.0))
}

///|
/// Under all of the window, an old view hosted in the tree whose box kept to a height of 100 ("low": rows 400 tall in
/// all) is at its top; over it, a layer of the tree's (`modal` or not) moving `outer` by the wheel as far as 1000 that
/// hosts an old view of its own at its top, 100 tall, holding a field alone (nothing of it scrolls): both at (80, 50).
/// `at_end`: the layer moved as far as it goes down.
fn wheel_over_tester(modal : Bool, at_end? : Bool = false) -> (Tester, WheelChain) {
  let k : WheelChain = { outer: Ref(if at_end { 1000.0 } else { 0.0 }), inner: Ref(0.0) }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.capped("low", 100.0, fn() {
        for i in 0..<10 {
          c.box(w=Px(160.0), h=Px(40.0), fn() { c.text("下第\{i}行") |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    .height(Is(Some(300.0)))
    |> ignore
    root.box(fn(o) {
      o
      .over(Is(true))
      .modal(Is(modal))
      .on_wheel_moves(fn(w) {
        let to = dclamp(k.outer.val + w.dy, 0.0, 1000.0)
        let moved = to != k.outer.val
        k.outer.val = to
        moved
      })
      |> ignore
      old(o, fn(c) { c.editor("up/field", placeholder="上面的字段") |> ignore }).height(Is(Some(100.0))) |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, k)
}

///|
fn low_at() -> Double {
  match sideways.get(g().capped_id("low")) {
    Some(s) => s.x
    None => -1.0
  }
}

///|
test "a layer of the tree's moving by the wheel over an old view's box kept to a height, a field of another old view's hosted in it there: what holds the field moves, the box under it none" {
  let (t, k) = wheel_over_tester(false)
  for _ in 0..<3 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq((k.outer.val, low_at()), (120.0, 0.0))
}

///|
test "a modal layer of the tree's moving by the wheel over an old view's box kept to a height it keeps from input, a field of another old view's hosted in it there: what holds the field moves, the box under it none" {
  let (t, k) = wheel_over_tester(true)
  for _ in 0..<3 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq((k.outer.val, low_at()), (120.0, 0.0))
}

///|
test "a layer of the tree's at its end that way over an old view's box kept to a height, a field of another old view's hosted in it there: none takes the wheel, the box under it none of it" {
  let (t, k) = wheel_over_tester(false, at_end=true)
  for _ in 0..<3 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq((k.outer.val, low_at()), (1000.0, 0.0))
}

///|
test "an old view over all of the window with nothing of its own where the wheel is (a page's over view), over one whose box kept to a height is there: the box under it scrolls" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.capped("low", 100.0, fn() {
        for i in 0..<10 {
          c.box(w=Px(160.0), h=Px(40.0), fn() { c.text("下第\{i}行") |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    .over(Is(true))
    |> ignore
    old(root, fn(c) {
      c.box(h=Px(200.0), fn() {  }) |> ignore
      c.button("上面的按钮") |> ignore
    })
    .over(Is(true))
    |> ignore
  })
  t.draw()
  for _ in 0..<3 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq(low_at(), 120.0)
}

///|
test "a node of the tree's taking presses alone (none of the wheel) over an old view whose box kept to a height is there: the box under it scrolls" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.capped("low", 100.0, fn() {
        for i in 0..<10 {
          c.box(w=Px(160.0), h=Px(40.0), fn() { c.text("下第\{i}行") |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(e) { e.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(100.0))).on_press(fn() {  }) |> ignore })
    |> ignore
  })
  t.draw()
  for _ in 0..<3 {
    t.wheel(80.0, 50.0, 40.0)
  }
  assert_eq(low_at(), 120.0)
}
