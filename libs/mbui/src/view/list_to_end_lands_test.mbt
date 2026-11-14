// A page's list asked back to its foot (ListPlace::to_end) ends at its foot as its foot is when it gets there: read up,
// the ask in the change a key comes at its end (counted at its estimate then, measured taller as it comes to show)
// and its pinned foot shrinks or grows on its way, the list glides on to where its end is now, place and speed going
// on where the end moves (no step, no stop and start again), down only, never past its end; at rest at its foot and
// following it from there (`follows`). The hand taking it on the way ends it where the hand leaves it. Asked at once
// (glide=false) in a layout that cannot make the rows that show there, or with a key on its way at its end, it is at
// its end once it can be (the chat's page made as nodes, words sent read up: the coordinator of the migration,
// 2026-11-14). Each scene looked at at moments it declares (rc_walk), in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall what shows of the list is; how many keys it has at first (each 40 tall, as counted); the key that comes
/// (the words sent), counted at 40 as it comes; where the list is read from (its top at that key's).
let lte_shows : Double = 200.0

///|
let lte_count : Int = 30

///|
let lte_sent : Int = 30

///|
let lte_read : Int = 18

///|
/// When the list is read up (the ask that puts it there), before rc_at.
let lte_read_at : Double = 20.0

///|
priv struct LteCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  foot : @signals.Signal[Double]
  foot_box : Ref[@view.View?]
  place : @view.ListPlace[Int]
}

///|
/// The list 300 by lte_shows of lte_count keys 40 tall (words 行k), the key lte_sent `sent_h` tall (counted at 40 till
/// it is measured), a pinned foot `foot` tall (words 脚), following its foot where `follows`; drawn at 0, then read
/// up: key lte_read brought to its top at lte_read_at.
fn lte_case(sent_h : Double, foot : Double, follows? : Bool = true) -> LteCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let keys = @signals.signal(Array::makei(lte_count, fn(i) { i }), same=fn(a, b) { a == b })
  let foot_h = @signals.signal(foot, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(lte_shows))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { follows },
        place~,
        foot=fn(f) {
          f.box(fn(b) {
            foot_box.val = Some(b)
            b.height(By(fn() { Some(foot_h.get()) })).shrink(Is(0.0)).words(Is("脚")) |> ignore
          })
          |> ignore
        },
        fn(b, k) {
          b.height(Is(Some(if k == lte_sent { sent_h } else { 40.0 }))).words(Is("行\{k}")) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  tree.event(lte_read_at, fn() { place.bring(lte_read) })
  tree.at(lte_read_at)
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, foot: foot_h, foot_box, place }
}

///|
/// Key `k` come at the end of case `c`'s keys.
fn LteCase::comes(self : LteCase, k : Int) -> Unit {
  self.keys.set(self.keys.untracked() + [k])
}

///|
/// The words sent (key lte_sent) come at its end, its pinned foot declared to resize to `foot_to` (where said), and the
/// list asked back to its foot, gliding: all in one change.
fn LteCase::sent(self : LteCase, foot_to? : Double) -> Unit {
  match foot_to {
    Some(f) => {
      self.foot_box.val.unwrap().resizes() |> ignore
      self.foot.set(f)
    }
    None => ()
  }
  self.comes(lte_sent)
  self.place.to_end()
}

///|
/// What is looked at: how far it is scrolled, whether it is at its foot (Scroll::at_foot_now), and how far the last
/// block's foot (key `last`, `h` tall) is drawn from the pinned foot's top (rc_none where it is not drawn).
priv struct LteSeen {
  x : Double
  at_foot : Bool
  last_off : Double
}

///|
fn LteCase::seen(self : LteCase, last : Int, h : Double) -> LteSeen {
  let y = rc_y(self.tree, "行\{last}")
  let foot = rc_y(self.tree, "脚")
  {
    x: self.scroll.at(self.tree),
    at_foot: self.scroll.at_foot_now(),
    last_off: if y == rc_none || foot == rc_none { rc_none } else { foot - (y + h) },
  }
}

///|
/// The glide of `seen` (looks rc_look_ms apart from the ask on): down only; once under way (a step of more than half a
/// point, its first two steps past), no step more than twice either step round it, to half a point, so it neither jumps
/// nor stops at once; never past where it comes to rest.
fn lte_glided(seen : Array[LteSeen], what : String) -> Unit raise {
  let xs = seen.map(fn(s) { s.x })
  for i in 1..<xs.length() {
    assert_true(xs[i] >= xs[i - 1] - 0.01, msg="\{what}, look \{i}: up again, \{xs[i - 1]} to \{xs[i]}")
  }
  let rest = xs[xs.length() - 1]
  for i, x in xs {
    assert_true(x <= rest + 0.01, msg="\{what}, look \{i}: at \{x}, past where it rests (\{rest})")
  }
  let steps = Array::makei(xs.length() - 1, fn(i) { xs[i + 1] - xs[i] })
  let mut under_way = -1
  for i, d in steps {
    if under_way < 0 && d > 0.5 {
      under_way = i
    }
  }
  guard under_way >= 0 else { fail("\{what}: it never moved: \{Repr(xs)}") }
  for i in (under_way + 2)..<(steps.length() - 1) {
    let d = steps[i]
    guard d > 0.5 else { continue }
    assert_true(
      d <= 2.0 * steps[i - 1] + 0.5 && d <= 2.0 * steps[i + 1] + 0.5,
      msg="\{what}, look \{i + 1}: a step of \{d} between \{steps[i - 1]} and \{steps[i + 1]}: \{Repr(steps)}",
    )
  }
}

///|
/// At rest at its foot: at its foot as the list tells it, its last block's foot on the pinned foot's top.
fn lte_at_foot(s : LteSeen, what : String) -> Unit raise {
  assert_true(s.at_foot, msg="\{what}: not at its foot (at \{s.x})")
  assert_true(s.last_off != rc_none && s.last_off.abs() < 0.5, msg="\{what}: its last block's foot \{s.last_off} off the pinned foot's top")
}

///|
/// Case `c` walked from the ask (`ask`, at rc_at) to rest, then a key come at rc_at + 1000 and walked on: the looks of the
/// glide, and the last after the key came. `more`: events on the way.
fn lte_walk(
  c : LteCase,
  rate : Double,
  ask : () -> Unit,
  sent_h : Double,
  more? : Array[(Double, () -> Unit)] = [],
  looks? : Array[Double] = rc_looks(rc_at + 900.0),
  last? : (Int, Double) = (lte_sent, sent_h),
) -> (Array[LteSeen], LteSeen) {
  let events = [(rc_at, ask)]
  events.append(more)
  let seen = rc_walk(c.tree, events, looks, rate, from=lte_read_at, fn() { c.seen(last.0, last.1) })
  let after = rc_walk(
    c.tree,
    [(rc_at + 1000.0, fn() { c.comes(lte_sent + 10) })],
    [rc_at + 1000.0, rc_at + 1500.0],
    rate,
    from=looks[looks.length() - 1],
    fn() { c.seen(lte_sent + 10, 40.0) },
  )
  (seen, after[after.length() - 1])
}

///|
test "read up, words sent counted at 40 and measured 160, the pinned foot shrinking 60 to 10 in the same change, asked back to its foot: down only, on to where its end is now, at rest at its foot, what comes after followed" {
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(160.0, 60.0)
    let (seen, after) = lte_walk(c, rate, fn() { c.sent(foot_to=10.0) }, 160.0)
    lte_glided(seen, what)
    lte_at_foot(seen[seen.length() - 1], what)
    lte_at_foot(after, "\{what}, a key come after")
  }
}

///|
test "the same, the pinned foot growing 60 to 100: on to its end, at rest at its foot, followed" {
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(160.0, 60.0)
    let (seen, after) = lte_walk(c, rate, fn() { c.sent(foot_to=100.0) }, 160.0)
    lte_glided(seen, what)
    lte_at_foot(seen[seen.length() - 1], what)
    lte_at_foot(after, "\{what}, a key come after")
  }
}

///|
test "the same, the words sent as tall as counted and the foot shrinking 60 to 10: its end nearer than asked, never past it, at rest at its foot" {
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(40.0, 60.0)
    let (seen, after) = lte_walk(c, rate, fn() { c.sent(foot_to=10.0) }, 40.0)
    for i, s in seen {
      // (past its end: its last block's foot over the pinned foot's top)
      assert_true(s.last_off == rc_none || s.last_off <= 0.01, msg="\{what}, look \{i}: past its end by \{s.last_off}")
    }
    lte_at_foot(seen[seen.length() - 1], what)
    lte_at_foot(after, "\{what}, a key come after")
  }
}

///|
test "the end moving twice on the way (the words sent measured taller, another key come at once out of sight): place and speed going on where it moves, at rest at its foot" {
  // (on the looks' grid, between two frames at every rate here)
  let moved_at = rc_at + 40.0
  let d = 0.25
  let looks = rc_looks(rc_at + 900.0)
  looks.append([moved_at - d, moved_at + d])
  looks.sort()
  let mut i0 = 0
  while looks[i0] < moved_at - d {
    i0 = i0 + 1
  }
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(160.0, 60.0)
    let (seen, after) = lte_walk(
      c,
      rate,
      fn() { c.sent() },
      160.0,
      more=[(moved_at, fn() { c.comes(lte_sent + 1) })],
      looks~,
      last=(lte_sent + 1, 40.0),
    )
    let before = seen[i0 + 1].x - seen[i0].x
    let then = seen[i0 + 2].x - seen[i0 + 1].x
    assert_true(before > 0.1, msg="\{what}: not on its way as its end moved (\{before} in \{d} ms)")
    assert_true(
      (then - before).abs() < 0.06,
      msg="\{what}: \{before} in the \{d} ms before its end moved, \{then} in those after",
    )
    // (the two looks a quarter of a ms round the moment left out of the steps of 10 ms)
    let kept = []
    for i, s in seen {
      if i != i0 && i != i0 + 2 {
        kept.push(s)
      }
    }
    lte_glided(kept, what)
    lte_at_foot(seen[seen.length() - 1], what)
    lte_at_foot(after, "\{what}, a key come after")
  }
}

///|
test "the hand taking the list on its way (a finger down and let go where it went down): where the hand left it from then, not at its foot, its end moving after" {
  let down_at = rc_at + 60.5
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(160.0, 60.0)
    rc_walk(c.tree, [(rc_at, fn() { c.sent(foot_to=10.0) })], [down_at - 0.5], rate, from=lte_read_at, fn() { () })
    |> ignore
    let id = c.tree.claimer_of(c.tree.claimers_at(150.0, 50.0), 0.0, 20.0).unwrap()
    c.tree.at(down_at)
    c.tree.drag_at(id, Down, 150.0, 50.0, down_at) |> ignore
    c.tree.frame(390.0, 844.0) |> ignore
    let held = c.scroll.at(c.tree)
    c.tree.at(down_at + 10.0)
    c.tree.drag_at(id, Up, 150.0, 50.0, down_at + 10.0) |> ignore
    c.tree.frame(390.0, 844.0) |> ignore
    let seen = rc_walk(
      c.tree,
      [(rc_at + 400.0, fn() { c.comes(lte_sent + 1) })],
      rc_looks(rc_at + 900.0).filter(fn(t) { t > down_at + 10.0 }),
      rate,
      from=down_at + 10.0,
      fn() { c.seen(lte_sent + 1, 40.0) },
    )
    for i, s in seen {
      assert_true((s.x - held).abs() < 0.01, msg="\{what}, look \{i}: at \{s.x}, the hand left it at \{held}")
    }
    assert_false(seen[seen.length() - 1].at_foot, msg="\{what}: at its foot, the hand having left it above")
  }
}

///|
test "asked at once (glide=false) as the list is made in a change that lays it out as it is made, its blocks there other heights than counted, not following its foot: at its foot from the first frame that draws it, and at rest" {
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let scroll = @view.Scroll::list()
    let place : @view.ListPlace[Int] = @view.ListPlace::new()
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(lte_shows))) |> ignore
        o.show(fn() { on.get() }, fn(v) {
          v.height(Is(Some(lte_shows))) |> ignore
          place.to_end(glide=false)
          v.box(fn(l) {
            l.height(Is(Some(lte_shows))) |> ignore
            l.scrolls_window(
              scroll,
              fn() { Array::makei(lte_count, fn(i) { i }) },
              est=40.0,
              place~,
              foot=fn(f) { f.box(fn(b) { b.height(Is(Some(30.0))).shrink(Is(0.0)).words(Is("脚")) |> ignore }) |> ignore },
              fn(b, k) {
                b.height(Is(Some(if k >= lte_count - 6 { 73.3 } else { 40.0 }))).words(Is("行\{k}")) |> ignore
              },
            )
            |> ignore
          })
          |> ignore
          // (where it is laid out, read as it is made: a layout in this change, its blocks not made in it)
          v.laid_window_now() |> ignore
        })
      })
      |> ignore
    })
    tree.frame(390.0, 844.0) |> ignore
    let seen = rc_walk(tree, [(rc_at, fn() { on.set(true) })], [rc_at, rc_at + 1000.0], rate, fn() {
      let y = rc_y(tree, "行\{lte_count - 1}")
      let foot = rc_y(tree, "脚")
      if y == rc_none || foot == rc_none {
        rc_none
      } else {
        foot - (y + 73.3)
      }
    })
    for i, off in seen {
      assert_true(off != rc_none && off.abs() < 0.5, msg="\{what}, look \{i}: its last block's foot \{off} off the pinned foot's top")
    }
  }
}

///|
test "asked at once (glide=false) at its end, not following its foot, in the change a key comes there on its way: at its foot as that way ends" {
  for rate in rc_rates {
    let what = "at \{rate} a second"
    let c = lte_case(160.0, 60.0, follows=false)
    rc_walk(c.tree, [(lte_read_at + 10.0, fn() { c.place.to_end(glide=false) })], [lte_read_at + 20.0], rate, from=lte_read_at, fn() {
      ()
    })
    |> ignore
    let seen = rc_walk(
      c.tree,
      [(rc_at, fn() {
        c.comes(lte_sent)
        c.place.to_end(glide=false)
      })],
      [rc_at + 1000.0],
      rate,
      from=lte_read_at + 20.0,
      fn() { c.seen(lte_sent, 160.0) },
    )
    let s = seen[0]
    assert_true(s.last_off != rc_none && s.last_off.abs() < 0.5, msg="\{what}: the key's foot \{s.last_off} off the pinned foot's top")
  }
}
