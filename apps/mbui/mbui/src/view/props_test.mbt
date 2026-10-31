// A node's properties each bound on its own (View::bind, by Prop): many of one node each followed as what says it
// changes, none letting go of another's; the two ways of saying its width one binding, the last said in force.

///|
test "props: one node's ground, opacity, scale, corner, words centred and words each followed as they change, none letting go of another" {
  let ground = @signals.signal(0x112233FFL, same=fn(a, b) { a == b })
  let alpha = @signals.signal(1.0, same=fn(a, b) { a == b })
  let scale = @signals.signal(1.0, same=fn(a, b) { a == b })
  let radius = @signals.signal(0.0, same=fn(a, b) { a == b })
  let centred = @signals.signal(false, same=fn(a, b) { a == b })
  let words = @signals.signal("a", same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .width(Is(Some(100.0)))
        .height(Is(Some(40.0)))
        .ground(By(fn() { ground.get() }))
        .alpha(By(fn() { alpha.get() }))
        .scale(By(fn() { scale.get() }), about=At(0.0, 0.0))
        .radius(By(fn() { radius.get() }))
        .words_centered(By(fn() { centred.get() }))
        .words(By(fn() { words.get() }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let seen = fn() {
    let d = t.drawn_of(id.val.unwrap()).unwrap()
    (d.ground, d.alpha, d.w, d.radius, d.words_center, d.words)
  }
  assert_eq(seen(), (0x112233FFL, 1.0, 100.0, 0.0, false, "a"), msg="as made")
  t.event(10.0, fn() {
    ground.set(0x445566FFL)
    alpha.set(0.5)
    scale.set(0.5)
    radius.set(8.0)
    centred.set(true)
    words.set("b")
  })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(seen(), (0x445566FFL, 0.5, 50.0, 8.0, true, "b"), msg="each as it changed")
  t.event(20.0, fn() {
    ground.set(0x778899FFL)
    words.set("c")
  })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(seen(), (0x778899FFL, 0.5, 50.0, 8.0, true, "c"), msg="each again, the rest as they were")
}

///|
test "props: a node's width bound in points, then bound as a share of what holds it: one binding, the first let go of; its points changed after take nothing back, its share changed is followed" {
  let points = @signals.signal(100.0, same=fn(a, b) { a == b })
  let share = @signals.signal(0.5, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .width(By(fn() { Some(points.get()) }))
        .width_share(By(fn() { share.get() }))
        .height(Is(Some(10.0)))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let w = fn() { t.drawn_of(id.val.unwrap()).unwrap().w }
  assert_eq(w(), 200.0, msg="the share in force")
  t.event(10.0, fn() { points.set(120.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(w(), 200.0, msg="its points changed: nothing taken back")
  t.event(20.0, fn() { share.set(0.25) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(w(), 100.0, msg="its share changed: followed")
}

///|
test "props: a node's words bound, then bound in pieces: one binding, the first let go of; its words changed after take nothing back, its pieces changed are followed" {
  let words = @signals.signal("plain", same=fn(a, b) { a == b })
  let runs = @signals.signal("pieces", same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .words(By(fn() { words.get() }))
        .words_runs(By(fn() { [{ text: runs.get(), weight: 0, ink: 0L }] }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let shown = fn() { t.drawn_of(id.val.unwrap()).unwrap().runs.map(fn(r) { r.text }) }
  assert_eq(shown(), ["pieces"], msg="the pieces in force")
  t.event(10.0, fn() { words.set("again") })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(shown(), ["pieces"], msg="its words changed: nothing taken back")
  t.event(20.0, fn() { runs.set("more") })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(shown(), ["more"], msg="its pieces changed: followed")
}
