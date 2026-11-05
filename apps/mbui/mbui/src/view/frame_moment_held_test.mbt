// A frame is worked out as of its one moment (Tree::now_of_change): what its layout tells and what that sets going,
// however long the working out takes on the host's clock, which goes on as it works (a phone's: the clock read anew
// on each pass of a layout following sizes that a leaving changes, never coming to rest, 2026-11-05).

///|
test "a frame and what its layout tells are of the frame's moment, however the host's clock goes on meanwhile" {
  let host = Ref(0.0)
  let reads = Ref(0)
  let shown_tall = Ref(0)
  let tall_h : Ref[Double] = Ref(0.0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(600.0))) |> ignore
        // (growing with the clock, as a leaving row's room closes: 20 at 0, 30 at 100)
        let grows = col.box(fn(g) {
          g
          .width(Is(Some(80.0)))
          .height(By(fn() { Some(20.0 + g.tree.drawn_at() / 10.0) }))
          .shrink(Is(0.0))
          |> ignore
        })
        // (made as it is told taller than 25: what follows its size, as a list follows its rows')
        col.show(fn() { grows.laid_size_told().map(fn(z) { z.1 }).unwrap_or(0.0) > 25.0 }, fn(t) {
          shown_tall.val += 1
          t.width(Is(Some(40.0))).height(Is(Some(10.0))) |> ignore
          t.reacts(fn() { grows.laid_size_told() }, fn(z) {
            match z {
              Some((_, h)) => tall_h.val = h
              None => ()
            }
          })
        })
      })
      |> ignore
    },
    // (the host's clock, 7 ms on each time it is read: it goes on as the frame is worked out)
    time=fn() {
      reads.val += 1
      host.val += 7.0
      host.val
    },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  reads.val = 0
  host.val = 200.0
  tree.at(100.0)
  tree.frame(390.0, 844.0, now=100.0) |> ignore
  assert_eq(reads.val, 0)
  assert_eq(tree.logic_at(), 100.0)
  assert_eq(tree.drawn_at(), 100.0)
  assert_eq(shown_tall.val, 1)
  assert_eq(tall_h.val, 30.0)
}
