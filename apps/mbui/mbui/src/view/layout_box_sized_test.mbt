// A box that lays out what it holds itself, given its width by what holds it and as tall as what it holds (View::
// layout_box's `sized`, Layout::size_to): its height said in the same layout, as a leaf's measure says it, never read
// back from it (retained.md, "Layout read back": room down, size up).

///|
test "a layout box sized by what it holds: as tall as its two children stacked, what follows it under it, one layout" {
  let tall = @signals.signal(30.0, same=fn(a, b) { a == b })
  let at : Ref[(@view.View, @view.View)?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        let held = col.box(fn(b) {
          b.layout_box(
            Is(()),
            fn(l, _) {
              let a = l.child("a", fn(v) { v.height(By(fn() { Some(tall.get()) })) |> ignore })
              let c = l.child("c", fn(v) { v.height(Is(Some(20.0))) |> ignore })
              let ha = l.measure(a, l.width).1
              let hc = l.measure(c, l.width).1
              l.place(a, 0.0, 0.0)
              l.place(c, 0.0, ha)
              l.size_to(ha + hc)
            },
            sized=true,
          )
          |> ignore
        })
        let after = col.box(fn(b) { b.height(Is(Some(10.0))) |> ignore })
        at.val = Some((held, after))
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let (held, after) = at.val.unwrap()
  assert_eq((held.rect().2, held.rect().3, after.rect().1), (390.0, 50.0, 50.0))
  let computes = tree.work().computes
  tall.set(70.0)
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  assert_eq((held.rect().3, after.rect().1), (90.0, 90.0))
  assert_eq(tree.work().computes - computes, 1, msg="one layout")
  tree.dispose()
}

///|
test "by_room sized by what it picks: as tall as the arrangement its width calls for" {
  let at : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      at.val = Some(col.box(fn(b) {
        b.by_room(Is(()), fn(_, w, _) { if w < 600.0 { 2 } else { 1 } }, fn(v, lines) {
          v.height(Is(Some(lines.to_double() * 20.0))) |> ignore
        }, sized=true)
        |> ignore
      }))
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(at.val.unwrap().rect().3, 40.0)
  tree.frame(800.0, 844.0) |> ignore
  assert_eq(at.val.unwrap().rect().3, 20.0)
  tree.dispose()
}

///|
test "panic: a layout box sized by what it holds that says no height aborts" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) { col.box(fn(b) { b.layout_box(Is(()), fn(_, _) {  }, sized=true) |> ignore }) |> ignore }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
}
