// A column that scrolls up and down in a node (View::scrolls): 100 tall under 100 of the window's, holding a button
// (40 tall, its presses counted) and nine rows of 40 (400 in all: it can go 300); what holds it moving by the wheel
// too, counted.

///|
/// Moments on a test's clock of a fling let go at 120 (fling_column's): 20 ms on, on its way; long after, at rest;
/// later still.
let fling_on_at : Double = 140.0

///|
let fling_long_after_at : Double = 5000.0

///|
let fling_later_at : Double = 6000.0

///|
/// The moment a fling's column is made again, let go at 200.
let made_again_at : Double = 200.0

///|
/// A moment just after a fling set out (at 120, a frame's worth on), short of its end.
let just_set_out_at : Double = 131.0

///|
/// Moments long after anything set out has come to rest, and longer.
let long_after_at : Double = 10000.0

///|
let longer_after_at : Double = 20000.0

///|
priv struct ScrollCase {
  tree : @view.Tree
  scroll : @view.Scroll
  now : Ref[Double]
  pressed : Ref[Int]
  outer : Ref[Double]
  rows : @signals.Signal[Int]
  focus : Ref[@view.NodeId?]
}

///|
fn scroll_case() -> ScrollCase {
  let now = Ref(0.0)
  let pressed = Ref(0)
  let outer = Ref(0.0)
  let rows = @signals.signal(9, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let focus : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .width(Is(Some(300.0)))
        .height(Is(Some(400.0)))
        .on_wheel_moves(fn(w) {
          outer.val = outer.val + w.dy
          true
        })
        |> ignore
        o.box(fn(gap) { gap.height(Is(Some(100.0))) |> ignore }) |> ignore
        o.box(fn(v) {
          v
          .height(Is(Some(100.0)))
          .scrolls(scroll, fn(held) {
            held.box(fn(b) {
              b.width(Is(Some(300.0))).height(Is(Some(40.0))).on_press(fn() { pressed.val += 1 }) |> ignore
            })
            |> ignore
            held.each(fn() { Array::makei(rows.get(), fn(i) { i }) }, fn(i) { i }, fn(r, i) {
              r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
              if @signals.untracked(fn() { i.get() }) == 8 {
                r.focusable(Is(true)) |> ignore
                focus.val = Some(r.id())
              }
            })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, now, pressed, outer, rows, focus }
}

///|
/// How far it is scrolled, as of the tree's logic.
fn ScrollCase::at(self : ScrollCase) -> Double {
  self.scroll.at(self.tree)
}

///|
test "scrolls: the wheel moves it as far as it goes; at its end, what holds it moves; turned back, it first" {
  let k = scroll_case()
  let took = k.tree.wheel_at(150.0, 150.0, 0.0, 120.0, 0, 10.0)
  let first = (took, k.at(), k.outer.val)
  for i in 0..<4 {
    k.tree.wheel_at(150.0, 150.0, 0.0, 120.0, 0, 20.0 + i.to_double()) |> ignore
  }
  let end = (k.at(), k.outer.val)
  k.tree.wheel_at(150.0, 150.0, 0.0, -40.0, 0, 30.0) |> ignore
  assert_eq((first, end, (k.at(), k.outer.val)), ((true, 120.0, 0.0), (300.0, 240.0), (260.0, 240.0)))
}

///|
test "scrolls: what it holds found within it alone: its button scrolled out of it over what is above it takes no press there, nor in it where it is not" {
  let k = scroll_case()
  let before = k.tree.target_at(150.0, 120.0) is Pressed(_)
  k.tree.wheel_at(150.0, 150.0, 0.0, 60.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (the button drawn at 40 to 80 now, over the column: above it, not found; the column's own top shows what is under it)
  let above = k.tree.target_at(150.0, 60.0) is Pressed(_)
  let atop = k.tree.target_at(150.0, 105.0) is Pressed(_)
  assert_eq((before, above, atop), (true, false, false))
}

///|
test "scrolls: a hold on what it holds moved up past the slop its own (across, or the way it cannot go, not); dragged as it moves; let go moving, flung on and slowing to rest, whatever frames come" {
  let k = scroll_case()
  // (down on its button at 120: across, or down at its top, not its; up past the slop, its)
  let across = k.tree.claimer_of(k.tree.claimers_at(150.0, 120.0), 30.0, -10.0)
  let down = k.tree.claimer_of(k.tree.claimers_at(150.0, 120.0), 0.0, 20.0)
  let short = k.tree.claimer_of(k.tree.claimers_at(150.0, 120.0), 0.0, -5.0)
  let id = match k.tree.claimer_of(k.tree.claimers_at(150.0, 120.0), 0.0, -20.0) {
    Some(id) => id
    None => abort("not taken over")
  }
  // (taken over as it went up 20 from 160: past the slop of 8 by 12 then; on by 20 more)
  k.tree.drag_at(id, Down, 150.0, 160.0, 100.0) |> ignore
  k.tree.drag_at(id, Moved, 150.0, 140.0, 110.0) |> ignore
  let taken = k.at()
  k.tree.drag_at(id, Moved, 150.0, 120.0, 120.0) |> ignore
  let dragged = k.at()
  k.tree.drag_at(id, Up, 150.0, 120.0, 120.0) |> ignore
  // (2 a ms, slowing: 20 ms on it has gone on; long after, at rest, no further)
  k.tree.advance(fling_on_at)
  let on = k.at()
  k.tree.advance(fling_long_after_at)
  let rest = k.at()
  k.tree.advance(fling_later_at)
  assert_eq(
    (across, down, short, taken, dragged, on > dragged, rest > on, k.at() == rest, rest <= 300.0),
    (None, None, None, 12.0, 32.0, true, true, true, true),
    msg="\{on} \{rest}",
  )
}

///|
test "scrolls: the focus come to what it holds out of its sight: brought into sight once laid out, its foot at the column's; scrolled away after, left so" {
  let k = scroll_case()
  let got = k.tree.focus_to(k.focus.val, visible=true)
  // (once laid out, before it is drawn)
  let before = k.at()
  k.tree.frame(390.0, 844.0) |> ignore
  let after = k.at()
  // (scrolled back by the wheel: kept so, the focus where it is)
  k.tree.wheel_at(150.0, 150.0, 0.0, -120.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((got, before, after, k.at()), (true, 0.0, 300.0, 180.0))
}

///|
test "scrolls: what it holds made shorter: no further than it can go now" {
  let k = scroll_case()
  for i in 0..<4 {
    k.tree.wheel_at(150.0, 150.0, 0.0, 120.0, 0, 10.0 + i.to_double()) |> ignore
  }
  let end = k.at()
  k.rows.set(4)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((end, k.at(), k.scroll.most()), (300.0, 100.0, 100.0))
}

///|
test "scrolls: the focus come to what one column holds in another, out of the sight of both: the inner brought to it first, the outer to where the inner then has it" {
  let inner = @view.Scroll::new()
  let outer = @view.Scroll::new()
  let target : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(outer, fn(oh) {
          oh.box(fn(gap) { gap.height(Is(Some(150.0))) |> ignore }) |> ignore
          oh.box(fn(i) {
            i
            .height(Is(Some(100.0)))
            .scrolls(inner, fn(ih) {
              for n in 0..<10 {
                ih.box(fn(r) {
                  r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
                  if n == 9 {
                    r.focusable(Is(true)) |> ignore
                    target.val = Some(r.id())
                  }
                })
                |> ignore
              }
            })
            |> ignore
          })
          |> ignore
          oh.box(fn(gap) { gap.height(Is(Some(400.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  tree.focus_to(target.val, visible=true) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  // (the row at 360 to 400 of the inner's: it at 300; the row then at 210 to 250 of the outer's, it at 150)
  assert_eq((inner.at(tree), outer.at(tree)), (300.0, 150.0))
}

///|
test "scrolls: let go flinging, made again holding the same scroll: at rest where the fling was as it went, nothing reading the time after" {
  let now = Ref(0.0)
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(scroll, fn(held) {
          for _ in 0..<10 {
            held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  let id = tree.claimer_of(tree.claimers_at(150.0, 50.0), 0.0, -20.0).unwrap()
  tree.drag_at(id, Down, 150.0, 70.0, 100.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 50.0, 110.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 30.0, 120.0) |> ignore
  tree.drag_at(id, Up, 150.0, 30.0, 120.0) |> ignore
  now.val = 140.0
  tree.frame(390.0, 844.0) |> ignore
  let flung = tree.clock_read()
  // (let go at 200, made again)
  tree.advance(made_again_at)
  there.set(false)
  now.val = 200.0
  tree.frame(390.0, 844.0) |> ignore
  there.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let kept = scroll.at(tree)
  now.val = long_after_at
  tree.advance(long_after_at)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((flung, kept > 32.0, scroll.at(tree), tree.clock_read()), (true, true, kept, false), msg="\{kept}")
}

///|
test "scrolls: held in what is drawn twice as big: what it holds drawn moving as far as the finger, past the slop" {
  let scroll = @view.Scroll::new()
  let row : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(big) {
        big.width(Is(Some(150.0))).height(Is(Some(200.0))).scale(Is(2.0), about=At(0.0, 0.0)) |> ignore
        big.box(fn(v) {
          v
          .width(Is(Some(150.0)))
          .height(Is(Some(100.0)))
          .scrolls(scroll, fn(held) {
            for i in 0..<10 {
              held.box(fn(r) {
                r.width(Is(Some(150.0))).height(Is(Some(40.0))).ground(Is(0x101010FFL)) |> ignore
                if i == 1 {
                  row.val = Some(r.id())
                }
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let drawn_y = fn() { tree.drawn().iter().find_first(fn(d) { Some(d.id) == row.val }).map(fn(d) { d.y }).unwrap() }
  let y0 = drawn_y()
  // (down at 150 of the window, up 20 then 60: taken over past the slop of 8 there)
  let chain = tree.claimers_at(100.0, 150.0)
  let id = tree.claimer_of(chain, 0.0, -20.0).unwrap()
  tree.drag_at(id, Down, 100.0, 150.0, 100.0) |> ignore
  tree.drag_at(id, Moved, 100.0, 130.0, 110.0) |> ignore
  tree.drag_at(id, Moved, 100.0, 90.0, 120.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((y0 - drawn_y(), scroll.at(tree)), (52.0, 26.0))
}

///|
test "claims: what takes over a hold let go after it went down, another made in its very place (its index): the hold taken over by none" {
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let ids : Array[@view.NodeId] = []
  let tree = @view.Tree::new(
    fn(root) {
      root.show(fn() { a_on.get() }, fn(a) {
        a.width(Is(Some(300.0))).height(Is(Some(100.0))).claims(fn(_, _) { true }).on_drag(fn(_) {  }) |> ignore
        ids.push(a.id())
      })
      root.show(fn() { !a_on.get() }, fn(b) {
        b.width(Is(Some(300.0))).height(Is(Some(100.0))).claims(fn(_, _) { true }).on_drag(fn(_) {  }) |> ignore
        ids.push(b.id())
      })
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let chain = tree.claimers_at(50.0, 50.0)
  a_on.set(false)
  tree.frame(390.0, 844.0) |> ignore
  let (a, b) = (ids[0], ids[ids.length() - 1])
  assert_eq((chain.length(), b.at == a.at, b.gen != a.gen, tree.claimer_of(chain, 0.0, -20.0)), (1, true, true, None))
}

///|
test "scrolls: at its end, what it holds made shorter, then as long again: at the end of the shorter, not back where it was" {
  let k = scroll_case()
  for i in 0..<4 {
    k.tree.wheel_at(150.0, 150.0, 0.0, 120.0, 0, 10.0 + i.to_double()) |> ignore
  }
  let end = k.at()
  k.rows.set(4)
  k.tree.frame(390.0, 844.0) |> ignore
  let short = k.at()
  k.rows.set(9)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((end, short, k.at()), (300.0, 100.0, 100.0))
}

///|
test "scrolls: flung on, what it holds made shorter on the way and kept so till the fling is at rest, then as long again: at rest within the shorter, not where the fling was going" {
  let k = scroll_case()
  let id = k.tree.claimer_of(k.tree.claimers_at(150.0, 180.0), 0.0, -20.0).unwrap()
  k.tree.drag_at(id, Down, 150.0, 180.0, 100.0) |> ignore
  k.tree.drag_at(id, Moved, 150.0, 160.0, 110.0) |> ignore
  k.tree.drag_at(id, Moved, 150.0, 120.0, 120.0) |> ignore
  k.tree.drag_at(id, Up, 150.0, 80.0, 130.0) |> ignore
  // (made shorter just after it set out, short of the shorter's end: flung on within it)
  k.now.val = just_set_out_at
  k.tree.advance(just_set_out_at)
  let set_out = k.at()
  k.rows.set(4)
  k.tree.frame(390.0, 844.0) |> ignore
  // (kept shorter till the fling is at rest, then as long again)
  k.now.val = long_after_at
  k.tree.advance(long_after_at)
  k.tree.frame(390.0, 844.0) |> ignore
  let rested = (k.at(), k.tree.clock_read())
  k.rows.set(9)
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((set_out < 100.0, rested.0 <= 100.0, rested.1, k.at() == rested.0), (true, true, false, true), msg="\{set_out} \{rested.0} \{k.at()}")
}

///|
test "scrolls: scrolled on, let go, made again holding the same scroll with what it holds shorter than it, then as long again: at its top, not back where it was" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let rows = @signals.signal(10, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(scroll, fn(held) {
          held.each(fn() { Array::makei(rows.get(), fn(i) { i }) }, fn(i) { i }, fn(r, _) {
            r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
          })
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  tree.wheel_at(150.0, 50.0, 0.0, 200.0, 0, 10.0) |> ignore
  let scrolled = scroll.at(tree)
  there.set(false)
  tree.frame(390.0, 844.0) |> ignore
  rows.set(2)
  there.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let short = scroll.at(tree)
  rows.set(10)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((scrolled, short, scroll.at(tree)), (200.0, 0.0, 0.0))
}

///|
test "scrolls: what it holds faded towards its top and its foot where it goes on past them, as far as that, 24 at most" {
  let k = scroll_case()
  let viewport = fn() {
    // (the column: the one that cuts what it holds, under the 100 at the top)
    let mut v : @view.NodeId? = None
    for d in k.tree.drawn() {
      if d.clips {
        v = Some(d.id)
      }
    }
    k.tree.fades_of(v.unwrap())
  }
  let top = viewport()
  k.tree.wheel_at(150.0, 150.0, 0.0, 10.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let ten = viewport()
  k.tree.wheel_at(150.0, 150.0, 0.0, 280.0, 0, 20.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  let near_end = viewport()
  k.tree.wheel_at(150.0, 150.0, 0.0, 100.0, 0, 30.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  assert_eq((top, ten, near_end, viewport()), ((0.0, 0.0, 0.0, 24.0), (0.0, 10.0, 0.0, 24.0), (0.0, 24.0, 0.0, 10.0), (0.0, 24.0, 0.0, 0.0)))
}

///|
/// In what is drawn twice as big, a column holding 100 rows flung by a finger going up at `v` of the window's points a
/// ms (three moves 10 ms apart): where it comes to rest.
fn flung_twice_big(v : Double) -> Double {
  let now = Ref(0.0)
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(big) {
        big.width(Is(Some(150.0))).height(Is(Some(300.0))).scale(Is(2.0), about=At(0.0, 0.0)) |> ignore
        big.box(fn(c) {
          c
          .width(Is(Some(150.0)))
          .height(Is(Some(100.0)))
          .scrolls(scroll, fn(held) {
            for _ in 0..<100 {
              held.box(fn(r) { r.width(Is(Some(150.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0) |> ignore
  let id = tree.claimer_of(tree.claimers_at(100.0, 190.0), 0.0, -20.0).unwrap()
  tree.drag_at(id, Down, 100.0, 190.0, 100.0) |> ignore
  for i in 1..=3 {
    tree.drag_at(id, Moved, 100.0, 190.0 - v * 10.0 * i.to_double(), 100.0 + 10.0 * i.to_double()) |> ignore
  }
  tree.drag_at(id, Up, 100.0, 190.0 - v * 35.0, 135.0) |> ignore
  let at_up = scroll.at(tree)
  now.val = longer_after_at
  tree.advance(longer_after_at)
  tree.frame(390.0, 844.0) |> ignore
  scroll.at(tree) - at_up
}

///|
test "scrolls: held in what is drawn twice as big, flung faster than a fling goes: no faster in the window's points than the fastest, as far on whatever faster" {
  let fast = flung_twice_big(12.0)
  let faster = flung_twice_big(20.0)
  assert_eq((fast - faster).abs() < 1.0e-6 && fast > 0.0, true, msg="\{fast} \{faster}")
}

///|
/// A bar as these tests have it: drawn whenever, black, coming and going straight along, as the old views' bars are
/// sized and timed.
fn test_bar() -> @view.ScrollBar {
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
/// A column 100 tall the window's top left, 300 wide, holding 10 rows of 40, with its bar; the moment as `now` says.
fn bar_case(now : Ref[Double]) -> (@view.Tree, @view.Scroll) {
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(scroll, bar=test_bar(), fn(held) {
          for _ in 0..<10 {
            held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))).ground(Is(0x101010FFL)) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=now.val) |> ignore
  (tree, scroll)
}

///|
/// The bar's thumb as drawn (x, y, w, h, opacity), if it is.
fn thumb_drawn(tree : @view.Tree) -> (Double, Double, Double, Double, Double)? {
  tree.drawn().iter().find_first(fn(d) { d.w == 3.0 && d.alpha > 0.0 }).map(fn(d) { (d.x, d.y, d.w, d.h, d.alpha) })
}

///|
test "a column's bar: none where it is first put; scrolled, it comes in (the time read), stays 900 after (none read), goes over 200 (read); its thumb along its right, as long as what shows of what it holds, where it is in it" {
  let now = Ref(0.0)
  let (tree, _) = bar_case(now)
  let first = thumb_drawn(tree)
  tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  now.val = 110.0
  tree.frame(390.0, 844.0, now=110.0) |> ignore
  let coming = thumb_drawn(tree)
  let coming_clock = tree.clock_read()
  now.val = 500.0
  tree.frame(390.0, 844.0, now=500.0) |> ignore
  let out = thumb_drawn(tree)
  let out_clock = tree.clock_read()
  now.val = 1010.0
  tree.frame(390.0, 844.0, now=1010.0) |> ignore
  let going = thumb_drawn(tree)
  let going_clock = tree.clock_read()
  now.val = 1200.0
  tree.frame(390.0, 844.0, now=1200.0) |> ignore
  let gone = (thumb_drawn(tree), tree.clock_read())
  // (100 of 400 shows: 25 of a track 100 less 2 each end, at least 28: 28 - 4 = 24 long? at least 28 with its insets
  // within: 28 - 4; a quarter of the way down 300 of it scrolls: (100 - 4 - 24) / 3 + 2)
  let long = 28.0 - 4.0
  let y = 2.0 + (100.0 - 4.0 - long) * 100.0 / 300.0
  assert_eq(
    (first, coming.map(fn(c) { c.4 }), out, going.map(fn(c) { c.4 }), gone, (coming_clock, out_clock, going_clock)),
    (None, Some(0.5), Some((295.0, y, 3.0, long, 1.0)), Some(0.5), (None, false), (true, false, true)),
    msg="\{coming} \{out} \{going}",
  )
}

///|
test "a column's bar: its thumb held and moved: the column moved as far as the thumb's track goes for it" {
  let now = Ref(0.0)
  let (tree, scroll) = bar_case(now)
  tree.wheel_at(150.0, 50.0, 0.0, 30.0, 0, 10.0) |> ignore
  now.val = 300.0
  tree.frame(390.0, 844.0, now=300.0) |> ignore
  let (x, y, w, h, _) = thumb_drawn(tree).unwrap()
  let id = match tree.target_at(x + w / 2.0, y + h / 2.0) {
    Dragged(id) => id
    _ => abort("the thumb takes no hold")
  }
  let at = scroll.at(tree)
  tree.drag_at(id, Down, x + w / 2.0, y + h / 2.0, 310.0) |> ignore
  tree.drag_at(id, Moved, x + w / 2.0, y + h / 2.0 + 18.0, 320.0) |> ignore
  // (the track 96 less the thumb 24: 72 for the 300 it scrolls)
  assert_eq((scroll.at(tree) - at - 18.0 * 300.0 / 72.0).abs() < 1.0e-9, true, msg="\{scroll.at(tree) - at}")
}

///|
test "a column's bar: flung far, the fling stopped soon by a finger down and nothing after: gone 900 after it was stopped, then at rest, not after where the fling was going" {
  let now = Ref(0.0)
  let (tree, scroll) = bar_case(now)
  let id = tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -20.0).unwrap()
  tree.drag_at(id, Down, 150.0, 90.0, 100.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 70.0, 110.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 40.0, 120.0) |> ignore
  tree.drag_at(id, Up, 150.0, 10.0, 130.0) |> ignore
  // (stopped at 150 by a finger down, let go there)
  now.val = 150.0
  tree.frame(390.0, 844.0, now=150.0) |> ignore
  let id2 = tree.claimer_of(tree.claimers_at(150.0, 50.0), 0.0, -20.0).unwrap()
  tree.drag_at(id2, Down, 150.0, 50.0, 150.0) |> ignore
  tree.drag_at(id2, Up, 150.0, 50.0, 160.0) |> ignore
  let stopped = scroll.at(tree)
  now.val = 1300.0
  tree.frame(390.0, 844.0, now=1300.0) |> ignore
  assert_eq((stopped < 300.0, thumb_drawn(tree), tree.clock_read()), (true, None, false), msg="\{stopped}")
}

///|
/// Two columns 100 tall, 300 wide at the window's top left with these bars, holding 10 rows of 40: `inner` in the
/// outer's place as tall and as wide (a column in it, held in two more boxes) while it says so; or, `stacked`, another
/// over the outer as a sibling of it, shallow. Their scrolls, the outer's first.
fn bars_two(now : Ref[Double], inner : @signals.Signal[Bool], stacked? : Bool = false) -> (@view.Tree, @view.Scroll, @view.Scroll) {
  let (a, b) = (@view.Scroll::new(), @view.Scroll::new())
  let rows = fn(held : @view.View) {
    for _ in 0..<10 {
      held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
    }
  }
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        v.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        v.box(fn(c) {
          c
          .width(Is(Some(300.0)))
          .height(Is(Some(100.0)))
          .scrolls(a, bar=test_bar(), fn(held) {
            held.show(fn() { inner.get() && !stacked }, fn(deep) {
              deep.box(fn(deeper) {
                deeper.box(fn(i) { i.width(Is(Some(300.0))).height(Is(Some(100.0))).scrolls(b, bar=blue_bar(), rows) |> ignore }) |> ignore
              })
              |> ignore
            })
            rows(held)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      if stacked {
        root.box(fn(v) {
          v.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(100.0))).scrolls(b, bar=blue_bar(), rows) |> ignore
        })
        |> ignore
      }
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=now.val) |> ignore
  (tree, a, b)
}

///|
/// The thumbs drawn as of `at`: each whose, by its ink (test_bar's the outer's, blue_bar's the other's).
fn thumbs_drawn(tree : @view.Tree, now : Ref[Double], at : Double) -> Array[String] {
  now.val = at
  tree.frame(390.0, 844.0, now=at) |> ignore
  tree.drawn().filter(fn(d) { d.w == 3.0 && d.alpha > 0.0 }).map(fn(d) { if d.ground == 0x0000FF42L { "other" } else { "outer" } })
}

///|
/// test_bar's, blue.
fn blue_bar() -> @view.ScrollBar {
  { ..test_bar(), ink: fn() { 0x0000FF42L } }
}

///|
test "a column's bar along its edge where the pointer stays still, another column made in its place there and let go: the inner's bar out, then the outer's again" {
  let now = Ref(0.0)
  let inner = @signals.signal(false, same=fn(a, b) { a == b })
  let (tree, _, _) = bars_two(now, inner)
  tree.pointer_is(295.0, 50.0)
  let outer_out = thumbs_drawn(tree, now, 300.0)
  // (made at 300, as one event then: the inner's coming in from then, half way at 400, test_bar's ease straight along)
  tree.event(300.0, fn() { inner.set(true) })
  now.val = 400.0
  tree.frame(390.0, 844.0, now=400.0) |> ignore
  let half = tree.drawn().filter(fn(d) { d.w == 3.0 && d.ground == 0x0000FF42L }).map(fn(d) { d.alpha })
  // (the outer's gone 900 and 200 after the pointer left it, the inner's come in)
  let then = thumbs_drawn(tree, now, 2000.0)
  inner.set(false)
  let back = thumbs_drawn(tree, now, 4000.0)
  assert_eq((outer_out, half, then, back), (["outer"], [0.5], ["other"], ["outer"]))
}

///|
test "two columns over one another, the upper of them shallow, the pointer along their edge: the upper's bar out, not the deeper one's under it" {
  let now = Ref(0.0)
  let (tree, a, b) = bars_two(now, @signals.signal(false, same=fn(a, b) { a == b }), stacked=true)
  ignore(a)
  tree.pointer_is(295.0, 50.0)
  ignore(b)
  assert_eq(thumbs_drawn(tree, now, 300.0), ["other"])
}

///|
test "a column's bar out, its logic short of where it starts to go, a frame drawn past that: drawn going as of the frame's moment" {
  let now = Ref(0.0)
  let (tree, _) = bar_case(now)
  tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
  now.val = 900.0
  tree.frame(390.0, 844.0, now=900.0) |> ignore
  let at_900 = thumb_drawn(tree).map(fn(c) { c.4 })
  // (a frame to be shown at 950, the logic at 900, as a host draws one ahead: 40 into its going of 200)
  tree.at(950.0)
  tree.frame(390.0, 844.0, now=900.0) |> ignore
  let at_950 = thumb_drawn(tree).map(fn(c) { c.4 })
  assert_eq(
    (at_900, at_950.map(fn(a) { (a - 0.8).abs() < 1.0e-9 }), tree.logic_at() < 910.0),
    (Some(1.0), Some(true), true),
    msg="\{at_950}",
  )
}

///|
test "a column's bar along its edge where the pointer stays still, a column in it with nothing to scroll: the outer's bar out; what the inner holds grown past it, the inner's; short again, the outer's" {
  let now = Ref(0.0)
  let rows = @signals.signal(1, same=fn(a, b) { a == b })
  let (outer, inner) = (@view.Scroll::new(), @view.Scroll::new())
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(outer, bar=test_bar(), fn(oh) {
          oh.box(fn(i) {
            i
            .width(Is(Some(300.0)))
            .height(Is(Some(100.0)))
            .scrolls(inner, bar=blue_bar(), fn(ih) {
              ih.each(fn() { Array::makei(rows.get(), fn(k) { k }) }, fn(k) { k }, fn(r, _) {
                r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore
              })
            })
            |> ignore
          })
          |> ignore
          for _ in 0..<10 {
            oh.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.pointer_is(295.0, 50.0)
  let short = thumbs_drawn(tree, now, 300.0)
  tree.event(300.0, fn() { rows.set(10) })
  let long = thumbs_drawn(tree, now, 2000.0)
  tree.event(2000.0, fn() { rows.set(1) })
  let again = thumbs_drawn(tree, now, 4000.0)
  assert_eq((short, long, again), (["outer"], ["other"], ["outer"]))
}

///|
test "drawn past a moment: a look by it alone, a frame drawn ahead past it, then an input before it, then the frame ahead again: as of each one's own moment, none of the clock read otherwise" {
  let past : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        past.val = Some(v)
        v.width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(0x101010FFL)).alpha(By(fn() { if v.drawn_past(100.0) { 0.5 } else { 1.0 } })) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let alpha = fn() { tree.drawn().iter().find_first(fn(d) { d.w == 10.0 }).map(fn(d) { d.alpha }).unwrap() }
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  let before = alpha()
  tree.at(150.0)
  tree.frame(390.0, 844.0, now=90.0) |> ignore
  let ahead = alpha()
  // (an input at 95, before it: found as of then)
  tree.bring_to(95.0)
  let input = alpha()
  tree.at(160.0)
  tree.frame(390.0, 844.0, now=96.0) |> ignore
  let again = alpha()
  ignore(past)
  assert_eq((before, ahead, input, again, tree.clock_read()), (1.0, 0.5, 1.0, 0.5, false))
}

///|
/// A box whose opacity reads whether what is drawn is past `at` and 100 after it (and, `clock`, the moment drawn): each
/// time it is worked out, what it read pushed (the moment drawn as of then, both).
fn drawn_reader(seen : Array[(Double, Bool, Bool)], at : @signals.Signal[Double], clock : Bool) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        v
        .width(Is(Some(10.0)))
        .height(Is(Some(10.0)))
        .ground(Is(0x101010FFL))
        .alpha(By(fn() {
          let t = at.get()
          let a = v.drawn_past(t)
          let b = v.drawn_past(t + 100.0)
          let now = if clock { v.drawn_at() } else { @signals.untracked(fn() { v.drawn_at() }) }
          seen.push((now, a, b))
          if a { 0.5 } else { 1.0 }
        }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
}

///|
test "drawn past a moment: watched with the moment drawn, both told as one; the next moment followed only as the first is passed, told as it is passed too" {
  let view : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        view.val = Some(v)
        v.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  let v = view.val.unwrap()
  let seen : Array[(Double, Bool, Bool)] = []
  let stop = @signals.effect(fn() {
    let now = v.drawn_at()
    let a = v.drawn_past(100.0)
    let b = if a { v.drawn_past(200.0) } else { false }
    seen.push((now, a, b))
  })
  tree.at(150.0)
  tree.at(250.0)
  stop()
  let torn = seen.iter().any(fn(e) { (e.0 >= 100.0 && !e.1) || (e.0 >= 200.0 && !e.2) })
  assert_eq(
    (torn, seen.iter().any(fn(e) { e == (150.0, true, false) }), seen.last()),
    (false, true, Some((250.0, true, true))),
    msg="\{seen}",
  )
}

///|
test "drawn past a moment: the moment waited for said anew, the one before passed after: nothing told of it" {
  let seen : Array[(Double, Bool, Bool)] = []
  let at = @signals.signal(100.0, same=fn(a, b) { a == b })
  let tree = drawn_reader(seen, at, false)
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  at.set(300.0)
  tree.frame(390.0, 844.0, now=85.0) |> ignore
  let n = seen.length()
  // (past 100 and 200, the moments waited for before: nothing worked out again; the logic where it was)
  tree.at(250.0)
  tree.frame(390.0, 844.0, now=85.0) |> ignore
  let after_old = seen.length() - n
  tree.at(350.0)
  tree.frame(390.0, 844.0, now=85.0) |> ignore
  assert_eq((after_old, seen.length() - n, seen.last().map(fn(e) { (e.1, e.2) })), (0, 1, Some((true, false))), msg="\{seen}")
}

///|
test "a column's bar in what is drawn twice as big: the pointer 18 in from its right edge brings none out, 6 in brings it, the hand's points either way" {
  let now = Ref(0.0)
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(big) {
        big.width(Is(Some(150.0))).height(Is(Some(100.0))).scale(Is(2.0), about=At(0.0, 0.0)) |> ignore
        big.box(fn(c) {
          c
          .width(Is(Some(150.0)))
          .height(Is(Some(50.0)))
          .scrolls(scroll, bar=test_bar(), fn(held) {
            for _ in 0..<10 {
              held.box(fn(r) { r.width(Is(Some(150.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (its thumb by its ink, drawn twice as wide as it is)
  let thumbs = fn(at : Double) {
    now.val = at
    tree.frame(390.0, 844.0, now=at) |> ignore
    tree.drawn().filter(fn(d) { d.ground == 0x00000042L && d.alpha > 0.0 }).map(fn(d) { d.w })
  }
  tree.pointer_is(282.0, 50.0)
  let far = thumbs(300.0)
  tree.pointer_is(294.0, 50.0)
  let near = thumbs(600.0)
  assert_eq((far, near), ([], [6.0]))
}

///|
test "a column's bar along its edge where the pointer stays still, a layer over it said modal, then not, as it was: the bar gone from the column, then back, at those moments" {
  let now = Ref(0.0)
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(c) {
        c
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .scrolls(scroll, bar=test_bar(), fn(held) {
          for _ in 0..<10 {
            held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
      // (a layer over all of it, there all along, nothing of it said anew but whether it is modal)
      root.box(fn(l) { l.over(Is(true)).modal(By(fn() { modal.get() })).width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.pointer_is(295.0, 50.0)
  let out = thumbs_drawn(tree, now, 300.0)
  tree.event(300.0, fn() { modal.set(true) })
  // (gone from 300: held 900, then 200 going)
  let kept_off = thumbs_drawn(tree, now, 1500.0)
  tree.event(1500.0, fn() { modal.set(false) })
  let back = thumbs_drawn(tree, now, 1600.0)
  assert_eq((out, kept_off, back), (["outer"], [], ["outer"]))
}

///|
test "a column's bar along its edge where the pointer stays still, the column itself said to take no press, then to again: gone, then back" {
  let now = Ref(0.0)
  let takes = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(c) {
        c
        .width(Is(Some(300.0)))
        .height(Is(Some(100.0)))
        .presses(By(fn() { takes.get() }))
        .scrolls(scroll, bar=test_bar(), fn(held) {
          for _ in 0..<10 {
            held.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.pointer_is(295.0, 50.0)
  let out = thumbs_drawn(tree, now, 300.0)
  tree.event(300.0, fn() { takes.set(false) })
  let off = thumbs_drawn(tree, now, 1500.0)
  tree.event(1500.0, fn() { takes.set(true) })
  let back = thumbs_drawn(tree, now, 1600.0)
  assert_eq((out, off, back), (["outer"], [], ["outer"]))
}

///|
test "a column's bar in another along its edge where the pointer stays still, the outer made shorter till that is out of it: the inner's bar gone" {
  let now = Ref(0.0)
  let tall = @signals.signal(200.0, same=fn(a, b) { a == b })
  let (outer, inner) = (@view.Scroll::new(), @view.Scroll::new())
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .width(Is(Some(300.0)))
        .height(By(fn() { Some(tall.get()) }))
        .scrolls(outer, bar=test_bar(), fn(oh) {
          oh.box(fn(gap) { gap.height(Is(Some(50.0))) |> ignore }) |> ignore
          oh.box(fn(i) {
            i
            .width(Is(Some(280.0)))
            .height(Is(Some(100.0)))
            .scrolls(inner, bar=blue_bar(), fn(ih) {
              for _ in 0..<10 {
                ih.box(fn(r) { r.width(Is(Some(280.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
          for _ in 0..<10 {
            oh.box(fn(r) { r.width(Is(Some(300.0))).height(Is(Some(40.0))) |> ignore }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  // (along the inner's edge, at 120 down: in the outer while it is 200 tall, out of it at 100)
  tree.pointer_is(275.0, 120.0)
  let out = thumbs_drawn(tree, now, 300.0)
  tree.event(300.0, fn() { tall.set(100.0) })
  let gone = thumbs_drawn(tree, now, 1500.0)
  assert_eq((out, gone), (["other"], []))
}
