// A way (way.mbt: what the window's tree's motions go by) and an Anim (anim.mbt: what the old views' go by) told the
// same at the same moment, a fraction into a ms: where each is at the same frames, the same, its time from its own
// start in whole ms (Spec::value_at) as an Anim's is.

///|
/// An Anim followed to 1 by `in_spec` (open) or 0 by `out_spec`, and a way sent the same at the same moments: opened at
/// `open_at`, closed at `close_at` (before its way in ends: turned back from where it is), each a frame's moment, frames
/// at each of `frames` after. Where each is at each frame (to a millionth), the Anim's then the way's.
fn way_and_anim(
  open_at : Double,
  close_at : Double,
  frames : Array[Double],
) -> (Array[(Double, Double)], (Double, Double)) {
  let in_spec = @motion.tween(140.0, ease=Out)
  let out_spec = @motion.tween(100.0, ease=Leave)
  let open = @signals.signal(false)
  let w = @motion.Way::new(0.0)
  let seen : Array[(Double, Double)] = []
  let kept : Ref[@motion.Anim?] = Ref(None)
  let f = fn(v : Double) { (v * 1000000.0).round() / 1000000.0 }
  let t = @ui.Tester::new(fn(c) {
    let a = @motion.anim(c, "a", 0.0)
    kept.val = Some(a)
    let o = open.get()
    a.follow(if o { 1.0 } else { 0.0 }, if o { in_spec } else { out_spec })
    seen.push((f(a.get()), f(w.value_at(c.moment()))))
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.frame_at(open_at - 50.0)
  // (opened at a frame's moment: the Anim from that frame's build, the way from that moment)
  open.set(true)
  w.go(1.0, in_spec, at=open_at)
  t.frame_at(open_at)
  let out = []
  let ends = Ref((0.0, 0.0))
  let mut closed = false
  for at in frames {
    if !closed && at >= close_at {
      closed = true
      open.set(false)
      w.go(0.0, out_spec, at=close_at)
      t.frame_at(close_at)
      out.push(seen[seen.length() - 1])
      ends.val = (kept.val.map(fn(a) { a.ends_at() }).unwrap_or(-1.0), w.ends_at())
      if at == close_at {
        continue
      }
    }
    t.frame_at(at)
    out.push(seen[seen.length() - 1])
  }
  (out, ends.val)
}

///|
test "a way and an Anim told alike a fraction into a ms: where each is at each frame, coming in, turned back and going, the same" {
  // (60 Hz from 1516.666…: in at once, turned back at 1583.333… part way, out to its end)
  let frame = 1000.0 / 60.0
  let open_at = 91.0 * frame
  let frames = Array::makei(14, fn(i) { open_at + (i + 1).to_double() * frame })
  let (seen, (anim_ends, way_ends)) = way_and_anim(open_at, open_at + 4.0 * frame, frames)
  let differ = seen.filter(fn(s) { s.0 != s.1 })
  // (and each over at the same moment, its way out's length after it was turned back)
  assert_eq((differ, way_ends - anim_ends), ([], 0.0), msg="\{seen}")
}
