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
    measure_runs=fn(rs, look, set, w) {
      measured.push(rs.length())
      runs_measure(rs, look, set, w)
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
test "presentation hover changes opacity in the same frame without another layout" {
  let there = @signals.signal(false, same=fn(a, b) { a == b })
  let down = @signals.signal(0.0, same=fn(a, b) { a == b })
  let id : Ref[NodeId?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.show(fn() { there.get() }, fn(band) {
      id.val = Some(band.id())
      band.width(Is(Some(200.0))).height(Is(Some(20.0)))
      .offset(By(fn() { (0.0, down.get()) }))
      .ground(Is(1L))
      .alpha(By(fn() { if band.pointer_within() { 1.0 } else { 0.5 } })) |> ignore
    })
  }, time=fn() { 0.0 })
  defer { t.dispose() }
  t.frame(400.0, 300.0) |> ignore
  t.point_at(10.0, 10.0)
  for (shown, y, alpha) in [(true, 0.0, 1.0), (true, 50.0, 0.5), (true, 0.0, 1.0)] {
    @signals.start_batch()
    there.set(shown)
    down.set(y)
    @signals.end_batch()
    t.work.computes = 0
    t.frame(400.0, 300.0) |> ignore
    assert_eq(t.drawn_of(id.val.unwrap()).unwrap().alpha, alpha)
    assert_true(t.work.computes <= 1, msg="one root layout in each frame")
    assert_false(t.due, msg="paint is finished in this frame")
    assert_false(t.layout_due, msg="no layout deferred to the next frame")
  }
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

///|
test "how pieces are set (RunsLook): a node made again where one let go was, saying none of it, set as words are (runs_plain); code's ground's colour changed drawn again alone, its coming or going (code's room either side) measured again" {
  let shown = @signals.signal(0, same=fn(a, b) { a == b })
  let set = @signals.signal(runs_plain, same=fn(a, b) { a == b })
  let measured = Ref(0)
  let ids : Array[NodeId] = []
  let t = Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.pick(fn() { shown.get() }, fn(p, k) {
        // (1: none)
        guard k != 1 else { return }
        p.box(fn(n) {
          ids.push(n.id())
          n.words_runs(Is([words_run("a "), @text.code("b()")])) |> ignore
          // (the first said its own; the second, made where it was, none)
          if k == 0 {
            n.runs_look(By(fn() { set.get() })) |> ignore
          }
        })
        |> ignore
      })
    },
    measure_runs=fn(rs, look, s, w) {
      measured.val = measured.val + 1
      runs_measure(rs, look, s, w)
    },
  )
  t.frame(390.0, 844.0) |> ignore
  let look = fn() { t.drawn_of(ids.last().unwrap()).unwrap().runs_look }
  // (code with no ground, then one: measured again; then another colour: drawn again alone)
  set.set({ ..runs_plain, code_ground: 0L, code_scale: 1.2, link: 0xFF0000FFL })
  t.frame(390.0, 844.0) |> ignore
  let was = measured.val
  set.set({ ..runs_plain, code_ground: 0x11223344L, code_scale: 1.2, link: 0xFF0000FFL })
  t.frame(390.0, 844.0) |> ignore
  assert_true(measured.val > was, msg="a ground come: measured again")
  let was = measured.val
  set.set({ ..runs_plain, code_ground: 0x55667788L, code_scale: 1.2, link: 0xFF0000FFL })
  t.frame(390.0, 844.0) |> ignore
  assert_eq(measured.val, was, msg="another colour: not measured again")
  assert_eq(look().code_ground, 0x55667788L)
  set.set({ ..runs_plain, code_ground: 0L, code_scale: 1.2, link: 0xFF0000FFL })
  t.frame(390.0, 844.0) |> ignore
  assert_true(measured.val > was, msg="the ground gone: measured again")
  // (let go, another made where it was: set as words are, none of the first's)
  shown.set(1)
  t.frame(390.0, 844.0) |> ignore
  shown.set(2)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(ids.length(), 2)
  assert_eq(ids[1].at, ids[0].at, msg="made where the first was")
  assert_true(ids[1].gen != ids[0].gen)
  assert_eq(look(), runs_plain)
}
