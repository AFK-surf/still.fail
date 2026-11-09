///|
/// What takes a finger at each point of a grid over the window, found going through all that is drawn: what
/// Tree::target_at finds there, passing over what holds nothing that takes a point.
fn targets_whole(t : Tree) -> Array[Target] {
  let out = []
  for y = 5.0; y < 400.0; y = y + 10.0 {
    for x = 5.0; x < 390.0; x = x + 30.0 {
      let at = t.logic_at()
      let found : Array[Target] = []
      t.each_drawn_scaled(fn(c, cx, cy, _, s) {
        if t.finger_on(c, cx, cy, s, x, y, at, tracked=false) {
          let n = t.nodes[c.id.at]
          if n.on_drag is Some(_) && n.claims is None {
            found.push(Dragged(c.id))
          } else if n.on_press is Some(_) {
            found.push(Pressed(c.id))
          } else if n.hosted {
            found.push(Hosted(c.id))
          } else if n.top_row {
            found.push(TopRow(c.id))
          }
        }
      })
      out.push(t.chosen(found, x, y))
    }
  }
  out
}

///|
/// Each living node whose count of what takes a point in it is not what it holds counts, said.
fn inputs_miscounted(t : Tree) -> Array[String] {
  let out = []
  fn count(at : Int) -> Int {
    let n = t.nodes[at]
    let mut c = if n.inputs_own { 1 } else { 0 }
    for k in n.kids {
      c = c + count(k)
    }
    c
  }
  for i, n in t.nodes {
    if n.live && (n.parent >= 0 || i == 0) && n.inputs_in != count(i) {
      out.push("node \{i}: \{n.inputs_in} against \{count(i)}")
    }
  }
  out
}

///|
fn targets_found(t : Tree) -> Array[Target] {
  let out = []
  for y = 5.0; y < 400.0; y = y + 10.0 {
    for x = 5.0; x < 390.0; x = x + 30.0 {
      out.push(t.target_at(x, y))
    }
  }
  out
}

///|
test "what takes a finger found passing over what holds nothing that takes one is what all of it gone through finds: rows come, go and move, a sheet over them shown and gone" {
  let keys = @signals.signal([1, 2, 3, 4, 5], same=fn(a, b) { a == b })
  let sheet = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tree::new(
    fn(root) {
      root.box(fn(list) {
        list.each(at_once=true, fn() { keys.get() }, fn(k) { k }, fn(row, k) {
          let key = k.untracked()
          row.height(Is(Some(40.0))) |> ignore
          // (a row held where its key is even, a button pressed in it where it is a multiple of three, words alone
          // in the rest)
          if key % 2 == 0 {
            row.on_drag(fn(_) {  }) |> ignore
          }
          row.box(fn(b) {
            b.width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore
            if key % 3 == 0 {
              b.on_press(fn() {  }) |> ignore
            }
          })
          |> ignore
          row.box(fn(w) { w.width(Is(Some(60.0))).height(Is(Some(20.0))) |> ignore }) |> ignore
        })
      })
      |> ignore
      root.show(at_once=true, fn() { sheet.get() }, fn(s) {
        s
        .box(fn(p) {
          p.width(Is(Some(390.0))).height(Is(Some(200.0))) |> ignore
          p.box(fn(b) { b.width(Is(Some(80.0))).height(Is(Some(40.0))).on_press(fn() {  }) |> ignore }) |> ignore
        })
        .stacked(Is(1))
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  assert_eq(targets_found(t), targets_whole(t))
  let steps : Array[() -> Unit] = [
    fn() { keys.set([1, 2, 3, 4, 5, 6]) },
    fn() { keys.set([6, 3, 9, 2]) },
    fn() { sheet.set(true) },
    fn() { keys.set([12, 1, 3]) },
    fn() { sheet.set(false) },
    fn() { keys.set([]) },
    fn() { keys.set([4, 8, 9, 10, 15]) },
  ]
  for i, step in steps {
    step()
    t.frame(390.0, 844.0) |> ignore
    assert_eq(targets_found(t), targets_whole(t), msg="step \{i}")
    assert_eq(inputs_miscounted(t), [], msg="step \{i}")
  }
  // (what it counts as it lets each go: none left over the root once all of it is gone that took a point)
  keys.set([])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(t.nodes[0].inputs_in, 0)
}

///|
test "a node put by and taken in elsewhere takes what takes a point in it with it" {
  let t = Tree::new(
    fn(root) {
      root.box(fn(a) { a.box(fn(b) { b.width(Is(Some(50.0))).height(Is(Some(50.0))).on_press(fn() {  }) |> ignore }) |> ignore })
      |> ignore
      root.box(fn(_) {  }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let a = t.handle(t.nodes[0].kids[0])
  let other = t.handle(t.nodes[0].kids[1])
  let b = t.handle(t.nodes[a.at].kids[0])
  assert_eq((t.nodes[a.at].inputs_in, t.nodes[0].inputs_in), (1, 1))
  let wake = a.park(b)
  assert_eq((t.nodes[a.at].inputs_in, t.nodes[0].inputs_in), (0, 0))
  other.take_in(b)
  wake()
  t.frame(390.0, 844.0) |> ignore
  assert_eq((t.nodes[a.at].inputs_in, t.nodes[other.at].inputs_in, t.nodes[0].inputs_in), (0, 1, 1))
  assert_eq(inputs_miscounted(t), [])
  assert_eq(targets_found(t), targets_whole(t))
}
