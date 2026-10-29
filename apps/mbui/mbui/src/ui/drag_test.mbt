// Who a press is (claim.mbt): a drag area lying in a list (a row swiped away across a list that scrolls up and down),
// a drag area holding one (a card swiped across over the list in it); whoever's way the finger goes past the slop
// first takes it, whoever holds whom.

///|
/// A list of rows, the second a drag area across; what it was moved by, and whether it was tapped, kept.
fn swipe_view(moved : Ref[Double], tapped : Ref[Bool]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.list("rows", 30, 40.0, fn(i) {
        if i == 1 {
          let id = c.id("swiped")
          c.drag_area(id, axis=Horizontal, w=Fill(1.0), h=Px(40.0), fn() {
            c.text("swipe me", size=10.0) |> ignore
          })
          |> ignore
          match c.drag_of(id) {
            Some(d) => {
              moved.val = moved.val + d.take_move().0
              if d.take_tap() {
                tapped.val = true
              }
            }
            None => ()
          }
        } else {
          c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
        }
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a drag area in a list: across first, it is the drag's and the list holds still; up or down first, the list's" {
  let moved = Ref::new(0.0)
  let tapped = Ref::new(false)
  let t = swipe_view(moved, tapped)
  t.draw()
  let (_, y, _, _) = t.rect_of("swipe me").unwrap()
  t.drag(250.0, y + 5.0, 100.0, y + 5.0)
  t.draw()
  assert_true(moved.val < -100.0)
  assert_eq(t.list_offset(), 0.0)
  moved.val = 0.0
  t.drag(150.0, y + 5.0, 150.0, y - 115.0)
  t.draw()
  assert_true(t.list_offset() > 80.0)
  assert_eq(moved.val, 0.0)
  assert_true(!tapped.val)
}

///|
/// A card that swipes across, a list of rows in it that scrolls up and down; what the card was moved by, and how its
/// press ended, kept.
fn card_view(moved : Ref[Double], ends : Ref[Int], taps : Ref[Int]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let id = c.id("card")
      c.drag_area(id, axis=Horizontal, w=Fill(1.0), h=Fill(1.0), fn() {
        c.list("in-card", 30, 40.0, fn(i) {
          c.box(h=Px(40.0), fn() { c.text("line \{i}", size=10.0) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
      match c.drag_of(id) {
        Some(d) => {
          moved.val = moved.val + d.take_move().0
          if d.take_end() {
            ends.val += 1
          }
          if d.take_tap() {
            taps.val += 1
          }
        }
        None => ()
      }
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a drag area holding a list: across first, it is the card's and the list holds still; up or down first, the list's" {
  let moved = Ref::new(0.0)
  let ends = Ref::new(0)
  let taps = Ref::new(0)
  let t = card_view(moved, ends, taps)
  t.draw()
  t.drag(250.0, 150.0, 100.0, 150.0)
  t.draw()
  assert_true(moved.val < -100.0)
  assert_eq(ends.val, 1)
  assert_eq(t.list_offset(), 0.0)
  moved.val = 0.0
  ends.val = 0
  t.drag(150.0, 200.0, 150.0, 80.0)
  t.draw()
  assert_true(t.list_offset() > 80.0)
  // the card's press let go: not moved, not ended, no tap
  assert_eq(moved.val, 0.0)
  assert_eq(ends.val, 0)
  assert_eq(taps.val, 0)
}

///|
test "dragged at 45°: no one's, till one way is clearly further" {
  let moved = Ref::new(0.0)
  let ends = Ref::new(0)
  let taps = Ref::new(0)
  let t = card_view(moved, ends, taps)
  t.draw()
  // as far across as down, past the slop both ways: neither takes it
  let diag = 30.0
  t.hold_drag(100.0, 100.0, 100.0 + diag, 100.0 + diag)
  t.draw()
  assert_eq(moved.val, 0.0)
  assert_eq(t.list_offset(), 0.0)
  // then on across: the card's
  let across = 120.0
  t.hold_drag(100.0 + diag, 100.0 + diag, 100.0 + diag + across, 100.0 + diag)
  t.release(100.0 + diag + across, 100.0 + diag)
  assert_true(moved.val > 0.0)
  assert_eq(t.list_offset(), 0.0)
  assert_eq(ends.val, 1)
}

///|
test "a list flung in the card is caught as the finger goes down: the press is the list's, the card's let go" {
  let moved = Ref::new(0.0)
  let ends = Ref::new(0)
  let taps = Ref::new(0)
  let t = card_view(moved, ends, taps)
  t.draw()
  // flung up fast
  t.drag(150.0, 280.0, 150.0, 40.0, steps=3)
  assert_true(t.list_moving())
  t.press_at(150.0, 150.0)
  assert_false(t.list_moving())
  t.release(150.0, 150.0)
  assert_eq(moved.val, 0.0)
  assert_eq(ends.val, 0)
  assert_eq(taps.val, 0)
}

///|
test "a press no one takes is a tap: the row's" {
  let moved = Ref::new(0.0)
  let tapped = Ref::new(false)
  let t = swipe_view(moved, tapped)
  t.draw()
  let (x, y, _, _) = t.rect_of("swipe me").unwrap()
  t.press_at(x + 5.0, y + 5.0)
  t.release(x + 5.0, y + 5.0)
  assert_true(tapped.val)
  assert_eq(moved.val, 0.0)
  assert_eq(t.list_offset(), 0.0)
}

///|
/// A rounded, clipped box 200 × 120 at (50, 50), made a drag area across (Ctx::drag_on) when `on`, drawn when `drawn`.
fn shaped_view(on : Ref[Bool], drawn : Ref[Bool], moved : Ref[Double], taps : Ref[Int]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let id = c.id("shaped")
      if on.val {
        c.drag_on(id, axis=Horizontal)
      }
      c.box(w=Fill(1.0), h=Fill(1.0), pl=50.0, pt=50.0, fn() {
        if drawn.val {
          c.box(w=Px(200.0), h=Px(120.0), radius=40.0, clip=true, bg=0x336699FFL, id~, fn() {
            c.text("held", size=10.0) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      match c.drag_of(id) {
        Some(d) => {
          moved.val = moved.val + d.take_move().0
          if d.take_tap() {
            taps.val += 1
          }
        }
        None => ()
      }
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "drag_on: a box drawn as it is, rounded and clipped, a drag area with no node of its own" {
  let on = Ref::new(false)
  let drawn = Ref::new(true)
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = shaped_view(on, drawn, moved, taps)
  t.draw()
  let plain = t.dump()
  on.val = true
  t.draw()
  // the same nodes as the box alone
  assert_eq(t.dump(), plain)
  t.drag(220.0, 110.0, 80.0, 110.0)
  t.draw()
  assert_true(moved.val < -100.0)
  t.press_at(150.0, 110.0)
  t.release(150.0, 110.0)
  assert_eq(taps.val, 1)
}

///|
test "drag_on: a press where a rounded clip cut it away is not its, as a tap there is not" {
  // the drag area's box filling a card rounded 40 and clipped: its top left corner, the card's cut away
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      let id = c.id("in-card")
      c.drag_on(id, axis=Horizontal)
      c.box(w=Fill(1.0), h=Fill(1.0), pl=50.0, pt=50.0, fn() {
        c.box(w=Px(200.0), h=Px(120.0), radius=40.0, clip=true, fn() {
          c.box(w=Fill(1.0), h=Fill(1.0), bg=0x336699FFL, id~, fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
      match c.drag_of(id) {
        Some(d) => {
          moved.val = moved.val + d.take_move().0
          if d.take_tap() {
            taps.val += 1
          }
        }
        None => ()
      }
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  // within the card's rect, outside its corner's curve
  t.drag(53.0, 53.0, 200.0, 53.0)
  t.draw()
  assert_eq(moved.val, 0.0)
  t.press_at(53.0, 53.0)
  t.release(53.0, 53.0)
  assert_eq(taps.val, 0)
  // inside it: its
  t.drag(150.0, 110.0, 60.0, 110.0)
  t.draw()
  assert_true(moved.val < -50.0)
}

///|
test "drag_on without its box drawn that frame: nothing there to press" {
  let on = Ref::new(true)
  let drawn = Ref::new(false)
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = shaped_view(on, drawn, moved, taps)
  t.draw()
  t.drag(220.0, 110.0, 80.0, 110.0)
  t.draw()
  assert_eq(moved.val, 0.0)
  assert_eq(taps.val, 0)
}

///|
test "pointer_at: each event by its own time, down, moved, up, not by the frames that take them" {
  let t = @ui.Tester::new(fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), fn() {  }) |> ignore }, w=200.0, h=200.0)
  t.draw()
  let gap_ms = 8.0
  let start = t.time()
  t.touch(0, 50.0, 50.0)
  assert_eq(t.ctx().pointer_at(), start)
  // two moves 8 ms apart, no frame between them
  t.advance(gap_ms)
  t.touch(1, 60.0, 50.0)
  let first = t.ctx().pointer_at()
  t.advance(gap_ms)
  t.touch(1, 70.0, 50.0)
  assert_eq(t.ctx().pointer_at() - first, gap_ms)
  t.advance(gap_ms)
  t.touch(2, 70.0, 50.0)
  assert_eq(t.ctx().pointer_at(), start + 3.0 * gap_ms)
  t.draw()
}

///|
/// A list of rows that scrolls up and down, a pager over it across, and a thin drag area across to be held first (a
/// column's edge) on the list's first row; what the area was moved by, its taps and the pager's page kept.
fn held_edge_view(
  moved : Ref[Double],
  taps : Ref[Int],
  pointing? : @ui.Pointing = Finger,
) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let id = c.id("edge")
      c.list("rows", 30, 40.0, fn(i) {
        c.box(h=Px(40.0), fn() { c.text("row \{i}", size=10.0) |> ignore }) |> ignore
      })
      |> ignore
      c.layer(fn() {
        c.drag_on(id, axis=Horizontal, hold=true)
        c.box(left=140.0, top=0.0, w=Px(20.0), h=Px(300.0), id~, fn() {  }) |> ignore
      })
      |> ignore
      match c.drag_of(id) {
        Some(d) => {
          moved.val = moved.val + d.take_move().0
          if d.take_tap() {
            taps.val += 1
          }
        }
        None => ()
      }
    },
    w=300.0,
    h=300.0,
    pointing~,
  )
}

///|
test "drag_on hold: a finger swiped across it at once moves it not, nor taps it" {
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = held_edge_view(moved, taps)
  t.draw()
  t.drag(150.0, 100.0, 250.0, 100.0)
  t.draw()
  assert_eq(moved.val, 0.0)
  assert_eq(taps.val, 0)
  assert_eq(t.haptics(), [])
}

///|
test "drag_on hold: a finger scrolling up and down over it scrolls the list" {
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = held_edge_view(moved, taps)
  t.draw()
  t.drag(150.0, 250.0, 150.0, 100.0)
  t.draw()
  assert_true(t.list_offset() > 100.0)
  assert_eq(moved.val, 0.0)
  assert_eq(taps.val, 0)
}

///|
test "drag_on hold: held still a long press's time, felt, then it follows the finger across" {
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = held_edge_view(moved, taps)
  t.draw()
  let short = @ui.long_press_ms / 8.0
  t.press_at(150.0, 100.0)
  t.run_for(@ui.long_press_ms - short)
  assert_eq(t.haptics(), [])
  t.run_for(short * 2.0)
  assert_eq(t.haptics(), [LongPress])
  for i in 1..=8 {
    t.advance(@ui.input_step_ms)
    t.touch(1, 150.0 + i.to_double() * 10.0, 100.0)
    t.draw()
  }
  t.release(230.0, 100.0)
  assert_eq(moved.val, 80.0)
  assert_eq(taps.val, 0)
  assert_eq(t.list_offset(), 0.0)
}

///|
test "drag_on hold: a finger's quick tap on it is its tap" {
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = held_edge_view(moved, taps)
  t.draw()
  t.press_at(150.0, 100.0)
  t.release(150.0, 100.0)
  assert_eq(taps.val, 1)
  assert_eq(moved.val, 0.0)
}

///|
test "drag_on hold: a mouse drags it at once" {
  let moved = Ref::new(0.0)
  let taps = Ref::new(0)
  let t = held_edge_view(moved, taps, pointing=Mouse)
  t.draw()
  t.drag(150.0, 100.0, 250.0, 100.0)
  t.draw()
  assert_true(moved.val > 80.0)
  assert_eq(t.haptics(), [])
}

///|
/// A drag area over the whole window (a remote screen's stage), a panel over it that stops the wheel (a popover's: its
/// box laid in a layer) with a button in it; how often the area was pressed down, tapped, and the button clicked.
fn panel_over_area(downs : Ref[Int], taps : Ref[Int], clicks : Ref[Int]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      let area = c.id("stage")
      let button = c.id("button")
      match c.drag_of(area) {
        Some(d) => {
          if d.down {
            downs.val += 1
          }
          if d.take_tap() {
            taps.val += 1
          }
        }
        None => ()
      }
      if c.clicked(button) {
        clicks.val += 1
      }
      c.drag_area(area, axis=Free, w=Fill(1.0), h=Fill(1.0), fn() {
        c.layer(fn() {
          let panel = c.box(id=c.id("panel"), w=Px(100.0), h=Px(100.0), fn() {
            c.box(id=button, w=Px(60.0), h=Px(40.0), fn() { c.text("原画", size=10.0) |> ignore }) |> ignore
          })
          c.stop_wheel(panel)
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
}

///|
test "a press on a panel that stops the wheel is the panel's: the drag area under it is not pressed, nor tapped" {
  let downs = Ref::new(0)
  let taps = Ref::new(0)
  let clicks = Ref::new(0)
  let t = panel_over_area(downs, taps, clicks)
  t.draw()
  t.press_at(20.0, 20.0)
  t.draw()
  t.release(20.0, 20.0)
  t.draw()
  assert_eq(clicks.val, 1)
  assert_eq(downs.val, 0)
  assert_eq(taps.val, 0)
  // beside the panel, the area is pressed as ever
  t.tap(200.0, 200.0)
  t.draw()
  assert_eq(taps.val, 1)
}
