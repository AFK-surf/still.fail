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
// kept across runs: the tree stopped by the expected abort, let go as the next run begins
let stopped_sized_tree : Ref[@view.Tree?] = Ref(None)

///|
test "panic: a layout box sized by what it holds that says no height aborts" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) { col.box(fn(b) { b.layout_box(Is(()), fn(_, _) {  }, sized=true) |> ignore }) |> ignore }) |> ignore
  })
  stopped_sized_tree.val = Some(tree)
  tree.frame(390.0, 844.0) |> ignore
}

///|
test "a run after an aborted sized layout lets go of its tree and drains after-flush work" {
  // A new run resets the reactive context before disposing of the stopped tree, then runs what other owners kept.
  @signals.reset_globals()
  match stopped_sized_tree.val {
    Some(tree) => {
      stopped_sized_tree.val = None
      tree.dispose()
    }
    None => () // Native's test driver skips the expected-abort test.
  }
  @signals.run_told()
  let ran = Ref(false)
  @signals.after_flush(fn() { ran.val = true })
  assert_true(ran.val, msg="after-flush work is not held by the stopped layout")
}

///|
test "a layout box sized by what it holds, in a row that scrolls across: as tall as it says, what holds it as tall" {
  let probe = fn(across : Bool) {
    let at : Ref[(@view.View, @view.View)?] = Ref(None)
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(col) {
        let body = fn(held : @view.View) {
          let b = held.box(fn(beside) {
            beside.min_width(Is(Some(424.0))) |> ignore
            beside.box(fn(grid) {
              grid.layout_box(
                Is(()),
                fn(l, _) {
                  let a = l.child("a", fn(v) { v.height(Is(Some(70.0))) |> ignore })
                  l.measure(a, l.width) |> ignore
                  l.place(a, 0.0, 0.0)
                  l.size_to(70.0)
                },
                sized=true,
              )
              |> ignore
            })
            |> ignore
          })
          at.val = Some((held, b))
        }
        if across {
          col.box(fn(outer) { outer.scrolls(@view.Scroll::across(), fn(held) { body(held) }) |> ignore }) |> ignore
        } else {
          col.box(fn(r) { r.row(Is(true)).box(fn(held) { held.shrink(Is(0.0)) |> ignore; body(held) }) |> ignore }) |> ignore
        }
      })
      |> ignore
    })
    tree.frame(300.0, 844.0, now=0.0) |> ignore
    let (held, b) = at.val.unwrap()
    let out = (held.rect().3, b.rect().3)
    tree.dispose()
    out
  }
  assert_eq(probe(false), (70.0, 70.0), msg="in a row")
  assert_eq(probe(true), (70.0, 70.0), msg="in a row that scrolls across")
}
