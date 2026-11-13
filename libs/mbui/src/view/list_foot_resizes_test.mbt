// A page's list's foot (View::scrolls_window's `foot`) declared to resize (View::resizes): one member of the list's one
// way, the held column's group, with a key come by data at that moment; the room under the last block as tall as the
// foot's way has it at each moment, not its measured whole; a list said at_once joining nothing, the foot's change
// alone. Each scene looked at at moments it declares (rc_walk), in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall each block is: 40, but key 77 (what comes in the scene of one way), 400, and key 52 (an answer come in
/// the place of words sent, taller), 60.
fn lfr_tall(k : Int) -> Double {
  match k {
    77 => 400.0
    52 => 60.0
    _ => 40.0
  }
}

///|
/// A page's list 300 by 200 of `keys` (each lfr_tall tall, words 行k), following its foot, a foot as tall as `foot`
/// with words 脚; `at_once` the list's; where `shown` is a key, its block 40 tall holding a show 60 tall under it, as
/// `on`; where `answer` is said, block 50 a pick of what it says (as tall as lfr_tall of it), words 行50: the tree, its
/// scroll, its keys, the foot's height and its box, the show.
priv struct LfrCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  foot : @signals.Signal[Double]
  foot_box : Ref[@view.View?]
  on : @signals.Signal[Bool]
}

///|
fn lfr_case(
  keys : Array[Int],
  foot : Double,
  at_once? : Bool = false,
  follows? : Bool = true,
  shown? : Int = -1,
  place? : @view.ListPlace[Int],
  answer? : @signals.Signal[Int],
) -> LfrCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let foot_h = @signals.signal(foot, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { follows },
        at_once~,
        place?,
        foot=fn(f) {
          f.box(fn(b) {
            foot_box.val = Some(b)
            b.height(By(fn() { Some(foot_h.get()) })).shrink(Is(0.0)).words(Is("脚")) |> ignore
          })
          |> ignore
        },
        fn(b, k) {
          if k == 50 && answer is Some(a) {
            // (the words sent and the core's answer to them, one in the other's place, by the key it was sent as)
            b.pick(fn() { a.get() }, fn(p, which) {
              p.height(Is(Some(lfr_tall(which)))).shrink(Is(0.0)).words(Is("行50")) |> ignore
            })
          } else if k == shown {
            b.box(fn(t) { t.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行\{k}")) |> ignore }) |> ignore
            b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(60.0))).shrink(Is(0.0)) |> ignore })
          } else {
            b.height(Is(Some(lfr_tall(k)))).words(Is("行\{k}")) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, foot: foot_h, foot_box, on }
}

///|
/// The foot's box of case `c`, declared to resize in this change.
fn LfrCase::foot_resizes(self : LfrCase) -> Unit {
  self.foot_box.val.unwrap().resizes() |> ignore
}

///|
/// How far case `c` is off its foot.
fn LfrCase::off_foot(self : LfrCase) -> Double {
  self.scroll.most() - self.scroll.at(self.tree)
}

///|
test "a page's list at its foot, its foot declared closing 90 to 30 as a key 400 tall comes at its end: one way, as a block's inside closing 60 with the same key coming, what is above going up one way only, at its foot all the way, the same at every rate" {
  // (the foot's top read against the group's way: its share of one Move as far as the farthest of it goes, 400, the
  // key's (flex's come_group_set: what each goes a share of one way); its own way, a Move of 60, is shorter, so a foot
  // left out of the list's way is told from one in it. The key's top drawn all the way, its 400 more than what shows)
  let looks = rc_looks(rc_at + 700.0)
  for rate in rc_rates {
    let c = lfr_case(rc_ten_and([]), 90.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.foot_resizes()
      c.foot.set(30.0)
      c.keys.set(c.keys.untracked() + [77])
    })], looks, rate, fn() { (rc_y(c.tree, "行77"), c.off_foot(), rc_y(c.tree, "脚")) })
    // (the foot's top at 200 less as tall as it is: 90 less its share, 60, of the key's Move of 400)
    let want = looks.map(fn(at) { 110.0 + 60.0 * @flex.come_way(0.0, 0.0, 400.0, at - rc_at).0 / 400.0 })
    let foot = got.map(fn(g) { g.2 })
    assert_true(
      rc_near(foot, want),
      msg="at \{rate} a second: the foot's top \{Repr(foot)} against \{Repr(want)}",
    )
    assert_true(got.iter().all(fn(g) { g.0 != rc_none }), msg="at \{rate} a second: 77 drawn all the way")
    assert_eq(rc_turns(got.map(fn(g) { g.0 })), 0, msg="at \{rate} a second: one way only")
    assert_true(got.iter().all(fn(g) { g.1.abs() < 1.0e-6 }), msg="at \{rate} a second: at its foot")
    assert_true(got[1].2 > 110.0 && got[1].2 < 170.0, msg="at \{rate} a second: the foot on its way at \{looks[1]}")
    assert_eq(got.last().unwrap().2, 170.0, msg="at \{rate} a second: the foot 30 at the end")
  }
}

///|
test "a page's list's foot declared opening 30 to 90 alone: at its foot, its last block's foot at the foot's shown top at every moment; scrolled up, what is read stays at every moment and it reaches further as the way goes, the same at every rate" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = lfr_case(rc_ten_and([]), 30.0)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.foot_resizes()
      c.foot.set(90.0)
    })], looks, rate, fn() { (lfr_foot_of(c.tree, "行9"), rc_y(c.tree, "脚")) })
    assert_true(got.iter().all(fn(g) { (g.0 - g.1).abs() < 1.0e-6 }), msg="at \{rate} a second, at its foot: \{Repr(got)}")
    assert_true(got[1].1 < 170.0 && got[1].1 > 110.0, msg="at \{rate} a second: on its way at \{looks[1]}")
    assert_eq(got.last().unwrap().1, 110.0, msg="at \{rate} a second: 90 at the end")
    // (scrolled up: key 2 at the top of what shows)
    let place : @view.ListPlace[Int] = @view.ListPlace::new()
    let u = lfr_case(rc_ten_and([]), 30.0, follows=false, place~)
    place.bring(2)
    u.tree.frame(390.0, 844.0) |> ignore
    let most_was = u.scroll.most()
    let up = rc_walk(u.tree, [(rc_at, fn() {
      u.foot_resizes()
      u.foot.set(90.0)
    })], looks, rate, fn() { (rc_y(u.tree, "行2"), u.scroll.most() - most_was) })
    assert_true(up.iter().all(fn(g) { g.0.abs() < 1.0e-6 }), msg="at \{rate} a second, scrolled up: what is read \{Repr(up)}")
    assert_true(up[1].1 > 0.0 && up[1].1 < 60.0, msg="at \{rate} a second, scrolled up: reaching further on its way")
    assert_true((up.last().unwrap().1 - 60.0).abs() < 1.0e-6, msg="at \{rate} a second, scrolled up: 60 further at the end")
  }
}

///|
test "a page's list said at_once, its foot declared opening 30 to 90 as a key comes: the foot's way its own, as alone, the key there at once" {
  let looks = rc_looks(rc_at + 600.0)
  for rate in rc_rates {
    let c = lfr_case(rc_ten_and([]), 30.0, at_once=true)
    let got = rc_walk(c.tree, [(rc_at, fn() {
      c.foot_resizes()
      c.foot.set(90.0)
      c.keys.set(c.keys.untracked() + [10])
    })], looks, rate, fn() { (rc_y(c.tree, "脚"), lfr_foot_of(c.tree, "行10")) })
    // (alone: the foot's own way, as in a list where nothing comes)
    let a = lfr_case(rc_ten_and([]), 30.0, at_once=true)
    let alone = rc_walk(a.tree, [(rc_at, fn() {
      a.foot_resizes()
      a.foot.set(90.0)
    })], looks, rate, fn() { rc_y(a.tree, "脚") })
    assert_true(rc_near(got.map(fn(g) { g.0 }), alone), msg="at \{rate} a second: the foot's way \{Repr(got)}")
    assert_true(got[1].0 < 170.0 && got[1].0 > 110.0, msg="at \{rate} a second: the foot on its way")
    // (the key there at once: its foot at the foot's shown top from the first look)
    assert_true(got.iter().all(fn(g) { (g.0 - g.1).abs() < 1.0e-6 }), msg="at \{rate} a second: key 10 there at once")
  }
}

///|
/// The words drawn `w`'s foot (its top and height), as the tree is drawn now; rc_none where none is.
fn lfr_foot_of(t : @view.Tree, w : String) -> Double {
  match t.drawn().filter(fn(d) { d.words == w }) {
    [d, ..] => d.y + d.h
    _ => rc_none
  }
}

///|
test "a page's list at its foot, its foot declared closing 90 to 30 as a key comes at its end, 400 tall and 40: the new block's top at the foot of the one before it at every moment, no gap ever, and that one's top going one way only, the same at every rate" {
  let looks = rc_looks(rc_at + 700.0)
  for come in [77, 10] {
    for rate in rc_rates {
      let c = lfr_case(rc_ten_and([]), 90.0)
      let got = rc_walk(c.tree, [(rc_at, fn() {
        c.foot_resizes()
        c.foot.set(30.0)
        c.keys.set(c.keys.untracked() + [come])
      })], looks, rate, fn() { (rc_y(c.tree, "行\{come}"), lfr_foot_of(c.tree, "行9"), rc_y(c.tree, "行9")) })
      // (where both are drawn: the one before gone up out of sight as the new one is taller than what shows)
      let both = got.filter(fn(g) { g.0 != rc_none && g.1 != rc_none })
      assert_true(both.length() > 0, msg="key \{come} at \{rate} a second: never both drawn")
      assert_true(
        both.iter().all(fn(g) { (g.0 - g.1).abs() < 1.0e-6 }),
        msg="key \{come} at \{rate} a second: a gap \{Repr(got.map(fn(g) { g.0 - g.1 }))}",
      )
      let nine = got.filter(fn(g) { g.2 != rc_none }).map(fn(g) { g.2 })
      assert_eq(rc_turns(nine), 0, msg="key \{come} at \{rate} a second: 9's top \{Repr(nine)}")
      // (and 9's top where the list's way has it: as with block 9's inside closing 60 as the key comes, its foot 30
      // all along; the foot's own way, shorter than the group's with 77, would be told)
      let r = lfr_case(rc_ten_and([]), 30.0, shown=9)
      let r_nine = rc_walk(r.tree, [(rc_at, fn() {
        r.on.set(false)
        r.keys.set(r.keys.untracked() + [come])
      })], looks, rate, fn() { rc_y(r.tree, "行9") })
      // (where both draw it: block 9 is taller there by what is left of its inside)
      let pairs : Array[(Double, Double)] = []
      for i, g in got {
        if g.2 != rc_none && r_nine[i] != rc_none {
          pairs.push((g.2, r_nine[i]))
        }
      }
      assert_true(pairs.length() > 1, msg="key \{come} at \{rate} a second: 9 drawn")
      assert_true(
        pairs.iter().all(fn(p) { (p.0 - p.1).abs() < 1.0e-6 }),
        msg="key \{come} at \{rate} a second: 9's top \{Repr(got.map(fn(g) { g.2 }))} against \{Repr(r_nine)}",
      )
    }
  }
}

///|
test "a page's list at its foot, words just sent answered 700 ms later in their place, by the key they were sent as, as tall: no block's top moves at any moment; 20 taller: what is above goes up along one way from that moment, as a column's one in another's place, the same at every rate" {
  // (the answer is the same key's, the core's row taking over what was sent (chat_body_node's row_keys): one in the
  // other's place in its block. Another key in its place is one going as another comes, the new one's top coming up
  // from under the one leaving, in a list as in a column)
  let answered = rc_at + 700.0
  let looks = rc_looks(answered + 600.0)
  for rate in rc_rates {
    // (as tall: nothing moves)
    let a = @signals.signal(50, same=fn(x, y) { x == y })
    let c = lfr_case(rc_ten_and([50]), 30.0, answer=a)
    let was = (rc_y(c.tree, "行9"), rc_y(c.tree, "行50"))
    let got = rc_walk(c.tree, [(answered, fn() { a.set(51) })], looks, rate, fn() {
      (rc_y(c.tree, "行9"), rc_y(c.tree, "行50"))
    })
    assert_true(
      got.iter().all(fn(g) { (g.0 - was.0).abs() < 1.0e-6 && (g.1 - was.1).abs() < 1.0e-6 }),
      msg="at \{rate} a second, as tall: \{Repr(got)} from \{Repr(was)}",
    )
    // (20 taller: the list's above going up as a column's 下 goes down, one in another's place)
    let b = @signals.signal(50, same=fn(x, y) { x == y })
    let t = lfr_case(rc_ten_and([50]), 30.0, answer=b)
    let t_was = rc_y(t.tree, "行9")
    let up = rc_walk(t.tree, [(answered, fn() { b.set(52) })], looks, rate, fn() { t_was - rc_y(t.tree, "行9") })
    let which = @signals.signal(50, same=fn(x, y) { x == y })
    let col = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))) |> ignore
        o.pick(fn() { which.get() }, fn(p, k) { p.height(Is(Some(lfr_tall(k)))).shrink(Is(0.0)) |> ignore })
        o.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
      })
      |> ignore
    })
    col.frame(390.0, 844.0) |> ignore
    let under = rc_y(col, "下")
    let down = rc_walk(col, [(answered, fn() { which.set(52) })], looks, rate, fn() { rc_y(col, "下") - under })
    assert_true(rc_near(up, down), msg="at \{rate} a second, 20 taller: \{Repr(up)} against \{Repr(down)}")
    assert_true(up.last().unwrap() == 20.0, msg="at \{rate} a second, 20 taller: \{Repr(up)}")
  }
}
///|
/// A page's list `wide` wide (300 unless said), 200 tall, of keys 0 to 29 each a block of words that wrap (wider, fewer lines), with a head
/// and a foot where said, and where `resized` one of its blocks declared to resize long before: the tree, its width.
fn lfr_wrapping(head : Bool, foot : Bool, resized : Bool, wide? : Double = 300.0) -> (@view.Tree, @signals.Signal[Double]) {
  let w = @signals.signal(wide, same=fn(a, b) { a == b })
  let grown = @signals.signal(40.0, same=fn(a, b) { a == b })
  let block3 : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(w.get()) })).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(
        @view.Scroll::list(),
        fn() { Array::makei(30, fn(i) { i }) },
        est=40.0,
        head?=if head { Some(fn(h : @view.View) { h.box(fn(b) { b.height(Is(Some(30.0))) |> ignore }) |> ignore }) } else { None },
        foot?=if foot { Some(fn(f : @view.View) { f.box(fn(b) { b.height(Is(Some(30.0))) |> ignore }) |> ignore }) } else { None },
        fn(b, k) {
          b.box(fn(t) { t.words(Is("词 \{k} 一 二 三 四 五 六 七 八 九 十 十一 十二 十三 十四 十五 十六 十七 十八 十九 二十")) |> ignore }) |> ignore
          if k == 3 {
            b.box(fn(g) {
              block3.val = Some(g)
              g.height(By(fn() { Some(grown.get()) })).shrink(Is(0.0)) |> ignore
            })
            |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  if resized {
    tree.at(100.0)
    tree.event(100.0, fn() {
      block3.val.unwrap().resizes() |> ignore
      grown.set(80.0)
    })
    tree.at(5000.0)
    tree.frame(390.0, 844.0) |> ignore
  }
  (tree, w)
}

///|
test "a page's list given another width at a moment, and back: in that frame every block where the layout at that width has it, what is read where it was, nothing on its way then or after; with a head and a foot, and with a resize declared long before" {
  let at = 6000.0
  let looks = [at, at + 10.0, at + 100.0, at + 300.0, at + 600.0]
  for case in [(false, false, false), (true, true, false), (false, false, true)] {
    let (head, foot, resized) = case
    for rate in rc_rates {
      let (t, w) = lfr_wrapping(head, foot, resized)
      t.at(at - 100.0)
      t.frame(390.0, 844.0) |> ignore
      let words = fn(k : Int) { "词 \{k} 一 二 三 四 五 六 七 八 九 十 十一 十二 十三 十四 十五 十六 十七 十八 十九 二十" }
      // (what is read: the block holding the top of what shows, at its top)
      let read_was = rc_y(t, words(0))
      let tops = rc_walk(t, [(at, fn() { w.set(240.0) })], looks, rate, from=at - 100.0, fn() {
        Array::makei(30, fn(k) { rc_y(t, words(k)) })
      })
      assert_eq(tops[0][0], read_was, msg="\{Repr(case)} at \{rate} a second: what is read where it was")
      // (where the layout at 240 has them: as a list made at 240)
      let (made, _) = lfr_wrapping(head, foot, resized, wide=240.0)
      if !resized {
        let made_tops = Array::makei(30, fn(k) { rc_y(made, words(k)) })
        assert_true(rc_near(tops[0], made_tops), msg="\{Repr(case)} at \{rate} a second: \{Repr(tops[0])} against \{Repr(made_tops)}")
      }
      // (every later frame the same as the one of the change: nothing on its way)
      for i, f in tops {
        assert_true(rc_near(f, tops[0]), msg="\{Repr(case)} at \{rate} a second, at \{looks[i]}: \{Repr(f)} against \{Repr(tops[0])}")
      }
    }
  }
}
