///|
test "what is done before a node is let go letting it, and what holds it, go meanwhile: each let go once, its index free once and made another's" {
  let firsts = Ref(0)
  let lets = Ref(0)
  let outer_lets = Ref(0)
  let outer : Ref[View?] = Ref(None)
  let inner : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(o) {
      outer.val = Some(o)
      o.owns(fn() { outer_lets.val += 1 }) |> ignore
      o.box(fn(b) {
        inner.val = Some(b)
        b.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
        b.before_let_go(fn() {
          firsts.val += 1
          // (it, and what holds it, let go from within: each once)
          o.let_go()
          b.let_go()
        })
        |> ignore
        b.owns(fn() { lets.val += 1 }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.frame(300.0, 300.0) |> ignore
  let alive = t.alive()
  let (o, b) = (outer.val.unwrap(), inner.val.unwrap())
  t.root().drop(o)
  assert_eq((firsts.val, lets.val, outer_lets.val), (1, 1, 1))
  assert_false(o.alive())
  assert_false(b.alive())
  assert_eq(t.alive(), alive - 2)
  let seen : Map[Int, Unit] = {}
  for at in t.free {
    assert_false(seen.contains(at))
    seen[at] = ()
  }
  // (each index free once: two made after, in two places)
  let made = []
  for _ in 0..<2 {
    t.root().box(fn(n) { made.push(n.at) }) |> ignore
  }
  assert_eq(made.length(), 2)
  assert_true(made[0] != made[1])
  assert_eq(t.alive(), alive)
}

///|
test "what is done before a node is let go letting what holds it go, and a node made in its place meanwhile: each let go once, the new one held as made, the focus and the pointer on it let go once" {
  let firsts = Ref(0)
  let lets = Ref(0)
  let outer_lets = Ref(0)
  let lost = Ref(0)
  let outer : Ref[View?] = Ref(None)
  let inner : Ref[View?] = Ref(None)
  let made : Ref[View?] = Ref(None)
  let held_then : Ref[Int??] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(o) {
      outer.val = Some(o)
      o.owns(fn() { outer_lets.val += 1 }) |> ignore
      o.box(fn(b) {
        inner.val = Some(b)
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .on_press(fn() {  })
        .focusable(Is(true))
        |> ignore
        b.before_let_go(fn() {
          firsts.val += 1
          // (what holds it let go from within, and a node made meanwhile: in the place that one let go of)
          root.drop(o)
          made.val = Some(root.box(fn(n) { n.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore }))
          // (it, still going: held by none now, not by the one made in its holder's place)
          held_then.val = Some(b.parent().map(fn(p) { p.at }))
        })
        |> ignore
        b.owns(fn() { lets.val += 1 }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.on_focus_lost(fn(_) { lost.val += 1 })
  t.frame(300.0, 300.0) |> ignore
  let alive = t.alive()
  let (o, b) = (outer.val.unwrap(), inner.val.unwrap())
  assert_true(b.ask_focus())
  t.point_at(10.0, 10.0)
  assert_true(b.pointed())
  // (it let go first, by what holds it)
  o.drop(b)
  assert_eq((firsts.val, lets.val, outer_lets.val), (1, 1, 1))
  assert_false(o.alive())
  assert_false(b.alive())
  assert_eq(lost.val, 1)
  assert_false(b.focused())
  assert_true(t.pointed is None)
  // (the one made meanwhile: in the place let go of, another's by its generation, held by what made it, holding none)
  let m = made.val.unwrap()
  assert_true(m.alive())
  assert_eq(m.at, o.at)
  assert_eq(held_then.val, Some(None))
  assert_true(m.gen != o.gen)
  assert_eq(m.parent().map(fn(p) { p.at }), Some(t.root().at))
  assert_true(t.root().kids().map(fn(k) { k.at }).contains(m.at))
  assert_eq(m.kids().length(), 0)
  assert_eq(t.alive(), alive - 1)
  let seen : Map[Int, Unit] = {}
  for at in t.free {
    assert_false(seen.contains(at))
    seen[at] = ()
  }
  assert_false(seen.contains(m.at))
  // (the tree as sound: laid out and drawn again)
  t.frame(300.0, 300.0) |> ignore
  assert_eq(m.rect().2, 10.0)
}

///|
test "what is done before a node is let go as it stops showing hiding what holds it: each let go once, shown again as made" {
  let outer_on = @signals.signal(true, same=fn(a, b) { a == b })
  let inner_on = @signals.signal(true, same=fn(a, b) { a == b })
  let firsts = Ref(0)
  let lets = Ref(0)
  let outer_lets = Ref(0)
  let shown : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.show(fn() { outer_on.get() }, fn(o) {
      o.owns(fn() { outer_lets.val += 1 }) |> ignore
      o.show(fn() { inner_on.get() }, fn(b) {
        shown.val = Some(b)
        b.width(Is(Some(80.0))).height(Is(Some(40.0))) |> ignore
        b.before_let_go(fn() {
          firsts.val += 1
          // (what holds it hidden from within)
          outer_on.set(false)
        })
        |> ignore
        b.owns(fn() { lets.val += 1 }) |> ignore
      })
    })
  })
  t.frame(300.0, 300.0) |> ignore
  let alive = t.alive()
  inner_on.set(false)
  t.frame(300.0, 300.0) |> ignore
  assert_eq((firsts.val, lets.val, outer_lets.val), (1, 1, 1))
  assert_true(t.alive() < alive)
  let seen : Map[Int, Unit] = {}
  for at in t.free {
    assert_false(seen.contains(at))
    seen[at] = ()
  }
  // (shown again: made anew, each once)
  inner_on.set(true)
  outer_on.set(true)
  t.frame(300.0, 300.0) |> ignore
  assert_eq(t.alive(), alive)
  assert_true(shown.val.unwrap().alive())
  assert_eq(shown.val.unwrap().rect().2, 80.0)
}
