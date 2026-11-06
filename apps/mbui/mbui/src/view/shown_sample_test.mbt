///|
test "a frame shown after the logic's moment works out a paint reading the clock and a mark crossed once, drawn as of then" {
  let reads = Ref(0)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(0x101010FFL)).alpha(By(fn() {
          reads.val += 1
          let t = v.drawn_at()
          if v.drawn_past(100.0) { 0.5 } else if t > 1000.0 { 0.2 } else { 1.0 }
        })) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let alpha = fn() { tree.drawn().iter().find_first(fn(d) { d.w == 10.0 }).map(fn(d) { d.alpha }).unwrap() }
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  let before = alpha()
  reads.val = 0
  tree.at(150.0)
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  let ahead = (alpha(), reads.val)
  reads.val = 0
  // (shown later again at the same logic's moment: sampled again, nothing else)
  tree.at(160.0)
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  assert_eq((before, ahead, (alpha(), reads.val)), (1.0, (0.5, 1), (0.5, 1)))
}

///|
test "a frame shown after the logic's moment works out a computed two paints read once" {
  let computed_reads = Ref(0)
  let tree = @view.Tree::new(
    fn(root) {
      let t = @signals.computed(fn(_) {
        computed_reads.val += 1
        root.drawn_at()
      })
      for w in [10.0, 12.0] {
        root.box(fn(v) {
          v.width(Is(Some(w))).height(Is(Some(10.0))).ground(Is(0x101010FFL)).alpha(By(fn() {
            if t.get() >= 100.0 { 0.5 } else { 1.0 }
          })) |> ignore
        })
        |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  let alphas = fn() { tree.drawn().filter(fn(d) { d.h == 10.0 }).map(fn(d) { d.alpha }) }
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  computed_reads.val = 0
  tree.at(150.0)
  tree.frame(390.0, 844.0, now=80.0) |> ignore
  assert_eq((alphas(), computed_reads.val), ([0.5, 0.5], 1))
}
