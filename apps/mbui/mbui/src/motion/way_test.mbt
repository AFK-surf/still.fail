// A way said once as it sets out (way.mbt): where it is at a moment a function of what it was told and that moment
// alone, whatever frames were drawn or sampled ahead of what has happened.

///|
/// A way from 0 to 1 over `way_ms` set out at `set_out_at`, a frame drawn at `ahead` first (none: -1), then sent back to
/// 0 at `back_at` (a cause come before that frame's moment, as an input handed on late): where it is at each of
/// `looks`, and when it ends.
fn sent_back(ahead : Double) -> (Array[Double], Double) {
  let t = @ui.Tester::new(fn(_c) {  })
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(way_ms, ease=Linear), at=set_out_at)
  if ahead >= 0.0 {
    t.frame_at(ahead)
    // (read where that frame has it)
    w.get() |> ignore
  }
  w.go(0.0, @motion.tween(way_ms, ease=Linear), at=back_at)
  (looks.map(fn(at) { w.value_at(at) }), w.ends_at())
}

///|
test "a way sent back at a moment before a frame drawn ahead of it: from where it was then, the same as with no frame" {
  let none = sent_back(-1.0)
  assert_eq(sent_back(set_out_at + 300.0), none)
  assert_eq(sent_back(set_out_at + 50.0), none)
  // (sent back at 1100, halfway: from 0.5, 200 ms on to 0)
  assert_eq(none, ([0.5, 0.25, 0.0, 0.0], back_at + way_ms))
}

///|
/// The way's length, when it set out and when it was sent back, and the moments looked at.
let way_ms : Double = 200.0

///|
let set_out_at : Double = 1000.0

///|
let back_at : Double = 1100.0

///|
let looks : Array[Double] = [1100.0, 1200.0, 1300.0, 1400.0]

///|
test "a way of a length and a delay not whole: at its end and after, exactly where it was sent, still" {
  let _ = @ui.Tester::new(fn(_c) {  })
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(odd_ms, ease=Linear, delay=odd_delay), at=set_out_at)
  let end = w.end()
  assert_eq((w.at(end), w.at(end + 1000.0)), ((1.0, 0.0), (1.0, 0.0)))
  // (short of it: not there yet)
  assert_true(w.value_at(end - 2.0) < 1.0)
}

///|
/// A length and a delay not whole.
let odd_ms : Double = 200.5

///|
let odd_delay : Double = 10.25

///|
/// A way from 0 to 1 over `way_ms` set out at `at`: when it set out and ends, and where it is a quarter and half way and
/// a hair before its end, each at a moment `frac` into its ms.
fn set_out_at_fraction(at : Double, frac : Double) -> (Double, Double, Array[Double]) {
  let w = @motion.Way::new(0.0)
  w.go(1.0, @motion.tween(way_ms, ease=Linear), at~)
  let s = w.starts_at()
  (s, w.ends_at(), [0.25, 0.5].map(fn(k) { w.value_at(s + way_ms * k + frac) }) + [w.value_at(w.ends_at() - 1.0 + frac)])
}

///|
test "a way set out a fraction into a ms: its time goes on the one clock's whole ms from that ms, as any motion's (where a moment falls in its ms changes nothing)" {
  // (set out at 1000.7: from 1000, ending at 1000 + its length; read at any fraction of a ms, as at its start)
  let whole = set_out_at_fraction(1000.0, 0.0)
  assert_eq(set_out_at_fraction(1000.7, 0.0), whole)
  assert_eq(set_out_at_fraction(1000.7, 0.6), whole)
  assert_eq(set_out_at_fraction(1000.0, 0.999), whole)
  assert_eq(whole, (1000.0, 1000.0 + way_ms, [0.25, 0.5, (way_ms - 1.0) / way_ms]))
}
