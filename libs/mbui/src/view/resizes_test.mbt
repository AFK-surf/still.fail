// A height change declared makes its way (View::resizes): said on a node in a handler, its coming out another height in
// the change that handler commits is for that change's cause, from as tall as it was to as tall as it comes out, one
// member of its column's one way (flex's ComeGroup); alone, as its spec says, else a Move; declared and the same height,
// nothing, nothing kept; not declared, at once. Held to a plain column of the same change made by a structure (a box
// 40 tall and a show of 60 under it, coming or going: the same Move of 60), each scene looked at at moments it
// declares (rc_walk, list_rows_come_test's), in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall each row an each brings in is: 300, so far that its Move alone is longer than the resize's of 60 (350 ms
/// against 250), one way for both told from each its own.
let rz_row : Double = 300.0

///|
/// A plain column 300 wide: the rows of `keys` (each rz_row tall, words 列k), then the node that resizes (as tall as
/// `h`, holding a box as tall with words 内), then 下 20 tall: the tree, the node, its height, the keys, and the box it
/// holds.
priv struct RzCase {
  tree : @view.Tree
  node : Ref[@view.View?]
  inner : Ref[@view.View?]
  h : @signals.Signal[Double]
  keys : @signals.Signal[Array[Int]]
}

///|
fn rz_case(h : Double, keys? : Array[Int] = []) -> RzCase {
  let h = @signals.signal(h, same=fn(a, b) { a == b })
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(r, k) {
        r.height(Is(Some(rz_row))).shrink(Is(0.0)).words(Is("列\{k.get()}")) |> ignore
      })
      col.box(fn(n) {
        node.val = Some(n)
        n.height(By(fn() { Some(h.get()) })).shrink(Is(0.0)) |> ignore
        n.box(fn(i) {
          inner.val = Some(i)
          i.height(By(fn() { Some(h.get()) })).shrink(Is(0.0)).words(Is("内")) |> ignore
        })
        |> ignore
      })
      |> ignore
      col.box(fn(b) { b.height(Is(Some(20.0))).shrink(Is(0.0)).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, node, inner, h, keys }
}

///|
/// The same column with the change made by a structure: the rows of `keys`, a box 40 tall, a show of a box 60 tall
/// under it (as `on`), then 下: the tree, whether the show shows, the keys.
fn rz_ref(on : Bool, keys? : Array[Int] = []) -> (@view.Tree, @signals.Signal[Bool], @signals.Signal[Array[Int]]) {
  let on = @signals.signal(on, same=fn(a, b) { a == b })
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(r, k) {
        r.height(Is(Some(rz_row))).shrink(Is(0.0)).words(Is("列\{k.get()}")) |> ignore
      })
      col.box(fn(b) { b.height(Is(Some(40.0))).shrink(Is(0.0)) |> ignore }) |> ignore
      col.show(fn() { on.get() }, fn(s) { s.height(Is(Some(60.0))).shrink(Is(0.0)) |> ignore })
      col.box(fn(b) { b.height(Is(Some(20.0))).shrink(Is(0.0)).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, on, keys)
}

///|
/// The node of case `c`.
fn RzCase::node(self : RzCase) -> @view.View {
  self.node.val.unwrap()
}

///|
/// Where 下 is drawn in `t`.
fn rz_under(t : @view.Tree) -> Double {
  rc_y(t, "下")
}

///|
/// The words 内's drawn height in `t`.
fn rz_inner_h(t : @view.Tree) -> Double {
  match t.drawn().filter(fn(d) { d.words == "内" }) {
    [d, ..] => d.h
    _ => rc_none
  }
}

///|
test "resizes: declared, 40 to 100 in a plain column: along a Move from the cause's moment, what is under it going down with it, as a column's show of 60 coming, the same at every rate; what it holds laid out at 100 from the first frame" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.node().resizes() |> ignore
      c.h.set(100.0)
    })], looks, rate, fn() { (rz_under(c.tree), rz_inner_h(c.tree)) })
    let (r, on, _) = rz_ref(false)
    let want = rc_walk(r, [(rc_at, fn() { on.set(true) })], looks, rate, fn() { rz_under(r) })
    assert_true(rc_near(got.map(fn(g) { g.0 }), want), msg="at \{rate} a second: \{Repr(got.map(fn(g) { g.0 }))}")
    assert_true(got[1].0 < 100.0, msg="at \{rate} a second: on its way at \{looks[1]}")
    assert_true(got.iter().all(fn(g) { g.1 == 100.0 }), msg="at \{rate} a second: what it holds")
  }
}

///|
test "resizes: declared, 100 to 40 in a plain column: closing along a Move from the cause's moment, as a column's show of 60 going, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(100.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.node().resizes() |> ignore
      c.h.set(40.0)
    })], looks, rate, fn() { rz_under(c.tree) })
    let (r, on, _) = rz_ref(true)
    let want = rc_walk(r, [(rc_at, fn() { on.set(false) })], looks, rate, fn() { rz_under(r) })
    assert_true(rc_near(got, want), msg="at \{rate} a second: \{Repr(got)}")
    assert_true(got[1] > 40.0, msg="at \{rate} a second: on its way at \{looks[1]}")
  }
}

///|
test "resizes: declared and the same height, or declared in a change that lays nothing of it out: nothing moves, nothing is kept; a change of it not declared after is at once" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(
      c.tree,
      [
        // (declared, set to the height it has)
        (rc_at, fn() {
          c.node().resizes() |> ignore
          c.h.set(40.0)
        }),
        // (declared, nothing of it changed in that change)
        (rc_at + 50.0, fn() { c.node().resizes() |> ignore }),
        // (not declared: 40 to 100)
        (rc_at + 100.0, fn() { c.h.set(100.0) }),
      ],
      looks,
      rate,
      fn() { rz_under(c.tree) },
    )
    for i, at in looks {
      let want = if at < rc_at + 100.0 { 40.0 } else { 100.0 }
      assert_eq(got[i], want, msg="at \{rate} a second, at \{at}")
    }
  }
}

///|
test "resizes: not declared, 40 to 100: at once, as on main" {
  let looks = rc_looks(rc_at + 300.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(c.tree, [(rc_at, fn() { c.h.set(100.0) })], looks, rate, fn() { rz_under(c.tree) })
    assert_true(got.iter().all(fn(y) { y == 100.0 }), msg="at \{rate} a second: \{Repr(got)}")
  }
}

///|
test "resizes: declared at the moment a row comes down the same column: one way, as a column's row and show coming together, the same at every rate" {
  let looks = rc_looks(rc_at + 700.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.keys.set([0])
      c.node().resizes() |> ignore
      c.h.set(100.0)
    })], looks, rate, fn() { rz_under(c.tree) })
    let (r, on, keys) = rz_ref(false)
    let want = rc_walk(r, [(rc_at, fn() {
      keys.set([0])
      on.set(true)
    })], looks, rate, fn() { rz_under(r) })
    assert_true(rc_near(got, want), msg="at \{rate} a second: \{Repr(got)} against \{Repr(want)}")
  }
}

///|
test "resizes: declared as a row come down the same column is still on its way: joined from that moment, place and speed going on, no step, as a column's row with a show coming mid-way, the same at every rate" {
  let looks = rc_looks(rc_at + 800.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(
      c.tree,
      [
        (rc_at, fn() { c.keys.set([0]) }),
        (rc_at + rc_again_ms, fn() {
          c.node().resizes() |> ignore
          c.h.set(100.0)
        }),
      ],
      looks,
      rate,
      fn() { rz_under(c.tree) },
    )
    let (r, on, keys) = rz_ref(false)
    let want = rc_walk(r, [(rc_at, fn() { keys.set([0]) }), (rc_at + rc_again_ms, fn() { on.set(true) })], looks, rate, fn() {
      rz_under(r)
    })
    assert_true(rc_near(got, want), msg="at \{rate} a second: \{Repr(got)} against \{Repr(want)}")
    assert_eq(rc_turns(got), 0, msg="at \{rate} a second: no step back")
  }
}

///|
test "resizes: alone with a spec of 250 ms: at rest at the cause and 250, along its curve; declared so with a row coming, the group's way, not 250" {
  let curve = fn(x : Double) { x * x }
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.node().resizes(spec=(250.0, curve)) |> ignore
      c.h.set(100.0)
    })], looks, rate, fn() { rz_under(c.tree) })
    for i, at in looks {
      let gone = at - rc_at
      let want = if gone >= 250.0 { 100.0 } else { 40.0 + 60.0 * curve(gone / 250.0) }
      assert_true((got[i] - want).abs() < 1.0e-6, msg="at \{rate} a second, at \{at}: \{got[i]} not \{want}")
    }
    // (with a row coming: the group's, as the column's row and show)
    let g = rz_case(40.0)
    let with_row = rc_walk(g.tree, [(rc_at, fn() {
      g.keys.set([0])
      g.node().resizes(spec=(250.0, curve)) |> ignore
      g.h.set(100.0)
    })], looks, rate, fn() { rz_under(g.tree) })
    let (r, on, keys) = rz_ref(false)
    let want = rc_walk(r, [(rc_at, fn() {
      keys.set([0])
      on.set(true)
    })], looks, rate, fn() { rz_under(r) })
    assert_true(rc_near(with_row, want), msg="at \{rate} a second, with a row: \{Repr(with_row)}")
  }
}

///|
test "resizes: told outside any change, after its height changed, with a spec of 400 ms (longer than a Move by how far): along its curve and at rest at 400, not cut at a Move's end, the same at every rate" {
  let curve = fn(x : Double) { x * x }
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    c.tree.at(rc_at)
    c.tree.frame(390.0, 844.0) |> ignore
    // (as an old view's height told its node as the frame is laid out: no handler's change round it)
    c.h.set(100.0)
    c.node().resizes(spec=(400.0, curve)) |> ignore
    let got = rc_walk(c.tree, [], looks, rate, fn() { rz_under(c.tree) }, from=rc_at)
    for i, at in looks {
      let gone = at - rc_at
      let want = if gone >= 400.0 { 100.0 } else { 40.0 + 60.0 * curve(gone / 400.0) }
      assert_true((got[i] - want).abs() < 1.0e-6, msg="at \{rate} a second, at \{at}: \{got[i]} not \{want}")
    }
  }
}

///|
test "resizes: declared again mid-way the other way: its place and speed going on, no step, as a column's show turned back, the same at every rate" {
  let looks = rc_looks(rc_at + 700.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let got = rc_walk(
      c.tree,
      [
        (rc_at, fn() {
          c.node().resizes() |> ignore
          c.h.set(100.0)
        }),
        (rc_at + 100.0, fn() {
          c.node().resizes() |> ignore
          c.h.set(40.0)
        }),
      ],
      looks,
      rate,
      fn() { rz_under(c.tree) },
    )
    let (r, on, _) = rz_ref(false)
    let want = rc_walk(r, [(rc_at, fn() { on.set(true) }), (rc_at + 100.0, fn() { on.set(false) })], looks, rate, fn() {
      rz_under(r)
    })
    assert_true(rc_near(got, want), msg="at \{rate} a second: \{Repr(got)} against \{Repr(want)}")
    assert_eq(rc_turns(got), 1, msg="at \{rate} a second: turned once")
  }
}

///|
test "resizes: a look of what it holds given, where it is drawn, how tall it shows: at every frame of the way what it is laid out at then" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = rz_case(40.0)
    let given : Array[Double] = []
    c.inner.val.unwrap().shown_by(c.node(), fn(h) {
      given.push(h)
      @view.ground_as_laid
    })
    |> ignore
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.node().resizes() |> ignore
      c.h.set(100.0)
    })], looks, rate, fn() {
      // (as a host draws it: its ground as the tree gives it there)
      c.tree.ground_drawn_of(c.inner.val.unwrap().id()) |> ignore
      (given.last(), c.node().rect().3)
    })
    assert_true(
      got.iter().all(fn(g) { g.0 is Some(h) && (h - g.1).abs() < 1.0e-6 }),
      msg="at \{rate} a second: \{Repr(got)}",
    )
    assert_true(got[1].1 > 40.0 && got[1].1 < 100.0, msg="at \{rate} a second: on its way")
  }
}
