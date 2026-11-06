// Reading a place after a user's scroll must not depend on a frame arriving in between.

///|
test "scroll activity reports event-time movement without treating reflow or an end as a move" {
  let scroll = @view.Scroll::list()
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let width = @signals.signal(200.0, same=fn(a, b) { a == b })
  let events : Array[(@view.ScrollActivity, (Int, Double)?)] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(By(fn() { Some(width.get()) })).height(Is(Some(100.0))) |> ignore
      scroll.on_activity(list, fn(event) { events.push((event, position.get())) })
      list.scrolls_anchored(scroll, fn() { Array::makei(20, fn(i) { i }) },
        from_end=false, ahead=0.0, position~, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(200.0, 200.0, now=0.0) |> ignore
  tree.wheel_at(50.0, 50.0, 0.0, 65.0, 0, 10.0) |> ignore
  assert_eq(events, [(@view.ScrollMoved(10.0), Some((1, 0.625)))])
  width.set(180.0)
  tree.frame(200.0, 200.0, now=20.0) |> ignore
  assert_eq(events.length(), 1)
  scroll.put(0.0)
  tree.frame(200.0, 200.0, now=30.0) |> ignore
  tree.wheel_at(50.0, 50.0, 0.0, -40.0, 0, 40.0) |> ignore
  assert_eq(events.length(), 1)
  tree.dispose()
}

///|
test "scroll activity reports an unpainted coast ending or interrupted at the event's moment" {
  let scroll = @view.Scroll::list()
  let position : @view.AnchoredPosition[Int] = @view.AnchoredPosition::new()
  let events : Array[(@view.ScrollActivity, (Int, Double)?)] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      scroll.on_activity(list, fn(event) { events.push((event, position.get())) })
      list.scrolls_anchored(scroll, fn() { Array::makei(100, fn(i) { i }) },
        from_end=false, ahead=0.0, position~, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(200.0, 200.0, now=0.0) |> ignore
  tree.wheel_at(50.0, 50.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
  assert_eq(events[0].0, @view.ScrollCoasting(10.0))
  tree.bring_to(50.0)
  scroll.stop()
  assert_eq(events[1].0, @view.ScrollStopped(50.0, true))
  assert_true(events[1].1 != Some((0, 0.0)))
  tree.wheel_at(50.0, 50.0, 0.0, 80.0, @view.wheel_notch, 60.0) |> ignore
  assert_eq(events[2].0, @view.ScrollCoasting(60.0))
  let end = scroll.glides_till().unwrap()
  tree.advance(end)
  assert_eq(events[3].0, @view.ScrollStopped(end, true))
  let count = events.length()
  tree.dispose()
  tree.advance(end + 1000.0)
  assert_eq(events.length(), count)
}

///|
test "interrupting a coast before it moves does not count as another scroll" {
  let scroll = @view.Scroll::list()
  let events : Array[@view.ScrollActivity] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      scroll.on_activity(list, fn(event) { events.push(event) })
      list.scrolls_anchored(scroll, fn() { Array::makei(20, fn(i) { i }) }, from_end=false, ahead=0.0,
        fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(200.0, 200.0, now=0.0) |> ignore
  tree.wheel_at(50.0, 50.0, 0.0, 80.0, @view.wheel_notch, 10.0) |> ignore
  scroll.stop()
  assert_eq(events, [@view.ScrollCoasting(10.0), @view.ScrollStopped(10.0, false)])
  tree.dispose()
}

///|
test "a scroll activity listener leaves with its owner" {
  let scroll = @view.Scroll::list()
  let watching = @signals.signal(true)
  let events : Array[@view.ScrollActivity] = []
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { watching.get() }, fn(owner) {
      scroll.on_activity(owner, fn(event) { events.push(event) })
    })
    root.box(fn(list) {
      list.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      list.scrolls_anchored(scroll, fn() { Array::makei(20, fn(i) { i }) }, from_end=false, ahead=0.0,
        fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(200.0, 200.0, now=0.0) |> ignore
  tree.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 10.0) |> ignore
  assert_eq(events, [@view.ScrollMoved(10.0)])
  watching.set(false)
  tree.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 20.0) |> ignore
  assert_eq(events, [@view.ScrollMoved(10.0)])
  tree.dispose()
}
