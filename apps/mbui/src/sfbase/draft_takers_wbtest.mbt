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
