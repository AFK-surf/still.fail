// The flying avatar of a message coming out of its agent's activity (sfbase's emit.mbt, the engine both frames
// play), as the phone draws it.

///|
/// The flying avatar over the list (Chat.kt Flyer): the agent's picture where emit_flight has it, drawn only.
fn emit_flyer(c : @ui.Ctx, key : String, e : Emits, v : ChatView) -> Unit {
  let (x, y, sx, sy) = match emit_flight(c, key, e, v.agents.map(fn(a) { a.key })) {
    Some(f) => f
    None => return
  }
  let a = match e.current {
    Some(t) => v.agents.iter().find_first(fn(a) { a.key == t.agent })
    None => None
  }
  let (maker, runtime, waiting) = match a {
    Some(a) => (a.maker, a.runtime, a.wait is Some(_))
    None => ("", "", false)
  }
  // the avatar with its ring round it, as its activity has them (Chat.kt Flyer)
  c.layer(fn() {
    let b = c.box(tx=x - ring_room, ty=y - ring_room, w=Px(24.0), h=Px(24.0), align=ACenter, justify=JCenter, fn() {
      agent_avatar(c, maker, runtime)
      c.layer(fn() { work_ring(c, waiting) }) |> ignore
    })
    c.look(b, @ui.look(sx~, sy~))
    c.draw_only(b)
  })
  |> ignore
  match e.current {
    Some(t) => {
      let (u, fy, ly) = e.trace
      @motion.log_frame(c, "emit/" + seq_s(t.seq), "pose=\{t.pose} x=\{x} y=\{y} sx=\{sx} sy=\{sy} u=\{u} from=\{fy} to=\{ly}")
    }
    None => ()
  }
}
