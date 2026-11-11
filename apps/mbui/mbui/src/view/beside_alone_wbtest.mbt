// What goes beside another as wide as it (View::beside's `Anchor`), laid out alone as its anchor's width changes
// (Tree::beside_widened, Tree::laid_over_alone) and laid out again by the layout of all of it after: the same, each node in
// it where it was and as big, whichever of the two laid it out last.

///|
/// Words `s` measured 8 a letter on lines 16 high, wrapped at the width offered (none offered: on one line).
fn alone_measure(s : String, _look : WordsLook, offered : Double, _scale : Double) -> (Double, Double) {
  let whole = s.length().to_double() * 8.0
  if offered > 0.0 && whole > offered {
    (offered, (whole / offered).ceil() * 16.0)
  } else {
    (whole, 16.0)
  }
}

///|
/// An anchor `aw` wide at (40, 40); beside it below, as wide as it, a layer padded 4 holding words that wrap, a box
/// at most 30 high holding one 80 high, one at least half as tall as the layer, and what is made by its room (half of
/// it wide); `poke` changing a least height
/// said in it to what makes no difference (what lays out all of it again, the layer with it). The tree, the layer.
fn alone_tree(aw : @signals.Signal[Double], poke : @signals.Signal[Int]) -> (Tree, Int) {
  let anchor : Ref[NodeId?] = Ref(None)
  let layer = Ref(-1)
  let t = Tree::new(
    fn(root) {
      root.box(fn(a) {
        anchor.val = Some(a.id())
        a.over(Is(true)).offset(Is((40.0, 40.0))).width(By(fn() { Some(aw.get()) })).height(Is(Some(20.0))) |> ignore
      })
      |> ignore
      root.box(fn(l) {
        l.over(Is(true)) |> ignore
        l.box(fn(p) {
          layer.val = p.at
          p.beside(anchor.val.unwrap(), side=Bottom, along=Start, offset=6.0, width=Anchor).padding(Is((4.0, 4.0, 4.0, 4.0)))
          |> ignore
          p.box(fn(w) { w.words(Is("words that wrap at the width they are given")) |> ignore }) |> ignore
          p.box(fn(m) {
            m
            .max_height(Is(Some(30.0)))
            .min_height(By(fn() { if poke.get() % 2 == 0 { None } else { Some(0.0) } }))
            |> ignore
            m.box(fn(x) { x.height(Is(Some(80.0))) |> ignore }) |> ignore
          })
          |> ignore
          // (at least half as tall as the layer: a share of a height it is given only as it is laid out at its size)
          p.box(fn(h) { h.min_height_share(Is(Some(0.5))) |> ignore }) |> ignore
          p.by_room(fn(held, room) {
            held.box(fn(c) { c.height(Is(Some(10.0))).width(By(fn() { Some(room.width() / 2.0) })) |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    measure=alone_measure,
    time=fn() { 0.0 },
  )
  t.frame(600.0, 400.0) |> ignore
  (t, layer.val)
}

///|
/// Where node `at` and each it holds are laid out and how big, in order.
fn laid_under(t : Tree, at : Int) -> Array[(Double, Double, Double, Double)] {
  let n = t.nodes[at]
  let out = [(n.lx, n.ly, n.lw, n.lh)]
  for k in n.kids {
    out.append(laid_under(t, k))
  }
  out
}

///|
test "beside as wide as its anchor: laid out alone as the anchor widens, then by the layout of all of it, each node in it the same; and the other way round" {
  let aw = @signals.signal(200.0, same=fn(a, b) { a == b })
  let poke = @signals.signal(0, same=fn(a, b) { a == b })
  let (t, p) = alone_tree(aw, poke)
  // the anchor 260: laid out alone, in that frame
  let at_first = t.nodes[p].flex.laid_out_at()
  t.event(10.0, fn() { aw.set(260.0) })
  t.frame(600.0, 400.0) |> ignore
  let alone = laid_under(t, p)
  assert_eq(alone[0].2, 260.0)
  // (the words wrapped at its width, the box at its most, what its room made half of it)
  assert_true(alone.length() >= 5, msg="\{Repr(alone)}")
  // what lays out all of it again, the layer too: the same
  let at_alone = t.nodes[p].flex.laid_out_at()
  assert_true(at_alone > at_first)
  t.event(20.0, fn() { poke.set(1) })
  t.frame(600.0, 400.0) |> ignore
  assert_true(t.nodes[p].flex.laid_out_at() > at_alone, msg="laid out again by the layout of all of it")
  assert_eq(laid_under(t, p), alone)
  // the other way round: laid out by all of it, then alone as the anchor widens again, then by all of it
  t.event(30.0, fn() { aw.set(200.0) })
  t.frame(600.0, 400.0) |> ignore
  let narrow = laid_under(t, p)
  t.event(40.0, fn() { poke.set(2) })
  t.frame(600.0, 400.0) |> ignore
  assert_eq(laid_under(t, p), narrow)
  t.event(50.0, fn() { aw.set(260.0) })
  t.frame(600.0, 400.0) |> ignore
  assert_eq(laid_under(t, p), alone)
  t.event(60.0, fn() { poke.set(3) })
  t.frame(600.0, 400.0) |> ignore
  assert_eq(laid_under(t, p), alone)
  // and as one made 260 wide from the first
  let (fresh, q) = alone_tree(@signals.signal(260.0, same=fn(a, b) { a == b }), @signals.signal(0, same=fn(a, b) { a == b }))
  assert_eq(laid_under(fresh, q), alone)
}

///|
test "beside as wide as its anchor: one let go, the node made next at its index beside another anchor as wide, as wide as that one from its first frame, nothing of the width kept for the one before" {
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let ids : Map[String, NodeId] = Map([])
  let at : Map[String, Int] = Map([])
  let t = Tree::new(
    fn(root) {
      for k in ["a", "b"] {
        root.box(fn(a) {
          ids[k] = a.id()
          a
          .over(Is(true))
          .offset(Is((40.0, if k == "a" { 40.0 } else { 200.0 })))
          .width(Is(Some(200.0)))
          .height(Is(Some(20.0)))
          |> ignore
        })
        |> ignore
      }
      root.box(fn(l) {
        l.over(Is(true)) |> ignore
        for k in ["a", "b"] {
          l.show(fn() { which.get() == (if k == "a" { 1 } else { 2 }) }, fn(s) {
            at[k] = s.at
            s.height(Is(Some(20.0))).beside(ids[k], side=Bottom, along=Start, offset=6.0, width=Anchor) |> ignore
          })
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(600.0, 400.0) |> ignore
  t.event(10.0, fn() { which.set(1) })
  t.frame(600.0, 400.0) |> ignore
  assert_eq(t.nodes[at["a"]].lw, 200.0)
  t.event(20.0, fn() { which.set(0) })
  t.frame(600.0, 400.0) |> ignore
  t.event(30.0, fn() { which.set(2) })
  t.frame(600.0, 400.0) |> ignore
  // (the same index, made again: what this is about)
  assert_eq(at["b"], at["a"])
  assert_eq((t.nodes[at["b"]].lw, t.nodes[at["b"]].ly), (200.0, 226.0))
}
