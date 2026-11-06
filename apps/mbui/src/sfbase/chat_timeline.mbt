// A retained chat owns its replies' declared phases. Input changes and owned
// deadlines advance them; drawing a frame only samples the ways they declared.

///|
pub fn chat_timeline(
  owner : @view.View,
  rk : String,
  rd : Reading,
  read : () -> ChatView?,
  shown : () -> Bool,
  in_front : () -> Bool,
) -> () -> Unit {
  let em = emits_of(rk)
  let stop : Ref[() -> Unit] = Ref(fn() { })
  let due = Ref(@double.infinity)
  let lingering : Map[String, (Int, Double)] = {}
  let advancing = Ref(false)
  owner.owns(fn() { (stop.val)() }) |> ignore
  fn advance() {
    if advancing.val || !owner.alive() { return }
    guard read() is Some(cv) else { return }
    advancing.val = true
    let c = @ui.current()
    let now = owner.cause_at()
    let showing = shown()
    chat_take(c, rk, rd, cv, shown=showing, in_front=in_front())
    if showing {
      emit_step(c, em, turns_of(rk), rd.landing.get(), at=now)
    }
    let keeps = emit_keeps(em)
    let gone : Array[String] = []
    let mut next = @double.infinity
    for k, l in rd.linger {
      if rd.running.contains(k) {
        gone.push(k)
      } else if keeps.contains(k) {
        lingering.remove(k) |> ignore
      } else {
        let until = match lingering.get(k) {
          Some((id, until)) if id == l.id => until
          _ => {
            let ended = emit_ended(em, k)
            let until = dmax(now, ended) + linger_ms
            lingering[k] = (l.id, until)
            until
          }
        }
        if until <= now { gone.push(k) } else { next = dmin(next, until) }
      }
    }
    for k in gone {
      rd.linger.remove(k)
      lingering.remove(k) |> ignore
    }
    if !gone.is_empty() {
      rd.linger_said.set(@signals.untracked(fn() { rd.linger_said.get() }) + 1)
    }
    if showing {
      match em.current {
        Some(t) => {
          let at = dmax(t.clock.end(), em.held_until)
          // An unknown sent row's landing is supplied by its geometry input,
          // not by polling an expired phase with another frame.
          if at > now { next = dmin(next, at) }
        }
        None => ()
      }
      for _, way in em.out_at {
        if way.end() > now { next = dmin(next, way.end()) }
      }
    }
    if next != due.val {
      (stop.val)()
      due.val = next
      if next < @double.infinity {
        stop.val = owner.at_moment(next, fn() {
          due.val = @double.infinity
          advance()
        })
      }
    }
    advancing.val = false
  }
  advance
}
