///|
test "words in pieces: drawn with their pieces, read as their words one after another, measured by what measures pieces; plain words said after them, no pieces left" {
  let pieces = @signals.signal([words_run("ab "), words_run("cd", weight=600, ink=7L)], same=fn(a, b) { a == b })
  let plain = @signals.signal(false, same=fn(a, b) { a == b })
  let measured : Array[Int] = []
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(n) {
        id.val = Some(n.id())
        n.words_runs(By(fn() { pieces.get() })) |> ignore
        n.reacts(fn() { plain.get() }, fn(p) { if p { n.words(Is("plain")) |> ignore } })
      })
      |> ignore
    },
    measure_runs=fn(rs, look, w) {
      measured.push(rs.length())
      runs_measure(rs, look, w)
    },
  )
  t.frame(390.0, 844.0) |> ignore
  let d = t.drawn_of(id.val.unwrap()).unwrap()
  assert_eq(d.words, "ab cd")
  assert_eq(d.runs, [words_run("ab "), words_run("cd", weight=600, ink=7L)])
  assert_eq(d.w, 35.0, msg="measured as its words")
  assert_true(measured.contains(2), msg="by what measures pieces: \{measured}")
  pieces.set([words_run("abc", weight=700)])
  t.frame(390.0, 844.0) |> ignore
  let d = t.drawn_of(id.val.unwrap()).unwrap()
  assert_eq(d.words, "abc")
  assert_eq(d.w, 21.0, msg="measured again as they change")
  plain.set(true)
  t.frame(390.0, 844.0) |> ignore
  let d = t.drawn_of(id.val.unwrap()).unwrap()
  assert_eq(d.words, "plain")
  assert_eq(d.runs, [], msg="no pieces left")
}

///|
test "a cycle read by a look: where it is as what is drawn is drawn (whatever frames came), read apart from the clock (a wait, no motion); read by nothing once its node is let go" {
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        id.val = Some(v.id())
        v.width(Is(Some(10.0))).height(Is(Some(10.0))).alpha(By(fn() { v.cycle(1000.0) })) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0, now=250.0) |> ignore
  assert_true(t.cycle_read(), msg="read")
  assert_true(!t.clock_read(), msg="no motion")
  assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, 0.25)
  t.frame(390.0, 844.0, now=1750.0) |> ignore
  assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, 0.75, msg="the frames between none")
  there.set(false)
  t.frame(390.0, 844.0, now=1800.0) |> ignore
  assert_true(!t.cycle_read(), msg="let go: read by nothing")
}

///|
test "the pointer within a node: told as it was placed, the pointer there before it was made; as what holds it moves or is drawn bigger under a pointer that stays, at the frame that places it, no move of the pointer's" {
  let there = @signals.signal(false, same=fn(a, b) { a == b })
  let down = @signals.signal(0.0, same=fn(a, b) { a == b })
  let big = @signals.signal(1.0, same=fn(a, b) { a == b })
  let within = Ref(false)
  let t = Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(holder) {
        holder.width(Is(Some(200.0))).height(Is(Some(100.0))).offset(By(fn() { (0.0, down.get()) })).scale(
          By(fn() { big.get() }),
          about=At(0.0, 0.0),
        )
        |> ignore
        holder.show(fn() { there.get() }, fn(band) {
          band.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
          band.reacts(fn() { band.pointer_within() }, fn(w) { within.val = w })
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  // (the pointer at (10, 10) before the band is made)
  t.point_at(10.0, 10.0)
  there.set(true)
  t.frame(400.0, 300.0) |> ignore
  assert_true(within.val, msg="made under the pointer: within, as it was placed")
  // (what holds it moved down 50, the pointer still)
  down.set(50.0)
  t.frame(400.0, 300.0) |> ignore
  assert_true(!within.val, msg="moved from under it: not within")
  // (drawn bigger about its top left, its band reaching down to the pointer at (10, 85))
  t.point_at(10.0, 85.0)
  assert_true(!within.val, msg="the pointer below the band")
  big.set(4.0)
  t.frame(400.0, 300.0) |> ignore
  assert_true(within.val, msg="drawn bigger under it: within")
}

///|
test "the pointer within a node, read by how it is drawn (its alpha) and by what it holds (one shown while within): in the frame that places it, made under a pointer that stays or moved from under it, drawn so at that frame's end, nothing owed after" {
  let there = @signals.signal(false, same=fn(a, b) { a == b })
  let down = @signals.signal(0.0, same=fn(a, b) { a == b })
  let id : Ref[NodeId?] = Ref(None)
  let mark : Ref[NodeId?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(holder) {
        holder.width(Is(Some(200.0))).height(Is(Some(100.0))).offset(By(fn() { (0.0, down.get()) })) |> ignore
        holder.show(fn() { there.get() }, fn(band) {
          id.val = Some(band.id())
          band
          .width(Is(Some(200.0)))
          .height(Is(Some(20.0)))
          .ground(Is(1L))
          .alpha(By(fn() { if band.pointer_within() { 1.0 } else { 0.5 } }))
          |> ignore
          band.show(fn() { band.pointer_within() }, fn(m) {
            mark.val = Some(m.id())
            m.width(Is(Some(10.0))).height(Is(Some(10.0))).ground(Is(2L)) |> ignore
          })
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  t.point_at(10.0, 10.0)
  there.set(true)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, 1.0, msg="made under the pointer: drawn as within, that frame")
  assert_true(mark.val is Some(m) && t.drawn_of(m) is Some(_), msg="and what it shows while within, that frame")
  assert_true(!t.due, msg="nothing owed")
  down.set(50.0)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, 0.5, msg="moved from under it: drawn as not, that frame")
  assert_true(t.drawn_of(mark.val.unwrap()) is None, msg="what it shows while within gone, that frame")
  assert_true(!t.due, msg="nothing owed")
}

///|
test "the pointer within a node, a chain of six: each placed under the pointer as the one before it is told it is under it, through its own properties; all of them under it and told so in the first frame, nothing owed after" {
  let ids : Array[NodeId] = []
  let views : Array[View] = []
  let t = Tree::new(
    fn(root) {
      for k in 0..<6 {
        root.box(fn(n) {
          ids.push(n.id())
          let before = if k > 0 { Some(views[k - 1]) } else { None }
          views.push(n)
          n
          .over(Is(true))
          .width(Is(Some(100.0)))
          .height(Is(Some(20.0)))
          .ground(Is(1L))
          // (the first under the pointer; each after it there once the one before it is told it is, else far below)
          .offset(By(fn() {
            match before {
              None => (0.0, 80.0)
              Some(b) => if b.pointer_within() { (0.0, 80.0) } else { (0.0, 250.0) }
            }
          }))
          |> ignore
        })
        |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  t.point_at(10.0, 90.0)
  t.frame(400.0, 300.0) |> ignore
  for k in 0..<6 {
    assert_eq(t.drawn_of(ids[k]).unwrap().y, 80.0, msg="\{k}: under the pointer, the first frame")
    assert_true(@signals.untracked(fn() { views[k].pointer_within() }), msg="\{k}: told so")
  }
  assert_true(!t.due, msg="nothing owed")
}

///|
test "the pointer within nodes, three counting up: each placed under the pointer as the next count its bits say (000 to 111, a cell told otherwise more than once on the way), as their own properties read it; all under it and told so in the first frame, nothing owed after" {
  let views : Array[View] = []
  let ids : Array[NodeId] = []
  let t = Tree::new(
    fn(root) {
      for k in 0..<3 {
        root.box(fn(n) {
          ids.push(n.id())
          views.push(n)
          n
          .over(Is(true))
          .width(Is(Some(100.0)))
          .height(Is(Some(20.0)))
          .ground(Is(1L))
          // (the count the three say now, one more (at most 7): this one under the pointer where its bit is set)
          .offset(By(fn() {
            let mut v = 0
            for j in 0..<views.length() {
              if views[j].pointer_within() {
                v = v + (1 << j)
              }
            }
            let next = if v + 1 > 7 { 7 } else { v + 1 }
            if ((next >> k) & 1) == 1 {
              (0.0, 80.0)
            } else {
              (0.0, 250.0)
            }
          }))
          |> ignore
        })
        |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  t.point_at(10.0, 90.0)
  t.frame(400.0, 300.0) |> ignore
  for k in 0..<3 {
    assert_eq(t.drawn_of(ids[k]).unwrap().y, 80.0, msg="\{k}: under the pointer, the first frame (111)")
    assert_true(@signals.untracked(fn() { views[k].pointer_within() }), msg="\{k}: told so")
  }
  assert_true(!t.due, msg="nothing owed")
}

///|
test "the pointer within a node, at the moment of what changed where it is (an event moving what holds it, or showing it), no frame drawn after it; the same as with one" {
  for frame in [false, true] {
    let there = @signals.signal(true, same=fn(a, b) { a == b })
    let down = @signals.signal(0.0, same=fn(a, b) { a == b })
    let seen : Array[(Bool, Double)] = []
    let t = Tree::new(
      fn(root) {
        root.lines_up(Is(Some(Start))) |> ignore
        root.box(fn(holder) {
          holder.width(Is(Some(200.0))).height(Is(Some(100.0))).offset(By(fn() { (0.0, down.get()) })) |> ignore
          holder.show(fn() { there.get() }, fn(band) {
            band.width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
            band.reacts(fn() { band.pointer_within() }, fn(w) { seen.push((w, band.cause_at())) })
          })
        })
        |> ignore
      },
      time=fn() { 0.0 },
    )
    t.frame(400.0, 300.0, now=0.0) |> ignore
    t.point_at(10.0, 10.0)
    t.frame(400.0, 300.0, now=10.0) |> ignore
    assert_eq(seen.last().map(fn(s) { s.0 }), Some(true), msg="frame \{frame}: within at first")
    // (moved from under it by an event at 100)
    t.event(100.0, fn() { down.set(50.0) })
    if frame {
      t.frame(400.0, 300.0, now=116.0) |> ignore
    }
    assert_eq(seen.last(), Some((false, 100.0)), msg="frame \{frame}: moved from under it, told at the event's moment")
    // (gone, and back under it by an event at 200: made anew under the pointer)
    t.event(200.0, fn() {
      there.set(false)
      down.set(0.0)
    })
    t.event(210.0, fn() { there.set(true) })
    if frame {
      t.frame(400.0, 300.0, now=226.0) |> ignore
    }
    assert_eq(seen.last(), Some((true, 210.0)), msg="frame \{frame}: shown under it, told at the event's moment")
  }
}
