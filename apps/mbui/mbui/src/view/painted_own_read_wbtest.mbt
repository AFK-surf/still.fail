// A Painted value is its node's own read (reads_own): worked out where what is laid out is shut (a host's hand-off,
// shut_layout_reads), what it reads of another node laid out is read as told, no fault; shut again after it.

///|
test "painted: worked out in a hand-off where what is laid out is shut, reading another node's size as told, shut again after" {
  let seen : Ref[(Double, Double)?] = Ref(None)
  let runs = Ref(0)
  let poke = @signals.signal(0, same=fn(a, b) { a == b })
  let other : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.box(fn(a) {
      other.val = Some(a)
      a.width(Is(Some(120.0))).height(Is(Some(30.0))) |> ignore
    }) |> ignore
    root.box(fn(b) {
      b.width(Is(Some(10.0))).height(Is(Some(10.0)))
      .offset(Painted(fn(_) {
        poke.get() |> ignore
        runs.val = runs.val + 1
        let z = other.val.unwrap().laid_size_told()
        seen.val = z
        (0.0, z.map(fn(s) { s.1 }).unwrap_or(0.0))
      })) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let first = runs.val
  let was = shut_layout_reads(Some("a hand-off in a test"))
  poke.set(1)
  tree.frame(400.0, 300.0, now=16.0) |> ignore
  let after = shut_layout_reads(was)
  tree.dispose()
  assert_true(runs.val > first, msg="worked out again while shut")
  assert_eq(seen.val, Some((120.0, 30.0)))
  assert_eq(after, Some("a hand-off in a test"), msg="shut again after it")
}
