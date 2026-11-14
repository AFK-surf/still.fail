// A page's list's foot declared to resize keeping what it holds to its foot (View::resizes `foot`): what it holds laid
// out whole at the height it comes to, its bottom at the foot's bottom at every moment, cut at the foot's top; the last
// block's bottom at the foot's top at every moment; one way with a key come by data then. A composer growing by a line
// sends the messages up and grows its ground as one motion (the coordinator of the migration, 2026-11-14: one cause
// moves things once; the owner's 2026-10-30, 「以底部为 origin」). Each scene looked at at moments it declares (rc_walk),
// in one jump and at 60, 120, 24 and 7 a second.

///|
/// A page's list 300 by 200 of `keys` (each lfr_tall tall, words 行k), following its foot, whose box is as tall as what
/// it holds: a box as tall as `held` (words 稿). The tree, its scroll, its keys, what the foot holds' height, the foot's
/// box and what it holds.
priv struct LkfCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  held : @signals.Signal[Double]
  foot_box : Ref[@view.View?]
  held_box : Ref[@view.View?]
}

///|
fn lkf_case(keys : Array[Int], held : Double) -> LkfCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let held_h = @signals.signal(held, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let held_box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        foot=fn(f) {
          f.box(fn(b) {
            foot_box.val = Some(b)
            b.shrink(Is(0.0)) |> ignore
            b.box(fn(h) {
              held_box.val = Some(h)
              h.height(By(fn() { Some(held_h.get()) })).shrink(Is(0.0)).words(Is("稿")) |> ignore
            })
            |> ignore
          })
          |> ignore
        },
        fn(b, k) { b.height(Is(Some(lfr_tall(k)))).words(Is("行\{k}")) |> ignore },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, held: held_h, foot_box, held_box }
}

///|
/// Case `c`'s foot's box and what it holds as drawn now: (the foot's top, its bottom, what it holds' bottom).
fn LkfCase::foot_now(self : LkfCase) -> (Double, Double, Double) {
  let f = self.tree.drawn_of(self.foot_box.val.unwrap().id()).unwrap()
  let h = self.tree.drawn_of(self.held_box.val.unwrap().id()).unwrap()
  (f.y, f.y + f.h, h.y + h.h)
}

///|
test "a page's list's foot declared growing 30 to 90 keeping what it holds to its foot: what it holds' bottom at the foot's bottom and the last block's bottom at the foot's top at every moment, one way, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = lkf_case(rc_ten_and([]), 30.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.foot_box.val.unwrap().resizes(foot=true) |> ignore
      c.held.set(90.0)
    })], looks, rate, fn() {
      let (top, bottom, held) = c.foot_now()
      (top, bottom, held, lfr_foot_of(c.tree, "行9"), c.scroll.most() - c.scroll.at(c.tree))
    })
    assert_true(
      got.iter().all(fn(g) { (g.2 - g.1).abs() < 1.0e-6 }),
      msg="at \{rate} a second: what the foot holds against its foot \{Repr(got)}",
    )
    assert_true(
      got.iter().all(fn(g) { (g.3 - g.0).abs() < 1.0e-6 }),
      msg="at \{rate} a second: the last block's bottom at the foot's top \{Repr(got)}",
    )
    assert_true(got.iter().all(fn(g) { g.4.abs() < 1.0e-6 }), msg="at \{rate} a second: at its foot")
    assert_true(got[1].0 < 170.0 && got[1].0 > 110.0, msg="at \{rate} a second: on its way at \{looks[1]}")
    assert_eq(rc_turns(got.map(fn(g) { g.0 })), 0, msg="at \{rate} a second: one way only")
    assert_eq(got.last().unwrap().0, 110.0, msg="at \{rate} a second: 90 at the end")
  }
}

///|
test "a page's list's foot declared closing 90 to 30 keeping what it holds to its foot as a key comes at its end: what it holds' bottom at the foot's bottom at every moment, the new block's top going one way only, the same at every rate" {
  let looks = rc_looks(rc_at + 700.0)
  for rate in rc_rates {
    let c = lkf_case(rc_ten_and([]), 90.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.foot_box.val.unwrap().resizes(foot=true) |> ignore
      c.held.set(30.0)
      c.keys.set(c.keys.untracked() + [10])
    })], looks, rate, fn() {
      let (_, bottom, held) = c.foot_now()
      (bottom, held, rc_y(c.tree, "行10"))
    })
    assert_true(
      got.iter().all(fn(g) { (g.1 - g.0).abs() < 1.0e-6 }),
      msg="at \{rate} a second: what the foot holds against its foot \{Repr(got)}",
    )
    assert_eq(rc_turns(got.map(fn(g) { g.2 })), 0, msg="at \{rate} a second: one way only")
  }
}

///|
test "a foot declared growing kept to its top as ever: what it holds' top at the foot's top, its bottom past the foot's while it goes" {
  let c = lkf_case(rc_ten_and([]), 30.0)
  let got = rc_walk(c.tree, [(rc_at, fn() {
    c.foot_box.val.unwrap().resizes() |> ignore
    c.held.set(90.0)
  })], rc_looks(rc_at + 600.0), 0.0, fn() { c.foot_now() })
  assert_true(got[1].2 > got[1].1 + 1.0, msg="what it holds past the foot's bottom on its way: \{Repr(got[1])}")
}

///|
test "a page's list's foot declared closing 90 to 30 alone keeping what it holds to its foot: what it holds' bottom at the foot's bottom at every moment" {
  let looks = rc_looks(rc_at + 700.0)
  let c = lkf_case(rc_ten_and([]), 90.0)
  let got = rc_walk(c.tree, [(rc_at, fn() {
    c.foot_box.val.unwrap().resizes(foot=true) |> ignore
    c.held.set(30.0)
  })], looks, 0.0, fn() {
    let (_, bottom, held) = c.foot_now()
    (bottom, held)
  })
  assert_true(got.iter().all(fn(g) { (g.1 - g.0).abs() < 1.0e-6 }), msg="closing alone: \{Repr(got)}")
}

///|
test "a page's list's foot declared growing 30 to 90 keeping what it holds to its foot as a key comes at its end: what it holds' bottom at the foot's bottom at every moment" {
  let looks = rc_looks(rc_at + 700.0)
  let c = lkf_case(rc_ten_and([]), 30.0)
  let got = rc_walk(c.tree, [(rc_at, fn() {
    c.foot_box.val.unwrap().resizes(foot=true) |> ignore
    c.held.set(90.0)
    c.keys.set(c.keys.untracked() + [10])
  })], looks, 0.0, fn() {
    let (_, bottom, held) = c.foot_now()
    (bottom, held)
  })
  assert_true(got.iter().all(fn(g) { (g.1 - g.0).abs() < 1.0e-6 }), msg="growing with a key: \{Repr(got)}")
}
