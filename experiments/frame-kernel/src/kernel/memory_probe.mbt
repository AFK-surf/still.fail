// The outer host observes linear-memory growth between identical rounds. Each
// owner finishes through the same input boundary as a page; it does not rely on
// a drawn exit frame to release dependency edges or render resources.

///|
pub fn memory_round() -> Int {
  let mut released = 0
  for _ in 0..<25 {
    let k = Kernel::new(3000)
    k.frame(0.0, 0.0, 390.0, 844.0) |> ignore
    k.commit(10.0, Anchor(0))
    k.commit(10.0, ScrollTo(80000.0, Snap(0.0)))
    k.frame(10.0, 10.0, 390.0, 844.0) |> ignore
    k.commit(20.0, RowHeight(10, 80.0))
    k.frame(20.0, 20.0, 390.0, 844.0) |> ignore
    k.commit(30.0, Leave(390.0, Snap(0.0)))
    guard !k.alive && k.placement.watch.gone() && k.inputs.leaves.is_empty() else {
      abort("an ended owner kept a live query or render leaves")
    }
    k.commit(40.0, Return(@motion.spring()))
    guard !k.alive else { abort("a late input revived an ended owner") }
    released += k.owner_releases
  }
  released
}
