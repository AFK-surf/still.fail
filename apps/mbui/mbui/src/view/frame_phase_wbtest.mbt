// A frame may be shown ahead of its event time. That prediction cannot change the layout or decide which event
// runs. Inputs receive their own single layout, so drawing between two inputs never changes what they hit.

///|
test "a frame lays out at its actual time even when it will be shown later" {
  let box : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    box.val = Some(root.box(fn(n) {
      n.height(By(fn() { Some(n.drawn_at()) })).shrink(Is(0.0))
      .alpha(By(fn() { n.paint_at() / 200.0 })).ground(Is(0x112233ffL)) |> ignore
    }))
  })
  t.at(100.0)
  t.frame(200.0, 300.0, now=50.0) |> ignore
  assert_eq(box.val.unwrap().laid_size().1, 50.0)
  assert_eq(t.work.computes, 1, msg="only one layout used to produce the frame")
  assert_eq(t.drawn_of(box.val.unwrap().id()).unwrap().alpha, 0.5, msg="paint samples the presentation time")
  t.dispose()
}

///|
test "panic a presentation clock cannot drive layout after the frame has been measured" {
  let t = Tree::new(fn(root) {
    root.box(fn(n) { n.height(By(fn() { Some(n.paint_at()) })) |> ignore }) |> ignore
  })
  t.at(100.0)
  t.frame(200.0, 300.0, now=50.0) |> ignore
}

///|
test "two inputs find the same geometry whether frames were inserted or predicted between them" {
  let run = fn(frames : Array[Double], prediction : Double) {
    let now = Ref(0.0)
    let changed = @signals.signal(false, same=fn(a, b) { a == b })
    let hits : Array[Double] = []
    let t = Tree::new(fn(root) {
      root.box(fn(n) {
        n.width(Is(Some(100.0))).height(Is(Some(20.0)))
        .offset(By(fn() { (0.0, if changed.get() { n.drawn_at() } else { 0.0 }) }))
        .drawn_off(By(fn() { (if changed.get() { n.paint_at() } else { 0.0 }, 0.0) }))
        .on_press(fn() { hits.push(n.logic_at()) }) |> ignore
      }) |> ignore
    }, time=fn() { now.val })
    t.frame(200.0, 300.0, now=0.0) |> ignore
    now.val = 10.0
    t.event(10.0, fn() { changed.set(true) })
    for frame in frames {
      now.val = frame
      t.at(frame + prediction)
      t.frame(200.0, 300.0, now=frame) |> ignore
    }
    now.val = 95.0
    t.press(97.0, 97.0) |> ignore
    t.dispose()
    hits
  }
  assert_eq(run([], 0.0), [95.0])
  for prediction in [0.0, 40.0] {
    assert_eq(run([16.0, 32.0, 48.0, 64.0, 80.0], prediction), [95.0])
    assert_eq(run([8.0, 16.0, 24.0, 32.0, 40.0, 48.0, 56.0, 64.0, 72.0, 80.0, 88.0], prediction), [95.0])
    assert_eq(run([37.0, 91.0], prediction), [95.0])
  }
}

///|
test "reading a layout result while publishing it cannot rewind the frame's clock" {
  let seen : Array[Double] = []
  let t = Tree::new(fn(root) {
    root.box(fn(n) {
      n.height(By(fn() { Some(n.drawn_at()) })).shrink(Is(0.0)) |> ignore
      n.reacts(fn() { n.laid_size_told() }, fn(size) {
        if size is Some(_) { seen.push(n.drawn_at()) }
      })
    }) |> ignore
  }, time=fn() { 40.0 })
  t.at(100.0)
  t.frame(200.0, 300.0, now=50.0) |> ignore
  assert_eq(seen, [50.0])
  assert_eq(t.work.computes, 1)
  t.dispose()
}
