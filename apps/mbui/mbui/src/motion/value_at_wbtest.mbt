// Anim::value_at: where a frame drawn at a moment has an Anim on the way it was told, asked as it is told, is the
// number Anim::get gives in the frame drawn at that moment, a fraction into a ms or not, before its delay, on its way,
// at its end and past it, whatever the spec (a tween, a Move, Compose's spring, Motion's transitions, done by their
// generator).

///|
/// An Anim told by `spec` to 1 at a moment a fraction into a ms, frames drawn after it every `gap` ms till past its end
/// and at its end exactly: each frame's moment, where value_at said as it was told a frame then would have it, and
/// where get has it in that frame.
fn value_at_and_get(spec : Spec, gap : Double) -> Array[(Double, Double, Double)] {
  let told_at = 1000.0 + 1000.0 / 3.0
  let go = @signals.signal(false)
  let tick = @signals.signal(0)
  let kept : Ref[Anim?] = Ref(None)
  let said : Array[(Double, Double)] = []
  let ats : Array[Double] = []
  let seen : Array[(Double, Double, Double)] = []
  let t = @ui.Tester::new(fn(c) {
    ignore(tick.get())
    let a = anim(c, "a", 0.0)
    if go.get() && kept.val is None {
      a.animate(c, 1.0, spec)
      kept.val = Some(a)
      // (its frames' moments, as far as past its end, and its end exactly)
      let mut at = told_at + gap
      while at < a.ends() + 3.0 * gap {
        ats.push(at)
        at = at + gap
      }
      ats.push(a.ends())
      ats.sort()
      for m in ats {
        said.push((m, a.value_at(m)))
      }
    }
    if kept.val is Some(_) && c.moment() > told_at {
      seen.push((c.moment(), match said.search_by(fn(s) { s.0 == c.moment() }) {
        Some(i) => said[i].1
        None => @double.not_a_number
      }, a.get(c)))
    }
    c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
  })
  t.frame_at(told_at - 50.0)
  go.set(true)
  t.frame_at(told_at)
  for i, m in ats {
    tick.set(i + 1)
    t.frame_at(m)
  }
  seen
}

///|
test "an Anim's value_at, asked as it is told, is what get has in the frame drawn at that moment, with a delay or none" {
  let specs : Array[(String, Spec)] = [
    ("tween", tween(200.0, ease=Out)),
    ("tween, delayed", tween(200.0, ease=Out, delay=70.0)),
    ("move", moved(points=300.0)),
    ("move, delayed", moved(points=300.0, delay=40.0)),
    ("Compose's spring", spring()),
    ("Compose's spring, delayed", spring(delay=50.0)),
    ("Motion's tween", tween_to(duration=200.0)),
    ("Motion's tween, delayed", tween_to(duration=200.0, delay=70.0)),
    ("Motion's spring", spring_to(stiffness=300.0, damping=20.0)),
    ("Motion's spring, delayed", spring_to(stiffness=300.0, damping=20.0, delay=50.0)),
  ]
  for s in specs {
    let (name, spec) = s
    for gap in [1000.0 / 60.0, 1000.0 / 120.0, 7.0] {
      let seen = value_at_and_get(spec, gap)
      assert_true(seen.length() > 3, msg="\{name}: frames drawn")
      for f in seen {
        let (at, said, got) = f
        assert_true(said == got, msg="\{name}, every \{gap} ms: at \{at} value_at said \{said}, get had \{got}")
      }
    }
  }
}
