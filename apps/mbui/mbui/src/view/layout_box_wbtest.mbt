///|
test "a custom parent measures the composer before laying out its list in one pass" {
  let composing = @signals.signal(40.0, same=fn(a, b) { a == b })
  let layouts = Ref(0)
  let footer : Ref[View?] = Ref(None)
  let row : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    let composer = root.box(fn(n) {
      footer.val = Some(n)
      n.height(By(fn() { Some(composing.get()) })).ground(Is(0x112233ffL)) |> ignore
    })
    let list = root.box(fn(n) {
      n.layout_box(Is(0), fn(l, _) {
        layouts.val += 1
        let last = l.child("last", fn(n) { row.val = Some(n); n.height(Is(Some(20.0))).ground(Is(0x223344ffL)) |> ignore })
        let size = l.measure(last, l.width)
        l.place(last, 0.0, l.height - size.1)
      }) |> ignore
    })
    root.layout_box(Is(0), fn(l, _) {
      let size = l.measure(composer, l.width)
      l.measure(list, l.width, height=l.height - size.1) |> ignore
      l.place(list, 0.0, 0.0)
      l.place(composer, 0.0, l.height - size.1)
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  assert_eq((t.work.computes, layouts.val), (1, 1))
  assert_eq(t.nodes[row.val.unwrap().at].flex.top, 240.0)
  assert_eq(t.nodes[footer.val.unwrap().at].flex.top, 260.0)
  composing.set(80.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq((t.work.computes, layouts.val), (2, 2))
  assert_eq(t.nodes[row.val.unwrap().at].flex.top, 200.0)
  assert_eq(t.nodes[footer.val.unwrap().at].flex.top, 220.0)
  t.dispose()
}

///|
test "a custom parent can fit a child to its intrinsic width" {
  let size = Ref((0.0, 0.0))
  let t = Tree::new(fn(root) {
    let child = root.box(fn(n) {
      n.measured(Is(0), fn(_, most) { (dmin(360.0, most.unwrap_or(360.0)), 50.0) }) |> ignore
    })
    root.layout_box(Is(0), fn(l, _) {
      size.val = l.fit(child, 1000.0)
      l.place(child, 0.0, 0.0)
    }) |> ignore
  })
  t.frame(1000.0, 500.0) |> ignore
  assert_eq(size.val, (360.0, 50.0))
  assert_eq(t.work.computes, 1)
  t.dispose()
}

///|
test "a lazy child keeps its identity and measurements while scrolling, and only leaves when omitted" {
  let offset = @signals.signal(0.0, same=fn(a, b) { a == b })
  let height = @signals.signal(20.0, same=fn(a, b) { a == b })
  let counts = [0, 0]
  let built = Ref(0)
  let dropped = Ref(0)
  let first : Ref[View?] = Ref(None)
  let hidden : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.layout_box(By(fn() { offset.get() }), fn(l, off) {
      if off < 50.0 {
        let a = l.child("a", fn(n) {
          first.val = Some(n)
          built.val += 1
          n.measured(By(fn() { height.get() }), fn(h, w) { counts[0] += 1; (w.unwrap_or(20.0), h) })
          .ground(Is(0x112233ffL)) |> ignore
          n.owns(fn() { dropped.val += 1 }) |> ignore
        })
        l.measure(a, l.width) |> ignore
        l.place(a, 0.0, off)
      }
      let b = l.child("b", fn(n) {
        hidden.val = Some(n)
        n.measured(Is(0), fn(_, w) { counts[1] += 1; (w.unwrap_or(20.0), 20.0) })
        .ground(Is(0x223344ffL)) |> ignore
      })
      l.measure(b, l.width) |> ignore
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let id = first.val.unwrap().id()
  let measured = counts.copy()
  assert_true(hidden.val.unwrap().alive())
  assert_true(t.out_at(hidden.val.unwrap().at), msg="kept without placing is neither drawn nor hit")
  offset.set(10.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(first.val.unwrap().id(), id)
  assert_eq(counts, measured, msg="scrolling reused both clean subtrees")
  height.set(30.0)
  t.frame(200.0, 300.0, now=20.0) |> ignore
  assert_true(counts[0] > measured[0])
  assert_eq(counts[1], measured[1], msg="one child's content did not remeasure the other")
  offset.set(60.0)
  t.frame(200.0, 300.0, now=30.0) |> ignore
  assert_false(first.val.unwrap().alive())
  assert_eq((built.val, dropped.val), (1, 1))
  offset.set(0.0)
  t.frame(200.0, 300.0, now=40.0) |> ignore
  assert_true(first.val.unwrap().id() != id, msg="an omitted key does not resurrect its released node")
  assert_eq(built.val, 2)
  t.dispose()
}

///|
///|
test "reordering lazy children changes their paint order without rebuilding either" {
  let reverse = @signals.signal(false, same=fn(a, b) { a == b })
  let built = Ref(0)
  let t = Tree::new(fn(root) {
    root.layout_box(By(fn() { reverse.get() }), fn(l, rev) {
      let keys = if rev { ["b", "a"] } else { ["a", "b"] }
      for k in keys {
        let child = l.child(k, fn(n) {
          built.val += 1
          n.height(Is(Some(20.0))).ground(Is(if k == "a" { 0x112233ffL } else { 0x223344ffL })) |> ignore
        })
        l.measure(child, l.width) |> ignore
        l.place(child, 0.0, 0.0)
      }
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let before = t.root().kids().map(fn(n) { n.id() })
  reverse.set(true)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(t.root().kids().map(fn(n) { n.id() }), [before[1], before[0]])
  assert_eq(built.val, 2)
  t.dispose()
}

///|
///|
test "a custom parent measures a child's ordinary font inputs without treating them as its own" {
  let theme = @signals.signal(20.0)
  let sizes : Array[(Double, Double)] = []
  let t = Tree::new(fn(root) {
    let child = root.box(fn(n) {
      n.measured(Is(0), fn(_, w) { (w.unwrap_or(10.0), theme.get()) }) |> ignore
    })
    root.layout_box(Is(0), fn(l, _) {
      sizes.push(l.measure(child, l.width))
      l.place(child, 0.0, 0.0)
    }) |> ignore
  })
  t.frame(200.0, 300.0) |> ignore
  assert_eq(sizes, [(200.0, 20.0)])
  t.dispose()
}

///|
/// A column 300 tall: a bar 40 tall, then a layout box sized by its share of what is left (no height of its own), its
/// one row `row` tall at its top; how many times the column's layout was computed and where the bar is.
fn sized_by_parent(row : @signals.Signal[Double]) -> (Tree, Ref[View?], Ref[View?]) {
  let bar : Ref[View?] = Ref(None)
  let boxed : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(b) { bar.val = Some(b); b.height(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(n) {
      boxed.val = Some(n)
      n.grow(Is(1.0)).layout_box(Is(0), fn(l, _) {
        let r = l.child("row", fn(c) { c.height(By(fn() { Some(row.get()) })) |> ignore })
        l.measure(r, l.width) |> ignore
        l.place(r, 0.0, 0.0)
      }) |> ignore
    })
    |> ignore
  })
  (t, bar, boxed)
}

///|
test "a layout box is as big as what holds it makes it, never as what it holds: a row of it grown, it and those beside it stay" {
  let row = @signals.signal(20.0, same=fn(a, b) { a == b })
  let (t, bar, boxed) = sized_by_parent(row)
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let box_h = t.nodes[boxed.val.unwrap().at].flex.height
  assert_eq(box_h, 260.0)
  row.set(500.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  // (its height its share of the column's, as before: what it holds laid out inside it, the column's other rows not
  // moved for it; so marking it stops there, its own layout_owner)
  assert_eq(t.nodes[boxed.val.unwrap().at].flex.height, 260.0)
  assert_eq(t.nodes[bar.val.unwrap().at].flex.top, 0.0)
  t.dispose()
}

///|
test "a layout box given no height of its own nor a share is as tall as nothing, whatever it holds: its rows never make it taller" {
  let row = @signals.signal(20.0, same=fn(a, b) { a == b })
  let boxed : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(n) {
      boxed.val = Some(n)
      n.layout_box(Is(0), fn(l, _) {
        let r = l.child("row", fn(c) { c.height(By(fn() { Some(row.get()) })) |> ignore })
        l.measure(r, l.width) |> ignore
        l.place(r, 0.0, 0.0)
      }) |> ignore
    })
    |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  assert_eq(t.nodes[boxed.val.unwrap().at].flex.height, 0.0)
  row.set(500.0)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  assert_eq(t.nodes[boxed.val.unwrap().at].flex.height, 0.0)
  t.dispose()
}

///|
test "a foot given marks the boxes that read it in their last layout alone: one let go and its place made again elsewhere not marked, none kept past its reading" {
  let foot = @signals.signal(10.0, same=fn(a, b) { a == b })
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let b_on = @signals.signal(true, same=fn(a, b) { a == b })
  let other_on = @signals.signal(false, same=fn(a, b) { a == b })
  let runs : Map[String, Int] = {}
  let ran = fn(k : String) { runs[k] = runs.get(k).unwrap_or(0) + 1 }
  let holder : Ref[View?] = Ref(None)
  let reader = fn(v : View, k : String) {
    v.layout_box(Is(0), fn(l, _) {
      ran(k)
      l.size_to(l.given_foot().map(fn(g) { g.1 }).unwrap_or(0.0))
    }, sized=true)
    |> ignore
  }
  let t = Tree::new(fn(root) {
    let h = root.box(fn(h) {
      holder.val = Some(h)
      h.show(fn() { a_on.get() }, fn(a) { reader(a, "a") })
      h.show(fn() { b_on.get() }, fn(b) { reader(b, "b") })
    })
    // (elsewhere, not under the foot: made as a reader under it is let go, in its place)
    let o = root.box(fn(o) { o.show(fn() { other_on.get() }, fn(x) { reader(x, "other") }) })
    root.layout_box(By(fn() { foot.get() }), fn(l, f) {
      l.measure(h, l.width, height=l.height / 2.0, foot=(0.0, f)) |> ignore
      l.measure(o, l.width, height=l.height / 2.0) |> ignore
      l.place(h, 0.0, 0.0)
      l.place(o, 0.0, l.height / 2.0)
    }) |> ignore
  })
  t.frame(200.0, 300.0, now=0.0) |> ignore
  let h = holder.val.unwrap()
  assert_true(runs.get("a") is Some(_) && runs.get("b") is Some(_))
  assert_eq(t.foot_readers.get(h.at).map(fn(rs) { rs.length() }), Some(2))
  // b let go, and the other box made in what was its place
  b_on.set(false)
  other_on.set(true)
  t.frame(200.0, 300.0, now=10.0) |> ignore
  let other_runs = runs.get("other").unwrap_or(0)
  let a_runs = runs.get("a").unwrap_or(0)
  assert_eq(t.foot_readers.get(h.at).map(fn(rs) { rs.length() }), Some(1))
  // the foot changes: a laid out again for it, the other (no reader of it) not
  foot.set(30.0)
  t.frame(200.0, 300.0, now=20.0) |> ignore
  assert_true(runs.get("a").unwrap_or(0) > a_runs)
  assert_eq(runs.get("other").unwrap_or(0), other_runs)
  // made again and let go again: those reading it now kept, none past
  b_on.set(true)
  t.frame(200.0, 300.0, now=30.0) |> ignore
  assert_eq(t.foot_readers.get(h.at).map(fn(rs) { rs.length() }), Some(2))
  b_on.set(false)
  t.frame(200.0, 300.0, now=40.0) |> ignore
  assert_eq(t.foot_readers.get(h.at).map(fn(rs) { rs.length() }), Some(1))
  assert_eq(t.foot_read.length(), 1, msg="feet read kept")
  t.dispose()
}
