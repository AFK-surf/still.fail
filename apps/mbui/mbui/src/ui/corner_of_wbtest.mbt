// Corners linked (corner_of.mbt): a corner says where it comes from, the chain is worked out from the window's corner
// each frame, and the corner rule holds what is linked to its link.

///|
/// A panel at the right of a window 400 by 200, 6 from its top, right and foot, its right corners linked to the
/// window's (6 in, 34 alone) and its left the ladder's 34; in its foot right corner, `d` from its right and foot, a
/// ground 30 square linked to the panel's corner there, 6 in (10 alone).
fn linked_panel(d : Double) -> (Ctx) -> Unit {
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
          fn() {
            c.box(
              style=style(radius=Linked(Follow(edge, 6.0, 10.0))),
              w=Px(30.0),
              h=Px(30.0),
              left=300.0 - 30.0 - d,
              top=188.0 - 30.0 - d,
              bg=0x555555FFL,
              fn() {  },
            )
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    })
  }
}

///|
/// The panel and the ground of linked_panel: their nodes.
fn linked_nodes() -> (Node, Node) {
  let c = g()
  let mut panel : Node? = None
  let mut ground : Node? = None
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.kind == kind_box && n.bg == 0x333333FFL {
      panel = Some(n)
    }
    if n.kind == kind_box && n.bg == 0x555555FFL {
      ground = Some(n)
    }
  }
  match (panel, ground) {
    (Some(p), Some(b)) => (p, b)
    _ => abort("no panel and ground")
  }
}

///|
test "corners linked: a panel's corners linked to a Mac window's follow it, a ground linked to the panel's follows that, the rule holds both" {
  let follow = concentric(16.0, 6.0)
  let t = Tester::new(linked_panel(6.0), w=400.0, h=200.0, window_corner=16.0)
  t.draw()
  let (p, b) = linked_nodes()
  assert_eq(corners4(p), (34.0, follow, follow, 34.0))
  assert_eq(corners4(b), (concentric(follow, 6.0), concentric(follow, 6.0), concentric(follow, 6.0), concentric(follow, 6.0)))
  assert_eq(t.corner_faults(), [])
}

///|
test "corners linked: the window square, each stands alone, worked out again; a ground's link as round as its half, a circle" {
  let t = Tester::new(linked_panel(6.0), w=400.0, h=200.0, corners_held=false)
  t.draw()
  let (p, b) = linked_nodes()
  assert_eq(corners4(p), (34.0, 34.0, 34.0, 34.0))
  // (the panel's 34 less 6 in: 29.2, past the ground's half, so drawn as a circle)
  assert_eq(b.radius, concentric(34.0, 6.0))
  assert_eq(b.corner(), 15.0)
  assert_true(t.corner_faults().iter().any(fn(f) { f.contains("whose drawn shape is not concentric") }), msg="\{t.corner_faults()}")
}

///|
test "corners linked: one standing elsewhere than its link says is said" {
  let t = Tester::new(linked_panel(8.0), w=400.0, h=200.0, window_corner=16.0, corners_held=false)
  t.draw()
  let faults = t.corner_faults()
  assert_true(faults.iter().any(fn(f) { f.contains("linked to follow") }), msg="\{faults}")
}

///|
test "corners linked: a link's radius, whether it follows, where it stands" {
  let t = Tester::new(
    fn(c) {
      c.with_theme({ ..Theme::light(), corner_fit: Some(fit_ranges) }, fn() { c.box(fn() {  }) |> ignore })
    },
    window_corner=16.0,
  )
  t.draw()
  g().corner_fit = Some(fit_ranges)
  let at = corner_roots()
  assert_eq(at, { window: 16.0, fit: Some(fit_ranges), zoom: 1.0 })
  let edge : CornerOf = Follow(Window, 6.0, 34.0)
  assert_eq(edge.radius(at), concentric(16.0, 6.0))
  assert_true(edge.follows(at))
  assert_eq(edge.inset(at), Some(6.0))
  assert_eq(edge.source(at), Some(16.0))
  // too far in to follow it (4.8, squarer than the ranges let a corner be): alone, standing nowhere it says
  let deep : CornerOf = Follow(Window, 14.0, 34.0)
  assert_eq(deep.radius(at), 34.0)
  assert_false(deep.follows(at))
  assert_eq(deep.inset(at), None)
  // a capsule 30 high in a 34 (a circle reads it as 32.52): 17.52 in, further than the ranges let; one 40 high, 12.52
  let own : CornerOf = Own(34.0)
  assert_eq(own.capsule_at(30.0, at), None)
  match own.capsule_at(40.0, at) {
    Some(d) => assert_true((d - (34.0 * smooth_round - 20.0)).abs() < 1.0e-9)
    None => fail("a capsule 40 high stands in a 34")
  }
}

///|
test "corners linked of the window's tree's nodes: worked out from the ranges of the theme the app tells its tree, as it tells them, no frame between; a Windows 11 window's 8, too square to follow 6 in, a button there alone; none told, as though there were none" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, window_corner=8.0)
  // (the app's theme's ranges, as its own signal says them)
  let fit : @signals.Signal[CornerFit?] = @signals.signal(None, same=fn(a, b) { a == b })
  let drawn : Ref[@view.NodeId?] = Ref(None)
  set_view_app(fn(root) {
    set_tree_theme(fn() { { ..Theme::light(), corner_fit: fit.get() } })
    root.box(fn(b) {
      b.width(Is(Some(32.0))).height(Is(Some(32.0))).radius(corner_of(Follow(Window, 6.0, 16.0))) |> ignore
      drawn.val = Some(b.id())
    })
    |> ignore
  })
  t.draw()
  let id = drawn.val.unwrap()
  let tree = view_tree().unwrap()
  // (the node's corner as the tree has it at the tester's moment, brought there, no frame drawn)
  let radius = fn() {
    tree.bring_to(t.time())
    tree.drawn().filter(fn(d) { d.id == id }).map(fn(d) { d.radius })
  }
  let seen = []
  for f in [None, Some(fit_ranges), None] {
    fit.set(f)
    seen.push((tree_corner_roots_now(), radius()))
  }
  assert_eq(seen[0], ({ window: 8.0, fit: None, zoom: 1.0 }, [concentric(8.0, 6.0)]), msg="none: followed, as any is")
  assert_eq(seen[1], ({ window: 8.0, fit: Some(fit_ranges), zoom: 1.0 }, [16.0]), msg="told: too square to follow, alone, at once")
  assert_eq(seen[2], seen[0], msg="none again: as before, at once")
}
