// What is done as a state comes to hold (View::reacts) is the node's: what it makes, at its making or as of a change
// told between frames, let go with the node; said from inside another effect, that effect running again stops nothing
// of it. A node shifted by its own size (View::shift) is drawn by the size the frame lays it out at.

///|
test "reacts: an effect made as of a change between frames is the node's, let go with it before any frame" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let go = @signals.signal(0, same=fn(a, b) { a == b })
  let x = @signals.signal(0, same=fn(a, b) { a == b })
  let runs = Ref(0)
  let cleaned = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.reacts(fn() { go.get() }, fn(n) {
        if n > 0 {
          @signals.effect_cleanup(fn() {
            x.get() |> ignore
            runs.val = runs.val + 1
            fn() { cleaned.val = cleaned.val + 1 }
          })
          |> ignore
        }
      })
    })
  })
  tree.frame(390.0, 844.0) |> ignore
  // (told between frames, at its moment: the effect made then)
  tree.event(100.0, fn() { go.set(1) })
  assert_eq(runs.val, 1)
  x.set(1)
  assert_eq(runs.val, 2)
  // (the node let go between frames: the effect stopped with it, its cleanup run, x followed no more)
  tree.event(200.0, fn() { on.set(false) })
  assert_eq(cleaned.val, 2)
  x.set(2)
  assert_eq(runs.val, 2)
}

///|
test "reacts: said from inside another effect, that effect running again stops nothing of it" {
  let y = @signals.signal(0, same=fn(a, b) { a == b })
  let s = @signals.signal(0, same=fn(a, b) { a == b })
  let seen : Array[Int] = []
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) { node.val = Some(root.box(fn(_) {  })) })
  tree.frame(390.0, 844.0) |> ignore
  let said = Ref(false)
  let outer = @signals.effect(fn() {
    y.get() |> ignore
    if !said.val {
      said.val = true
      node.val.unwrap().reacts(fn() { s.get() }, fn(v) { seen.push(v) })
    }
  })
  y.set(1)
  y.set(2)
  s.set(5)
  assert_eq(seen, [0, 5])
  outer()
  s.set(6)
  assert_eq(seen, [0, 5, 6])
}

///|
test "shift: a node off by half its width is drawn by the width the frame lays it out at, its binding not run again" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) { v.grow(Is(1.0)).shift(Is((0.5, 0.0))) |> ignore }) |> ignore
  })
  tree.frame(400.0, 800.0) |> ignore
  let first = tree.drawn().map(fn(d) { (d.x, d.w) })
  let bound = tree.work().bound
  tree.frame(300.0, 800.0) |> ignore
  // (the window, then the node)
  assert_eq(first, [(0.0, 400.0), (200.0, 400.0)])
  assert_eq(tree.drawn().map(fn(d) { (d.x, d.w) }), [(0.0, 300.0), (150.0, 300.0)])
  assert_eq(tree.work().bound, bound)
}

///|
/// A node as wide as the moment it is drawn at (By drawn_at), in a window `tree` makes; its handle.
fn timed_width() -> (@view.Tree, Ref[@view.View?]) {
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    node.val = Some(root.box(fn(v) { v.width(By(fn() { Some(v.drawn_at()) })) |> ignore }))
  })
  (tree, node)
}

///|
test "laid_size: asked in an event at 95, as of 95, whether the frame before was drawn ahead at 100 or not" {
  let asked = fn(ahead : Bool) {
    let (tree, node) = timed_width()
    tree.at(if ahead { 100.0 } else { 90.0 })
    tree.frame(400.0, 800.0, now=90.0) |> ignore
    let size = Ref((0.0, 0.0))
    tree.event(95.0, fn() { size.val = node.val.unwrap().laid_size() })
    // (the next frame, to be shown at 110: drawn as of then)
    tree.at(110.0)
    tree.frame(400.0, 800.0, now=110.0) |> ignore
    (size.val.0, node.val.unwrap().rect().2)
  }
  assert_eq(asked(false), (95.0, 110.0))
  assert_eq(asked(true), (95.0, 110.0))
}

///|
test "laid_size: asked by what is due at 95 as a frame to be shown at 100 is brought: as of 95, the frame drawn at 100" {
  let (tree, node) = timed_width()
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let size = Ref((0.0, 0.0))
  node.val.unwrap().at_moment(95.0, fn() { size.val = node.val.unwrap().laid_size() }) |> ignore
  tree.at(100.0)
  tree.frame(400.0, 800.0, now=100.0) |> ignore
  assert_eq((size.val.0, node.val.unwrap().rect().2), (95.0, 100.0))
}

///|
test "laid_size: asked mid-change, what shows as the change ends is kept: nothing let go and made again for it" {
  let asked = fn(ask : Bool) {
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let made = Ref(0)
    let cleaned = Ref(0)
    let node : Ref[@view.View?] = Ref(None)
    let tree = @view.Tree::new(fn(root) {
      node.val = Some(root.box(fn(v) { v.width(Is(Some(50.0))) |> ignore }))
      root.show(fn() { on.get() }, fn(_) {
        made.val = made.val + 1
        @signals.effect_cleanup(fn() { fn() { cleaned.val = cleaned.val + 1 } }) |> ignore
      })
    })
    tree.frame(400.0, 800.0, now=0.0) |> ignore
    tree.event(10.0, fn() {
      on.set(false)
      if ask {
        node.val.unwrap().laid_size() |> ignore
      }
      on.set(true)
    })
    (made.val, cleaned.val)
  }
  assert_eq(asked(false), (1, 0))
  assert_eq(asked(true), (1, 0))
}

///|
test "laid_size: asked mid-change, what an effect follows is not seen as it was partway" {
  let seen = fn(ask : Bool) {
    let a = @signals.signal(0, same=fn(x, y) { x == y })
    let got : Array[Int] = []
    let node : Ref[@view.View?] = Ref(None)
    let tree = @view.Tree::new(fn(root) {
      node.val = Some(root.box(fn(v) { v.width(By(fn() { Some(a.get().to_double() * 10.0 + 10.0) })) |> ignore }))
    })
    @signals.effect(fn() { got.push(a.get()) }) |> ignore
    tree.frame(400.0, 800.0, now=0.0) |> ignore
    let size = Ref(0.0)
    tree.event(10.0, fn() {
      a.set(1)
      if ask {
        size.val = node.val.unwrap().laid_size().0
      }
      a.set(2)
    })
    (got, size.val)
  }
  assert_eq(seen(false), ([0, 2], 0.0))
  // (the size as of then, a at 1; the effect sees 2 alone, as the change ends)
  assert_eq(seen(true), ([0, 2], 20.0))
}

///|
test "bindings held: let go as their node goes, at once, none asked of the tree's size between; none once it is disposed" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let x = @signals.signal(1.0, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.width(By(fn() { Some(x.get()) })).height(By(fn() { Some(x.get()) })) |> ignore
    })
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let held = tree.bindings_held()
  let counts : Array[Int] = []
  for i in 0..<5 {
    tree.event(10.0 + i.to_double(), fn() { on.set(true) })
    counts.push(tree.bindings_held() - held)
    tree.event(10.5 + i.to_double(), fn() { on.set(false) })
    counts.push(tree.bindings_held() - held)
  }
  assert_eq(counts, [2, 0, 2, 0, 2, 0, 2, 0, 2, 0])
  on.set(true)
  tree.dispose()
  assert_eq(tree.bindings_held(), 0)
}

///|
test "a binding told, then pulled as the tree is brought to an input, then the frame: worked out once" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let reads = Ref(0)
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    node.val = Some(
      root.box(fn(v) {
        v.width(By(fn() {
          reads.val = reads.val + 1
          Some(s.get() * 10.0)
        }))
        |> ignore
      }),
    )
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let r0 = reads.val
  // (told between frames, as a change ended: queued; an input brought to its moment pulls it; the frame after has it)
  s.set(2.0)
  tree.bring_to(10.0)
  tree.frame(400.0, 800.0, now=20.0) |> ignore
  assert_eq((reads.val - r0, node.val.unwrap().rect().2), (1, 20.0))
  // (set in a change, asked at once in it: worked out then, not again as the change ends or the frame comes)
  let r1 = reads.val
  tree.event(30.0, fn() {
    s.set(3.0)
    node.val.unwrap().laid_size() |> ignore
  })
  tree.frame(400.0, 800.0, now=40.0) |> ignore
  assert_eq((reads.val - r1, node.val.unwrap().rect().2), (1, 30.0))
}

///|
test "pulled at once: only the bindings marked looked at, however many the tree holds" {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let still = @signals.signal(5.0, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    for _ in 0..<100 {
      root.box(fn(v) { v.height(By(fn() { Some(still.get()) })) |> ignore }) |> ignore
    }
    node.val = Some(root.box(fn(v) { v.width(By(fn() { Some(s.get()) })) |> ignore }))
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let p0 = tree.work().pulled
  tree.event(10.0, fn() {
    s.set(2.0)
    node.val.unwrap().laid_size() |> ignore
  })
  assert_eq(tree.work().pulled - p0, 1)
}

///|
test "laid_size twice in a change: a binding found the same the first time is marked again by what changes after" {
  let s = @signals.signal(0, same=fn(a, b) { a == b })
  let memo = @signals.computed(fn(_) { s.get() % 2 }, same=fn(a, b) { a == b })
  let seen : Array[Int] = []
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    node.val = Some(root.box(fn(v) { v.width(By(fn() { Some(10.0 + 10.0 * memo.get().to_double()) })) |> ignore }))
  })
  @signals.effect(fn() { seen.push(s.get()) }) |> ignore
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let sizes : Array[Double] = []
  tree.event(10.0, fn() {
    s.set(2)
    sizes.push(node.val.unwrap().laid_size().0)
    s.set(3)
    sizes.push(node.val.unwrap().laid_size().0)
  })
  assert_eq(sizes, [10.0, 20.0])
  // (what follows s, an effect, sees it as the change ends: once)
  assert_eq(seen, [0, 3])
}

///|
/// A node whose padding the test binds (`bind`), holding one box: where that box is laid out in it (left, top).
fn padded(bind : (@view.View) -> Unit) -> (@view.Tree, () -> (Double, Double)) {
  let kid : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      bind(v)
      kid.val = Some(v.box(fn(k) { k.height(Is(Some(10.0))) |> ignore }))
    })
    |> ignore
  })
  let at = fn() {
    let (x, y, _, _) = kid.val.unwrap().rect()
    (x, y)
  }
  (tree, at)
}

///|
test "padding: pad bound By, then sides said: the sides' alone, what pad read changing sets nothing" {
  let p = @signals.signal(4.0, same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let (tree, at) = padded(fn(v) {
    node.val = Some(v)
    v.pad(By(fn() { p.get() })) |> ignore
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  assert_eq(at(), (4.0, 4.0))
  // (pad's read changed and queued, then sides said before the frame: pad's binding runs no more)
  p.set(7.0)
  node.val.unwrap().sides(Is((10.0, 20.0))) |> ignore
  tree.frame(400.0, 800.0, now=10.0) |> ignore
  assert_eq(at(), (10.0, 0.0))
  p.set(5.0)
  tree.frame(400.0, 800.0, now=20.0) |> ignore
  assert_eq(at(), (10.0, 0.0))
}

///|
test "padding: sides bound By, then pad said: pad's alone, what sides read changing sets nothing" {
  let q = @signals.signal((8.0, 9.0), same=fn(a, b) { a == b })
  let node : Ref[@view.View?] = Ref(None)
  let (tree, at) = padded(fn(v) {
    node.val = Some(v)
    v.sides(By(fn() { q.get() })) |> ignore
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  assert_eq(at(), (8.0, 0.0))
  node.val.unwrap().pad(Is(3.0)) |> ignore
  q.set((30.0, 40.0))
  tree.frame(400.0, 800.0, now=10.0) |> ignore
  assert_eq(at(), (3.0, 3.0))
}
