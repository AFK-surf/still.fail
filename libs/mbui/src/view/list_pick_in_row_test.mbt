// A pick in a row of a page's list (a row's top gap, one box `height(Is(Some(room)))` in the other's place as the room
// changes): the place makes its way from as tall as it was to as tall as it comes to, as the same pick does in a row of
// a plain column, never laid out none on the way, never outside the two; alone, several at one moment, in a list said
// `at_once`, at the moment a key comes at its foot (there in the list's one way), and as the list is given another
// width, between frames or in a room as it is laid out (View::by_room: what a page's list is in). Each looked at every
// 10 ms (rc_walk, from list_rows_come_test), drawn in one jump and at 60, 120, 24 and 7 a second. With the group of what
// comes said before what it comes to is measured (Tree::come_group_settle not waiting for the layout under way), the
// room's case fails at every rate: each gap laid out none all the way, 20 at its end (2026-11-12).

///|
/// How tall a row's mark over its gap is, and its words under it.
let pr_mark : Double = 10.0

///|
let pr_words : Double = 30.0

///|
/// Row `k` made in `r` (a list's block or a column's row): 上k, a pick of a box as tall as `room` says of it at the
/// width `wide` says the rows are given, 行k.
fn pr_row(r : @view.View, k : Int, room : (Int, Double) -> Double, wide : () -> Double) -> Unit {
  r.box(fn(m) { m.height(Is(Some(pr_mark))).words(Is("上\{k}")) |> ignore }) |> ignore
  r.pick(fn() { room(k, wide()) }, fn(g, room) { g.height(Is(Some(room))) |> ignore })
  r.box(fn(w) { w.height(Is(Some(pr_words))).words(Is("行\{k}")) |> ignore }) |> ignore
}

///|
/// How tall row `k`'s gap is laid out, read off its mark and its words as drawn now; rc_none where it is not drawn.
fn pr_gap(t : @view.Tree, k : Int) -> Double {
  let m = rc_y(t, "上\{k}")
  let w = rc_y(t, "行\{k}")
  if m == rc_none || w == rc_none {
    rc_none
  } else {
    w - m - pr_mark
  }
}

///|
/// A page's list `width` wide (300 where none is said) and 600 tall of `keys` at its foot, its rows by pr_row, given
/// that width; `roomed`, made in a room (View::by_room), its rows given the width the room is given as it is laid out
/// (a page's: chat_page_node's). Drawn once, at 0.
fn pr_list(
  keys : Array[Int],
  room : (Int, Double) -> Double,
  at_once? : Bool = false,
  width? : @signals.Signal[Double],
  roomed? : Bool = false,
) -> RcCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o
      .width(By(fn() { Some(pr_width(width)) }))
      .height(Is(Some(600.0)))
      |> ignore
      let list = fn(l : @view.View, wide : () -> Double) {
        l.scrolls_window(scroll, fn() { keys.get() }, est=44.0, follows=fn() { true }, at_once~, fn(b, k) {
          pr_row(b, k, room, wide)
        })
        |> ignore
      }
      if roomed {
        o.by_room(fn(held, r) {
          held.box(fn(l) {
            l.height(Is(Some(600.0))) |> ignore
            list(l, fn() { r.width() })
          })
          |> ignore
        })
        |> ignore
      } else {
        list(o, fn() { pr_width(width) })
      }
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys }
}

///|
/// A plain column of the same rows (pr_row's, by an each), as wide as the list, 下 under them, `roomed` as the list's;
/// drawn once, at 0.
fn pr_column(
  keys : Array[Int],
  room : (Int, Double) -> Double,
  width? : @signals.Signal[Double],
  roomed? : Bool = false,
) -> (@view.Tree, @signals.Signal[Array[Int]]) {
  let keys = @signals.signal(keys, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(By(fn() { Some(pr_width(width)) })) |> ignore
      let rows = fn(c : @view.View, wide : () -> Double) {
        c.each(fn() { keys.get() }, fn(k) { k }, fn(r, k) { pr_row(r, k.get(), room, wide) })
        c.box(fn(b) { b.height(Is(Some(20.0))).words(Is("下")) |> ignore }) |> ignore
      }
      if roomed {
        col.by_room(fn(held, r) { rows(held, fn() { r.width() }) }) |> ignore
      } else {
        rows(col, fn() { pr_width(width) })
      }
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, keys)
}

///|
/// Keys 0 to 13.
fn pr_keys() -> Array[Int] {
  Array::makei(14, fn(i) { i })
}

///|
/// What a scene is made of, built anew for each tree: how tall each row's gap is, and the changes told (its keys, and
/// the list's width where it is given one).
priv struct PrScene {
  room : (Int, Double) -> Double
  events : (@signals.Signal[Array[Int]]) -> Array[(Double, () -> Unit)]
  width : @signals.Signal[Double]?
  roomed : Bool
}

///|
/// A scene's list and column walked to `looks` at `rate`: at each look the gaps of rows `read` (list, column), how far
/// the mark of the first of them in the list has gone down (its foot held) and how far 下 under the column up.
fn pr_against(
  scene : () -> PrScene,
  read : Array[Int],
  looks : Array[Double],
  rate : Double,
  at_once? : Bool = false,
) -> (Array[Array[Double]], Array[Array[Double]], Array[Double], Array[Double]) {
  let s = scene()
  let c = match s.width {
    Some(w) => pr_list(pr_keys(), s.room, at_once~, width=w, roomed=s.roomed)
    None => pr_list(pr_keys(), s.room, at_once~, roomed=s.roomed)
  }
  // (what is over the first row read: down as far as what is under it closes, its foot held)
  let mark = "上\{read[0]}"
  let was = rc_y(c.tree, mark)
  let list = rc_walk(c.tree, (s.events)(c.keys), looks, rate, fn() {
    (read.map(fn(k) { pr_gap(c.tree, k) }), rc_y(c.tree, mark) - was + c.off_foot() * 1.0e6)
  })
  let s2 = scene()
  let (t, ks) = match s2.width {
    Some(w) => pr_column(pr_keys(), s2.room, width=w, roomed=s2.roomed)
    None => pr_column(pr_keys(), s2.room, roomed=s2.roomed)
  }
  let under = rc_y(t, "下")
  let column = rc_walk(t, (s2.events)(ks), looks, rate, fn() {
    (read.map(fn(k) { pr_gap(t, k) }), rc_y(t, "下") - under)
  })
  (list.map(fn(r) { r.0 }), column.map(fn(r) { r.0 }), list.map(fn(r) { r.1 }), column.map(fn(r) { r.1 }))
}

///|
/// The checks of a scene from `from` to `to`, its gaps read at every look: in the list each the column's, within the
/// two (never none on the way), from the one at the first look to the other at the last, one way; what is over them in
/// the list gone down as the column's 下 up, at its foot all the way; the same at every rate as drawn in one jump.
/// `joined`: with a key that comes at the list's foot, the list's one way (Tree::come_group_join), which the plain
/// column, where the key comes down the column and the gap in its row, has not: held to the numbers alone.
fn pr_held(
  name : String,
  scene : () -> PrScene,
  read : Array[Int],
  from : Double,
  to : Double,
  at_once? : Bool = false,
  joined? : Bool = false,
) -> Unit raise {
  let looks = rc_looks(rc_at + @flex.move_most_ms + 100.0)
  let runs = rc_rates.map(fn(rate) { pr_against(scene, read, looks, rate, at_once~) })
  let lo = if from < to { from } else { to }
  let hi = if from < to { to } else { from }
  for i, rate in rc_rates {
    let (list, column, above, under) = runs[i]
    let at = "\{name} \{iw_at(rate)}"
    for j, k in read {
      let gaps = list.map(fn(r) { r[j] })
      let col = column.map(fn(r) { r[j] })
      assert_true(gaps.iter().all(fn(g) { g >= lo - 1.0e-6 && g <= hi + 1.0e-6 }), msg="\{at}, 行\{k}'s gap \{Repr(gaps)}")
      assert_true((gaps[0] - from).abs() < 1.0e-6 && (gaps[gaps.length() - 1] - to).abs() < 1.0e-6, msg="\{at}, 行\{k}'s gap \{Repr(gaps)}")
      assert_eq(rc_turns(gaps), 0, msg="\{at}, 行\{k}'s gap \{Repr(gaps)}")
      if !joined {
        assert_true(rc_near(gaps, col), msg="\{at}, 行\{k}'s gap \{Repr(gaps)}, the column's \{Repr(col)}")
      }
    }
    if !joined {
      let up = under.map(fn(d) { -d })
      assert_true(rc_near(above, up), msg="\{at}, over them \{Repr(above)}, under the column \{Repr(under)}")
    }
    assert_eq(list, runs[0].0, msg=at)
  }
}

///|
/// Rows `rows` with a gap as `g` says, the others 4.
fn pr_room(rows : Array[Int], g : @signals.Signal[Double]) -> (Int, Double) -> Double {
  fn(k, _) { if rows.contains(k) { g.get() } else { 4.0 } }
}

///|
/// Rows `rows`' gaps from `from` to `to` at rc_at, and with that what `also` does to the keys.
fn pr_gaps(
  rows : Array[Int],
  from : Double,
  to : Double,
  also? : (@signals.Signal[Array[Int]]) -> Unit = fn(_) {  },
) -> () -> PrScene {
  fn() {
    let g = @signals.signal(from)
    {
      room: pr_room(rows, g),
      events: fn(ks) { [(rc_at, iw_both(fn() { g.set(to) }, fn() { also(ks) }))] },
      width: None,
      roomed: false,
    }
  }
}

///|
test "a page's list at its foot, the last row's gap a pick from 4 to 20: the place goes from 4 tall to 20 as a column's, never none, the same at every rate" {
  pr_held("4 to 20", pr_gaps([13], 4.0, 20.0), [13], 4.0, 20.0)
}

///|
test "a page's list at its foot, the last row's gap a pick from 28 to 20: the place goes from 28 tall to 20 as a column's, never none, the same at every rate" {
  pr_held("28 to 20", pr_gaps([13], 28.0, 20.0), [13], 28.0, 20.0)
}

///|
test "a page's list at its foot, seven rows' gaps picks from 28 to 20 at one moment: each place goes from 28 to 20 as a column's, what is over them going down 56 one way, the same at every rate" {
  let rows = Array::makei(7, fn(i) { i + 7 })
  pr_held("seven", pr_gaps(rows, 28.0, 20.0), rows, 28.0, 20.0)
}

///|
test "a page's list said at_once, seven rows' gaps picks from 28 to 20 at one moment: each place its own way from 28 to 20 as a column's, the same at every rate" {
  let rows = Array::makei(7, fn(i) { i + 7 })
  pr_held("at_once", pr_gaps(rows, 28.0, 20.0), rows, 28.0, 20.0, at_once=true)
}

///|
test "a page's list at its foot, the last row's gap a pick from 28 to 20 as a key comes under it: the place from 28 to 20 in the list's one way, never none, the same at every rate" {
  let then = pr_keys()
  then.push(71)
  pr_held("with a key", pr_gaps([13], 28.0, 20.0, also=fn(ks) { ks.set(then) }), [13], 28.0, 20.0, joined=true)
}

///|
/// Rows `rows`' gaps picked by the width the rows are given (28 at 290 and wider, 20 narrower), the others 4; the list
/// given 280 for 300 at rc_at, `roomed` as pr_list's.
fn pr_by_width(rows : Array[Int], roomed : Bool) -> () -> PrScene {
  fn() {
    let w = @signals.signal(300.0)
    {
      room: fn(k, wide) { if rows.contains(k) { if wide < 290.0 { 20.0 } else { 28.0 } } else { 4.0 } },
      events: fn(_) { [(rc_at, fn() { w.set(280.0) })] },
      width: Some(w),
      roomed,
    }
  }
}

///|
test "a page's list at its foot given another width, its rows' gaps picked by the width (28 wide, 20 narrow): each place as a column's given the same width, a way as any pick's" {
  let rows = Array::makei(7, fn(i) { i + 7 })
  pr_held("by its width", pr_by_width(rows, false), rows, 28.0, 20.0)
}

///|
test "a page's list in a room given another width, its rows' gaps picked by the width it is given there as it is laid out (View::by_room): each place from 28 to 20 as a column's in the same room, never none, the same at every rate" {
  // (the group of what comes set off in the middle of that layout: said once that layout has measured what it comes
  // to, never of heights not known yet; else each laid out none all the way and all of it at its end)
  let rows = Array::makei(7, fn(i) { i + 7 })
  pr_held("in a room", pr_by_width(rows, true), rows, 28.0, 20.0)
}

///|
/// How wide `width` says, 300 where none is said.
fn pr_width(width : @signals.Signal[Double]?) -> Double {
  match width {
    Some(w) => w.get()
    None => 300.0
  }
}
