///|
test "the tree's work timed by part: its structures' changes, its bindings, its layout and the words measured in it, its placing" {
  let rows = @signals.signal([], same=fn(a : Array[Int], b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.each(fn() { rows.get() }, fn(n) { n }, fn(row, _) { row.words(Is("a row")) |> ignore })
    })
    |> ignore
  })
  t.frame(300.0, 600.0, now=0.0) |> ignore
  // (a clock a ms on at each reading: every part timed comes out 1 ms at least)
  let clock = Ref(0.0)
  let took : Map[String, Double] = Map([])
  let listening = Ref(true)
  t.timed_by(
    Some(
      (
        fn() {
          if listening.val {
            clock.val += 1.0
            clock.val
          } else {
            -1.0
          }
        },
        fn(what, ms) { took[what] = took.get(what).unwrap_or(0.0) + ms },
      ),
    ),
  )
  t.event(1.0, fn() { rows.set([1, 2, 3]) })
  t.frame(300.0, 600.0, now=1.0) |> ignore
  for part in ["tree bindings", "tree layout", "tree placing", "tree structures", "tree words measured"] {
    assert_true(took.contains(part), msg="\{part} not told: \{Repr(took)}")
  }
  assert_eq(took.length(), 5)
  assert_true(took.values().all(fn(ms) { ms >= 1.0 }), msg=Repr(took).to_string())
  // (nobody listening: nothing timed, nothing told)
  took.clear()
  listening.val = false
  t.event(2.0, fn() { rows.set([1, 2, 3, 4]) })
  t.frame(300.0, 600.0, now=2.0) |> ignore
  assert_eq(took.length(), 0)
  // (and none given: the same)
  t.timed_by(None)
  t.event(3.0, fn() { rows.set([]) })
  t.frame(300.0, 600.0, now=3.0) |> ignore
  assert_eq(took.length(), 0)
  t.dispose()
}
