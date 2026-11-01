// What is presented, as it is told: written whole before what reads it is told (an effect, a node's binding, reading it
// as it is told, finds it there), one change for the host and for whether each is drawn; opened and closed with no frame
// between, what each closed unsaid lets go of once; one opened by what another does as it is said, kept open as that
// one closes.

///|
test "presented as it is told: what reads it as it is told finds it there, each opened one after another with no frame between" {
  presenters_reset()
  let seen : Array[(Array[Int], Bool)] = []
  let stop = @signals.effect(fn() {
    presented_said.get() |> ignore
    let serials = @signals.untracked(fn() { presented_now.map(fn(p) { p.serial }) })
    let last = @signals.untracked(fn() { last_presented() })
    seen.push((serials, presented_drawn_of(last)))
  })
  confirm("甲", "", "好", fn() {  })
  confirm("乙", "", "好", fn() {  })
  stop()
  assert_eq(seen, [([], false), ([1], true), ([1, 2], true)])
}

///|
test "opened, closed and another opened with no frame between: the one closed unsaid lets go of what it holds once, the other open" {
  let gone = Ref(0)
  let t = presenting_tester(desk, fn(_) {  })
  panel("甲", fn(c, _) { c.text("甲的") |> ignore }, from=Unanchored, gone=fn() { gone.val = gone.val + 1 })
  close_presented()
  confirm("乙", "", "好", fn() {  })
  t.frame()
  t.run_for(@kit.presence_in_ms)
  let shown = (t.find("甲") is None, t.find("乙") is Some(_), presented_open_of(1), presented_open_of(2))
  t.run_for(@kit.presence_out_ms)
  assert_eq((shown, gone.val), ((true, true, false, true), 1))
}

///|
test "one said that opens another as it is done: the one said closes, its run once, the one it opened stays open" {
  let runs = Ref(0)
  let t = presenting_tester(desk, fn(_) {  })
  confirm("甲", "", "好", fn() {
    runs.val = runs.val + 1
    confirm("乙", "", "再来", fn() {  })
  })
  t.frame()
  t.run_for(@kit.presence_in_ms)
  t.tap_text("好")
  t.run_for(@kit.presence_out_ms + @kit.presence_in_ms)
  assert_eq((runs.val, presented_open_of(1), presented_open_of(2), t.find("再来") is Some(_)), (1, false, true, true))
}
