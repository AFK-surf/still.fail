// A page's list's blocks come by data on their way (View::scrolls_window, list_rows_come_test's cases): what reads a
// place while that way goes reads it as the way has it (Places), a hand or an ask taking the list mid-way; a second
// change before what came first is measured; the moment the way comes to rest, wherever between two frames the data
// came; and the work of a frame of a way, as many blocks as it holds.

///|
/// How far a finger's drag goes each step, and how far its first step goes past the slop to take the list.
let bw_drag_step : Double = 20.0

///|
/// How long after the data's moment the hand or the ask comes, its block still on its way.
let bw_mid_ms : Double = 100.0

///|
/// A page's list 300 by 200 of `keys` (as rc_case: following its foot, blocks as tall as rc_tall), asked by `place`.
fn bw_case(keys : Array[Int], place : @view.ListPlace[Int]) -> RcCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, place~, fn(b, k) {
        b.height(Is(Some(rc_tall(k)))).words(Is("行\{k}")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys }
}

///|
test "a page's list at its foot, a block on its way taken by the hand mid-way: what is read goes with the finger, and stays where the hand has it as the block opens under it, the same at every rate" {
  let tall = rc_tall(70)
  let held_at = rc_at + bw_mid_ms
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [held_at + 1.0, held_at + 50.0, ends, ends + 100.0]
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(Array::makei(10, fn(i) { i }))
    let tree = c.tree
    // (just before the hand: 9 as far up as the way has it)
    let before = rc_walk(tree, [(rc_at, fn() { c.keys.set(rc_ten_and([70])) })], [held_at], rate, fn() {
      rc_y(tree, "行9")
    })
    let id = tree.claimer_of(tree.claimers_at(150.0, 100.0), 0.0, bw_drag_step).unwrap()
    tree.at(held_at)
    tree.drag_at(id, Down, 150.0, 100.0, held_at) |> ignore
    tree.drag_at(id, Moved, 150.0, 100.0 + bw_drag_step, held_at) |> ignore
    tree.drag_at(id, Moved, 150.0, 100.0 + 2.0 * bw_drag_step, held_at) |> ignore
    tree.frame(390.0, 844.0) |> ignore
    // (taken: 9 down as far as the finger went past where it took the list)
    let taken = rc_y(tree, "行9")
    let after = rc_walk(tree, [], looks, rate, from=held_at, fn() { (rc_y(tree, "行9"), rc_y(tree, "行70")) })
    (before[0], taken, after)
  })
  for i, rate in rc_rates {
    let (before, taken, after) = by_rate[i]
    assert_true(taken > before && taken - before <= 2.0 * bw_drag_step, msg="taken at \{rate}: \{before} \{taken}")
    // (where the hand left it all along, 70 opening under 9 to its whole 60)
    assert_true(after.iter().all(fn(r) { r.0 == taken }), msg="held at \{rate} a second: \{taken} \{Repr(after)}")
    assert_eq(after[after.length() - 1].1, taken + rc_tall(9), msg="at \{rate} a second")
    assert_eq(by_rate[i], by_rate[0], msg="at \{rate} a second")
  }
}

///|
test "a page's list at its foot, a block on its way, one over it brought to the top mid-way: there at once, and there all the while the block opens, the same at every rate" {
  let tall = rc_tall(70)
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [rc_at + bw_mid_ms, rc_at + bw_mid_ms + 50.0, ends, ends + 100.0]
  for rate in rc_rates {
    let place = @view.ListPlace::new()
    let c = bw_case(Array::makei(10, fn(i) { i }), place)
    let got = rc_walk(
      c.tree,
      [(rc_at, fn() { c.keys.set(rc_ten_and([70])) }), (rc_at + bw_mid_ms, fn() { place.bring(5) })],
      looks,
      rate,
      fn() { (rc_y(c.tree, "行5"), rc_y(c.tree, "行6")) },
    )
    assert_true(got.iter().all(fn(r) { r == (0.0, 40.0) }), msg="at \{rate} a second: \{Repr(got)}")
  }
}

///|
test "a page's list at its foot, a second block come a quarter of a ms after the first, no frame between: one way with it, as a column's, at rest as one, the same at every rate" {
  let keys = Array::makei(10, fn(i) { i })
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) {
    rc_against_column(keys, 9, [(rc_at, rc_ten_and([70])), (rc_at + 0.25, rc_ten_and([70, 71]))], looks, rate)
  })
  for i, rate in rc_rates {
    let (list, column) = runs[i]
    assert_true(rc_near(list, column), msg="at \{rate} a second, the list \{Repr(list)}, the column \{Repr(column)}")
    assert_eq(rc_turns(list), 0, msg="at \{rate} a second: \{Repr(list)}")
    assert_eq(list, runs[0].0, msg="at \{rate} a second")
  }
  assert_eq(runs[0].0[runs[0].0.length() - 1], rc_tall(70) + rc_tall(71))
}

///|
test "a page's list at its foot, the same block come at different moments between two frames: at rest at its moment and the way's length, to the bit, not before, at every rate" {
  let tall = rc_tall(70)
  let way = @flex.come_way_ms(0.0, 0.0, tall)
  for at in [rc_at, rc_at + 3.3, rc_at + 7.9, rc_at + 12.25] {
    let ends = at + way
    let by_rate = rc_rates.map(fn(rate) {
      let c = rc_case(Array::makei(10, fn(i) { i }))
      rc_walk(c.tree, [(at, fn() { c.keys.set(rc_ten_and([70])) })], [ends - 0.5, ends, ends + 50.0], rate, fn() {
        (rc_y(c.tree, "行9"), rc_y(c.tree, "行70"), c.off_foot())
      })
    })
    for i, rate in rc_rates {
      let got = by_rate[i]
      // (half a ms short: on its way still; at its end and after, there: 70 at its foot, 9 a block up)
      assert_true(got[0].0 > 100.0, msg="come at \{at}, \{rate} a second: \{Repr(got)}")
      assert_eq((got[1], got[2]), ((100.0, 140.0, 0.0), (100.0, 140.0, 0.0)), msg="come at \{at}, \{rate} a second")
      assert_eq(got, by_rate[0], msg="come at \{at}, \{rate} a second")
    }
  }
}

///|
/// How many flex items the frames of a block's way down a page's list of `n` blocks lay out, at its foot, a block come
/// by data at its end, frames 60 a second from its moment to its rest: their sizes worked out, and found kept.
fn bw_way_items(n : Int) -> (Int, Int) {
  let c = rc_case(Array::makei(n, fn(i) { i }))
  let ends = rc_at + @flex.move_most_ms
  let keys = Array::makei(n, fn(i) { i })
  // (one none of them is)
  keys.push(-1)
  // (the change told and the frame of its moment drawn: what that takes is what any list's change takes, not the way's)
  rc_walk(c.tree, [(rc_at, fn() { c.keys.set(keys) })], [rc_at], 0.0, fn() { () }) |> ignore
  let was = (@flex.counters[0], @flex.counters[1])
  let looks = []
  let mut at = rc_at + rc_second / 60.0
  while at <= ends {
    looks.push(at)
    at = at + rc_second / 60.0
  }
  rc_walk(c.tree, [], looks, 0.0, from=rc_at, fn() { () }) |> ignore
  (@flex.counters[0] - was.0, @flex.counters[1] - was.1)
}

///|
test "a page's list's block on its way: its frames lay out as many flex items holding 1,500 blocks as holding 30" {
  assert_eq(bw_way_items(1500), bw_way_items(30))
}

///|
/// Keys 0 to `n` - 1 but `gone`, then `more`.
fn bw_keys(n : Int, gone : Array[Int], more : Array[Int]) -> Array[Int] {
  let all = Array::makei(n, fn(i) { i }).filter(fn(k) { !gone.contains(k) })
  all.append(more)
  all
}

///|
/// The moments the scenes of a change told at once are looked at: its own, on the way a Move would have gone, after.
fn bw_at_once_looks() -> Array[Double] {
  [rc_at, rc_at + 50.0, rc_at + @flex.move_most_ms + 100.0]
}

///|
test "a page's list at its foot, motion reduced: a key come and one gone in sight there and gone in the frame of the change, as at rest, the same at every rate" {
  for rate in rc_rates {
    let c = rc_case(Array::makei(10, fn(i) { i }), reduced=true)
    let got = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(bw_keys(10, [8], [70])) })], bw_at_once_looks(), rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行8"), rc_y(c.tree, "行9"), rc_y(c.tree, "行70"), c.off_foot())
    })
    // (7 at 280, 9 at 320, 70 at 360 of 420, its foot's 200 in sight: 60, 100, 140; 8 gone)
    assert_true(got.iter().all(fn(r) { r == (60.0, rc_none, 100.0, 140.0, 0.0) }), msg="at \{rate} a second: \{Repr(got)}")
  }
}

///|
test "a page's list scrolled up, a key in sight under what is read gone by data: what is over it stays at every moment, what is under it goes up along a Move from the data's moment, the same at every rate" {
  let tall = rc_tall(10)
  let ends = rc_at + @flex.come_way_ms(tall, 0.0, 0.0)
  let looks = [rc_at, rc_at + 16.0, rc_at + 50.0, rc_at + 125.0, ends - 0.5, ends, ends + 100.0]
  // (what is still of it as it closes, at each of those moments)
  let left = looks.map(fn(at) { @flex.come_way(tall, 0.0, 0.0, at - rc_at).0 })
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(Array::makei(20, fn(i) { i }))
    // (300 down: 7 from 20 over the top of what shows, 10 at 100, 11 at 140)
    c.scroll.put(300.0)
    c.tree.frame(390.0, 844.0) |> ignore
    rc_walk(c.tree, [(rc_at, fn() { c.keys.set(bw_keys(20, [10], [])) })], looks, rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行9"), rc_y(c.tree, "行11"))
    })
  })
  for i, rate in rc_rates {
    let got = by_rate[i]
    assert_true(got.iter().all(fn(r) { r.0 == -20.0 && r.1 == 60.0 }), msg="over it at \{rate} a second: \{Repr(got)}")
    assert_true(rc_near(got.map(fn(r) { r.2 - 100.0 }), left), msg="under it at \{rate} a second: \{Repr(got)} for \{Repr(left)}")
    assert_eq(got, by_rate[0], msg="at \{rate} a second")
  }
}

///|
test "a page's list scrolled up, a key out of sight under it gone and one over what is read gone: each at once, what is read where it was at every moment, the same at every rate" {
  for rate in rc_rates {
    let c = rc_case(Array::makei(20, fn(i) { i }))
    c.scroll.put(300.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let got = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(bw_keys(20, [3, 15], [])) })], bw_at_once_looks(), rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行8"), rc_y(c.tree, "行9"), rc_y(c.tree, "行12"))
    })
    assert_true(got.iter().all(fn(r) { r == (-20.0, 20.0, 60.0, 180.0) }), msg="at \{rate} a second: \{Repr(got)}")
  }
}

///|
test "a page's list that says its keys are simply there and simply gone (comes and goes fn(_) { false }): a key come and one gone at its foot, and scrolled up in sight, each in the frame of the change as at rest, the same at every rate" {
  let none = fn(_k : Int) { false }
  for rate in rc_rates {
    // (at its foot: as with motion reduced)
    let c = rc_case(Array::makei(10, fn(i) { i }), comes=none, goes=none)
    let foot = rc_walk(c.tree, [(rc_at, fn() { c.keys.set(bw_keys(10, [8], [70])) })], bw_at_once_looks(), rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行8"), rc_y(c.tree, "行9"), rc_y(c.tree, "行70"), c.off_foot())
    })
    assert_true(foot.iter().all(fn(r) { r == (60.0, rc_none, 100.0, 140.0, 0.0) }), msg="at its foot at \{rate} a second: \{Repr(foot)}")
    // (scrolled up: 100, 60 tall, put in after 9, and 11 taken: 9 where it was, 100 at 100, 10 at 160, 12 out of sight)
    let u = rc_case(Array::makei(20, fn(i) { i }), comes=none, goes=none)
    u.scroll.put(300.0)
    u.tree.frame(390.0, 844.0) |> ignore
    let changed = Array::makei(10, fn(i) { i })
    changed.push(100)
    changed.push(10)
    changed.append(Array::makei(8, fn(i) { i + 12 }))
    let up = rc_walk(u.tree, [(rc_at, fn() { u.keys.set(changed) })], bw_at_once_looks(), rate, fn() {
      (rc_y(u.tree, "行9"), rc_y(u.tree, "行100"), rc_y(u.tree, "行10"), rc_y(u.tree, "行11"))
    })
    assert_true(up.iter().all(fn(r) { r == (60.0, 100.0, 160.0, rc_none) }), msg="scrolled up at \{rate} a second: \{Repr(up)}")
  }
}

///|
test "a page's list that says its keys are simply gone (goes fn(_) { false }) and come as ever: at its foot the gone one at once, the come one on its way, what is above going up with it alone, the same at every rate" {
  let tall = rc_tall(70)
  let ends = rc_at + @flex.come_way_ms(0.0, 0.0, tall)
  let looks = [rc_at, rc_at + 50.0, rc_at + 125.0, ends, ends + 100.0]
  let by_rate = rc_rates.map(fn(rate) {
    let c = rc_case(Array::makei(10, fn(i) { i }), goes=fn(_) { false })
    rc_walk(c.tree, [(rc_at, fn() { c.keys.set(bw_keys(10, [8], [70])) })], looks, rate, fn() {
      (rc_y(c.tree, "行8"), rc_y(c.tree, "行9"), c.off_foot())
    })
  })
  for i, rate in rc_rates {
    let got = by_rate[i]
    for j, at in looks {
      let up = @flex.come_way(0.0, 0.0, tall, at - rc_at).0
      // (8 gone in the frame of the change; 9 at 160 as 70 sets out, up as far as 70's way has got)
      assert_true(got[j].0 == rc_none && (got[j].1 - (160.0 - up)).abs() < 1.0e-6 && got[j].2 == 0.0, msg="at \{at}, \{rate} a second: \{Repr(got)}")
    }
    assert_eq(got, by_rate[0], msg="at \{rate} a second")
  }
}

///|
test "a page's list, a block's button pressed that opens what is under it as a key comes by data over it at that moment: what was pressed stays where it was at every moment, the key opening over it, the same at every rate" {
  let looks = [rc_at, rc_at + 50.0, rc_at + 125.0, rc_at + @flex.move_most_ms, rc_at + @flex.move_most_ms + 100.0]
  let by_rate = rc_rates.map(fn(rate) {
    let now = Ref(0.0)
    let keys = @signals.signal(Array::makei(12, fn(i) { i }), same=fn(a, b) { a == b })
    let opened : Map[Int, @signals.Signal[Bool]] = Map([])
    let buttons : Map[Int, @view.View] = Map([])
    let tree = @view.Tree::new(
      fn(root) {
        root.box(fn(win) {
          win.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
          win.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, fn(b, k) {
            let on = @signals.signal(false, same=fn(a, b) { a == b })
            opened[k] = on
            b.box(fn(p) {
              buttons[k] = p
              p
              .height(Is(Some(40.0)))
              .shrink(Is(0.0))
              .words(Is("行\{k}"))
              .on_press(fn() { on.set(!on.untracked()) })
              .says(By(fn() { Some(@view.said(Button, label="row \{k}", expanded=on.get())) }))
              |> ignore
            })
            |> ignore
            b.box(fn(u) { u.height(By(fn() { Some(if on.get() { 100.0 } else { 0.0 }) })).shrink(Is(0.0)) |> ignore })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      },
      time=fn() { now.val },
    )
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    // (row 3's button pressed at its middle as key 50 is put in after row 0, over it and in sight, under what is read)
    let (x, y, w, h) = buttons[3].rect()
    now.val = rc_at
    tree.at(rc_at)
    tree.press(x + w / 2.0, y + h / 2.0) |> ignore
    let put_in = [0, 50]
    put_in.append(Array::makei(11, fn(i) { i + 1 }))
    let got = rc_walk(tree, [(rc_at, fn() { keys.set(put_in) })], looks, rate, from=rc_at - 1.0, fn() {
      (rc_y(tree, "行3"), rc_y(tree, "行50"))
    })
    (y, got)
  })
  for i, rate in rc_rates {
    let (was, got) = by_rate[i]
    assert_true(got.iter().all(fn(r) { r.0 == was }), msg="pressed at \{rate} a second: \{was} \{Repr(got)}")
    // (at rest, 50 drawn whole over it, all over 3 gone up by its 40: 50's top 40 over 1's, 1 and 2 over 3)
    assert_eq(got[got.length() - 1].1, was - 120.0, msg="at \{rate} a second")
    assert_eq(got, by_rate[0].1, msg="at \{rate} a second")
  }
}
