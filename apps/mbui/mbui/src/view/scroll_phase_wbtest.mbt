// A bar and the space it occupies are measured with the content they describe, before geometry is published.

///|
fn phase_bar() -> ScrollBar {
  { drawn: fn() { true }, ink: fn() { 0x2468acffL }, ink_held: fn() { 0x2468acffL },
    ease: fn(t) { t }, size: 3.0, inset: 2.0, least: 28.0, near: 12.0, grab: 4.0,
    hold_ms: 900.0, fade_ms: 200.0 }
}

///|
test "a scroll bar uses this layout's content height without feeding geometry back into layout" {
  let height = @signals.signal(400.0, same=fn(a, b) { a == b })
  let s = Scroll::new()
  let t = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls(s, bar=phase_bar(), fn(held) {
        held.box(fn(row) { row.height(By(fn() { Some(height.get()) })) |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  t.wheel_at(100.0, 50.0, 0.0, 30.0, 0, 10.0) |> ignore
  t.frame(390.0, 844.0, now=300.0) |> ignore
  let first = t.drawn().iter().find_first(fn(d) { d.ground == 0x2468acffL }).unwrap()
  assert_eq(first.h, 24.0)
  height.set(200.0)
  let before = t.work.computes
  t.frame(390.0, 844.0, now=310.0) |> ignore
  let next = t.drawn().iter().find_first(fn(d) { d.ground == 0x2468acffL }).unwrap()
  assert_eq(t.work.computes - before, 1)
  assert_eq((next.h, s.most()), (46.0, 100.0))
  assert_true(t.target_at(next.x + 1.0, next.y + next.h - 1.0) is Dragged(_))
  t.dispose()
}

///|
test "a horizontal scroll's intrinsic height includes its bar in the same parent layout" {
  let width = @signals.signal(300.0, same=fn(a, b) { a == b })
  let r : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    r.val = Some(root.box(fn(v) {
      v.width(Is(Some(120.0))).scrolls(Scroll::across(), bar=phase_bar(), fn(held) {
        held.box(fn(c) { c.width(By(fn() { Some(width.get()) })).height(Is(Some(40.0))) |> ignore }) |> ignore
      }) |> ignore
    }))
  })
  for (at, w, h) in [(0.0, 300.0, 47.0), (10.0, 80.0, 40.0), (20.0, 300.0, 47.0)] {
    width.set(w)
    let before = t.work.computes
    t.frame(200.0, 300.0, now=at) |> ignore
    assert_eq((r.val.unwrap().laid_size().1, t.work.computes - before), (h, 1))
  }
  t.dispose()
}

///|
test "an anchored list publishes changing extent in a fixed viewport without a second layout" {
  for from_end in [false, true] {
    let keys = @signals.signal([0, 1], same=fn(a, b) { a == b })
    let s = Scroll::list()
    let column : Ref[NodeId?] = Ref(None)
    let t = Tree::new(fn(root) {
      root.box(fn(v) {
        column.val = Some(v.id())
        v.width(Is(Some(300.0))).height(Is(Some(100.0)))
        .scrolls_anchored(s, fn() { keys.get() }, est=40.0, from_end~, bar=phase_bar(), fn(row, _) {
          row.height(Is(Some(40.0))) |> ignore
        }) |> ignore
      }) |> ignore
    })
    t.frame(390.0, 844.0, now=0.0) |> ignore
    assert_false(t.scrolls_now(column.val.unwrap()), msg="a short virtual list cannot scroll")
    let ranges : Array[Double] = []
    let stop = @signals.effect(fn() { ranges.push(s.most_now()) })
    assert_eq(ranges, [0.0])
    t.event(10.0, fn() { keys.set([0, 1, 2, 3, 4]) })
    let before = t.work.computes
    t.frame(390.0, 844.0, now=20.0) |> ignore
    assert_true(t.work.computes - before <= 1, msg="the host frame does not repeat layout")
    assert_eq(ranges.last(), Some(100.0))
    assert_true(t.scrolls_now(column.val.unwrap()),
      msg="the content, not the viewport-sized holder, determines whether a virtual list scrolls")
    t.wheel_at(100.0, 50.0, 0.0, if from_end { -30.0 } else { 30.0 }, 0, 30.0) |> ignore
    t.frame(390.0, 844.0, now=300.0) |> ignore
    assert_true(t.drawn().iter().any(fn(d) { d.ground == 0x2468acffL && d.alpha > 0.0 }))
    t.event(310.0, fn() { keys.set([0, 1]) })
    let before = t.work.computes
    t.frame(390.0, 844.0, now=320.0) |> ignore
    assert_true(t.work.computes - before <= 1)
    assert_eq(ranges.last(), Some(0.0))
    assert_false(t.scrolls_now(column.val.unwrap()), msg="a virtual list shortened again cannot scroll")
    assert_eq(s.at(t), 0.0)
    assert_false(t.drawn().iter().any(fn(d) { d.ground == 0x2468acffL && d.alpha > 0.0 }))
    stop()
    t.dispose()
  }
}

///|
test "an anchored list keeps its end when its viewport shrinks and grows without feeding scroll back into layout" {
  let run = fn(insert_frames : Bool) -> (Array[Int], Array[(Int, Double)], Double) raise {
    let height = @signals.signal(100.0, same=fn(a, b) { a == b })
    let shown = @signals.signal([], same=fn(a : Array[Int], b) { a == b })
    let rows : Map[Int, View] = Map([])
    let s = Scroll::list()
    let t = Tree::new(fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(300.0))).height(By(fn() { Some(height.get()) }))
        .scrolls_anchored(s, fn() { Array::makei(10, fn(i) { i }) }, est=40.0, ahead=0.0, shown~, bar=phase_bar(), fn(row, k) {
          rows[k] = row
          row.owns(fn() { rows.remove(k) }).height(Is(Some(40.0))) |> ignore
        }) |> ignore
      }) |> ignore
    }, time=fn() { 0.0 })
    t.frame(390.0, 844.0, now=0.0) |> ignore
    for (at, h) in [(10.0, 60.0), (110.0, 140.0)] {
      t.event(at, fn() { height.set(h) })
      if insert_frames {
        for dt in [16.0, 32.0, 48.0, 64.0] {
          t.frame(390.0, 844.0, now=at + dt) |> ignore
        }
      }
      t.frame(390.0, 844.0, now=at + 80.0) |> ignore
      assert_eq(rows[9].rect().1, h - 40.0, msg="the last row stays at the new viewport's foot")
      assert_eq(s.at(t), 400.0 - h)
    }
    let visible = shown.get()
    let placed = visible.map(fn(k) { (k, rows[k].rect().1) })
    let result = (visible, placed, s.at(t))
    t.dispose()
    result
  }
  assert_eq(run(false), run(true))
}

///|
test "an anchored list changing its measured extent does not change the hand's layout input" {
  let height = @signals.signal(40.0, same=fn(a, b) { a == b })
  let s = Scroll::list()
  let t = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(s, fn() { [0, 1, 2] }, est=40.0, rooms=fn() {
        let snapshot = Ref(0)
        fn(_, natural) { snapshot.val += 1; list_room(natural) }
      }, fn(row, _) { row.height(By(fn() { Some(height.get()) })) |> ignore }) |> ignore
    }) |> ignore
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  t.event(10.0, fn() { height.set(80.0) })
  let before = t.work.computes
  t.frame(390.0, 844.0, now=10.0) |> ignore
  assert_eq(t.work.computes - before, 1)
  assert_eq(s.most(), 140.0)
  t.dispose()
}
