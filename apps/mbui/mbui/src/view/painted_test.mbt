// What reads where layout put things reads it as the frame is painted (Live's `Painted`, retained.md "Layout read
// back"), in that frame, and lays nothing out again; where it is read by the hand, as the tree last placed it
// (View::shown_rect); what a box holds chosen by its room in its own layout (View::by_room); a width within its holder
// said, not read back (View::min_width_within, max_width_within).

///|
test "a ring offset by where another node is laid out: in the frame that laid it out, one layout in it" {
  let wide = @signals.signal(80.0)
  let at : Ref[(@view.View, @view.View)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        let card = r.box(fn(c) { c.width(By(fn() { Some(wide.get()) })).height(Is(Some(20.0))) |> ignore })
        let ring = r.box(fn(g) {
          g.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
          // (beside the card's right edge, wherever the row lays the card out)
          g.offset(Painted(fn(laid) { laid.rect(card).map(fn(c) { (c.0 + c.2, 0.0) }).unwrap_or((0.0, 0.0)) })) |> ignore
        })
        at.val = Some((card, ring))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let (card, ring) = at.val.unwrap()
  assert_eq(card.rect().2, 80.0)
  // (the ring laid out after the card, at 80, drawn off by the card's right edge, 80 more)
  assert_eq(ring.rect().0, 160.0)
  let computes = tree.work().computes
  wide.set(120.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(ring.rect().0, 240.0, msg="drawn where the card is in the frame it was laid out in")
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  // (nothing changed: no frame owed)
  assert_false(tree.frame(390.0, 844.0, now=32.0))
  tree.dispose()
}

///|
test "a Painted value reading a signal: drawn again as it changes, nothing laid out" {
  let shift = @signals.signal(0.0)
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      at.val = Some(root.box(fn(b) {
        b.width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Painted(fn(_) { (shift.get(), 0.0) })) |> ignore
      }))
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let b = at.val.unwrap()
  assert_eq(b.rect().0, 0.0)
  let computes = tree.work().computes
  shift.set(30.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq(b.rect().0, 30.0)
  assert_eq(tree.work().computes - computes, 0, msg="nothing laid out for a place")
  tree.dispose()
}

///|
test "panic: a property layout reads said Painted aborts" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(b) { b.width(Painted(fn(_) { Some(10.0) })) |> ignore }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}

///|
test "where the hand finds a node: as the tree last placed it" {
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(holder) {
      holder.padding(Is((12.0, 8.0, 0.0, 0.0))) |> ignore
      at.val = Some(holder.box(fn(b) { b.width(Is(Some(50.0))).height(Is(Some(20.0))) |> ignore }))
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(at.val.unwrap().shown_rect(), Some((12.0, 8.0, 50.0, 20.0)))
  assert_eq(at.val.unwrap().shown_size(), Some((50.0, 20.0)))
  tree.dispose()
}

///|
test "what a box holds chosen by its room, in its own layout: the other made as the room changes, one layout a frame" {
  let made : Array[String] = []
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b.grow(Is(1.0)) |> ignore
        b.by_room(fn(w, _) { if w < 600.0 { "narrow" } else { "wide" } }, fn(v, k) {
          made.push(k)
          v.box(fn(x) { x.height(Is(Some(10.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  assert_eq(made, ["narrow"])
  let computes = tree.work().computes
  tree.frame(800.0, 844.0, now=16.0) |> ignore
  assert_eq(made, ["narrow", "wide"])
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "a card at least 360 and at most 560 within its room: said, not read back" {
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      at.val = Some(col.box(fn(c) {
        c.min_width_within(Is(Some(360.0))).max_width_within(Is(Some(560.0))).height(Is(Some(10.0))) |> ignore
      }))
    })
    |> ignore
  })
  tree.frame(300.0, 844.0) |> ignore
  // (a room of 300: the least is all of it, 300)
  assert_eq(at.val.unwrap().rect().2, 300.0)
  tree.frame(800.0, 844.0) |> ignore
  // (a room of 800: a column stretches it, at most 560)
  assert_eq(at.val.unwrap().rect().2, 560.0)
  tree.dispose()
}
