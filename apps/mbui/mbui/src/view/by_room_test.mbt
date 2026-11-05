// What a node holds made by the room it is laid out in (View::by_room): worked out in the frame's one layout, made
// again only as what that says comes out otherwise, the node as tall as what it holds in the same frame.

///|
test "by_room: what it holds made for the width it is laid out at, in the frame that lays it out; made again only as that comes out otherwise, as tall as it in the same frame" {
  let beside = @signals.signal(100.0)
  let made : Array[Bool] = []
  let room : Ref[@view.View?] = Ref(None)
  let under : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))) |> ignore
      col.box(fn(line) {
        line.row(Is(true)) |> ignore
        line.box(fn(b) { b.width(By(fn() { Some(beside.get()) })).shrink(Is(0.0)) |> ignore }) |> ignore
        // (as wide as the line leaves it: 200 of its 300, giving way to what is beside it)
        room.val = Some(
          line.box(fn(r) {
            r.basis(Is(Some(200.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            r.by_room(fn(w) { w >= 150.0 }, fn(v, wide) {
              made.push(wide)
              v.height(Is(Some(if wide { 20.0 } else { 40.0 }))) |> ignore
            })
            |> ignore
          }),
        )
      })
      |> ignore
      // (laid out under it, as tall as it comes to)
      under.val = Some(col.box(fn(u) { u.height(Is(Some(10.0))) |> ignore }))
    })
    |> ignore
  })
  let seen = fn() {
    let (_, _, w, h) = room.val.unwrap().rect()
    let (_, y, _, _) = under.val.unwrap().rect()
    (w, h, y)
  }
  tree.frame(400.0, 300.0) |> ignore
  let first = seen()
  // (more beside it: 120 of the line's 300 left, narrow; drawn so in the frame it changes in)
  beside.set(180.0)
  tree.frame(400.0, 300.0) |> ignore
  let narrow = seen()
  // (narrower still: as narrow as it was said, nothing made again)
  beside.set(200.0)
  tree.frame(400.0, 300.0) |> ignore
  let narrower = seen()
  beside.set(100.0)
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(
    (first, narrow, narrower, seen(), made),
    ((200.0, 20.0, 20.0), (120.0, 40.0, 40.0), (100.0, 40.0, 40.0), (200.0, 20.0, 20.0), [true, false, true]),
  )
  assert_true(!tree.told_since(), msg="nothing owed")
}

///|
test "a property layout reads worked out of where what holds its root is laid out, as that root is laid out: in what a block of a windowed list makes by its room, the list laid out wider and narrower" {
  let holder : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let s = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.height(Is(Some(300.0))) |> ignore
      col.scrolls_window(s, fn() { ["a"] }, fn(b, _) {
        holder.val = Some(
          b.box(fn(h) {
            h.by_room(fn(_) { () }, fn(v, _) {
              // (half as wide as what holds it is laid out in the list's block: worked out as its own is laid out)
              inner.val = Some(v.box(fn(i) { i.width(Placed(fn() { Some(h.laid_size().0 / 2.0) })).height(Is(Some(10.0))) |> ignore }))
            })
            |> ignore
          }),
        )
      })
      |> ignore
    })
    |> ignore
  })
  let seen = fn() { (holder.val.unwrap().laid_size().0, inner.val.unwrap().laid_size().0) }
  tree.frame(400.0, 300.0) |> ignore
  let first = seen()
  tree.frame(300.0, 300.0) |> ignore
  let narrower = seen()
  tree.frame(500.0, 300.0) |> ignore
  assert_eq((first, narrower, seen()), ((400.0, 200.0), (300.0, 150.0), (500.0, 250.0)))
  assert_true(!tree.told_since(), msg="nothing owed")
}

///|
test "a property layout reads worked out of where what holds its root is laid out, asked at a cause before any frame lays it out: worked out as the read lays things out, never asked of again inside that" {
  let holder : Ref[@view.View?] = Ref(None)
  let inner : Ref[@view.View?] = Ref(None)
  let wide = @signals.signal(400.0)
  let s = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.width(By(fn() { Some(wide.get()) })).height(Is(Some(300.0))) |> ignore
      col.scrolls_window(s, fn() { ["a"] }, fn(b, _) {
        holder.val = Some(
          b.box(fn(h) {
            h.by_room(fn(_) { () }, fn(v, _) {
              inner.val = Some(v.box(fn(i) { i.width(Placed(fn() { Some(h.laid_size().0 / 2.0) })).height(Is(Some(10.0))) |> ignore }))
            })
            |> ignore
          }),
        )
      })
      |> ignore
    })
    |> ignore
  })
  let seen = fn() { (holder.val.unwrap().laid_size().0, inner.val.unwrap().laid_size().0) }
  tree.frame(500.0, 300.0) |> ignore
  // (a cause: the column made narrower, where things are read then, before a frame lays them out)
  wide.set(300.0)
  let at_cause = seen()
  tree.frame(500.0, 300.0) |> ignore
  assert_eq((at_cause, seen()), ((300.0, 150.0), (300.0, 150.0)))
  assert_true(!tree.told_since(), msg="nothing owed")
}
