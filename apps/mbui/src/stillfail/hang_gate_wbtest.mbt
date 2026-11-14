///|
fn gate_hang(trigger : @ui.HangTrigger, end : Double, stall : Double) -> @ui.Hang {
  {
    trigger,
    page: "Chat",
    arranged: "",
    window_w: 0.0,
    window_h: 0.0,
    sealed_by: Presented,
    startup: false,
    start: end - stall,
    end,
    stall_ms: stall,
    work_ms: stall,
    pieces: 1,
    small: 0,
    small_ms: 0.0,
    lost: 0,
    contributors: [],
    elided: 0,
  }
}

///|
test "past each ten minutes' first twenty, the heaviest twenty held, stalls first, sent as the app is hidden" {
  let g = HangGate::new()
  let mut sent = 0
  for i in 0..<20 {
    sent += g.offer(gate_hang(LateFrame, 1000.0 + i.to_double(), 30.0)).length()
  }
  assert_eq(sent, 20)
  // (forty more late frames, then five stalls: none sent at once)
  for i in 0..<40 {
    assert_eq(g.offer(gate_hang(LateFrame, 2000.0 + i.to_double(), 20.0 + i.to_double())).length(), 0)
  }
  for i in 0..<5 {
    assert_eq(g.offer(gate_hang(Stall, 3000.0 + i.to_double(), 60.0)).length(), 0)
  }
  let (held, unsent) = g.flush()
  assert_eq(held.length(), 20)
  assert_eq(held.filter(fn(h) { h.trigger is Stall }).length(), 5)
  // (the late frames kept are the longest: 45 to 59 ms)
  let late = held.filter(fn(h) { h.trigger is LateFrame }).map(fn(h) { h.stall_ms })
  assert_eq(late.length(), 15)
  assert_true(late.iter().all(fn(ms) { ms >= 45.0 }), msg=Repr(late).to_string())
  assert_eq(unsent, 25)
  assert_eq(g.flush(), ([], 0))
}

///|
test "the held ones go first as the next ten minutes begin" {
  let g = HangGate::new()
  for i in 0..<21 {
    g.offer(gate_hang(LateFrame, 1000.0 + i.to_double(), 30.0)) |> ignore
  }
  let out = g.offer(gate_hang(Stall, 1000.0 + 600000.0, 80.0))
  assert_eq(out.map(fn(h) { h.trigger }), [LateFrame, Stall])
  let (held, unsent) = g.flush()
  assert_eq(held.length(), 0)
  assert_eq(unsent, 0)
}
