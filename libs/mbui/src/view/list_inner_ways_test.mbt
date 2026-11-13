// What a page's list's block holds that comes or goes by its own structures (a show, a pick in a row) makes its way in
// the list's one way (View::scrolls_window, flex's ComeGroup): at a moment when a row comes or goes down the list too, or
// another block changes inside, all of it goes one way, as a plain column holding the same changes as its items does,
// from the moment of the change, whatever frames are drawn; one alone its own way, as ever; a list said `at_once`
// as it was, each block's inside its own way. Each scene looked at at moments it declares (rc_walk, from
// list_rows_come_test), drawn in one jump and at 60, 120, 24 and 7 a second.
// Its sizes are chosen so that one way is told from two (move_ms goes by 50 ms: 300 and 150 against a row's 40): with
// the list's blocks joined to nothing (its held column's list_joins_inner left out), the scenes of one, two, three and
// five fail at every rate; those of four (one alone), six (its gap made with its block: one that moves) and seven (said
// at_once) pass either way, as they must (2026-11-12).

///|
/// How tall what opens in a block is (things under a post): 300, so far that its way alone is longer than a row's of
/// 40 (move_ms: 350 against 250), and one way for both is told from each its own; the other block's in the scene of
/// two, 20; what opens in a block under what is read, 150 (300 ms against a row's 250); a card open and answered: 400
/// and 40 (its 360 a Move of 350 ms, a row's way of 44 or 70 one of 250); the gap over a block's words: 16.
let iw_open : Double = 300.0

///|
let iw_other : Double = 20.0

///|
let iw_card_open : Double = 400.0

///|
let iw_card_done : Double = 40.0

///|
let iw_mid : Double = 150.0

///|
let iw_gap : Double = 16.0

///|
/// What each block of a scene holds under its words, by its key: what opens as `on` says (a show), a card (a pick of
/// open and answered), a gap over its words (a pick of none or the gap), or nothing.
priv enum IwInner {
  Opens(Double, @signals.Signal[Bool])
  Card(@signals.Signal[Bool])
  Gap(@signals.Signal[Bool])
  Nothing
}

///|
/// Block `k` made in `b` (a list's block or a column's row): its words 行k as tall as rc_tall says, what `inner` gives
/// it (the gap over the words, else under them).
fn iw_block(b : @view.View, k : Int, inner : IwInner) -> Unit {
  let words = fn(b : @view.View) {
    b.box(fn(w) { w.height(Is(Some(rc_tall(k)))).words(Is("行\{k}")) |> ignore }) |> ignore
  }
  match inner {
    Gap(on) => {
      b.pick(fn() { on.get() }, fn(s, on) { s.height(Is(Some(if on { iw_gap } else { 0.0 }))) |> ignore })
      words(b)
    }
    Opens(h, on) => {
      words(b)
      b.show(fn() { on.get() }, fn(s) { s.height(Is(Some(h))) |> ignore })
    }
    Card(open) => {
      words(b)
      b.pick(fn() { open.get() }, fn(s, open) {
        s.height(Is(Some(if open { iw_card_open } else { iw_card_done }))) |> ignore
      })
    }
    Nothing => words(b)
  }
}

///|
/// A page's list 300 by `tall` of `keys` following its foot (rc_case's), each block made by iw_block with what `inner`
/// says of its key; `at_once`, `from_end` as View::scrolls_window's. Drawn once, at 0.
fn iw_list(
  keys : Array[Int],
  inner : (Int) -> IwInner,
  at_once? : Bool = false,
  from_end? : Bool = false,
  tall? : Double = 200.0,
) -> RcCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(tall))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, at_once~, from_end~, fn(b, k) {
        iw_block(b, k, inner(k))
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys }
}

///|
/// A plain column of the same blocks by `keys`, but what each of those there at first holds that opens or closes (a
/// show, a card) put in the column itself after them, every item down one column (where in it moves 下 none the less);
/// a gap over a block's words, made with it, in its row. Under them 下. Drawn once, at 0.
fn iw_column(keys : Array[Int], inner : (Int) -> IwInner) -> (@view.Tree, @signals.Signal[Array[Int]]) {
  let first = keys.copy()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.each(fn() { keys.get() }, fn(k) { k }, fn(r, k) {
        let k = k.get()
        iw_block(r, k, match inner(k) {
          Gap(_) as g => g
          _ => Nothing
        })
      })
      for k in first {
        match inner(k) {
          Gap(_) | Nothing => ()
          other => iw_block_inside(col, other)
        }
      }
      col.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys)
}

///|
/// What `inner` opens or closes, made in `col` by itself (iw_block's, without its words).
fn iw_block_inside(col : @view.View, inner : IwInner) -> Unit {
  match inner {
    Opens(h, on) => col.show(fn() { on.get() }, fn(s) { s.height(Is(Some(h))) |> ignore })
    Card(open) =>
      col.pick(fn() { open.get() }, fn(s, open) {
        s.height(Is(Some(if open { iw_card_open } else { iw_card_done }))) |> ignore
      })
    _ => ()
  }
}

///|
/// Both of `a` told as one change (what a page's data says at one moment).
fn iw_both(a : () -> Unit, b : () -> Unit) -> () -> Unit {
  fn() {
    @signals.start_batch()
    a()
    b()
    @signals.end_batch()
  }
}

///|
/// A scene's list and column walked to `looks` at `rate`, each told the changes `events` makes of its own signals and
/// keys (built anew for each): how far the list at its foot has gone down what it holds (what is over its foot gone up
/// as far, out of sight or not), and how far 下 under the column down.
fn iw_against(
  keys : Array[Int],
  scene : () -> ((Int) -> IwInner, (@signals.Signal[Array[Int]], (Int) -> IwInner) -> Array[(Double, () -> Unit)]),
  looks : Array[Double],
  rate : Double,
) -> (Array[Double], Array[Double]) {
  let (inner, events) = scene()
  let c = iw_list(keys, inner)
  let was = c.scroll.at(c.tree)
  // (at its foot all the while: off it, what it reads is how far it was scrolled away, not its foot's)
  let list = rc_walk(c.tree, events(c.keys, inner), looks, rate, fn() {
    c.scroll.at(c.tree) - was + c.off_foot() * 1.0e6
  })
  let (inner2, events2) = scene()
  let (t, ks) = iw_column(keys, inner2)
  let under = rc_y(t, "下")
  let column = rc_walk(t, events2(ks, inner2), looks, rate, fn() { rc_y(t, "下") - under })
  (list, column)
}

///|
/// What opens in block 9 as `on` says (a show), the others nothing.
fn iw_nine_opens(on : @signals.Signal[Bool]) -> (Int) -> IwInner {
  fn(k) { if k == 9 { Opens(iw_open, on) } else { Nothing } }
}

///|
/// The way's name in a message: at what rate.
fn iw_at(rate : Double) -> String {
  "at \{rate} a second"
}

///|
/// The checks of a scene held to its column: the same within 1e-6, one way (turning back at most `turns` times), the
/// same at every rate as drawn in one jump; what it comes to at rest.
fn iw_held(runs : Array[(Array[Double], Array[Double])], turns : Int) -> Double raise {
  for i, rate in rc_rates {
    let (list, column) = runs[i]
    assert_true(rc_near(list, column), msg="\{iw_at(rate)}, the list \{Repr(list)}, the column \{Repr(column)}")
    assert_true(rc_turns(list) <= turns, msg="\{iw_at(rate)}: \{Repr(list)}")
    assert_eq(list, runs[0].0, msg=iw_at(rate))
  }
  runs[0].0[runs[0].0.length() - 1]
}

///|
test "a page's list at its foot, its last block opening 300 inside as a key 40 tall comes under it: one way as a column's two items, what is above going up one way only, at its foot all the way, the same at every rate" {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) {
    iw_scene_one(Array::makei(10, fn(i) { i }), looks, rate)
  })
  let rest = iw_held(runs, 0)
  assert_eq(rest, iw_open + rc_tall(71))
}

///|
/// Scene one: block 9 opens 30 and key 71 comes under it, at rc_at as one change.
fn iw_scene_one(keys : Array[Int], looks : Array[Double], rate : Double) -> (Array[Double], Array[Double]) {
  iw_against(
    keys,
    fn() {
      let on = @signals.signal(false)
      (iw_nine_opens(on), fn(ks, _) {
        [(rc_at, iw_both(fn() { on.set(true) }, fn() { ks.set(rc_ten_and([71])) }))]
      })
    },
    looks,
    rate,
  )
}

///|
test "a page's list at its foot, a block's card closing 400 to 40 as a working row goes and its answer comes: one way, what is above going one way only, the same at every rate" {
  let keys = Array::makei(10, fn(i) { i })
  keys.push(50)
  let then = Array::makei(10, fn(i) { i })
  then.push(51)
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) {
    iw_against(
      keys,
      fn() {
        let open = @signals.signal(true)
        (fn(k) { if k == 9 { Card(open) } else { Nothing } }, fn(ks, _) {
          [(rc_at, iw_both(fn() { open.set(false) }, fn() { ks.set(then) }))]
        })
      },
      looks,
      rate,
    )
  })
  let rest = iw_held(runs, 0)
  assert_eq(rest, iw_card_done - iw_card_open + rc_tall(51) - rc_tall(50))
}

///|
test "a page's list at its foot, a block opening inside, still on its way as a key comes: joined from that moment, place and speed going on, one way as a column's, the same at every rate" {
  let looks = rc_looks(rc_at + rc_again_ms + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) {
    iw_against(
      Array::makei(10, fn(i) { i }),
      fn() {
        let on = @signals.signal(false)
        (iw_nine_opens(on), fn(ks, _) {
          [(rc_at, fn() { on.set(true) }), (rc_at + rc_again_ms, fn() { ks.set(rc_ten_and([71])) })]
        })
      },
      looks,
      rate,
    )
  })
  let rest = iw_held(runs, 0)
  assert_eq(rest, iw_open + rc_tall(71))
}

///|
test "a page's list at its foot, a block opening inside alone: its own way, as a plain column's single way, the same at every rate" {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let want = looks.map(fn(at) { @flex.come_way(0.0, 0.0, iw_open, at - rc_at).0 })
  let runs = rc_rates.map(fn(rate) {
    iw_against(
      Array::makei(10, fn(i) { i }),
      fn() {
        let on = @signals.signal(false)
        (iw_nine_opens(on), fn(_, _) { [(rc_at, fn() { on.set(true) })] })
      },
      looks,
      rate,
    )
  })
  iw_held(runs, 0) |> ignore
  assert_true(rc_near(runs[0].0, want), msg="the list \{Repr(runs[0].0)}, a Move alone \{Repr(want)}")
}

///|
test "a page's list scrolled up, a block in sight under what is read opening inside as a key is put in within sight: what is read stays at every moment, what is under them moves down one way, as a column's, the same at every rate" {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let keys = Array::makei(30, fn(i) { i })
  // (100, 60 tall, put in after 9; block 8 opening 150 under its words; 600 tall, so all of it in sight)
  let put_in = Array::makei(10, fn(i) { i })
  put_in.push(100)
  put_in.append(Array::makei(20, fn(i) { i + 10 }))
  let by_rate = rc_rates.map(fn(rate) {
    let on = @signals.signal(false)
    let inner = fn(k) { if k == 8 { Opens(iw_mid, on) } else { Nothing } }
    let c = iw_list(keys, inner, tall=600.0)
    // (300 down: 7 from 20 over the top of what shows, 8 at 20, 9 at 60, 10 at 100)
    c.scroll.put(300.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let was10 = rc_y(c.tree, "行10")
    let list = rc_walk(c.tree, [(rc_at, iw_both(fn() { on.set(true) }, fn() { c.keys.set(put_in) }))], looks, rate, fn() {
      (rc_y(c.tree, "行7"), rc_y(c.tree, "行10") - was10)
    })
    let on2 = @signals.signal(false)
    let inner2 = fn(k) { if k == 8 { Opens(iw_mid, on2) } else { Nothing } }
    let (t, ks) = iw_column(keys, inner2)
    let under = rc_y(t, "下")
    let column = rc_walk(t, [(rc_at, iw_both(fn() { on2.set(true) }, fn() { ks.set(put_in) }))], looks, rate, fn() {
      rc_y(t, "下") - under
    })
    (list, column)
  })
  for i, rate in rc_rates {
    let (list, column) = by_rate[i]
    assert_true(list.iter().all(fn(r) { r.0 == -20.0 }), msg="what is read \{iw_at(rate)}: \{Repr(list)}")
    let moved = list.map(fn(r) { r.1 })
    assert_true(rc_near(moved, column), msg="under them \{iw_at(rate)}: \{Repr(moved)}, the column \{Repr(column)}")
    assert_eq(rc_turns(moved), 0, msg=iw_at(rate))
    assert_eq(list, by_rate[0].0, msg=iw_at(rate))
  }
  assert_eq(by_rate[0].0[by_rate[0].0.length() - 1].1, iw_mid + rc_tall(100))
}

///|
test "a page's list said from_end holding nothing, its first key come, its block holding a gap over its words: opening from the data's moment, as a column's row, at its foot all the way, the same at every rate" {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let by_rate = rc_rates.map(fn(rate) {
    let gap = @signals.signal(true)
    let c = iw_list([], fn(_) { Gap(gap) }, from_end=true)
    // (how tall its block is, read off its words' top at the foot of 200: the gap over them)
    let list = rc_walk(c.tree, [(rc_at, fn() { c.keys.set([0]) })], looks, rate, fn() {
      let y = rc_y(c.tree, "行0")
      (if y == rc_none { 0.0 } else { 200.0 - (y - iw_gap) }, c.off_foot())
    })
    let gap2 = @signals.signal(true)
    let (t, ks) = iw_column([], fn(_) { Gap(gap2) })
    let under = rc_y(t, "下")
    let column = rc_walk(t, [(rc_at, fn() { ks.set([0]) })], looks, rate, fn() { rc_y(t, "下") - under })
    (list, column)
  })
  for i, rate in rc_rates {
    let (list, column) = by_rate[i]
    let tall = list.map(fn(r) { r.0 })
    assert_true(rc_near(tall, column), msg="\{iw_at(rate)}: \{Repr(tall)}, the column \{Repr(column)}")
    assert_true(list.iter().all(fn(r) { r.1 == 0.0 }), msg="at its foot \{iw_at(rate)}")
    assert_eq(list, by_rate[0].0, msg=iw_at(rate))
  }
  assert_eq(by_rate[0].0[by_rate[0].0.length() - 1].0, iw_gap + rc_tall(0))
}

///|
test "a page's list said at_once: two blocks opening inside at one moment each go their own way, as before; a key come and one gone there and gone in the frame of the change, the same at every rate" {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  // (each its own Move, from its own moment: the two summed)
  let want = looks.map(fn(at) {
    @flex.come_way(0.0, 0.0, iw_open, at - rc_at).0 + @flex.come_way(0.0, 0.0, iw_other, at - rc_at).0
  })
  for rate in rc_rates {
    let a = @signals.signal(false)
    let b = @signals.signal(false)
    let inner = fn(k) {
      if k == 8 {
        Opens(iw_open, a)
      } else if k == 9 {
        Opens(iw_other, b)
      } else {
        Nothing
      }
    }
    let c = iw_list(Array::makei(10, fn(i) { i }), inner, at_once=true)
    let was = c.scroll.at(c.tree)
    let got = rc_walk(c.tree, [(rc_at, iw_both(fn() { a.set(true) }, fn() { b.set(true) }))], looks, rate, fn() {
      c.scroll.at(c.tree) - was
    })
    assert_true(rc_near(got, want), msg="\{iw_at(rate)}: \{Repr(got)} for \{Repr(want)}")
    // (then 6 gone and 71 come: there and gone at once, its last at its foot)
    let at = looks[looks.length() - 1] + 100.0
    let keys = Array::makei(10, fn(i) { i }).filter(fn(k) { k != 6 })
    keys.push(71)
    let after = rc_walk(c.tree, [(at, fn() { c.keys.set(keys) })], [at, at + 100.0], rate, from=looks[looks.length() - 1], fn() {
      (rc_y(c.tree, "行6"), rc_y(c.tree, "行71"), c.off_foot())
    })
    assert_true(after.iter().all(fn(r) { r == (rc_none, 160.0, 0.0) }), msg="come and gone \{iw_at(rate)}: \{Repr(after)}")
  }
}
