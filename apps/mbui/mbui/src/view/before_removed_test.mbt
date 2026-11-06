// A reader must save its event-time position while the old list is still intact, even if no frame was painted.

///|
fn checkpoint_list(
  host : @view.View,
  saved : Ref[(Int, Double)?],
  calls : Ref[Int],
  put : @signals.Signal[(Int, Double, Double)?],
) -> Unit {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  host.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
  host.before_removed(fn() {
    calls.val += 1
    saved.val = position.get()
  }) |> ignore
  host.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) }, from_end=false,
    ahead=0.0, put_fraction=put, position~, fn(row, _) {
      row.height(Is(Some(40.0))) |> ignore
    }) |> ignore
}

///|
test "before removal reads the live list when pick replaces its ancestor" {
  let which = @signals.signal(0)
  let saved : Ref[(Int, Double)?] = Ref(None)
  let calls = Ref(0)
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { which.get() }, fn(parent, selected) {
      if selected == 0 {
        parent.box(fn(outer) {
          outer.box(fn(list) { checkpoint_list(list, saved, calls, put) }) |> ignore
        }) |> ignore
      }
    })
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 100.0, 0.0, 65.0, 0, 10.0) |> ignore
  which.set(1)
  assert_eq(calls.val, 1)
  assert_eq(saved.val, Some((1, 0.625)))
  tree.frame(390.0, 844.0, now=10.0) |> ignore
  tree.dispose()
  assert_eq(calls.val, 1)
}

///|
test "before removal runs for an ancestor hidden without another frame" {
  let shown = @signals.signal(true)
  let saved : Ref[(Int, Double)?] = Ref(None)
  let calls = Ref(0)
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { shown.get() }, fn(outer) {
      outer.box(fn(list) { checkpoint_list(list, saved, calls, put) }) |> ignore
    })
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 100.0, 0.0, 65.0, 0, 10.0) |> ignore
  shown.set(false)
  assert_eq(saved.val, Some((1, 0.625)))
  assert_eq(calls.val, 1)
  tree.dispose()
  assert_eq(calls.val, 1)
}

///|
test "before tree disposal a pending jump wins over the old list position" {
  let saved : Ref[(Int, Double)?] = Ref(None)
  let calls = Ref(0)
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) { checkpoint_list(list, saved, calls, put) }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  put.set(Some((70, 0.5, 120.0)))
  tree.dispose()
  assert_eq(saved.val, Some((70, 0.5)))
  assert_eq(calls.val, 1)
  tree.dispose()
  assert_eq(calls.val, 1)
}

///|
test "tree disposal reads a scroll that has not been painted" {
  let saved : Ref[(Int, Double)?] = Ref(None)
  let calls = Ref(0)
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(outer) {
      outer.box(fn(list) { checkpoint_list(list, saved, calls, put) }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 100.0, 0.0, 65.0, 0, 10.0) |> ignore
  tree.dispose()
  assert_eq(saved.val, Some((1, 0.625)))
  assert_eq(calls.val, 1)
}

///|
test "a checkpoint can read layout and write state without rebuilding the removed tree" {
  let which = @signals.signal(0)
  let said = @signals.signal(0)
  let old_rebuilt = Ref(0)
  let new_saw = Ref(0)
  let saved : Ref[(Int, Double)?] = Ref(None)
  let calls = Ref(0)
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { which.get() }, fn(parent, selected) {
      if selected == 0 {
        parent.show(fn() { said.get() != 0 }, fn(_) { old_rebuilt.val += 1 })
        parent.box(fn(list) {
          checkpoint_list(list, saved, calls, put)
          list.before_removed(fn() { said.set(1) }) |> ignore
        }) |> ignore
      } else {
        new_saw.val = said.get()
      }
    })
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 100.0, 0.0, 65.0, 0, 10.0) |> ignore
  which.set(1)
  assert_eq(saved.val, Some((1, 0.625)))
  assert_eq(calls.val, 1)
  assert_eq(old_rebuilt.val, 0)
  assert_eq(new_saw.val, 1)
  tree.dispose()
}

///|
test "a checkpoint reads all current row geometry and end-following without reporting a paint" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let painted = Ref(0)
  let scroll = @view.Scroll::list()
  let saved : Ref[@view.AnchoredGeometry[Int]?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.before_removed(fn() { saved.val = position.geometry() }) |> ignore
      list.scrolls_anchored(scroll, fn() { Array::makei(20, fn(i) { i }) }, est=40.0, ahead=0.0,
        position~, sighted=fn(_) { painted.val += 1 }, fn(row, _) {
          row.height(Is(Some(40.0))) |> ignore
        }) |> ignore
    }) |> ignore
  })
  assert_true(position.geometry() is None)
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(painted.val, 1)
  assert_true(position.geometry().unwrap().follows)
  tree.wheel_at(150.0, 50.0, 0.0, -65.0, 0, 10.0) |> ignore
  tree.dispose()
  assert_eq(painted.val, 1)
  assert_eq(tree.take_after_paint().length(), 0)
  let geometry = saved.val.unwrap()
  assert_eq((geometry.height, geometry.cover, geometry.follows), (100.0, (0.0, 0.0), false))
  assert_eq(geometry.rows[0], (15, -35.0, 40.0))
  assert_true(position.geometry() is None)
}

///|
test "replacing a subtree does not report checkpoint layout as painted" {
  let shown = @signals.signal(true)
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let saved : Ref[@view.AnchoredGeometry[Int]?] = Ref(None)
  let painted = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { shown.get() }, fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.before_removed(fn() { saved.val = position.geometry() }) |> ignore
      list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(20, fn(i) { i }) },
        est=40.0, from_end=false, ahead=0.0, position~, sighted=fn(_) { painted.val += 1 },
        fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    })
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(painted.val, 1)
  tree.wheel_at(150.0, 50.0, 0.0, 65.0, 0, 10.0) |> ignore
  shown.set(false)
  assert_true(saved.val is Some(_))
  tree.frame(390.0, 844.0, now=10.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(painted.val, 1)
  tree.dispose()
}

///|
test "an empty laid out list has geometry but no position, and neither survives removal" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.scrolls_anchored(@view.Scroll::list(), fn() { [] }, position~, fn(row, _) {
        row.height(Is(Some(40.0))) |> ignore
      }) |> ignore
    }) |> ignore
  })
  assert_true(position.geometry() is None)
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(position.get() is None)
  assert_eq(position.geometry().unwrap().rows.length(), 0)
  tree.dispose()
  assert_true(position.get() is None)
  assert_true(position.geometry() is None)
}

///|
test "a resize checkpoint keeps an unpainted scroll in the old window" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let saved : Ref[@view.AnchoredGeometry[Int]?] = Ref(None)
  let painted = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { root.window().0 < 500.0 }, fn(shell, small) {
      if small {
        shell.box(fn(list) {
          list.width(By(fn() { Some(root.window().0) })).height(By(fn() { Some(root.window().1) })) |> ignore
          list.before_removed(fn() { saved.val = position.geometry() }) |> ignore
          list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) },
            from_end=false, est=40.0, ahead=0.0, position~, sighted=fn(_) { painted.val += 1 },
            fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
        }) |> ignore
      }
    })
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(painted.val, 1)
  tree.wheel_at(150.0, 50.0, 0.0, 65.0, 0, 10.0) |> ignore
  tree.frame(700.0, 160.0, now=10.0) |> ignore
  let g = saved.val.unwrap()
  assert_eq((g.height, g.rows[0], g.follows), (100.0, (1, -25.0, 40.0), false))
  for f in tree.take_after_paint() { f() }
  assert_eq(painted.val, 1, msg="the old window was not painted again")
  tree.dispose()
}

///|
test "an unlaid fractional jump survives a resize that replaces its list" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let put : @signals.Signal[(Int, Double, Double)?] = @signals.signal(None)
  let saved : Ref[(Int, Double)?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { root.window().0 < 500.0 }, fn(shell, small) {
      if small {
        shell.box(fn(list) {
          list.width(By(fn() { Some(root.window().0) })).height(By(fn() { Some(root.window().1) })) |> ignore
          list.before_removed(fn() { saved.val = position.get() }) |> ignore
          list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) },
            from_end=false, est=40.0, ahead=0.0, put_fraction=put, position~,
            fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
        }) |> ignore
      }
    })
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  put.set(Some((50, 0.5, 120.0)))
  tree.frame(700.0, 160.0, now=10.0) |> ignore
  assert_eq(saved.val, Some((50, 0.5)))
  tree.dispose()
}

///|
test "a resize checkpoint does not report its unpainted old layout when the list stays" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let sightings : Array[@view.Sighted[Int]] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(By(fn() { Some(root.window().0) })).height(By(fn() { Some(root.window().1) })) |> ignore
      list.before_removed(fn() { position.get() |> ignore }) |> ignore
      list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) },
        from_end=false, est=40.0, ahead=0.0, position~, sighted=fn(s) { sightings.push(s) },
        fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  for f in tree.take_after_paint() { f() }
  tree.wheel_at(150.0, 50.0, 0.0, 65.0, 0, 10.0) |> ignore
  tree.frame(400.0, 160.0, now=10.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(sightings.length(), 2)
  assert_eq((sightings[1].height, sightings[1].rows[0]), (160.0, (1, -25.0, 40.0)))
  let computes = tree.work().computes
  tree.frame(410.0, 160.0, now=20.0) |> ignore
  assert_eq(tree.work().computes - computes, 1, msg="an ordinary resize lays out once")
  tree.dispose()
}

///|
test "a surviving fixed-size list reports its scroll even if resize does not lay it out again" {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let sightings : Array[@view.Sighted[Int]] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.before_removed(fn() { position.get() |> ignore }) |> ignore
      list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) },
        from_end=false, est=40.0, ahead=0.0, position~, sighted=fn(s) { sightings.push(s) },
        fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  for f in tree.take_after_paint() { f() }
  tree.wheel_at(150.0, 50.0, 0.0, 65.0, 0, 10.0) |> ignore
  tree.frame(400.0, 160.0, now=10.0) |> ignore
  for f in tree.take_after_paint() { f() }
  assert_eq(sightings.length(), 2)
  assert_eq((sightings[1].height, sightings[1].rows[0]), (100.0, (1, -25.0, 40.0)))
  tree.dispose()
}

///|
fn resize_coasting_case() -> (@view.Tree, @view.AnchoredPosition[Int], Ref[@view.AnchoredGeometry[Int]?]) {
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let saved : Ref[@view.AnchoredGeometry[Int]?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.pick(fn() { root.window().0 < 500.0 }, fn(shell, small) {
      if small {
        shell.box(fn(list) {
          list.width(By(fn() { Some(root.window().0) })).height(By(fn() { Some(root.window().1) })) |> ignore
          list.before_removed(fn() { saved.val = position.geometry() }) |> ignore
          list.scrolls_anchored(@view.Scroll::list(), fn() { Array::makei(100, fn(i) { i }) },
            from_end=false, est=40.0, ahead=0.0, position~,
            fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
        }) |> ignore
      }
    })
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 50.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
  (tree, position, saved)
}

///|
test "a resize checkpoints a coast at its event time in the old window" {
  let (reference, position, _) = resize_coasting_case()
  let (resized, _, saved) = resize_coasting_case()
  reference.bring_to(50.0)
  let expected = position.geometry().unwrap()
  resized.frame(700.0, 160.0, now=50.0) |> ignore
  let actual = saved.val.unwrap()
  assert_eq((actual.height, actual.rows, actual.follows), (expected.height, expected.rows, expected.follows))
  reference.dispose()
  resized.dispose()
}
