// Each corner its own (Radius::Corners, LinkedEach; scene.mbt 36-39): drawn so, cut so, and held by the corner rule
// corner by corner. Only said so: what mbui works out keeps a box's corners alike (corners.mbt), unlike only as its
// container's are where it fills it (the user, 2026-10-26: 每个四边圆角不一致的都应该手动确认是否 by design).

///|
/// The first instance of kind `kind` drawn at (`x`, `y`): its corners' radii (36-39), its corner (4).
fn corners_drawn(kind : Double, x : Double, y : Double) -> ((Double, Double, Double, Double), Double) {
  let c = g()
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == kind && (c.inst[b] - x).abs() < 0.01 && (c.inst[b + 1] - y).abs() < 0.01 {
      return ((c.inst[b + 36], c.inst[b + 37], c.inst[b + 38], c.inst[b + 39]), c.inst[b + 4])
    }
  }
  abort("nothing of kind \{kind} drawn at \{x},\{y}")
}

///|
test "corners: each its own is drawn so, its shadow and its cut too; the draw list says them only then" {
  let t = Tester::new(
    fn(c) {
      c.box(pad=20.0, align=AStart, fn() {
        c.box(style=style(radius=Corners(30.0, 4.0, 12.0, 0.0)), w=Px(120.0), h=Px(80.0), bg=0x333333FFL, shadow=8.0, clip=true, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=0xEEEEEEFFL, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  assert_eq(corners_drawn(0.0, 20.0, 20.0), ((30.0, 4.0, 12.0, 0.0), 30.0))
  let (shadow, _) = corners_drawn(2.0, 20.0, 20.0 + 8.0 * 0.35)
  assert_eq(shadow, (30.0, 4.0, 12.0, 0.0))
  // what it holds cut by each of its corners (the clip's 24-27)
  let c = g()
  let mut cut = false
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b + 8] > 0.9 {
      cut = (c.inst[b + 24], c.inst[b + 25], c.inst[b + 26], c.inst[b + 27]) == (30.0, 4.0, 12.0, 0.0)
    }
  }
  assert_true(cut, msg="what it holds is not cut by its corners")
  assert_true(t.drawlist().has_prefix("mbui-dl 6\n"))
  // all four one: as before, 32 numbers an instance
  let t = Tester::new(
    fn(c) { c.box(pad=20.0, align=AStart, fn() { c.box(w=Px(120.0), h=Px(80.0), radius=12.0, bg=0x333333FFL, fn() {  }) |> ignore }) |> ignore },
    w=200.0,
    h=200.0,
  )
  t.draw()
  assert_eq(corners_drawn(0.0, 20.0, 20.0), ((12.0, 12.0, 12.0, 12.0), 12.0))
  assert_true(t.drawlist().has_prefix("mbui-dl 4\n"))
}

///|
/// A panel at the right of a window 400 by 200, 6 from its top, right and foot (a Mac's tape's page, in use), its right
/// corners linked to the window's 6 in, its left ones the ladder's 34 (LinkedEach: said so), in the ladder's theme;
/// across its foot `d` from its sides and foot a box 60 high, its own corner `own` (`fill`: as tall as it leaves, in
/// all four of its corners).
fn foot_panel(d : Double, own : Radius, fill? : Bool = false) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        let edge : CornerOf = Follow(Window, 6.0, 34.0)
        c.box(
          style=style(radius=LinkedEach(Own(34.0), edge, edge, Own(34.0))),
          w=Px(300.0),
          h=Px(188.0),
          left=94.0,
          top=6.0,
          bg=0x333333FFL,
          pad=d,
          justify=JEnd,
          fn() {
            c.box(style=style(w=Full, h=if fill { Full } else { Fixed(60.0) }, radius=own, bg=Faint), fn() {  }) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    })
  }
}

///|
/// The panel (foot_panel's) and the box across its foot: their nodes.
fn foot_nodes() -> (Node, Node) {
  let c = g()
  let mut panel : Node? = None
  let mut box : Node? = None
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_box && n.bg == 0x333333FFL {
      panel = Some(n)
    }
    if n.kind == kind_box && n.fh == 60.0 {
      box = Some(n)
    }
  }
  match (panel, box) {
    (Some(p), Some(b)) => (p, b)
    _ => abort("no panel and box at its foot")
  }
}

///|
fn corners4(n : Node) -> (Double, Double, Double, Double) {
  (n.radius_at(0), n.radius_at(1), n.radius_at(2), n.radius_at(3))
}

///|
test "corners: a box across a panel's foot keeps one corner for all four: concentric where it can be, alone in a corner too square for it, never followed in some corners only" {
  let follow = concentric(16.0, 6.0)
  // a Mac's window, 16 round: the panel's right corners in its, 6 in, 11.2 (linked); its left ones 34. The box 10 in:
  // its left foot corner the card's 26 there (concentric, its own); its right in the 11.2, too square for a 26 (8 at
  // the nearest it could stand): alone, as it is, nothing said
  for own in [Radius::Exact(26.0), InnerOr(Exact(26.0))] {
    let t = Tester::new(foot_panel(10.0, own), w=400.0, h=200.0, window_corner=16.0)
    t.draw()
    let (p, b) = foot_nodes()
    assert_eq(corners4(p), (34.0, follow, follow, 34.0))
    assert_true(b.radii is None && b.radius == 26.0, msg="\{corners4(b)}")
    assert_eq(t.corner_faults(), [])
  }
  // 6.5 in: following each foot corner it lies in would make its corners unlike (28.8 at its left, 6 at its right, 26
  // over): never worked out so; its own kept all round, and said where it is not concentric (its left foot corner)
  let t = Tester::new(foot_panel(6.5, InnerOr(Exact(26.0))), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let (_, b) = foot_nodes()
  assert_eq(corners4(b), (26.0, 26.0, 26.0, 26.0))
  let faults = t.corner_faults()
  assert_true(faults.length() == 1 && faults[0].contains("bottom left"), msg="\{faults}")
  // a square window: the panel 34 all round, the box 10 in the card's 26 all round
  let t = Tester::new(foot_panel(10.0, InnerOr(Exact(26.0))), w=400.0, h=200.0)
  t.draw()
  let (p, b) = foot_nodes()
  assert_true(p.radii is None && p.radius == 34.0)
  assert_true(b.radii is None && b.radius == 26.0, msg="\{corners4(b)}")
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: radius=Inner follows the container's corners where it fills it; in only some of them, unlike, it is said" {
  let follow = concentric(16.0, 6.0)
  let inner = concentric(follow, 6.5)
  let outer = concentric(34.0, 6.5)
  // filling the panel, in all four of its corners: each the panel's there, as unlike as the panel's are (said so)
  let t = Tester::new(foot_panel(6.5, Inner, fill=true), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let (_, b) = foot_nodes_filled()
  assert_eq(corners4(b), (outer, inner, inner, outer))
  // across its foot, in two: they would be unlike there, its top's not in any; as round as the squarest, and said
  let t = Tester::new(foot_panel(6.5, Inner), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let (_, b) = foot_nodes()
  assert_eq(corners4(b), (inner, inner, inner, inner))
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("would not be alike") }), msg="\{t.corner_faults()}")
}

///|
/// The box foot_panel draws filling the panel (`fill`): its node.
fn foot_nodes_filled() -> (Node, Node) {
  let c = g()
  let mut panel : Node? = None
  let mut box : Node? = None
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_box && n.bg == 0x333333FFL {
      panel = Some(n)
    } else if n.kind == kind_box && panel is Some(_) && n.parent >= 0 && c.nodes[n.parent].bg == 0x333333FFL {
      box = Some(n)
    }
  }
  match (panel, box) {
    (Some(p), Some(b)) => (p, b)
    _ => abort("no panel and box filling it")
  }
}

///|
test "corners: Tester::mixed_corners lists every box drawn with corners not alike, and how it came to have them" {
  // the panel's right corners linked to a Mac window's, a box across its foot alone (all four alike), a box said each
  let t = Tester::new(
    fn(c) {
      foot_panel(10.0, InnerOr(Exact(26.0)))(c)
      c.box(style=style(radius=Corners(12.0, 12.0, 0.0, 0.0)), w=Px(40.0), h=Px(40.0), left=10.0, top=10.0, bg=0x555555FFL, fn() {  })
      |> ignore
    },
    w=400.0,
    h=200.0,
    window_corner=16.0,
    corners_held=false,
  )
  t.draw()
  let mixed = t.mixed_corners()
  assert_eq(mixed.length(), 2, msg=mixed.join("\n"))
  assert_true(mixed.iter().any(fn(m) { m.has_suffix("linked each") }), msg=mixed.join("\n"))
  assert_true(mixed.iter().any(fn(m) { m.has_suffix("(12, 12, 0, 0), said each") }), msg=mixed.join("\n"))
}
