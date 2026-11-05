///|
test "composer and list share one layout result at the requested moment" {
  let k = Kernel::new(3000)
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
  let run = fn(n) {
    let k = Kernel::new(n)
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
  assert_eq(shown.layout.rows[0].1.height, 75.0)
}

///|
test "sampling a page ahead neither lays out again nor finishes its logical lifetime" {
  let k = Kernel::new(3000)
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
}

///|
test "interruption and the result at a moment do not depend on intermediate frames" {
  let run = fn(frames : Bool) {
    let k = Kernel::new(3000)
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
