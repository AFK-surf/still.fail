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
