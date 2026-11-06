// A reader's place is a share of a row, not a height measured at a previous width.

///|
priv struct FractionCase {
  tree : @view.Tree
  live : Map[Int, @view.View]
  put : @signals.Signal[(Int, Double, Double)?]
  put_top : @signals.Signal[(Int, Double)?]
  position : @view.AnchoredPosition[Int]
  width : @signals.Signal[Double]
  height : @signals.Signal[Double]
  size : @signals.Signal[Double]
}

///|
fn fraction_case(from_end : Bool, first? : (Int, Double, Double), tall? : Double = 200.0, lead_within_row? : Bool = false) -> FractionCase {
  let scroll = @view.Scroll::list()
  let live : Map[Int, @view.View] = Map([])
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(first)
  let put_top : @signals.Signal[(Int, Double)?] = @signals.signal(None)
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let width = @signals.signal(300.0, same=fn(a, b) { a == b })
  let height = @signals.signal(tall, same=fn(a, b) { a == b })
  let size = @signals.signal(1.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(width.get()) })).height(By(fn() { Some(height.get()) })) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(100, fn(i) { i }) }, from_end~, ahead=0.0, put=put_top, put_fraction=put,
        put_fraction_lead_within_row=lead_within_row, position~, fn(row, k) {
        live[k] = row
        row.owns(fn() { live.remove(k) }) |> ignore
        row.layout_box(By(fn() { size.get() }), sized=true, fn(l, scale) {
          l.size_to(if k == 50 { l.width * scale } else { 40.0 })
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, live, put, put_top, position, width, height, size }
}

///|
fn FractionCase::top(self : FractionCase, key : Int) -> Double {
  self.live[key].rect().1
}

///|
test "a reader's fractional lead stays within its measured row through reflow" {
  for from_end in [false, true] {
    let c = fraction_case(from_end, lead_within_row=true)
    for (fraction, expected) in [(0.0, 0.0), (0.2, 0.0), (0.5, -30.0)] {
      c.put.set(Some((50, fraction, 120.0)))
      c.tree.frame(390.0, 844.0, now=10.0) |> ignore
      assert_eq(c.top(50), expected)
    }
    c.width.set(240.0)
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.top(50), 0.0)
    c.width.set(400.0)
    c.tree.frame(390.0, 844.0, now=30.0) |> ignore
    assert_eq(c.top(50), -80.0)
    c.tree.dispose()
  }
}

///|
test "an unlaid fractional jump returns its valid target, not an older viewport" {
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(Some((5, 0.5, 120.0)))
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let tree = @view.Tree::new(fn(root) {
    root.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(10, fn(i) { i }) },
      put_fraction=put, position~, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
  })
  assert_eq(position.get(), Some((5, 0.5)))
  put.set(Some((11, 0.5, 120.0)))
  assert_eq(position.get(), None)
  tree.dispose()
  assert_eq(position.get(), None)
}

///|
test "a fractional put measures an unseen row at the current width in one layout, from either end" {
  for from_end in [false, true] {
    let c = fraction_case(from_end)
    assert_false(c.live.contains(50))
    let computes = c.tree.work().computes
    c.put.set(Some((50, 0.5, 120.0)))
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_eq(c.top(50), -30.0)
    assert_eq(c.put.get(), None)
    assert_eq(c.tree.work().computes - computes, 1)
    c.tree.dispose()
  }
}

///|
test "a fractional put follows the current measured height through width and text size changes" {
  for from_end in [false, true] {
    let c = fraction_case(from_end, first=(50, 0.5, 0.0))
    assert_eq(c.top(50), -150.0)
    let before = c.tree.work().computes
    c.width.set(240.0)
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_eq(c.top(50), -120.0)
    assert_eq(c.tree.work().computes - before, 1)
    let before = c.tree.work().computes
    c.size.set(2.0)
    c.tree.words_again()
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.top(50), -240.0)
    assert_eq(c.tree.work().computes - before, 1)
    c.tree.dispose()
  }
}

///|
test "a later fractional request replaces the earlier one and a pending request can be cancelled" {
  let c = fraction_case(false)
  c.put.set(Some((40, 0.5, 0.0)))
  c.put.set(Some((50, 0.25, 0.0)))
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq(c.top(50), -75.0)
  c.put.set(Some((70, 0.5, 0.0)))
  c.put.set(None)
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  assert_eq(c.top(50), -75.0)
  c.tree.dispose()
}

///|
test "a cancelled request does not run after the list gains room" {
  let c = fraction_case(false, first=(50, 0.5, 0.0), tall=0.0)
  c.put.set(None)
  c.height.set(200.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_true(c.live.contains(0))
  assert_false(c.live.contains(50))
  c.tree.dispose()
}

///|
test "the latest fractional or top placement wins over the other pending kind" {
  for from_end in [false, true] {
    let c = fraction_case(from_end)
    c.put_top.set(Some((40, 0.0)))
    c.put.set(Some((50, 0.5, 0.0)))
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_eq(c.top(50), -150.0)
    c.put.set(Some((50, 0.25, 0.0)))
    c.put_top.set(Some((60, 0.0)))
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.top(60), 0.0)
    c.tree.dispose()
  }
}

///|
test "a hand scrolling releases a fractional put, so a later resize does not restore it" {
  for from_end in [false, true] {
    let c = fraction_case(from_end, first=(50, 0.5, 0.0))
    c.tree.wheel_at(150.0, 100.0, 0.0, 40.0, 0, 10.0) |> ignore
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.top(50), -190.0)
    c.width.set(240.0)
    c.tree.frame(390.0, 844.0, now=30.0) |> ignore
    assert_true(c.top(50) != -120.0)
    c.tree.dispose()
  }
}

///|
test "a new fractional request stops an earlier wheel glide" {
  let c = fraction_case(false, first=(50, 0.5, 0.0))
  c.tree.wheel_at(150.0, 100.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
  c.tree.frame(390.0, 844.0, now=20.0) |> ignore
  c.put.set(Some((60, 0.5, 0.0)))
  c.tree.frame(390.0, 844.0, now=30.0) |> ignore
  assert_eq(c.top(60), -20.0)
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_eq(c.top(60), -20.0)
  c.tree.dispose()
}

///|
test "a fractional put waits for room and can be given again on a rebuilt list" {
  let c = fraction_case(false, first=(50, 0.5, 0.0), tall=0.0)
  assert_eq(c.put.get(), Some((50, 0.5, 0.0)))
  c.height.set(200.0)
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq(c.top(50), -150.0)
  c.tree.dispose()
  let rebuilt = fraction_case(true, first=(50, 0.5, 0.0))
  assert_eq(rebuilt.top(50), -150.0)
  rebuilt.tree.dispose()
}

///|
test "a fractional put respects list ends and clamps its fraction" {
  for from_end in [false, true] {
    let c = fraction_case(from_end)
    c.put.set(Some((0, -1.0, 120.0)))
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_eq(c.top(0), 0.0)
    c.put.set(Some((99, 2.0, 0.0)))
    c.tree.frame(390.0, 844.0, now=20.0) |> ignore
    assert_eq(c.top(99), 160.0)
    c.tree.dispose()
  }
}

///|
test "an attempted scroll at an end releases the fraction even when the list cannot move" {
  let last_after_resize = fn(from_end : Bool, attempt : Bool) -> Double? raise {
    let c = fraction_case(from_end)
    c.put.set(Some((99, 0.5, 0.0)))
    c.tree.frame(390.0, 844.0, now=10.0) |> ignore
    assert_eq(c.top(99), 160.0)
    if attempt {
      c.tree.wheel_at(150.0, 100.0, 0.0, 40.0, 0, 20.0) |> ignore
    }
    c.height.set(10.0)
    c.tree.frame(390.0, 844.0, now=30.0) |> ignore
    let y = c.live.get(99).map(fn(row) { row.rect().1 })
    c.tree.dispose()
    y
  }
  for from_end in [false, true] {
    assert_eq(last_after_resize(from_end, false), Some(-20.0))
    assert_true(last_after_resize(from_end, true) != Some(-20.0))
  }
}

///|
test "a position can be read and restored after a scroll without another painted frame" {
  for from_end in [false, true] {
    let c = fraction_case(from_end, first=(50, 0.5, 0.0))
    assert_eq(c.position.get(), Some((50, 0.5)))
    // This passes several unmeasured rows. Reading must lay those out, not shift only the last visible rows.
    c.tree.wheel_at(150.0, 100.0, 0.0, 880.0, 0, 10.0) |> ignore
    let place = c.position.get()
    assert_eq(place, Some((69, 0.25)))
    c.tree.dispose()
    assert_eq(c.position.get(), None)
    let rebuilt = fraction_case(!from_end, first=(69, 0.25, 0.0))
    assert_eq(rebuilt.position.get(), place)
    rebuilt.tree.dispose()
  }
}

///|
test "a position read before a jump is laid out preserves its explicit target" {
  for from_end in [false, true] {
    let c = fraction_case(from_end, first=(50, 0.5, 0.0))
    c.put.set(Some((70, 0.25, 120.0)))
    assert_eq(c.position.get(), Some((70, 0.25)))
    c.tree.dispose()
    let rebuilt = fraction_case(!from_end, first=(70, 0.25, 0.0))
    assert_eq(rebuilt.position.get(), Some((70, 0.25)))
    rebuilt.put.set(Some((101, 0.5, 0.0)))
    assert_eq(rebuilt.position.get(), None)
    rebuilt.tree.dispose()
  }
}

///|
test "a position reads a wheel glide at the current event moment" {
  for from_end in [false, true] {
    let a = fraction_case(from_end, first=(50, 0.5, 0.0))
    let b = fraction_case(from_end, first=(50, 0.5, 0.0))
    a.tree.wheel_at(150.0, 100.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
    b.tree.wheel_at(150.0, 100.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
    a.tree.bring_to(30.0)
    let place = a.position.get()
    b.tree.frame(390.0, 844.0, now=30.0) |> ignore
    assert_eq(place, Some((50, -b.top(50) / 300.0)))
    assert_true(place != Some((50, 0.5)))
    a.tree.dispose()
    b.tree.dispose()
  }
}

///|
test "an unattached, unlaid, empty or disposed list has no position" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  assert_eq(position.get(), None)
  let tree = @view.Tree::new(fn(root) {
    root.scrolls_anchored(@view.Scroll::list(), fn() { [] }, position~, fn(_, _k : Int) {}) |> ignore
  })
  assert_eq(position.get(), None)
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_eq(position.get(), None)
  tree.dispose()
  assert_eq(position.get(), None)
}

///|
test "letting go of an older list does not detach a position handle from its replacement" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let make_tree = fn(key : Int) {
    let tree = @view.Tree::new(fn(root) {
      root.scrolls_anchored(@view.Scroll::list(), fn() { [key] }, position~, fn(row, _) {
        row.height(Is(Some(100.0))) |> ignore
      }) |> ignore
    })
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    tree
  }
  let old = make_tree(1)
  let current = make_tree(2)
  old.dispose()
  assert_eq(position.get(), Some((2, 0.0)))
  current.dispose()
  assert_eq(position.get(), None)
}
