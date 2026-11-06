// What takes what is put into a draft from elsewhere (draft_taker_said, draft_given_to): the last said of those still
// there takes it, at once, once; one of a draft let go while another of it stays, the one that stays takes it; none
// there, none of them.

///|
test "two of a draft's takers, the later let go first: the earlier takes what comes, once; both gone, none" {
  let hits : Array[String] = []
  let a_on = @signals.signal(true)
  let b_on = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.show(fn() { a_on.get() }, fn(n) { draft_taker_said(n, "ws/st:s", fn() { hits.push("a") }) })
    root.show(fn() { b_on.get() }, fn(n) { draft_taker_said(n, "ws/st:s", fn() { hits.push("b") }) })
  })
  t.draw()
  draft_given_to("ws/st:s")
  assert_eq(hits, ["b"], msg="the last said takes it")
  b_on.set(false)
  t.draw()
  draft_given_to("ws/st:s")
  assert_eq(hits, ["b", "a"], msg="the one that stays takes it, once")
  a_on.set(false)
  t.draw()
  draft_given_to("ws/st:s")
  assert_eq(hits, ["b", "a"], msg="none there: none of them")
}

///|
/// Two takers of draft ws/st:s, `a` said after `b`, each while its signal holds, each taking what waits (shared_into) and
/// saying so into `hits`.
fn two_takers(hits : Array[String], a_on : @signals.Signal[Bool], b_on : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0)
  @ui.set_view_app(fn(root) {
    root.show(fn() { b_on.get() }, fn(n) {
      draft_taker_said(n, "ws/st:s", fn() {
        hits.push("b")
        shared_into.remove("ws/st:s")
      })
    })
    root.show(fn() { a_on.get() }, fn(n) {
      draft_taker_said(n, "ws/st:s", fn() {
        hits.push("a")
        shared_into.remove("ws/st:s")
      })
    })
  })
  t.draw()
  t
}

///|
test "what waits for a draft, to be taken at its moment by its last taker, that taker let go after: it takes it first, as what is due by then is done before the change that lets it go" {
  let hits : Array[String] = []
  let a_on = @signals.signal(true)
  let b_on = @signals.signal(true)
  let t = two_takers(hits, a_on, b_on)
  shared_into["ws/st:s"] = []
  draft_take_at("ws/st:s")
  a_on.set(false)
  t.draw()
  t.draw()
  assert_eq(hits, ["a"], msg="taken once, by the one it was told to: \{hits}")
  assert_true(!shared_into.contains("ws/st:s"))
}

///|
test "what waits for a draft, its last taker let go before it is taken: the one that stays takes it at that moment, once, nothing else asked" {
  let hits : Array[String] = []
  let a_on = @signals.signal(true)
  let b_on = @signals.signal(true)
  let t = two_takers(hits, a_on, b_on)
  // (left for it, no taking of it told yet: a let go)
  shared_into["ws/st:s"] = []
  a_on.set(false)
  t.draw()
  t.draw()
  assert_eq(hits, ["b"], msg="the one that stays takes it, once: \{hits}")
  assert_true(!shared_into.contains("ws/st:s"))
  t.draw()
  assert_eq(hits, ["b"])
}
