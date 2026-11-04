// The answer's room and the avatar that brings it must open together. A second ease toward a destination
// that is already moving lets the list finish making room while the avatar is still at its source.

///|
test "an answer's avatar travels with the room opening above its activity" {
  let clock = Ref(0.0)
  let t = emit_core(clock)
  let rk = "ws1/st1\u{1}s-c1"
  let em = emits_of(rk)
  fix_clock_set(clock, clock.val + fix_answer_ms)
  t.draw()
  let behind : Array[String] = []
  let mut seen = 0
  let until = t.time() + Pose::Fold.ms() + Pose::Float.ms()
  while t.time() < until {
    t.frame()
    match em.current {
      Some(turn) if turn.pose == Float => {
        let home = emit_place(t.ctx(), "emit-avatar/" + rk + "/" + turn.agent).unwrap()
        let land = emit_place(t.ctx(), "emit-landing/" + rk + "/" + seq_s(turn.seq)).unwrap()
        let face = emit_flight(t.ctx(), rk, em, [turn.agent]).unwrap()
        if home.1 - (land.1 + 3.0) > 1.0 {
          seen += 1
          if (face.1 - (land.1 + 3.0)).abs() > 1.0 {
            behind.push("at \{t.time()}: room to \{land.1 + 3.0}, avatar \{face.1}, from \{home.1}")
          }
        }
      }
      _ => ()
    }
  }
  emit_restore()
  assert_true(seen > 0)
  assert_eq(behind, [])
}
