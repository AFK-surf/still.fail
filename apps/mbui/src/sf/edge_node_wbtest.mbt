// A column's edge as a node (edge_node): its tip by the pointer, as edge_tip's is, where the pointer is in the window,
// whatever moves what holds the edge.

///|
/// A window 400 by 300, a mouse's: in it, at (`at`), a box drawn `scale` as big about its top left, holding an edge 20
/// by 200 at its left; its tips over all of it. The pointer rested on the edge at (110, 100) a while, then what holds the
/// edge moved down `by` (the pointer still on it), the frame it asks for drawn (`away`: the pointer gone off it, a
/// moment into its tip's going, instead): where its tip was each time, in the window.
fn edge_tip_rects(
  scale : Double,
  by : Double,
  away? : Bool = false,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let shift = @signals.signal(0.0, same=fn(a, b) { a == b })
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(h) {
      h
      .over(Is(true))
      .offset(By(fn() { (100.0, 20.0 + shift.get()) }))
      .scale(Is(scale), about=At(0.0, 0.0))
      |> ignore
      h.box(fn(e) {
        e.width(Is(Some(20.0 / scale))).height(Is(Some(200.0 / scale))) |> ignore
        edge_node(
          e,
          fn() { "调整宽度" },
          fn() { 240.0 },
          fn() { 200.0 },
          fn() { 300.0 },
          Right,
          fn(_, _) {  },
          fn(_) {  },
          tips~,
          side=Right,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  let tip = fn() raise {
    match t.semantics().filter(fn(s) { s.role == Tooltip && s.label == "调整宽度" }) {
      [s, ..] => s.rect
      [] => fail("no tip: \{Repr(t.semantics().map(fn(s) { (s.role, s.label) }))}")
    }
  }
  t.move_to(110.0, 100.0)
  t.run_for(edge_tip_ms + tip_settled_ms)
  let first = tip()
  if away {
    // (the pointer off the edge: its tip going, a moment into it)
    t.move_to(300.0, 250.0)
    t.run_for(@kit.pop_out_ms / 2.0)
  } else {
    shift.set(by)
    t.frame()
  }
  (first, tip())
}

///|
test "an edge's tip by the pointer: beside where the pointer is, its middle level with it, edge_tip_gap off; what holds the edge moved under the still pointer, drawn by it still, as big or drawn bigger" {
  for scale in [1.0, 2.0] {
    let (first, after) = edge_tip_rects(scale, 30.0)
    let (x, y, _, h) = first
    assert_true((x - (110.0 + edge_tip_gap)).abs() < 0.5 && (y + h / 2.0 - 100.0).abs() < 0.5, msg="scale \{scale}: \{Repr(first)}")
    assert_eq(after, first, msg="scale \{scale}: moved under the pointer")
  }
}

///|
/// A window 400 by 300 (`platform`: 0 a mouse's, 2 a finger's) holding an edge 20 by 200 at (100, 20), the part of it
/// past 10 across over what is beside its column: what is done with it, in order, as `presses` go (each down at its
/// first point and let go at its second, `gap_ms` after the press before, as a host hands them on).
fn edge_presses(
  platform : Int,
  presses : Array[((Double, Double), (Double, Double))],
) -> Array[String] {
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((100.0, 20.0))) |> ignore
      h.box(fn(e) {
        e.width(Is(Some(20.0))).height(Is(Some(200.0))) |> ignore
        edge_node(
          e,
          fn() { "调整宽度" },
          fn() { 240.0 },
          fn() { 200.0 },
          fn() { 300.0 },
          Right,
          fn(r, _) { said.push("\{r}") },
          fn(on) { said.push("held \{on}") },
          on_beside=fn(x) { x >= 10.0 },
          beside=fn(_) { said.push("beside") },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let mut at = t.time() + edge_gap_ms
  for p in presses {
    let ((x0, y0), (x1, y1)) = p
    t.advance(at - t.time())
    t.touch_at(0, x0, y0, at)
    t.touch_at(2, x1, y1, at)
    at = at + edge_gap_ms
  }
  said
}

///|
/// How far apart the presses of edge_presses are: well within two clicks' while.
let edge_gap_ms : Double = 100.0

///|
test "an edge pressed and let go 3 off it (within the slop): no press of it, none of what is beside it, nor a first of two; let go on it, its press" {
  for platform in [0, 2] {
    // (down on the part over what is beside it, let go just past its right)
    assert_eq(edge_presses(platform, [((118.0, 100.0), (123.0, 100.0))]), ["held true", "held false"], msg="\{platform}")
    // (down in its gap, let go just past its left, then once on it: one press, no second of two)
    assert_eq(
      edge_presses(platform, [((101.0, 100.0), (97.0, 100.0)), ((101.0, 100.0), (101.0, 100.0))]),
      ["held true", "held false", "held true", "held false", "Pressed"],
      msg="\{platform}",
    )
    // (let go on it: the part over what is beside it, that one's; in its gap, its press)
    assert_eq(edge_presses(platform, [((118.0, 100.0), (118.0, 100.0))]), ["held true", "held false", "beside"])
    assert_eq(edge_presses(platform, [((101.0, 100.0), (101.0, 100.0))]), ["held true", "held false", "Pressed"])
  }
}

///|
test "an edge pressed twice in its gap: its own width again where both are at one place; far apart along it, two presses" {
  for platform in [0, 2] {
    assert_eq(
      edge_presses(platform, [((101.0, 100.0), (101.0, 100.0)), ((101.0, 101.0), (101.0, 101.0))]),
      ["held true", "held false", "Pressed", "held true", "held false", "Twice"],
      msg="\{platform}",
    )
    assert_eq(
      edge_presses(platform, [((101.0, 60.0), (101.0, 60.0)), ((101.0, 160.0), (101.0, 160.0))]),
      ["held true", "held false", "Pressed", "held true", "held false", "Pressed"],
      msg="\{platform}",
    )
  }
}

///|
/// A window 400 by 300, a mouse's: at (100, 20) a box drawn `scale` as big about its top left, holding an edge 20 by
/// 200 of the window's at its left. What is done with it, in order, as it is pressed at `down` and let go at `up`
/// `held_ms` after, no move told between, no frame drawn.
fn edge_scaled_press(scale : Double, down : (Double, Double), up : (Double, Double), held_ms : Double) -> Array[String] {
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((100.0, 20.0))).scale(Is(scale), about=At(0.0, 0.0)) |> ignore
      h.box(fn(e) {
        e.width(Is(Some(20.0 / scale))).height(Is(Some(200.0 / scale))) |> ignore
        edge_node(
          e,
          fn() { "调整宽度" },
          fn() { 240.0 },
          fn() { 200.0 },
          fn() { 300.0 },
          Right,
          fn(r, _) { said.push("\{r}") },
          fn(on) { said.push("held \{on}") },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let at = t.time() + edge_gap_ms
  t.advance(at - t.time())
  t.touch_at(0, down.0, down.1, at)
  t.advance(held_ms)
  t.touch_at(2, up.0, up.1, at + held_ms)
  said
}

///|
test "an edge drawn bigger, a mouse's let go 10 across the window from where it went down, no move told: its drag's end there, no press of it, though that is 5 of its own; held long and let go where it went down, its press" {
  for scale in [1.0, 2.0] {
    for held_ms in [edge_gap_ms, @ui.long_press_ms * 2.0] {
      assert_eq(
        edge_scaled_press(scale, (105.0, 100.0), (115.0, 100.0), held_ms),
        ["held true", "Dropped(250)", "held false"],
        msg="scale \{scale}, held \{held_ms}",
      )
    }
    assert_eq(
      edge_scaled_press(scale, (105.0, 100.0), (105.0, 100.0), @ui.long_press_ms * 2.0),
      ["held true", "held false", "Pressed"],
      msg="scale \{scale}",
    )
  }
}

///|
/// A window 400 by 300 (`platform`: 0 a mouse's, 2 a finger's) holding an edge 20 by 200 at (100, 20), of a column
/// 240 wide between 200 and 300: pressed at (105, 100) at `t0`, held still long_press_ms twice over, moved `moves`
/// along (each slow_drag_ms after the one before), let go at the last. What was felt, in order, and the widths said.
fn edge_felt(platform : Int, moves : Array[Double]) -> (Array[@ui.Haptic], Array[Double]) {
  let widths : Array[Double] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(h) {
      h.over(Is(true)).offset(Is((100.0, 20.0))) |> ignore
      h.box(fn(e) {
        e.width(Is(Some(20.0))).height(Is(Some(200.0))) |> ignore
        edge_node(
          e,
          fn() { "调整宽度" },
          fn() { 240.0 },
          fn() { 200.0 },
          fn() { 300.0 },
          Right,
          fn(r, _) {
            match r {
              Dragging(w) | Dropped(w) => widths.push(w)
              _ => ()
            }
          },
          fn(_) {  },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let t0 = t.time() + edge_gap_ms
  t.advance(edge_gap_ms)
  t.touch_at(0, 105.0, 100.0, t0)
  let held_at = t0 + @ui.long_press_ms * 2.0
  t.advance(held_at - t.time())
  tree.bring_to(held_at)
  let mut at = held_at
  for m in moves {
    at = at + edge_slow_ms
    t.advance(at - t.time())
    t.touch_at(1, 105.0 + m, 100.0, at)
  }
  at = at + edge_slow_ms
  t.advance(at - t.time())
  t.touch_at(2, 105.0 + (if moves.length() > 0 { moves[moves.length() - 1] } else { 0.0 }), 100.0, at)
  (t.haptics(), widths)
}

///|
let edge_slow_ms : Double = 50.0

///|
test "an edge felt: a finger's hold taken (LongPress), then its most reached (TextHandleMove), its least (again), the way between felt no more; a mouse's needs no hold and nothing is felt but the ends" {
  // (a finger: +60 is its most (300), +70 past it still there (felt once), -40 back between, -100 its least (200))
  let (felt, widths) = edge_felt(2, [30.0, 60.0, 70.0, -40.0, -100.0])
  assert_eq(felt, [LongPress, TextHandleMove, TextHandleMove], msg="\{Repr(felt)} \{Repr(widths)}")
  assert_eq(widths, [270.0, 300.0, 300.0, 200.0, 200.0, 200.0])
  // (a mouse: no hold, the ends alone)
  let (felt, _) = edge_felt(0, [60.0, -100.0])
  assert_eq(felt, [TextHandleMove, TextHandleMove], msg="\{Repr(felt)}")
  // (held and let go where it went down: nothing felt but the hold; let go after a hold, a drag's end at its width)
  let (felt, widths) = edge_felt(2, [])
  assert_eq((felt, widths), ([LongPress], [240.0]))
}

///|
test "an edge's tip by the pointer, the pointer gone off the edge: it goes where it was, not after the pointer nor to the edge's middle" {
  let (first, going) = edge_tip_rects(1.0, 0.0, away=true)
  // (drawn a little smaller as it goes, about its edge by the pointer's point: that edge and its middle where they were)
  let (x, y, _, h) = first
  let (gx, gy, _, gh) = going
  assert_true((gx - x).abs() < 0.5 && (gy + gh / 2.0 - (y + h / 2.0)).abs() < 0.5, msg="going: \{Repr(going)} from \{Repr(first)}")
}
