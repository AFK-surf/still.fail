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
