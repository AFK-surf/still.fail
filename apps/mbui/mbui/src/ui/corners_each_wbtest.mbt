// Each corner its own (Radius::Corners, scene.mbt 36-39): drawn so, cut so, and held by the corner rule corner by
// corner: a box's corner lying in a container's corner follows that corner, its others its own.

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
/// A panel at the right of a window 400 by 200, 6 from its top, right and foot (a Mac's tape's page, in use), its corner
/// the ladder's 34 standing alone, in the ladder's theme; across its foot `d` from its sides and foot a box 60 high,
/// its own corner `own`.
fn foot_panel(d : Double, own : Radius) -> (Ctx) -> Unit {
  fn(c) {
    c.with_theme({ ..Theme::light(), corner_ladder: [34.0, 26.0, 18.0, 10.0], corner_fit: Some(fit_ranges) }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(w=Px(300.0), h=Px(188.0), left=94.0, top=6.0, radius=34.0, bg=0x333333FFL, pad=d, justify=JEnd, fn() {
          c.box(style=style(w=Full, h=Fixed(60.0), radius=own, bg=Faint), fn() {  }) |> ignore
        })
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
test "corners: a panel's corners in the window's follow it, its others stand alone; a box across its foot follows each foot corner it lies in" {
  let follow = concentric(16.0, 6.0)
  // a Mac's window, 16 round: the panel's right corners in its, 6 in, 11.2; its left ones in none, 34. The box 6.5 in:
  // its right foot corner in the panel's 11.2, 6 round; its left in its 34, 28.8 (off the ladder: the place its right
  // one has it); its top's, in no corner, the card's 26 it has alone
  for own in [Radius::Exact(26.0), InnerOr(Exact(26.0))] {
    let t = Tester::new(foot_panel(6.5, own), w=400.0, h=200.0, window_corner=16.0)
    t.draw()
    let (p, b) = foot_nodes()
    assert_eq(corners4(p), (34.0, follow, follow, 34.0))
    assert_eq(corners4(b), (26.0, 26.0, concentric(follow, 6.5), concentric(34.0, 6.5)))
    assert_eq(t.corner_faults(), [])
  }
  // the ladder's 10 in: its left foot corner the card's 26, its right too far in to follow the 11.2 (3.2, as good as
  // square): its own kept there, and said where it would fit
  let t = Tester::new(foot_panel(10.0, Radius::Exact(26.0)), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let (_, b) = foot_nodes()
  assert_eq(corners4(b), (26.0, 26.0, 26.0, 26.0))
  let faults = t.corner_faults()
  assert_true(
    faults.length() == 1 && faults[0].contains("bottom right") && faults[0].contains("too far in to follow it"),
    msg="\{faults}",
  )
  // a square window: the panel 34 all round, the box 10 in the card's 26 all round, one corner as before
  let t = Tester::new(foot_panel(10.0, InnerOr(Exact(26.0))), w=400.0, h=200.0)
  t.draw()
  let (p, b) = foot_nodes()
  assert_true(p.radii is None && p.radius == 34.0)
  assert_true(b.radii is None && b.radius == 26.0, msg="\{corners4(b)}")
  assert_eq(t.corner_faults(), [])
}

///|
test "corners: radius=Inner follows the container's matching corner at each of its corners" {
  let follow = concentric(16.0, 6.0)
  let t = Tester::new(foot_panel(6.5, Inner), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let (_, b) = foot_nodes()
  let inner = concentric(follow, 6.5)
  let outer = concentric(34.0, 6.5)
  assert_eq(corners4(b), (outer, inner, inner, outer))
}
