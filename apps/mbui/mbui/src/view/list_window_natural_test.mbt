// A window sized by its rows, up to the room its holder gives it, without making the rest of a long list.

///|
test "a natural window sizes to its rows in the same layout and stops at its holder's limit" {
  let keys = @signals.signal([0, 1], same=fn(a, b) { a == b })
  let row_height = @signals.signal(40.0, same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let made = Ref(0)
  let list : Ref[@view.View?] = Ref(None)
  let below : Ref[@view.View?] = Ref(None)
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).max_height(Is(Some(120.0))) |> ignore
      list.val = Some(body.box(fn(v) {
        v.scrolls_window(scroll, fn() { keys.get() }, est=80.0, natural=true, fn(row, k) {
          made.val += 1
          live[k] = row
          row.owns(fn() { live.remove(k) }) |> ignore
          row.height(By(fn() { Some(row_height.get()) })) |> ignore
        }) |> ignore
      }))
    }) |> ignore
    below.val = Some(root.box(fn(v) { v.height(Is(Some(10.0))) |> ignore }))
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((list.val.unwrap().rect().3, below.val.unwrap().rect().1), (80.0, 80.0))
  let computes = tree.work().computes
  row_height.set(30.0)
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((list.val.unwrap().rect().3, below.val.unwrap().rect().1), (60.0, 60.0))
  assert_eq(tree.work().computes - computes, 1)
  row_height.set(40.0)
  let made_before = made.val
  keys.set(Array::makei(10, fn(i) { i }))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((list.val.unwrap().rect().3, below.val.unwrap().rect().1), (120.0, 120.0))
  assert_true(live.length() < 10, msg="a bounded window does not build every row")
  assert_true(made.val - made_before < 10, msg="a sizing probe did not build the whole long list")
  tree.wheel_at(100.0, 50.0, 0.0, 120.0, 0, 10.0) |> ignore
  tree.frame(300.0, 300.0) |> ignore
  assert_true(live.contains(3))
  tree.dispose()
}

///|
test "a natural window follows the end only until the hand leaves it" {
  let keys = @signals.signal([0, 1], same=fn(a, b) { a == b })
  let follows = @signals.signal(true, same=fn(a, b) { a == b })
  let live : Map[Int, @view.View] = Map([])
  let list : Ref[@view.View?] = Ref(None)
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).max_height(Is(Some(120.0))) |> ignore
      list.val = Some(body.box(fn(v) {
        v.scrolls_window(scroll, fn() { keys.get() }, est=40.0, natural=true, from_end=true, align_end=false,
          follows~, fn(row, k) {
            live[k] = row
            row.owns(fn() { live.remove(k) }) |> ignore
            row.height(Is(Some(40.0))) |> ignore
          }) |> ignore
      }))
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((list.val.unwrap().rect().3, live[0].rect().1), (80.0, 0.0))
  keys.set(Array::makei(6, fn(i) { i }))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 120.0)
  assert_eq(scroll.at(tree), scroll.most())
  tree.wheel_at(100.0, 50.0, 0.0, -80.0, 0, 10.0) |> ignore
  tree.frame(300.0, 300.0) |> ignore
  let away = scroll.at(tree)
  assert_false(follows.get())
  keys.set(Array::makei(7, fn(i) { i }))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(scroll.at(tree), away)
  assert_false(follows.get())
  tree.dispose()
}

///|
test "a natural window shares a height limit with a preceding fixed header" {
  let keys = @signals.signal([0, 1], same=fn(a, b) { a == b })
  let list : Ref[@view.View?] = Ref(None)
  let header : Ref[@view.View?] = Ref(None)
  let live : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).max_height(Is(Some(120.0))) |> ignore
      header.val = Some(body.box(fn(v) { v.height(Is(Some(20.0))).shrink(Is(0.0)) |> ignore }))
      list.val = Some(body.box(fn(v) {
        v.scrolls_window(@view.Scroll::list(), fn() { keys.get() }, est=40.0, natural=true, fn(row, k) {
          live[k] = row
          row.owns(fn() { live.remove(k) }) |> ignore
          row.height(Is(Some(40.0))) |> ignore
        }) |> ignore
      }))
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((header.val.unwrap().rect().3, list.val.unwrap().rect().1, list.val.unwrap().rect().3), (20.0, 20.0, 80.0))
  keys.set(Array::makei(10, fn(i) { i }))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((header.val.unwrap().rect().3, list.val.unwrap().rect().1, list.val.unwrap().rect().3), (20.0, 20.0, 100.0))
  assert_true(live.length() < 10)
  tree.dispose()
}

///|
test "a natural window keeps an explicit height" {
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    list.val = Some(root.box(fn(v) {
      v.height(Is(Some(100.0))).scrolls_window(@view.Scroll::list(), fn() { [0, 1] },
        natural=true, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }))
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 100.0)
  tree.dispose()
}

///|
test "a natural window respects a holder's limit inside an unbounded scrolling column" {
  let made = Ref(0)
  let minimum : @signals.Signal[Double?] = @signals.signal(None)
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.height(Is(Some(300.0))).scrolls(@view.Scroll::new(), fn(held) {
      held.box(fn(body) {
        body.max_height(Is(Some(120.0))).min_height(By(fn() { minimum.get() })) |> ignore
        body.box(fn(header) { header.height(Is(Some(20.0))).shrink(Is(0.0)) |> ignore }) |> ignore
        list.val = Some(body.box(fn(v) {
          v.scrolls_window(@view.Scroll::list(), fn() { Array::makei(10, fn(i) { i }) },
            natural=true, fn(row, _) {
              made.val += 1
              row.height(Is(Some(40.0))) |> ignore
            }) |> ignore
        }))
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 100.0)
  assert_true(made.val < 10, msg="the holder's explicit limit bounds the probe")
  minimum.set(Some(160.0))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 140.0, msg="a minimum above the maximum takes precedence")
  tree.dispose()
}

///|
test "a natural window sees a changed enclosing limit through an unsized wrapper" {
  let cap = @signals.signal(Some(120.0))
  let made = Ref(0)
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.height(Is(Some(300.0))).scrolls(@view.Scroll::new(), fn(held) {
      held.box(fn(body) {
        body.max_height(By(fn() { cap.get() })) |> ignore
        body.box(fn(header) { header.height(Is(Some(20.0))).shrink(Is(0.0)) |> ignore }) |> ignore
        body.box(fn(wrapper) {
          wrapper.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          list.val = Some(wrapper.box(fn(v) {
            v.scrolls_window(@view.Scroll::list(), fn() { Array::makei(50, fn(i) { i }) },
              natural=true, fn(row, _) {
                made.val += 1
                row.height(Is(Some(40.0))) |> ignore
              }) |> ignore
          }))
        }) |> ignore
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 100.0)
  assert_true(made.val < 50)
  cap.set(Some(80.0))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 60.0)
  cap.set(Some(160.0))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 140.0)
  assert_true(made.val < 50)
  tree.dispose()
}

///|
test "adding a limit replaces an unbounded natural measurement" {
  let cap : @signals.Signal[Double?] = @signals.signal(None)
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.height(Is(Some(300.0))).scrolls(@view.Scroll::new(), fn(held) {
      held.box(fn(body) {
        body.max_height(By(fn() { cap.get() })) |> ignore
        body.box(fn(header) { header.height(Is(Some(20.0))).shrink(Is(0.0)) |> ignore }) |> ignore
        list.val = Some(body.box(fn(v) {
          v.scrolls_window(@view.Scroll::list(), fn() { Array::makei(10, fn(i) { i }) },
            natural=true, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
        }))
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 400.0)
  cap.set(Some(80.0))
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 60.0)
  tree.dispose()
}

///|
test "a window's intrinsic limit does not limit its rows' own content" {
  let outer : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.height(Is(Some(300.0))).scrolls(@view.Scroll::new(), fn(held) {
      held.box(fn(body) {
        body.max_height(Is(Some(120.0))) |> ignore
        outer.val = Some(body.box(fn(v) {
          v.scrolls_window(@view.Scroll::list(), fn() { [0] }, natural=true, fn(row, _) {
            inner.val = Some(row.box(fn(contents) {
              contents.scrolls_window(@view.Scroll::list(), fn() { [0, 1, 2, 3, 4] }, natural=true,
                fn(item, _) { item.height(Is(Some(40.0))) |> ignore }) |> ignore
            }))
          }) |> ignore
        }))
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(outer.val.unwrap().rect().3, 120.0)
  assert_eq(inner.val.unwrap().rect().3, 200.0)
  tree.dispose()
}

///|
test "a natural window uses the current animated rooms instead of their full heights" {
  let opening = @signals.signal(1.0, same=fn(a, b) { a == b })
  let list : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).max_height(Is(Some(120.0))) |> ignore
      list.val = Some(body.box(fn(v) {
        v.scrolls_window(@view.Scroll::list(), fn() { [0, 1] }, natural=true,
          rooms=fn() {
            let factor = opening.get()
            fn(_k, h, _w) { { ..@view.list_room(h), height: h * factor } }
          }, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
      }))
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 80.0)
  opening.set(0.5)
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(list.val.unwrap().rect().3, 40.0)
  tree.dispose()
}
