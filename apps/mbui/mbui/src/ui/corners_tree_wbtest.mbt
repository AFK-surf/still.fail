// The corner rule held of the window's tree's nodes too (corners.mbt, Ctx::with_tree_nodes): a ground in a rounded
// node's corner, a node's or an old view's in it, concentric with it or said; one shown only under the hand said as
// all is lit (Tester::lit_all_faults); the frame as it was after.

///|
/// A card of the tree, 200×120, its ground 20 round, 6 in all round, holding what `inside` makes there, 188×108; drawn
/// `scale` as big; `corners_held`: each frame held to the corner rule as it is drawn (Tester::hold_corners).
fn tree_card(
  inside : (@view.View) -> Unit,
  scale? : Double = 1.0,
  alpha? : Double = 1.0,
  clips? : Bool = false,
  corners_held? : Bool = true,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held~)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .pad(Is(6.0))
      .ground(Is(0x333333FFL))
      .radius(Is(20.0))
      .scale(Is(scale))
      .alpha(Is(alpha))
      .clips(Is(clips))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
        inside(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// A node's ground in the card's corners, `r` round.
fn tree_ground(r : Double) -> (@view.View) -> Unit {
  fn(v) { v.ground(Is(0xEEEEEEFFL)).radius(Is(r)) |> ignore }
}

///|
/// An old view's box in the card's corners, filling the old view, `r` round.
fn tree_old(r : Double) -> (@view.View) -> Unit {
  fn(v) {
    old(v, fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), radius=r, bg=0xEEEEEEFFL, fn() {  }) |> ignore }).grow(Is(1.0))
    |> ignore
  }
}

///|
/// An old view's box at the card's top, across it, 60 high, `r` round: in its top corners alone, so not made concentric
/// with them as it is laid out (its corners would not stay alike: corners_in_corners), what the rule says of it as it
/// is.
fn tree_old_top(r : Double) -> (@view.View) -> Unit {
  fn(v) {
    old(v, fn(c) { c.box(w=Fill(1.0), h=Px(60.0), radius=r, bg=0xEEEEEEFFL, fn() {  }) |> ignore }).grow(Is(1.0))
    |> ignore
  }
}

///|
/// Whether one of `faults` says a corner wants to be `r` round.
fn wants(faults : Array[String], r : Double) -> Bool {
  faults.iter().any(fn(f) { f.contains("wants corner \{r}") })
}

///|
test "corners of the window's tree: a node's ground 20 round in a node's 20, 6 in, said (it wants 15.2); one concentric with it, nothing" {
  let follow = concentric(20.0, 6.0)
  let wrong = tree_card(tree_ground(20.0)).corner_faults()
  let right = tree_card(tree_ground(follow)).corner_faults()
  assert_eq((wants(wrong, follow), right), (true, []), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: the card drawn half as big (10 round, 3 in), a ground 20 round in it said (it wants 7.6), one concentric with it as laid out (7.6 drawn) nothing" {
  let wrong = tree_card(tree_ground(20.0), scale=0.5).corner_faults()
  let right = tree_card(tree_ground(concentric(20.0, 6.0)), scale=0.5).corner_faults()
  assert_eq((wants(wrong, concentric(10.0, 3.0)), right), (true, []), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: an old view's box 20 round in a node's 20's top corners, 6 in, said; one concentric with it, nothing" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(tree_old_top(20.0))
  // (the frame's nodes as they were after: how many, what holds each, what takes a press)
  let c = g()
  let nodes = fn() { (c.count, Array::makei(c.count, fn(i) { (c.nodes[i].parent, c.nodes[i].first, c.nodes[i].next, c.nodes[i].hit, c.nodes[i].id) })) }
  let before = nodes()
  let wrong = t.corner_faults()
  let after = nodes()
  let right = tree_card(tree_old_top(follow)).corner_faults()
  assert_eq((wants(wrong, follow), right, after == before), (true, [], true), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: a node's ground shown only while pointed at, 20 round in a node's 20, said as all is lit, not at rest; the hand as it was after" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(fn(v) {
    v.radius(Is(20.0)).ground(By(fn() { if v.pointed() { 0xEEEEEEFFL } else { 0L } })) |> ignore
  })
  let rest = t.corner_faults()
  let lit = t.lit_all_faults()
  let tree = view_tree().unwrap()
  let after = t.corner_faults()
  assert_eq((rest, wants(lit, follow), tree.pointed, tree.pressing, after), ([], true, None, None, []), msg=lit.join("\n"))
}

///|
test "corners of the window's tree, held on every frame at rest (Tester::hold_corners): a node's ground 20 round in a node's 20 said, a moment it waits for to come (a tip's) beside it; nothing moving" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(fn(v) {
    tree_ground(20.0)(v)
    // (something due on the tree's timeline, nothing drawn by it moving: a tip waiting to come)
    v.at_moment(1.0e9, fn() {  }) |> ignore
  })
  t.draw()
  let c = g()
  c.corner_ladder = [34.0, 26.0, 20.0, 10.0]
  let tree = view_tree().unwrap()
  let held = c.held_corner_faults()
  assert_eq((tree.due_count() > 0, c.motion_left, wants(held, follow)), (true, false, true), msg=held.join("\n"))
}

///|
/// A card of the tree, 200×120, its ground 20 round, cutting what it holds to it (`clips`) or not, holding what
/// `inside` makes there as big as it.
fn tree_cut_card(inside : (@view.View) -> Unit, clips : Bool) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .ground(Is(0x333333FFL))
      .radius(Is(20.0))
      .clips(Is(clips))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(200.0))).height(Is(Some(120.0))) |> ignore
        inside(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "corners of the window's tree: a square ground filling a node 20 round that cuts it, drawn round by the cut, nothing; not cut, said; an old view's the same" {
  let cut = tree_cut_card(tree_ground(0.0), true).corner_faults()
  let uncut = tree_cut_card(tree_ground(0.0), false).corner_faults()
  let old_cut = tree_cut_card(tree_old(0.0), true).corner_faults()
  let old_uncut = tree_cut_card(tree_old(0.0), false).corner_faults()
  assert_eq(
    (cut, wants(uncut, 20.0), old_cut, wants(old_uncut, 20.0)),
    ([], true, [], true),
    msg=(cut + uncut + old_cut + old_uncut).join("\n"),
  )
}

///|
test "corners of the window's tree: the same corner off the rule, a node's ground or an old view's in the card: said while the card is drawn; drawn as nothing (faded out, 0.005, short of what is seen at 0.01), not; the old view's boxes as they were after" {
  let r = 20.0
  let out = 0.005
  // (the card cutting what it holds to its corners, as a panel does: what lies in it held to them by that too)
  let said = fn(inside : (@view.View) -> Unit, alpha : Double) { tree_card(inside, alpha~, clips=true).corner_faults().length() > 0 }
  let t = tree_card(tree_old_top(r), alpha=out, clips=true)
  let before = t.boxes().map(fn(b) { (b.x, b.y, b.w, b.h, b.radius, b.opacity) })
  let hidden_old = t.corner_faults().length() > 0
  let after = t.boxes().map(fn(b) { (b.x, b.y, b.w, b.h, b.radius, b.opacity) })
  assert_eq(
    (said(tree_ground(r), 1.0), said(tree_old_top(r), 1.0), said(tree_ground(r), out), hidden_old, after == before),
    (true, true, false, false, true),
  )
}

///|
/// The corner what is said to be concentric with its container (radius=Inner) is worked out to, a box of an old view's
/// filling where it is (`hosted`: an old view in the tree's card, 20 round, 6 in; else an old view's own box the same,
/// 20 round, 6 in, the window's old frame alone), and what is said of corners said Inner the frame found no container
/// for (Ctx's inner_faults).
fn inner_worked(hosted : Bool) -> (Double, Array[String]) {
  let body = fn(c : Ctx) {
    c.box(style=style(w=Full, h=Full, radius=Inner, bg=Faint), fn() {  }) |> ignore
  }
  let t = if hosted {
    tree_card(fn(v) { old(v, fn(c) { body(c) }).grow(Is(1.0)) |> ignore }, corners_held=false)
  } else {
    let t = Tester::new(
      fn(c) {
        c.box(w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL, fn() {
          c.box(w=Px(188.0), h=Px(108.0), fn() { body(c) }) |> ignore
        })
        |> ignore
      },
      w=400.0,
      h=300.0,
      platform=0,
      corners_held=false,
    )
    t.draw()
    t
  }
  let c = g()
  // (the one said Inner, as the frame found it)
  let r = if c.inners.length() == 1 { c.nodes[c.inners[0]].corner() } else { -1.0 * c.inners.length().to_double() }
  ignore(t)
  (r, c.inner_faults.copy())
}

///|
test "corners of the window's tree: an old view's box said concentric with what holds it (radius=Inner), in a node 20 round, 6 in: worked out concentric with it as an old view's box's in an old view's 20 round would be, nothing said" {
  let follow = concentric(20.0, 6.0)
  assert_eq((inner_worked(false), inner_worked(true)), (((follow, []), (follow, []))))
}

///|
/// The rects drawn in the last frame of `colour` (opaque): where, how big, how round (each corner, to a thousandth).
fn drawn_round(colour : Int64) -> Array[(Double, Double, Double, Double, Double, Double, Double, Double)] {
  let c = g()
  let f = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let i = c.inst
    let col = (ch(i[b + 8]) << 24) | (ch(i[b + 9]) << 16) | (ch(i[b + 10]) << 8) | ch(i[b + 11])
    if i[b + 5] == 0.0 && col == colour {
      out.push((f(i[b]), f(i[b + 1]), f(i[b + 2]), f(i[b + 3]), f(i[b + 36]), f(i[b + 37]), f(i[b + 38]), f(i[b + 39])))
    }
  }
  out
}

///|
/// A card of the tree at (30, 40), 200×120, its ground `radius()` round, 6 in all round, drawn `scale()` as big about
/// its top left, holding an old view all of it (188×108) whose one box fills it, said concentric with what holds it
/// (radius=Inner), `inner_colour`. Its corners not held to the rule as it is drawn.
fn inner_tree_card(radius : @signals.Signal[Double], scale : @signals.Signal[Double]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .over(Is(true))
      .offset(Is((30.0, 40.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .pad(Is(6.0))
      .ground(Is(0x333333FFL))
      .radius(By(fn() { radius.get() }))
      .scale(By(fn() { scale.get() }), about=At(0.0, 0.0))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
        old(v, fn(c) { c.box(style=style(w=Full, h=Full, radius=Inner), bg=inner_colour, fn() {  }) |> ignore }).grow(
          Is(1.0),
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
let inner_colour : Int64 = 0x55AA77FFL

///|
/// The corner the one said Inner is worked out to, as laid out (-n: n of them).
fn inner_now() -> Double {
  let c = g()
  if c.inners.length() == 1 {
    c.nodes[c.inners[0]].corner()
  } else {
    -1.0 * c.inners.length().to_double()
  }
}

///|
test "corners of the window's tree: an old view's box said concentric (radius=Inner) in a card moved off its place and drawn half as big: worked out as laid out, the same; drawn where the card puts it, as big, its corners as big" {
  let radius = @signals.signal(20.0)
  let scale = @signals.signal(1.0)
  let t = inner_tree_card(radius, scale)
  let follow = concentric(20.0, 6.0)
  let whole = (inner_now(), drawn_round(inner_colour), g().inner_faults.copy())
  scale.set(0.5)
  t.clock_frame()
  let half = (inner_now(), drawn_round(inner_colour), g().inner_faults.copy())
  let h = follow / 2.0
  assert_eq(
    (whole, half),
    (
      (follow, [(36.0, 46.0, 188.0, 108.0, follow, follow, follow, follow)], []),
      (follow, [(33.0, 43.0, 94.0, 54.0, h, h, h, h)], []),
    ),
  )
}

///|
test "corners of the window's tree: an old view's box said concentric (radius=Inner) in a card whose corner changes alone (20 to 26), nothing else of it nor of the old view: worked out and drawn concentric with the new corner from the next frame" {
  let radius = @signals.signal(20.0)
  let scale = @signals.signal(1.0)
  let t = inner_tree_card(radius, scale)
  let before = (inner_now(), drawn_round(inner_colour).map(fn(r) { r.4 }))
  radius.set(26.0)
  t.clock_frame()
  let after = (inner_now(), drawn_round(inner_colour).map(fn(r) { r.4 }), g().inner_faults.copy())
  let (f20, f26) = (concentric(20.0, 6.0), concentric(26.0, 6.0))
  assert_eq((before, after), ((f20, [f20]), (f26, [f26], [])))
}

///|
test "corners: a box 20 round 6 in a container 20 round, an old view's own or one hosted in the tree's card: what the frame works it out to, what the rule says: made concentric as it is laid out either way, nothing said" {
  let colour = 0x77AA55FFL
  let old_own = Tester::new(
    fn(c) {
      c.box(w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL, fn() {
        c.box(w=Px(188.0), h=Px(108.0), radius=20.0, bg=colour, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  old_own.draw()
  let own = (drawn_round(colour), old_own.corner_faults())
  let hosted = tree_card(
    fn(v) {
      old(v, fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), radius=20.0, bg=colour, fn() {  }) |> ignore }).grow(Is(1.0))
      |> ignore
    },
    corners_held=false,
  )
  let tree = (drawn_round(colour), hosted.corner_faults())
  // (made concentric with the container as it is laid out, nothing said, either way)
  let follow = concentric(20.0, 6.0)
  let made = ([(6.0, 6.0, 188.0, 108.0, follow, follow, follow, follow)], [])
  assert_eq((own, tree), (made, made))
}

///|
/// A container 200×120, 6 in all round, its corners each its own (24, 12, 24, 12: top left, then round it), holding a box
/// filling it, said concentric with what holds it (radius=Inner), `inner_colour`: an old view's own (`hosted` false), or
/// a card of the window's tree's at (30, 40), drawn `scale` as big about its top left, an old view in it all of it.
/// Each corner it is drawn with, and what is said of the corners said Inner.
fn inner_each(hosted : Bool, scale? : Double = 1.0) -> (Array[(Double, Double, Double, Double)], Array[String]) {
  let body = fn(c : Ctx) { c.box(style=style(w=Full, h=Full, radius=Inner), bg=inner_colour, fn() {  }) |> ignore }
  let t = if hosted {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
    set_view_app(fn(root) {
      root.box(fn(card) {
        card
        .over(Is(true))
        .offset(Is((30.0, 40.0)))
        .width(Is(Some(200.0)))
        .height(Is(Some(120.0)))
        .pad(Is(6.0))
        .ground(Is(0x333333FFL))
        .radius(Is(24.0))
        .corners(Is(Some((24.0, 12.0, 24.0, 12.0))))
        .scale(Is(scale), about=At(0.0, 0.0))
        |> ignore
        card.box(fn(v) {
          v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
          old(v, fn(c) { body(c) }).grow(Is(1.0)) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    t
  } else {
    let t = Tester::new(
      fn(c) {
        c.box(style=style(w=Fixed(200.0), h=Fixed(120.0), radius=Corners(24.0, 12.0, 24.0, 12.0)), pad=6.0, bg=0x333333FFL, fn() {
          c.box(w=Px(188.0), h=Px(108.0), fn() { body(c) }) |> ignore
        })
        |> ignore
      },
      w=400.0,
      h=300.0,
      platform=0,
      corners_held=false,
    )
    t.draw()
    t
  }
  ignore(t)
  (drawn_round(inner_colour).map(fn(r) { (r.4, r.5, r.6, r.7) }), g().inner_faults.copy())
}

///|
test "corners of the window's tree: an old view's box said concentric (radius=Inner) in a card whose corners are each their own: each corner concentric with the card's there, as an old view's own in such a box; drawn half as big, each half as round" {
  let own = inner_each(false)
  let hosted = inner_each(true)
  let half = inner_each(true, scale=0.5)
  let halved = own.0.map(fn(r) { (r.0 / 2.0, r.1 / 2.0, r.2 / 2.0, r.3 / 2.0) })
  // (as an old view's own: not all alike)
  let unlike = own.0.length() == 1 && own.0[0].0 != own.0[0].1
  assert_eq((unlike, hosted, half), (true, own, (halved, [])), msg="\{own}")
}

///|
test "corners of the window's tree: an old view's box at the top of a card whose corners are each their own (24, 12, …), 4 round, drawn half as big: said wanting what is concentric with the card's corners as drawn there" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .over(Is(true))
      .offset(Is((30.0, 40.0)))
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .pad(Is(6.0))
      .ground(Is(0x333333FFL))
      .radius(Is(24.0))
      .corners(Is(Some((24.0, 12.0, 24.0, 12.0))))
      .scale(Is(0.5), about=At(0.0, 0.0))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
        tree_old_top(4.0)(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let faults = t.corner_faults()
  // (its top left in the card's 24 drawn 12, 3 in; its top right in its 12 drawn 6, 3 in)
  assert_eq((wants(faults, concentric(12.0, 3.0)), wants(faults, concentric(6.0, 3.0))), (true, true), msg=faults.join("\n"))
}

///|
/// Rows 30 high, `rows()` of them, as round as concentric with a container 20 round 6 in, the first 4 further down than
/// the container's sides are in, in a box that scrolls them up and down kept to the 188×108 inside it: an old view's own
/// in an old box 20 round (`hosted` false: Ctx::capped), or in a node of the window's tree's (View::scrolls) in the tree's
/// card drawn `scale` as big, an old view as tall as what it holds in it. What the rule says with 8 rows, then with 2
/// (only `rows` told, the next frame drawn by the clock).
fn scrolled_rows(hosted : Bool, scale? : Double = 1.0) -> (Array[String], Array[String]) {
  let rows = @signals.signal(8)
  let body = fn(c : Ctx) {
    c.box(w=Fill(1.0), pt=4.0, fn() {
      for _ in 0..<rows.get() {
        c.box(w=Fill(1.0), h=Px(30.0), radius=concentric(20.0, 6.0), bg=0xEEEEEEFFL, fn() {  }) |> ignore
      }
    })
    |> ignore
  }
  let t = if hosted {
    let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, corners_held=false)
    set_view_app(fn(root) {
      root.box(fn(card) {
        card
        .width(Is(Some(200.0)))
        .height(Is(Some(120.0)))
        .pad(Is(6.0))
        .ground(Is(0x333333FFL))
        .radius(Is(20.0))
        .scale(Is(scale), about=At(0.0, 0.0))
        |> ignore
        card.box(fn(v) {
          v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
          v.scrolls(@view.Scroll::new(), fn(s) { old(s, natural=true, fn(c) { body(c) }) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    t
  } else {
    let t = Tester::new(
      fn(c) {
        c.box(w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL, fn() {
          c.capped("rows", 108.0, fn() { body(c) }) |> ignore
        })
        |> ignore
      },
      w=400.0,
      h=300.0,
      platform=0,
      corners_held=false,
    )
    t.draw()
    t
  }
  let many = t.corner_faults()
  rows.set(2)
  t.clock_frame()
  (many, t.corner_faults())
}

///|
test "corners of the window's tree: rows in a node that scrolls them up and down, holding more than it shows: under its top and foot as they scroll, near its sides alone, nothing said; holding no more than it shows (told fewer, the next frame), lying in the card's corners for good, said; as an old view's own in a box kept to a height; drawn half as big, the same" {
  let pass = fn(r : (Array[String], Array[String])) { (r.0, r.1.length() > 0) }
  assert_eq((pass(scrolled_rows(false)), pass(scrolled_rows(true)), pass(scrolled_rows(true, scale=0.5))), (([], true), ([], true), ([], true)))
}
