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
test "corners of the window's tree: a node's ground shown only while pointed at, 20 round in a node's 20, said at rest as all is lit (its ground read the hand: Node's ground_by_hand); the hand as it was after" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(
    fn(v) { v.radius(Is(20.0)).ground(By(fn() { if v.pointed() { 0xEEEEEEFFL } else { 0L } })) |> ignore },
    corners_held=false,
  )
  let rest = t.corner_faults()
  let lit = t.lit_all_faults()
  let tree = view_tree().unwrap()
  let after = t.corner_faults()
  assert_eq(
    (wants(rest, follow), wants(lit, follow), tree.pointed, tree.pressing, wants(after, follow)),
    (true, true, None, None, true),
    msg="\{Repr(rest)}\n\{Repr(lit)}",
  )
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
test "corners of the window's tree: a card clipped by an ancestor above its own container is checked only where it shows; outside the window's side without that clip it is still checked" {
  let x = @signals.signal(204.0)
  let clips = @signals.signal(true)
  let t = Tester::new(fn(_c) { }, w=400.0, h=300.0, platform=0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(pane) {
      pane.width(Is(Some(200.0))).height(Is(Some(200.0))).clips(By(fn() { clips.get() })) |> ignore
      pane.box(fn(card) {
        card.over(Is(true)).offset(By(fn() { (x.get(), 0.0) }))
        .width(Is(Some(180.0))).height(Is(Some(120.0)))
        .radius(Is(20.0)).ground(Is(0x333333FFL)).pad(Is(6.0)) |> ignore
        card.box(fn(inner) {
          inner.width(Is(Some(168.0))).height(Is(Some(60.0)))
          .radius(Is(20.0)).ground(Is(0xEEEEEEFFL)) |> ignore
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_eq(t.corner_faults(), [], msg="the card's corners are beyond the ancestor's clip")
  x.set(10.0)
  t.draw()
  assert_true(wants(t.corner_faults(), concentric(20.0, 6.0)), msg="brought into the pane: its wrong corner is checked")
  clips.set(false)
  x.set(404.0)
  t.draw()
  assert_true(wants(t.corner_faults(), concentric(20.0, 6.0)), msg="past the window's side alone: the card's corner is still checked")
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
  assert_eq((unlike, hosted, half), (true, own, (halved, [])), msg="\{Repr(own)}")
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
  // (holding more than it shows, its first row in the card's top corners at its top, as far from the card's top as
  // from its sides, concentric there; holding no more, 4 further down: off, said)
  let body = fn(c : Ctx) {
    c.box(w=Fill(1.0), pt=if rows.get() > 3 { 0.0 } else { 4.0 }, fn() {
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

///|
test "corners of the window's tree: in a card said to be a picture (Role Image: another system's screen drawn), its corners what it draws, nothing said; not said so, the same said" {
  let follow = concentric(20.0, 6.0)
  let picture = fn(said : Bool) {
    fn(v : @view.View) {
      if said {
        v.parent().unwrap().says(Is(Some(@view.said(Image, label="preview")))) |> ignore
      }
      tree_ground(20.0)(v)
    }
  }
  let plain = tree_card(picture(false), corners_held=false).corner_faults()
  let said = tree_card(picture(true), corners_held=false).corner_faults()
  assert_eq((wants(plain, follow), said), (true, []), msg=plain.join("\n") + "\n--\n" + said.join("\n"))
}

///|
/// What is in the card's top corners: a node's (`tree`) or an old view's box across its top, 60 high, 20 round, filled as
/// the card (`fill`) or not, a line 1 wide round it (an old view's: in the top corners alone, so not made concentric as
/// it is laid out, tree_old_top).
fn tree_edged(tree : Bool, fill : Bool) -> (@view.View) -> Unit {
  let bg = if fill { 0x333333FFL } else { 0L }
  fn(v) {
    if tree {
      v.box(fn(b) {
        b.height(Is(Some(60.0))).ground(Is(bg)).edge(Is((1.0, 0xEEEEEEFFL))).radius(Is(20.0)) |> ignore
      })
      |> ignore
    } else {
      old(v, fn(c) {
        c.box(w=Fill(1.0), h=Px(60.0), radius=20.0, bg~, border=1.0, border_color=0xEEEEEEFFL, fn() {  }) |> ignore
      })
      .grow(Is(1.0))
      |> ignore
    }
  }
}

///|
test "corners of the window's tree: a box 20 round across the top of a node's 20, 6 in, filled as the card or not filled, a line round it: said as an old view's is (it wants 14), its line its ground" {
  let follow = concentric(20.0, 6.0)
  let got = []
  for fill in [true, false] {
    for tree in [false, true] {
      let t = tree_card(tree_edged(tree, fill), corners_held=false)
      // (drawn 20 round as it says, not made concentric as it is laid out: what the rule is asked of)
      let drawn_20 = t.drawn_instances().iter().any(fn(a) { a[5] == 0.0 && a[3] == 60.0 && a[4] == 20.0 })
      got.push((drawn_20, wants(t.corner_faults(), follow)))
    }
  }
  assert_eq(got, [(true, true), (true, true), (true, true), (true, true)])
}

///|
/// A panel 42 round, 300 high, a list scrolling up and down across it: eight cards `inset` from its sides, `corner`
/// round, 80 high, 8 apart, `ends` of room over the first and under the last.
fn scrolled_cards(inset : Double, corner : Double, ends : Double, foot_right? : Double = 42.0) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme({ ..Theme::light(), corner_fit: Some(fit_ranges) }, fn() { c.box(pad=20.0, align=AStart, fn() {
      c.box(style=style(radius=Corners(42.0, 42.0, foot_right, 42.0)), w=Px(400.0), h=Px(300.0), bg=0xFFFFFFFFL, fn() {
        c.list("cards", 10, 88.0, fn(k) {
          if k == 0 || k == 9 {
            c.box(w=Fill(1.0), h=Px(ends), fn() {  }) |> ignore
          } else {
            c.box(w=Fill(1.0), padx=inset, pt=if k == 1 { 0.0 } else { 8.0 }, fn() {
              c.box(w=Fill(1.0), h=Px(80.0), radius=corner, bg=0xEEEEEEFFL, fn() {  }) |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    })
  }
}

///|
/// The faults of cards in what scrolls, with the list at its top, scrolled to its middle and to its end.
fn scrolled_faults(view : (Ctx) -> Unit) -> (Int, Int, Int) {
  let t = Tester::new(view, corners_held=false)
  t.draw()
  let n = fn() { t.corner_faults().filter(fn(f) { f.contains("in what scrolls there") }).length() }
  let top = n()
  t.scroll_to(4)
  t.draw()
  t.draw()
  let middle = n()
  t.scroll_to_end()
  t.draw()
  t.draw()
  (top, middle, n())
}

///|
test "corners: cards in a list in a panel, scrolled to its top, its middle and its end: near a corner only at its ends, concentric there (16 in a 42, 26); 12 in with a 24 said at its ends; 40 in, none; in the middle, none" {
  assert_eq(scrolled_faults(scrolled_cards(16.0, 26.0, 16.0)), (0, 0, 0))
  let (top, middle, end) = scrolled_faults(scrolled_cards(12.0, 24.0, 12.0))
  assert_true(top > 0 && end > 0, msg="\{Repr((top, middle, end))}")
  assert_eq(middle, 0)
  assert_eq(scrolled_faults(scrolled_cards(40.0, 24.0, 16.0)), (0, 0, 0))
  // (as far in from its sides as a 26 follows a 42 from, but 10 from its top and foot: said at its ends)
  let (top, middle, end) = scrolled_faults(scrolled_cards(16.0, 26.0, 10.0))
  assert_true(top > 0 && end > 0, msg="\{Repr((top, middle, end))}")
  assert_eq(middle, 0)
  // (corners unlike: its foot's right one 10, too square for a card 16 in to follow: that corner alone, the others
  // judged each by their own)
  assert_eq(scrolled_faults(scrolled_cards(16.0, 26.0, 16.0, foot_right=10.0)), (0, 0, 0))
}

///|
test "corners of the window's tree: a round key 12 in a node's 20, 6 and 10 in, with no ground of its own: said while it takes presses, as its ground shows under the hand; said to take none (View::presses), nothing, it never lights; taking them again, said again" {
  let on = @signals.signal(false)
  let t = tree_card(corners_held=false, fn(v) {
    v.box(fn(k) {
      k
      .width(Is(Some(24.0)))
      .height(Is(Some(24.0)))
      .radius(Is(12.0))
      .margin(Is((0.0, 4.0, 0.0, 0.0)))
      .presses(By(fn() { on.get() }))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Button, label="turn"))))
      |> ignore
    })
    |> ignore
  })
  let off = t.corner_faults()
  on.set(true)
  t.draw()
  let taking = t.corner_faults()
  on.set(false)
  t.draw()
  let off_again = t.corner_faults()
  on.set(true)
  t.draw()
  let taking_again = t.corner_faults()
  assert_eq(
    (off, taking.length() > 0, off_again, taking_again.length() > 0),
    ([], true, [], true),
    msg="\{Repr(off)} | \{Repr(taking)} | \{Repr(off_again)} | \{Repr(taking_again)}",
  )
}

///|
/// What the rule says of a box said concentric (radius=Inner) at the top of a card 20 round, 6 in, `tall` tall: its
/// foot as far from the card's as 108 - tall + 6 (the old view's way, Ctx's inner_faults).
fn inner_foot_faults(tall : Double) -> Array[String] {
  let t = Tester::new(
    fn(c) {
      c.box(w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL, fn() {
        c.box(w=Px(188.0), h=Px(108.0), fn() {
          c.box(style=style(w=Full, h=Fixed(tall), radius=Inner, bg=Faint), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  t.draw()
  g().inner_faults.copy()
}

///|
test "the corner rule, a box said concentric whose foot is at the card's corner's radius: at it, or a float's breadth short of it (a size laid by a sum), it is not near that edge; a hundredth of a point inside, it is, as before" {
  // (its foot 20 from the card's, the card 20 round: 108 - 94 + 6)
  let at_radius = inner_foot_faults(94.0)
  // (as a laid size summed one way comes to it: 19.999999999999886, a float's breadth inside)
  let a_hair_in = inner_foot_faults(94.0 + 1.1e-13)
  // (a hundredth inside: near it, its edges at 6 and 19.99, said)
  let inside = inner_foot_faults(94.01)
  assert_eq((at_radius, a_hair_in), ([], []))
  assert_true(inside.length() == 1, msg="\{Repr(inside)}")
}

///|
/// The window's old frame beside the window's tree, whose nodes' grounds read the hand: drawn first with nothing in the
/// old frame, then (`full` set) with a card 200×120, 20 round, holding 40 boxes one in another, 10×10, 6 in from its
/// top left, with no ground of their own: the corner rule's faults of that frame.
fn old_beside_lit_faults() -> Array[String] {
  let full = @signals.signal(false)
  let t = Tester::new(
    fn(c) {
      if full.get() {
        c.box(w=Px(200.0), h=Px(120.0), pad=6.0, radius=20.0, bg=0x333333FFL, fn() {
          fn nest(n : Int) -> Unit {
            if n > 0 {
              c.box(w=Px(10.0), h=Px(10.0), fn() { nest(n - 1) }) |> ignore
            }
          }

          nest(40)
        })
        |> ignore
      }
    },
    tree=fn(root) {
      root.box(fn(col) {
        col.pad(Is(40.0)) |> ignore
        for _ in 0..<40 {
          col.box(fn(v) {
            v
            .width(Is(Some(100.0)))
            .height(Is(Some(4.0)))
            .ground(By(fn() { if v.pointed() { 0xEEEEEEFFL } else { 0L } }))
            .presses(Is(true))
            .on_press(fn() {  })
            .says(Is(Some(@view.said(Button, label="lit"))))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  t.draw()
  t.corner_faults() |> ignore
  full.set(true)
  t.draw()
  t.corner_faults()
}

///|
test "corners: an old view's boxes made where the window's tree's nodes were held to the corner rule the frame before, one of them a ground read under the hand, are none of theirs; with no ground of their own, nothing said" {
  // (Ctx::box sets all of a box's look but that mark, which Ctx::with_tree_nodes clears in what it leaves the frame:
  // one of its nodes made in what had been one of the tree's said a ground by the hand of a box with none, in the
  // print-only run of 2026-11-12: a confirm's button's words, 0 round in its 18)
  let faults = old_beside_lit_faults()
  assert_eq(faults, [])
}

///|
/// A row 18 round in the window's tree holding a dot 8×8 near its top left (10 and 12 in), with a halo 16×16 laid over
/// the dot (`halo`: View::over and offset (-4, -4), else laid in the row itself at (6, 8)): the corner rule's faults.
fn tree_dot_halo_faults(hung : Bool) -> Array[String] {
  let t = Tester::new(
    fn(_) {  },
    tree=fn(root) {
      root.box(fn(page) {
        page.pad(Is(40.0)) |> ignore
        page.box(fn(row) {
          row
          .width(Is(Some(240.0)))
          .height(Is(Some(48.0)))
          .padding(Is((10.0, 12.0, 10.0, 12.0)))
          .radius(Is(18.0))
          .ground(Is(0x222222FFL))
          |> ignore
          if hung {
            row.box(fn(dot) {
              dot.width(Is(Some(8.0))).height(Is(Some(8.0))).radius(Is(4.0)).ground(Is(0x4ADE80FFL)) |> ignore
              dot.box(fn(halo) {
                halo
                .over(Is(true))
                .offset(Is((-4.0, -4.0)))
                .width(Is(Some(16.0)))
                .height(Is(Some(16.0)))
                .radius(Is(8.0))
                .ground(Is(0x4ADE8033L))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          } else {
            row.box(fn(halo) {
              halo
              .margin(Is((-4.0, -4.0, 0.0, 0.0)))
              .width(Is(Some(16.0)))
              .height(Is(Some(16.0)))
              .radius(Is(8.0))
              .ground(Is(0x4ADE8033L))
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  t.draw()
  t.corner_faults()
}

///|
test "corners: a mark hung over a small dot in a tree row's corner (over + offset) is exempt as an old view's is; the same circle laid in the row's flow is checked" {
  assert_eq(tree_dot_halo_faults(true), [])
  assert_eq(tree_dot_halo_faults(false).length(), 1)
}

///|
/// A panel 24 round in the window's tree, `pad` in at its sides, holding a row pressed whole (240 by 48) `r` round whose
/// ground shows only under the hand: the corner rule's faults, the row not pointed at.
fn tree_lit_row_faults(pad : Double, r : Double) -> Array[String] {
  let t = Tester::new(
    fn(_) {  },
    tree=fn(root) {
      root.box(fn(page) {
        page.pad(Is(40.0)) |> ignore
        page.box(fn(panel) {
          panel.width(Is(Some(300.0))).padding(Is((pad, 48.0, pad, 48.0))).radius(Is(24.0)).ground(Is(0x222222FFL)) |> ignore
          panel.box(fn(v) {
            v
            .height(Is(Some(48.0)))
            .radius(Is(r))
            .ground(By(fn() { if v.pointed() { 0xEEEEEEFFL } else { 0L } }))
            .presses(Is(true))
            .on_press(fn() {  })
            .says(Is(Some(@view.said(Button, label="row"))))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
    platform=0,
    corners_held=false,
  )
  t.draw()
  t.corner_faults()
}

///|
test "corners: a row's ground under the hand drawn square, standing in from a rounded panel's sides far from its corners, is a fault; round, or flush with the panel's sides, none" {
  let square = tree_lit_row_faults(20.0, 0.0)
  assert_true(square.length() == 1 && square[0].contains("lit square under the hand"), msg=list_text(square))
  assert_eq(tree_lit_row_faults(20.0, 12.0), [])
  assert_eq(tree_lit_row_faults(0.0, 0.0), [])
}
