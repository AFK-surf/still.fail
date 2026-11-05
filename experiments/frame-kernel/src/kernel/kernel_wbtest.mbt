///|
test "composer and list share one layout result at the requested moment" {
  let k = Kernel::new(3000)
  defer { k.placement.release() }
  let before = k.frame(0.0, 0.0, 350.7692307692308, 804.9230769230769)
  k.commit(100.0, Composer(100.0))
  let passes = k.work.layouts
  let after = k.frame(100.0, 108.0, 350.7692307692308, 804.9230769230769)
  assert_eq(k.logic_at, 100.0)
  assert_eq(after.logic_at, 100.0)
  assert_eq(after.layout.composer.y, after.layout.viewport.height)
  assert_eq(after.layout.composer.y + after.layout.composer.height, 804.9230769230769)
  assert_eq(before.layout.viewport.height - after.layout.viewport.height, 40.0)
  assert_eq(k.work.layouts - passes, 1)
}

///|
test "one row changed costs the same with 30 and 3000 rows" {
  let run = fn(n : Int) -> (Int, Int, Int) raise {
    let k = Kernel::new(n)
    defer { k.placement.release() }
    k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
    let reads = k.work.row_reads
    let measures = k.work.measures
    let made = k.work.made
    k.commit(100.0, RowHeight(n - 1, 80.0))
    let p = k.frame(100.0, 108.0, 390.0, 844.0)
    assert_eq(p.layout.rows[0].1.height, 80.0)
    (k.work.row_reads - reads, k.work.measures - measures, k.work.made - made)
  }
  assert_eq(run(30), run(3000))
  assert_eq(run(3000).1, 1)
}

///|
test "an offscreen row update does no layout until the row is requested" {
  let k = Kernel::new(3000)
  defer { k.placement.release() }
  let p = k.frame(0.0, 0.0, 390.0, 844.0)
  let passes = k.work.layouts
  let reads = k.work.row_reads
  k.commit(100.0, RowHeight(0, 75.0))
  let after = k.frame(100.0, 108.0, 390.0, 844.0)
  assert_eq(after.layout, p.layout)
  assert_eq(k.work.layouts, passes)
  assert_eq(k.work.row_reads, reads)
  k.commit(150.0, Anchor(0))
  let shown = k.frame(150.0, 158.0, 390.0, 844.0)
  let first = shown.layout.rows[shown.layout.rows.length() - 1]
  assert_eq((first.0, first.1.y, first.1.height), (0, 0.0, 75.0))
}

///|
test "sampling a page ahead neither lays out again nor finishes its logical lifetime" {
  let k = Kernel::new(3000)
  defer { k.placement.release() }
  k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
  k.commit(100.0, Leave(390.0, @motion.tween(300.0, ease=Linear)))
  let passes = k.work.layouts
  let measures = k.work.measures
  let p = k.frame(200.0, 1000.0, 390.0, 844.0)
  assert_true(p.alive)
  assert_eq(p.offset, 390.0)
  assert_eq(k.logic_at, 200.0)
  assert_eq(k.owner_releases, 0)
  assert_eq(k.work.layouts, passes)
  assert_eq(k.work.measures, measures)
  k.frame(400.0, 408.0, 390.0, 844.0) |> ignore
  k.frame(800.0, 808.0, 390.0, 844.0) |> ignore
  assert_eq(k.owner_releases, 1)
  assert_eq(k.owner_released_at, Some(400.0))
}

///|
test "interruption and the result at a moment do not depend on intermediate frames" {
  let run = fn(frames : Bool) -> Picture raise {
    let k = Kernel::new(3000)
    defer { k.placement.release() }
    k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
    k.commit(100.0, Leave(390.0, @motion.spring()))
    if frames {
      for at in [108.0, 116.0, 125.0, 133.0, 141.0, 150.0, 166.0] {
        k.frame(at, at + 8.0, 390.0, 844.0) |> ignore
      }
    }
    let before = k.page.sample(180.0)
    k.commit(180.0, Return(@motion.spring()))
    assert_eq(k.page.sample(180.0), before)
    if frames {
      for at in [188.0, 196.0, 205.0, 213.0, 221.0] {
        k.frame(at, at + 8.0, 390.0, 844.0) |> ignore
      }
    }
    k.frame(250.0, 258.0, 390.0, 844.0)
  }
  assert_eq(run(false), run(true))
}

///|
test "hit testing uses the same projection and clip as the picture" {
  let k = Kernel::new(30)
  defer { k.placement.release() }
  k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
  k.commit(100.0, Leave(390.0, @motion.tween(300.0, ease=Linear)))
  let p = k.frame(200.0, 200.0, 390.0, 844.0)
  assert_true(p.offset > 0.0)
  let (_, rect) = p.layout.rows[0]
  assert_eq(p.row_at(p.offset + 10.0, rect.y + 1.0), Some(29))
  assert_eq(p.row_at(p.offset - 1.0, rect.y + 1.0), None)
  assert_eq(p.row_at(p.offset + 10.0, -1.0), None)
  assert_eq(p.row_at(p.offset + 10.0, p.layout.composer.y + 1.0), None)
}

///|
test "a zero-duration transition is already at its target at its cause" {
  let trajectory = Trajectory::still(0.0).toward(390.0, 100.0, Snap(0.0))
  assert_eq(trajectory.sample(100.0), (390.0, 0.0))
}

///|
test "an immediate exit completes before another input at the same moment" {
  let k = Kernel::new(30)
  defer { k.placement.release() }
  k.commit(100.0, Leave(390.0, Snap(0.0)))
  assert_false(k.alive)
  assert_eq(k.owner_released_at, Some(100.0))
  assert_eq(k.owner_releases, 1)
  k.commit(100.0, Return(@motion.spring()))
  assert_false(k.alive)
  assert_eq(k.owner_releases, 1)
}

///|
test "a late observation records the deadline's cause and rejects late owner input" {
  let k = Kernel::new(30)
  defer { k.placement.release() }
  k.commit(100.0, Leave(390.0, @motion.tween(300.0, ease=Linear)))
  k.commit(1000.0, Return(@motion.spring()))
  assert_false(k.alive)
  assert_eq(k.owner_released_at, Some(400.0))
  assert_eq(k.owner_releases, 1)
  assert_eq(k.page.target, 390.0)
}

///|
test "composer changes, measured scrolling and interrupted page motion share one frame-independent picture" {
  let run = fn(step : Int) -> Picture raise {
    let k = Kernel::with_rows(Array::makei(100, fn(i) { Fixed(if i % 2 == 0 { 40.0 } else { 80.0 }) }))
    defer { k.placement.release() }
    k.commit(0.0, Anchor(0))
    k.commit(0.0, ScrollTo(1000.0, @motion.tween(1000.0, ease=Linear)))
    k.frame(0.0, 0.0, 300.0, 200.0) |> ignore
    let between = fn(from : Int, upto : Int) {
      if step > 0 {
        for at = from + step; at < upto; at = at + step {
          k.frame(at.to_double(), at.to_double() + 8.0, 300.0, 200.0) |> ignore
        }
      }
    }
    between(0, 250)
    k.commit(250.0, Composer(100.0))
    between(250, 300)
    k.commit(300.0, Leave(300.0, @motion.tween(400.0, ease=Linear)))
    between(300, 350)
    k.commit(350.0, RowHeight(16, 120.0))
    between(350, 450)
    let before = k.page.sample(450.0)
    k.commit(450.0, Return(@motion.spring()))
    assert_eq(k.page.sample(450.0), before)
    between(450, 1000)
    let picture = k.frame(1000.0, 1008.0, 300.0, 200.0)
    assert_eq(picture.layout.viewport.height, 100.0)
    assert_eq(picture.layout.rows.map(fn(row) { (row.0, row.1.y) }), [(17, 80.0), (16, -40.0)])
    assert_eq(picture.row_at(picture.offset + 10.0, 1.0), Some(16))
    assert_eq(k.owner_releases, 0)
    picture
  }
  assert_eq(run(0), run(8))
  assert_eq(run(0), run(16))
  assert_eq(run(0), run(127))
}

///|
test "presentation prediction cannot move the layout's scroll moment" {
  let k = Kernel::new(100)
  defer { k.placement.release() }
  k.commit(0.0, Anchor(0))
  k.commit(0.0, ScrollTo(1000.0, @motion.tween(1000.0, ease=Linear)))
  let actual = k.frame(200.0, 200.0, 300.0, 160.0)
  let passes = k.work.layouts
  let predicted = k.frame(200.0, 1000.0, 300.0, 160.0)
  assert_eq(predicted.layout, actual.layout)
  assert_eq(predicted.layout.rows.map(fn(row) { row.0 }), [7, 6, 5])
  assert_eq(k.work.layouts, passes)
}
