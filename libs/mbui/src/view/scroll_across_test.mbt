// A row that scrolls across in a node (View::scrolls with Scroll::across), as an old view's box scrolled sideways
// (ui's Ctx::sideways): 300 wide, holding ten cells 60 wide (600 in all: it can go 300), in a column that scrolls up
// and down 100 tall, 150 below the column's top, 400 more under it.

///|
priv struct AcrossCase {
  tree : @view.Tree
  across : @view.Scroll
  column : @view.Scroll
  cells : @signals.Signal[Int]
  focus : Ref[@view.NodeId?]
  row : Ref[@view.NodeId?]
}

///|
/// The row in the column, its cells `cells` of them, with its bar along its foot where `bar` says.
fn across_case(bar? : Bool = false, now? : Ref[Double] = Ref(0.0)) -> AcrossCase {
  let across = @view.Scroll::across()
  let column = @view.Scroll::new()
  let cells = @signals.signal(10, same=fn(a, b) { a == b })
  let focus : Ref[@view.NodeId?] = Ref(None)
  let row : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(column, fn(oh) {
          oh.box(fn(gap) { gap.height(Is(Some(150.0))) |> ignore }) |> ignore
          oh.box(fn(r) {
            row.val = Some(r.id())
            // (its cells side by side)
            let held = fn(rh : @view.View) {
              rh.row(Is(true)) |> ignore
              rh.each(at_once=true, fn() { Array::makei(cells.get(), fn(i) { i }) }, fn(i) { i }, fn(c, i) {
                c.width(Is(Some(60.0))).height(Is(Some(40.0))).ground(Is(0x101010FFL)) |> ignore
                if i.untracked() == 9 {
                  c.focusable(Is(true)) |> ignore
                  focus.val = Some(c.id())
                }
              })
            }
            if bar {
              r.scrolls(across, bar=across_bar(), bar_in=10.0, held) |> ignore
            } else {
              r.scrolls(across, held) |> ignore
            }
          })
          |> ignore
          oh.box(fn(gap) { gap.height(Is(Some(400.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=now.val) |> ignore
  { tree, across, column, cells, focus, row }
}

///|
fn across_bar() -> @view.ScrollBar {
  {
    drawn: fn() { true },
    ink: fn() { 0x00000042L },
    ink_held: fn() { 0x00000073L },
    ease: fn(t) { t },
    size: 3.0,
    inset: 2.0,
    least: 28.0,
    near: 12.0,
    grab: 4.0,
    hold_ms: 900.0,
    fade_ms: 200.0,
  }
}

///|
test "scrolls across: the wheel across moves it as far as it goes, as much across as up or down too; up or down, the column it is in; at its end across, nothing" {
  let k = across_case()
  // (the column scrolled to show the row: it at 150 to 190 of it, 100 down shows 50 to 90 of the window)
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let column = k.column.at(k.tree)
  let took = k.tree.wheel_at(150.0, 70.0, 120.0, 0.0, 0, 10.0)
  let first = k.across.at(k.tree)
  k.tree.wheel_at(150.0, 70.0, 50.0, 50.0, 0, 20.0) |> ignore
  let even = k.across.at(k.tree)
  for i in 0..<4 {
    k.tree.wheel_at(150.0, 70.0, 120.0, 0.0, 0, 30.0 + i.to_double()) |> ignore
  }
  let end = k.across.at(k.tree)
  // (at its end: on to what holds it, which takes nothing across; still at its end)
  k.tree.wheel_at(150.0, 70.0, 120.0, 0.0, 0, 40.0) |> ignore
  let past = k.across.at(k.tree)
  // (up or down over it: the column it is in, it as it was)
  k.tree.wheel_at(150.0, 70.0, 0.0, -30.0, 0, 50.0) |> ignore
  let down = (k.across.at(k.tree), k.column.at(k.tree))
  // (where the column has it now, 80 to 120 of the window, cut at the column's foot at 100: across again, back)
  k.tree.frame(390.0, 844.0) |> ignore
  k.tree.wheel_at(150.0, 90.0, -100.0, 0.0, 0, 60.0) |> ignore
  assert_eq(
    (column, took, first, even, end, past, down, k.across.at(k.tree)),
    (100.0, true, 120.0, 170.0, 300.0, 300.0, (300.0, 70.0), 200.0),
  )
}

///|
test "scrolls across: a hold on it moved across past the slop its own (up or down, the column's); dragged as it moves; let go moving, flung on and slowing to rest" {
  let k = across_case()
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (down on the row at 70: up past the slop, the column's; across the way it cannot go, not its; across, its)
  let at = k.tree.claimers_at(150.0, 70.0)
  let up = k.tree.claimer_of(at, 0.0, -20.0)
  let back = k.tree.claimer_of(at, 20.0, 0.0)
  let id = match k.tree.claimer_of(at, -20.0, 0.0) {
    Some(id) => id
    None => @halt.saying("not taken over")
  }
  k.tree.drag_at(id, Down, 160.0, 70.0, 100.0) |> ignore
  k.tree.drag_at(id, Moved, 140.0, 70.0, 110.0) |> ignore
  let taken = k.across.at(k.tree)
  k.tree.drag_at(id, Moved, 120.0, 70.0, 120.0) |> ignore
  let dragged = k.across.at(k.tree)
  k.tree.drag_at(id, Up, 120.0, 70.0, 120.0) |> ignore
  k.tree.advance(fling_on_at)
  let on = k.across.at(k.tree)
  k.tree.advance(fling_long_after_at)
  let rest = k.across.at(k.tree)
  assert_eq(
    (up == Some(id), back, taken, dragged, on > dragged, rest > on, rest <= 300.0, k.column.at(k.tree)),
    (false, None, 12.0, 32.0, true, true, true, 100.0),
    msg="\{on} \{rest}",
  )
}

///|
test "scrolls across: the focus come to its last cell, out of the sight of the row and of the column it is in: the row brought to it across first, the column down to where the row then has it" {
  let k = across_case()
  k.tree.focus_to(k.focus.val, visible=true) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (the cell at 540 to 600 of the row's: it at 300; the row at 150 to 190 of the column's: it at 90)
  assert_eq((k.across.at(k.tree), k.column.at(k.tree)), (300.0, 90.0))
}

///|
test "scrolls across, with its bar: room under its cells for it while it can go, its thumb along its foot, 10 in from either end; its cells made narrower than it: no room, no bar; wider again, both" {
  let now = Ref(0.0)
  let k = across_case(bar=true, now~)
  let tall = fn() {
    k.tree.frame(390.0, 844.0, now=now.val) |> ignore
    match k.tree.drawn().search_by(fn(d) { Some(d.id) == k.row.val }) {
      Some(i) => k.tree.drawn()[i].h
      None => -1.0
    }
  }
  let wide = tall()
  k.cells.set(4)
  let narrow = tall()
  k.cells.set(10)
  let again = tall()
  // (the column scrolled to show the row, 50 to 97 of the window; the row scrolled across: its bar out)
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
  k.tree.frame(390.0, 844.0, now=now.val) |> ignore
  k.tree.wheel_at(150.0, 70.0, 100.0, 0.0, 0, 10.0) |> ignore
  now.val = 500.0
  k.tree.frame(390.0, 844.0, now=500.0) |> ignore
  let thumb = k.tree.drawn().iter().find_first(fn(d) { d.h == 3.0 && d.alpha > 0.0 }).map(fn(d) { (d.y, d.x >= 10.0, d.x + d.w <= 290.0) })
  // (40 and its bar's 3 with 2 either side; its thumb 2 above its foot: 50 + 47 - 2 - 3)
  assert_eq((wide, narrow, again, thumb), (47.0, 40.0, 47.0, Some((92.0, true, true))))
}

///|
/// A node 300 by 100 that scrolls (`across` as said), holding `w` by `h`: whether it scrolls now (Tree::scrolls_now).
fn scrolls_now_of(across : Bool, w : Double, h : Double) -> Bool {
  let id : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        id.val = Some(v.id())
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(if across { @view.Scroll::across() } else { @view.Scroll::new() }, fn(held) {
          held.box(fn(b) { b.width(Is(Some(w))).height(Is(Some(h))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  tree.scrolls_now(id.val.unwrap())
}

///|
test "scrolls now, the way it scrolls alone: up and down taller than it, not wider; across wider, not taller" {
  assert_eq(
    (
      scrolls_now_of(false, 300.0, 400.0),
      scrolls_now_of(false, 600.0, 100.0),
      scrolls_now_of(true, 600.0, 100.0),
      scrolls_now_of(true, 300.0, 400.0),
    ),
    (true, false, true, false),
  )
}

///|
test "scrolls across, its bar 10 in from either end: its thumb as an old view's foot bar has it (bar_track_of), held and moved, the row moved as far as its track goes for it" {
  let now = Ref(0.0)
  let k = across_case(bar=true, now~)
  k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
  k.tree.frame(390.0, 844.0, now=now.val) |> ignore
  k.tree.wheel_at(150.0, 70.0, 30.0, 0.0, 0, 10.0) |> ignore
  now.val = 300.0
  k.tree.frame(390.0, 844.0, now=300.0) |> ignore
  let (x, y, w, h) = match k.tree.drawn().iter().find_first(fn(d) { d.h == 3.0 && d.alpha > 0.0 }) {
    Some(d) => (d.x, d.y, d.w, d.h)
    None => @halt.saying("no thumb")
  }
  // (300 less 10 either end: 280 of 580; at least 28; 2 in from either end of it; 30 of the 300 it goes)
  let (tx, tw, ratio) = @view.bar_track_of(10.0, 280.0, 280.0, 580.0, 30.0, 0.0, 0.0, 28.0, 2.0)
  let id = match k.tree.target_at(x + w / 2.0, y + h / 2.0) {
    Dragged(id) => id
    _ => @halt.saying("the thumb takes no hold")
  }
  let at = k.across.at(k.tree)
  k.tree.drag_at(id, Down, x + w / 2.0, y + h / 2.0, 310.0) |> ignore
  k.tree.drag_at(id, Moved, x + w / 2.0 + 10.0, y + h / 2.0, 320.0) |> ignore
  assert_eq(
    ((x - tx).abs() < 1.0e-9, (w - tw).abs() < 1.0e-9, (k.across.at(k.tree) - at - 10.0 * ratio).abs() < 1.0e-9),
    (true, true, true),
    msg="\{x} \{w} of \{tx} \{tw}; moved \{k.across.at(k.tree) - at}, \{ratio}",
  )
}

///|
test "scrolls across: let go flinging, made again holding the same scroll: at rest where the fling was as it went, nothing reading the time after" {
  let now = Ref(0.0)
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::across()
  let tree = @view.Tree::new(
    fn(root) {
      root.show(at_once=true, fn() { there.get() }, fn(v) {
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(scroll, fn(held) {
          held.row(Is(true)) |> ignore
          for _ in 0..<10 {
            held.box(fn(c) { c.width(Is(Some(60.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  let id = tree.claimer_of(tree.claimers_at(150.0, 20.0), -20.0, 0.0).unwrap()
  tree.drag_at(id, Down, 170.0, 20.0, 100.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 20.0, 110.0) |> ignore
  tree.drag_at(id, Moved, 130.0, 20.0, 120.0) |> ignore
  tree.drag_at(id, Up, 130.0, 20.0, 120.0) |> ignore
  now.val = 140.0
  tree.frame(390.0, 844.0) |> ignore
  let flung = tree.clock_read()
  tree.advance(across_gone_at)
  there.set(false)
  now.val = 200.0
  tree.frame(390.0, 844.0) |> ignore
  there.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let kept = scroll.at(tree)
  now.val = across_long_after_at
  tree.advance(across_long_after_at)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((flung, kept > 32.0, scroll.at(tree), tree.clock_read()), (true, true, kept, false), msg="\{kept}")
}

///|
/// Moments on a test's clock of a row flung at 120 (as fling_on_at's): let go of on its way; long after, at rest.
let across_gone_at : Double = 200.0

///|
let across_long_after_at : Double = 10000.0
