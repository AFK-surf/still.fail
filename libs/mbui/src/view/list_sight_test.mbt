// What a page's list has in sight, told to handlers (ListPlace::on_sight, ListPlace::sight_now): told once after its
// first layout, then only at the moments the hand is found again (an input, a glide's or a way's end that moved what
// shows, a change of data at rest), each time what is told differs, never on a frame as a glide or a way goes; counted
// by its keys' blocks, its head and its foot never the first nor the last; and telling it lays out and measures nothing.
// Each held to what is drawn (sg_seen: where its blocks' words are), in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall each block is, and how tall what shows of the list is.
let sg_tall : Double = 40.0

///|
let sg_shows : Double = 200.0

///|
priv struct SgCase {
  tree : @view.Tree
  scroll : @view.Scroll
  place : @view.ListPlace[Int]
  keys : @signals.Signal[Array[Int]]
  /// each sight told, in order, with the moment of the cause it was told in (Tree::moment; -1 in none)
  told : Array[(Double, @view.Sight[Int])]
  /// what a press on a block read of it in its handler (ListPlace::sight_now)
  pressed : Ref[@view.Sight[Int]?]
  foot : Double
}

///|
/// A page's list 300 by 200 of `n` blocks 40 tall (words 行k at each one's top, the whole block pressed), following
/// its foot where `follows`; a head and a foot as tall as `head` and `foot` where they are more than 0; `cover` of its
/// top covered (View::scrolls_window's `top_covered`: a bar it runs under); told what is in sight where `listens`.
/// Drawn once, at 0.
fn sg_case(
  n : Int,
  follows? : Bool = true,
  head? : Double = 0.0,
  foot? : Double = 0.0,
  cover? : Double = 0.0,
  listens? : Bool = true,
) -> SgCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let told : Array[(Double, @view.Sight[Int])] = []
  let pressed : Ref[@view.Sight[Int]?] = Ref(None)
  let made : Ref[@view.Tree?] = Ref(None)
  if listens {
    place.on_sight(fn(s) {
      let at = match made.val {
        Some(t) => t.moment().unwrap_or(-1.0)
        None => -1.0
      }
      told.push((at, s))
    })
  }
  let tree = @view.Tree::new(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(sg_shows))) |> ignore
        o.scrolls_window(
          scroll,
          fn() { keys.get() },
          est=sg_tall,
          follows=fn() { follows },
          top_covered=fn() { cover },
          place~,
          head?=if head > 0.0 { Some(fn(h : @view.View) { h.box(fn(b) { b.height(Is(Some(head))) |> ignore }) |> ignore }) } else { None },
          foot?=if foot > 0.0 { Some(fn(f : @view.View) { f.box(fn(b) { b.height(Is(Some(foot))) |> ignore }) |> ignore }) } else { None },
          fn(b, k) {
            b
            .height(Is(Some(sg_tall)))
            .words(Is("行\{k}"))
            .on_press(fn() { pressed.val = place.sight_now() })
            .says(Is(Some(@view.said(Button, label="行\{k}"))))
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
  })
  made.val = Some(tree)
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, place, keys, told, pressed, foot }
}

///|
/// What case `c` shows, read off what is drawn: its blocks' tops (each one's words at its top, 40 tall), the first and
/// the last whose block meets what shows, the last wholly over the foot's top, how far it is from its foot.
fn sg_seen(c : SgCase) -> @view.Sight[Int] {
  let tops : Array[(Int, Double)] = []
  for k in c.keys.untracked() {
    let y = rc_y(c.tree, "行\{k}")
    if y != rc_none && y + sg_tall > 0.0 && y < sg_shows {
      tops.push((k, y))
    }
  }
  let edge = sg_shows - c.foot
  let whole = tops.filter(fn(t) { t.1 >= 0.0 && t.1 + sg_tall <= edge + 1.0e-6 })
  let from_foot = c.scroll.most() - c.scroll.at(c.tree)
  {
    first: tops[0].0,
    into: -tops[0].1,
    last: tops[tops.length() - 1].0,
    whole: whole.last().map(fn(t) { t.0 }),
    from_foot,
    shows: sg_shows,
    at_foot: from_foot.abs() < 1.0e-6,
  }
}

///|
/// Case `c` walked to `to` at `rate`, frames between (none at 0, as rc_walk's), from `from`.
fn sg_walk(c : SgCase, from : Double, to : Double, rate : Double) -> Unit {
  rc_walk(c.tree, [], [to], rate, from~, fn() { () }) |> ignore
}

///|
/// What was told of case `c` since `n` were, each with its moment.
fn sg_since(c : SgCase, n : Int) -> Array[(Double, @view.Sight[Int])] {
  c.told[n:].to_owned()
}

///|
/// Nothing told twice the same in a row.
fn sg_none_twice(c : SgCase) -> Bool {
  for i in 1..<c.told.length() {
    if c.told[i].1 == c.told[i - 1].1 {
      return false
    }
  }
  true
}

///|
test "a page's list tells what is in sight once after its first layout: at its foot, its last key the last, wholly shown" {
  let c = sg_case(30)
  assert_eq(c.told.length(), 1, msg="\{Repr(c.told)}")
  assert_eq(c.told[0].1, sg_seen(c))
  assert_eq(c.told[0].1, { first: 25, into: 0.0, last: 29, whole: Some(29), from_foot: 0.0, shows: sg_shows, at_foot: true })
  assert_eq(c.place.sight_now(), Some(c.told[0].1))
}

///|
test "a wheel's notch tells what will be in sight at that input, once, nothing as it eases there, the same at every rate" {
  for rate in rc_rates {
    let c = sg_case(30)
    let at = 100.0
    c.tree.at(at)
    c.tree.wheel_at(150.0, 100.0, 0.0, -60.0, 0, at) |> ignore
    let told_then = sg_since(c, 1)
    sg_walk(c, at, at + 1000.0, rate)
    assert_eq(told_then.length(), 1, msg="at \{rate} a second: \{Repr(c.told)}")
    assert_eq(told_then[0].0, at, msg="at \{rate} a second: told at the input")
    assert_eq(c.told.length(), 2, msg="at \{rate} a second, nothing as it eases: \{Repr(c.told)}")
    assert_eq(told_then[0].1, sg_seen(c), msg="at \{rate} a second")
    assert_true(!told_then[0].1.at_foot && told_then[0].1.from_foot > 0.0, msg="at \{rate} a second")
  }
}

///|
test "a fling tells nothing while it glides and what is in sight once at its end, the same at every rate" {
  for rate in rc_rates {
    let c = sg_case(60, follows=false)
    let tree = c.tree
    let id = tree.claimer_of(tree.claimers_at(150.0, 150.0), 0.0, -20.0).unwrap()
    let mut at = 100.0
    let mut y = 150.0
    tree.drag_at(id, Down, 150.0, y, at) |> ignore
    for _ in 0..<3 {
      y = y - 20.0
      at = at + 10.0
        tree.drag_at(id, Moved, 150.0, y, at) |> ignore
    }
    tree.drag_at(id, Up, 150.0, y, at) |> ignore
    let n = c.told.length()
    // (the glide's frames: none told; at its end, once)
    sg_walk(c, at, at + 3000.0, rate)
    let glided = sg_since(c, n)
    assert_eq(glided.length(), 1, msg="at \{rate} a second: \{Repr(glided)}")
    assert_true(glided[0].0 > at, msg="at \{rate} a second: told at the glide's end, \{glided[0].0}")
    assert_eq(glided[0].1, sg_seen(c), msg="at \{rate} a second")
    assert_true(sg_none_twice(c), msg="at \{rate} a second: \{Repr(c.told)}")
  }
}

///|
test "a key come at its foot as it follows it tells, at the data's moment, where its way ends: the new key the last, wholly shown, at its foot; nothing on the way's frames, the same at every rate" {
  for rate in rc_rates {
    let c = sg_case(30)
    let at = rc_at
    c.tree.event(at, fn() { c.keys.set(c.keys.untracked() + [30]) })
    let then = sg_since(c, 1)
    sg_walk(c, at, at + @flex.move_most_ms + 100.0, rate)
    assert_eq(then.length(), 1, msg="at \{rate} a second: \{Repr(c.told)}")
    assert_eq(then[0].0, at, msg="at \{rate} a second: told at the data's moment")
    assert_eq(c.told.length(), 2, msg="at \{rate} a second, nothing on its way: \{Repr(c.told)}")
    assert_eq(then[0].1.last, 30, msg="at \{rate} a second")
    assert_eq(then[0].1.whole, Some(30), msg="at \{rate} a second")
    assert_true(then[0].1.at_foot, msg="at \{rate} a second")
    assert_eq(then[0].1, sg_seen(c), msg="at \{rate} a second")
  }
}

///|
test "scrolled up, a key put at its end out of sight tells it further from its foot by as tall, what is in sight the same, the same at every rate" {
  for rate in rc_rates {
    let c = sg_case(30, follows=false)
    // (asked there as a press asks it, in its change)
    c.tree.event(50.0, fn() { c.place.bring(2) })
    c.tree.at(50.0)
    c.tree.frame(390.0, 844.0) |> ignore
    let was = c.place.sight_now().unwrap()
    let n = c.told.length()
    let at = rc_at
    c.tree.event(at, fn() { c.keys.set(c.keys.untracked() + [30]) })
    sg_walk(c, at, at + @flex.move_most_ms + 100.0, rate)
    let then = sg_since(c, n)
    assert_eq(then.length(), 1, msg="at \{rate} a second: \{Repr(then)}")
    assert_eq(then[0].1, { ..was, from_foot: was.from_foot + sg_tall }, msg="at \{rate} a second: \{Repr(then)} from \{Repr(was)}")
    assert_eq(then[0].1, sg_seen(c), msg="at \{rate} a second")
  }
}

///|
test "what a press's handler reads of what is in sight is what was told last" {
  let c = sg_case(30)
  c.tree.at(100.0)
  c.tree.wheel_at(150.0, 100.0, 0.0, -60.0, 0, 100.0) |> ignore
  sg_walk(c, 100.0, 1100.0, 0.0)
  c.tree.at(1200.0)
  c.tree.press(150.0, 100.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(c.pressed.val, Some(c.told[c.told.length() - 1].1))
}

///|
test "with a head and a foot: the first key the first even under its head (into less than 0: the head's height over it), wholly shown what is over the foot's top; neither ever the first nor the last" {
  // (at its top: the head 30 over block 0, block 0 down from the top of what shows by 30; its blocks to 170, the foot's
  // top: 0 to 3 wholly over it, 4 cut by it)
  let c = sg_case(30, follows=false, head=30.0, foot=30.0)
  assert_eq(c.told[c.told.length() - 1].1, sg_seen(c))
  assert_eq(c.told[c.told.length() - 1].1.first, 0)
  assert_eq(c.told[c.told.length() - 1].1.into, -30.0)
  assert_eq(c.told[c.told.length() - 1].1.whole, Some(2))
  assert_eq(c.told[c.told.length() - 1].1.last, 4)
  // (at its foot: the last key's block ends at the foot's top, wholly shown)
  let f = sg_case(30, head=30.0, foot=30.0)
  assert_eq(f.told[f.told.length() - 1].1, sg_seen(f))
  assert_eq(f.told[f.told.length() - 1].1.last, 29)
  assert_eq(f.told[f.told.length() - 1].1.whole, Some(29))
}

///|
test "telling what is in sight lays out and measures nothing: the same work with a listener as without, a finger's drag let go at speed, a wheel's notches and a key come" {
  let run = fn(listens : Bool) -> (Int, Int, Int) {
    let c = sg_case(30, listens~)
    let w0 = c.tree.work()
    // (a drag down the list, let go at speed: every step an input, the glide's end told)
    let id = c.tree.claimer_of(c.tree.claimers_at(150.0, 50.0), 0.0, 20.0).unwrap()
    let mut y = 50.0
    let mut at = 20.0
    c.tree.drag_at(id, Down, 150.0, y, at) |> ignore
    for _ in 0..<4 {
      y = y + 20.0
      at = at + 10.0
      c.tree.drag_at(id, Moved, 150.0, y, at) |> ignore
    }
    c.tree.drag_at(id, Up, 150.0, y, at) |> ignore
    sg_walk(c, at, 99.0, 60.0)
    for i in 0..<5 {
      let at = 100.0 + i.to_double() * 50.0
        c.tree.wheel_at(150.0, 100.0, 0.0, -30.0, 0, at) |> ignore
      sg_walk(c, at, at + 40.0, 60.0)
    }
    c.tree.event(500.0, fn() { c.keys.set(c.keys.untracked() + [30]) })
    sg_walk(c, 500.0, 1200.0, 60.0)
    let w = c.tree.work()
    (w.computes - w0.computes, w.laid - w0.laid, w.measured - w0.measured)
  }
  assert_eq(run(true), run(false))
}

///|
test "with its top covered 0, 44 and 52: the first key the first with something showing under what covers it, how far into it against that edge; the last wholly shown and the last as against its foot, how tall it shows as it is" {
  for cover in [0.0, 44.0, 52.0] {
    // (at its top: block 0 at 0 to 40, wholly under a cover of 44 or 52, block 1 from 40 the first showing under it)
    let c = sg_case(30, follows=false, cover~)
    let at_top = c.told[c.told.length() - 1].1
    let (first, into) = if cover >= sg_tall { (1, cover - sg_tall) } else { (0, cover) }
    assert_eq(
      at_top,
      { first, into, last: 4, whole: Some(4), from_foot: c.scroll.most(), shows: sg_shows, at_foot: false },
      msg="covered \{cover}, at its top",
    )
    // (at its foot: block 25 at the top of what shows, under the cover where it is 40 or more)
    let f = sg_case(30, cover~)
    let at_foot = f.told[f.told.length() - 1].1
    let (first, into) = if cover >= sg_tall { (26, cover - sg_tall) } else { (25, cover) }
    assert_eq(
      at_foot,
      { first, into, last: 29, whole: Some(29), from_foot: 0.0, shows: sg_shows, at_foot: true },
      msg="covered \{cover}, at its foot",
    )
  }
}

///|
test "a block brought to its middle with its top covered and a foot: its middle at the middle of what shows between them, at every rate" {
  for case in [(0.0, 0.0), (44.0, 0.0), (0.0, 30.0), (44.0, 30.0), (52.0, 30.0)] {
    let (cover, foot) = case
    for rate in rc_rates {
      let c = sg_case(30, follows=false, foot~, cover~)
      let at = rc_at
      c.tree.event(at, fn() { c.place.centre(15) })
      sg_walk(c, at, at + @flex.move_most_ms + 100.0, rate)
      let middle = rc_y(c.tree, "行15") + sg_tall / 2.0
      let want = (cover + sg_shows - foot) / 2.0
      assert_true(
        (middle - want).abs() < 1.0e-6,
        msg="covered \{cover}, a foot \{foot}, at \{rate} a second: its middle at \{middle}, the middle of what shows \{want}",
      )
    }
  }
}

///|
test "with its top covered 44 and 52, a row partly under the cover and ending over the foot's top is not wholly in what shows; with none covered it is" {
  // (at its top, a foot of 110: its top at 90. Block 1 from 40 to 80: under a cover of 44 or 52 in part, over the foot's
  // top; block 0 wholly under the cover; block 2 cut by the foot)
  for cover in [0.0, 44.0, 52.0] {
    let c = sg_case(30, follows=false, foot=110.0, cover~)
    let told = c.told[c.told.length() - 1].1
    let whole = if cover > sg_tall { None } else { Some(1) }
    assert_eq((told.first, told.whole), (if cover >= sg_tall { 1 } else { 0 }, whole), msg="covered \{cover}")
  }
}

///|
test "with its top covered 0, 44 and 52: a block brought with no offset has its top at the cover's edge; the first in sight brought with how far into it the edge was is where it was, nothing moving, at every rate" {
  for cover in [0.0, 44.0, 52.0] {
    for rate in rc_rates {
      let c = sg_case(30, follows=false, cover~)
      let at = rc_at
      c.tree.event(at, fn() { c.place.bring(10) })
      sg_walk(c, at, at + @flex.move_most_ms + 100.0, rate)
      let y = rc_y(c.tree, "行10")
      assert_true((y - cover).abs() < 1.0e-6, msg="covered \{cover}, at \{rate} a second: brought to \{y}")
      // (read 70 further by the wheel: what is in sight told, and brought back by it)
      let wheel_at = at + @flex.move_most_ms + 200.0
      c.tree.at(wheel_at)
      c.tree.wheel_at(150.0, 100.0, 0.0, 70.0, 0, wheel_at) |> ignore
      sg_walk(c, wheel_at, wheel_at + 1000.0, rate)
      let seen = c.place.sight_now().unwrap()
      let was = rc_y(c.tree, "行\{seen.first}")
      let back_at = wheel_at + 1100.0
      c.tree.event(back_at, fn() { c.place.bring(seen.first, offset=seen.into) })
      sg_walk(c, back_at, back_at + @flex.move_most_ms + 100.0, rate)
      let now = rc_y(c.tree, "行\{seen.first}")
      assert_true(
        (now - was).abs() < 1.0e-6 && (now - (cover - seen.into)).abs() < 1.0e-6,
        msg="covered \{cover}, at \{rate} a second: \{seen.first} at \{was}, \{seen.into} into it, back at \{now}",
      )
    }
  }
}
