// What a node owns and what is queued for it end with it (the review of 9eff822ff): a binding stopped runs no more,
// queued or not; what a node is made with is its own, read in untracked or not; a handle on a node let go makes, reads
// and follows nothing.

///|
test "a binding queued, then the property bound again: the one before runs no more, reads nothing again" {
  let a = @signals.signal(1L, same=fn(x, y) { x == y })
  let b = @signals.signal(2L, same=fn(x, y) { x == y })
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) {
    node.val = Some(root.box(fn(v) { v.ground(By(fn() { a.get() })) |> ignore }))
  })
  t.frame(390.0, 844.0) |> ignore
  let v = node.val.unwrap()
  // (queued by its read, then bound again before the frame: once given, once worked out)
  a.set(5L)
  v.ground(Is(7L)) |> ignore
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.drawn_of(v.id()).unwrap().ground, 7L)
  assert_false(a.watched())
  a.set(6L)
  v.ground(By(fn() { b.get() })) |> ignore
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.drawn_of(v.id()).unwrap().ground, 2L)
  assert_false(a.watched())
}


///|
test "a shown part let go with its own binding queued: that binding runs no more" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let words = @signals.signal("甲", same=fn(a, b) { a == b })
  let runs = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.words(By(fn() {
        runs.val = runs.val + 1
        words.get()
      }))
      |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  let was = runs.val
  // (the show's binding queued first, the words' after it: the show lets the part go, the words' binding with it,
  // queued as it is)
  on.set(false)
  words.set("乙")
  t.frame(390.0, 844.0) |> ignore
  assert_eq(runs.val, was)
  assert_false(words.watched())
}


///|
test "disposed with bindings queued: nothing of them runs, nothing read is followed" {
  let a = @signals.signal(1L, same=fn(x, y) { x == y })
  let runs = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      v.ground(By(fn() {
        runs.val = runs.val + 1
        a.get()
      }))
      |> ignore
    })
    |> ignore
  })
  t.frame(390.0, 844.0) |> ignore
  a.set(2L)
  t.dispose()
  t.frame(390.0, 844.0) |> ignore
  assert_eq(runs.val, 1)
  assert_false(a.watched())
}


///|
test "made in untracked inside a node's making: still the node's, let go with it" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let outside = @signals.signal(0)
  let runs = Ref(0)
  let cleanups = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(_) {
      @signals.untracked(fn() {
        @signals.effect_cleanup(fn() {
          outside.get() |> ignore
          runs.val = runs.val + 1
          fn() { cleanups.val = cleanups.val + 1 }
        })
        |> ignore
      })
    })
  })
  t.frame(390.0, 844.0) |> ignore
  on.set(false)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(cleanups.val, 1)
  assert_false(outside.watched())
  outside.set(1)
  assert_eq(runs.val, 1)
  t.dispose()
}


///|
test "a handle on a node let go: what comes and goes made on it reads nothing, follows nothing, makes nothing" {
  let items = @signals.signal([{ key: "a", words: "甲" }, { key: "b", words: "乙" }])
  let t = list_tree(items, Ref(0))
  t.frame(390.0, 844.0) |> ignore
  let old = t.root().kids()[0].kids()[1]
  items.set([{ key: "a", words: "甲" }])
  t.frame(390.0, 844.0) |> ignore
  items.set([{ key: "a", words: "甲" }, { key: "c", words: "丙" }])
  t.frame(390.0, 844.0) |> ignore
  let alive = t.alive()
  let reads = Ref(0)
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  old.show(fn() {
    reads.val = reads.val + 1
    shown.get()
  }, fn(_) {  })
  old.pick(fn() {
    reads.val = reads.val + 1
    shown.get()
  }, fn(_, _) {  })
  old.each(fn() {
    reads.val = reads.val + 1
    shown.get() |> ignore
    [1]
  }, fn(i) { i }, fn(_, _) {  })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(reads.val, 0)
  assert_false(shown.watched())
  assert_eq(t.alive(), alive)
}

///|
test "leaving followed: a reaction on it, of what leaves and of one it holds, told as it starts leaving and as it comes back, not as the frames come; reading no clock" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let own : Array[Bool] = []
  let held : Array[Bool] = []
  let t = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.reacts(fn() { v.leaving() }, fn(l) { own.push(l) })
      v.box(fn(k) { k.reacts(fn() { k.leaving() }, fn(l) { held.push(l) }) }) |> ignore
    }, leave=100.0)
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  on.set(false)
  t.frame(390.0, 844.0, now=10.0) |> ignore
  t.frame(390.0, 844.0, now=20.0) |> ignore
  let clock = t.clock_read()
  t.frame(390.0, 844.0, now=30.0) |> ignore
  on.set(true)
  t.frame(390.0, 844.0, now=40.0) |> ignore
  assert_eq((own, held, clock), ([false, true, false], [false, true, false], false))
}
