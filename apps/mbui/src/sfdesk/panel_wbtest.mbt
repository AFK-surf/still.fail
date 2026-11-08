// The side panel beside the page (panel.mbt side_beside): what it puts past its left edge.

///|
fn panel_tree_frames(retained : Bool, width : Double) -> Array[(Double, Double, Double, Double)?] raise {
  side_slide_reset()
  let open = @signals.signal(true)
  let draw_panel = fn(c : @ui.Ctx) {
    c.box(left=0.0, top=100.0, style=@ui.style(w=Fixed(32.0), h=Fixed(18.0)), bg=0xff0000ffL, fn() { }) |> ignore
  }
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    @ui.old_views_here(c)
  }, w=width, h=800.0, platform=2, tree=fn(root) {
    if retained {
      side_beside_node(root, "test", fn() { open.get() }, fn() { root.window().0 },
        fn(p, _left) { p.grow(Is(1.0)) |> ignore },
        fn(p, _over) { @ui.old(p, draw_panel).grow(Is(1.0)) |> ignore })
    } else {
      @ui.old(root, fn(c) {
        side_beside(c, "test", open.get(), side_width(c.width), fn() { }, fn() { draw_panel(c) })
      }).grow(Is(1.0)) |> ignore
    }
  })
  t.draw()
  let frames = [panel_visible(t, width)]
  side_changing("test", ["a"], "a", false)
  open.set(false)
  t.draw()
  t.run_for(@ui.move_most_ms / 2.0)
  frames.push(panel_visible(t, width))
  t.run_for(@ui.move_most_ms / 2.0)
  frames.push(panel_visible(t, width))
  side_changing("test", [], "", true)
  open.set(true)
  t.draw()
  t.run_for(@ui.move_most_ms / 2.0)
  frames.push(panel_visible(t, width))
  t.run_for(@ui.move_most_ms / 2.0)
  frames.push(panel_visible(t, width))
  side_changing("test", ["a"], "a", false)
  open.set(false)
  t.draw()
  t.run_for(@ui.move_most_ms / 4.0)
  frames.push(panel_visible(t, width))
  side_changing("test", [], "", true)
  open.set(true)
  t.draw()
  frames.push(panel_visible(t, width))
  t.run_for(@ui.move_most_ms / 4.0)
  frames.push(panel_visible(t, width))
  assert_eq(t.squeeze_faults(), [])
  side_slide_reset()
  frames
}

///|
fn panel_visible(t : @ui.Tester, width : Double) -> (Double, Double, Double, Double)? {
  for a in t.drawn_instances() {
    if a[5] == 0.0 && a[2] == 32.0 && a[3] == 18.0 {
      let x = dmax(a[0], a[16])
      let y = dmax(a[1], a[17])
      let w = dmax(0.0, dmin(width, dmin(a[0] + a[2], a[18])) - x)
      let h = dmax(0.0, dmin(a[1] + a[3], a[19]) - y)
      if w > 0.0 && h > 0.0 { return Some((x, y, w, h)) }
    }
  }
  None
}

///|
test "retained side panel preserves beside and overlay positions across closing and reopening" {
  for width in [1400.0, 700.0] {
    let retained = panel_tree_frames(true, width)
    let old = panel_tree_frames(false, width)
    for i in 0..<old.length() {
      match (retained[i], old[i]) {
        (Some(a), Some(b)) =>
          for (x, y) in [(a.0, b.0), (a.1, b.1), (a.2, b.2), (a.3, b.3)] {
            assert_true((x - y).abs() < 0.00000001, msg="\{width}: \{retained} vs \{old}")
          }
        (None, None) => ()
        _ => fail("\{width}: \{retained} vs \{old}")
      }
    }
  }
}

///|
test "the side panel at rest cuts nothing past its left edge: its edge's handle, half over the page, shows whole; sliding, it is cut to its column" {
  side_slide_reset()
  let open = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        side_beside(c, "test", open.val, 400.0, fn() {  }, fn() {
          c.box(style=@ui.style(w=Full, h=Full), fn() {
            c.box(left=-20.0, top=100.0, fn() { c.text("past its edge", size=13.0) |> ignore }) |> ignore
          })
          |> ignore
        })
      })
    },
    w=1400.0,
    h=800.0,
    platform=2,
  )
  t.draw()
  let (x, _, w, _) = t.shown_of("past its edge").unwrap()
  assert_eq(x, 1000.0 - 20.0)
  assert_true(w > 20.0, msg="\{w}")
  // closing: cut to the column as it narrows
  side_changing("test", ["a"], "a", false)
  open.val = false
  t.draw()
  t.run_for(@ui.move_most_ms / 2.0)
  match t.shown_of("past its edge") {
    Some((x, _, _, _)) => assert_true(x > 1000.0, msg="\{x}")
    None => ()
  }
  side_slide_reset()
}
