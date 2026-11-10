// The made-up core a late core's tests run over (sffixture's round_trip_again) sits under the app's own client of its
// core: what it takes for a topic subscribed and let go of is what the client sent, the messages a run's trace keeps,
// never a count of its own of who reads what.

///|
/// What of `heard` is a subscription to, or a letting go of, a topic (the client's messages out): `sub <topic>`,
/// `unsub <topic>`, in order.
fn wire_subs(heard : Array[String]) -> Array[String] {
  let topics : Map[Int, String] = {}
  let out : Array[String] = []
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let text = h.view(start_offset=4).to_string()
    let j = @json.parse(text) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(t)), _) =>
        match t.get("topic") {
          Some(String(topic)) => {
            topics[n.to_int()] = topic
            out.push("sub " + topic)
          }
          _ => ()
        }
      (_, Some(True)) => out.push("unsub " + topics.get(n.to_int()).unwrap_or("?"))
      _ => ()
    }
  }
  out
}

///|
test "two readers of a topic over the late core: subscribed once; the first let go of, still subscribed; both, let go of; read again, subscribed again and answered late again" {
  new_run()
  let heard : Array[String] = []
  let src = round_trip_again(fixture("home"), place_core_soon_ms, heard=fn(h) { heard.push(h) })
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  // (the made-up core's moments the window's, as the app's view gives them it: sffixture's made_frame)
  @sffixture.fix_ctx.val = Some(t.ctx())
  t.draw()
  let read = fn() {
    let owner = @signals.set_owner(None)
    let stop = @signals.effect(fn() { src.topic("prefs", {}).get() |> ignore })
    @signals.set_owner(owner) |> ignore
    stop
  }
  let one = read()
  let two = read()
  t.run_for(place_core_soon_ms * 2.0)
  let both = wire_subs(heard)
  let answered = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  one()
  t.run_for(@ui.frame_period_default * 2.0)
  let first_gone = wire_subs(heard)
  two()
  t.run_for(@ui.frame_period_default * 2.0)
  let all_gone = wire_subs(heard)
  let three = read()
  t.draw()
  let again_now = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  t.run_for(place_core_soon_ms * 2.0)
  let again_later = @signals.untracked(fn() { src.topic("prefs", {}).get().value is Some(_) })
  let read_again = wire_subs(heard)
  three()
  assert_eq(
    (both, answered, first_gone, all_gone, read_again, again_now, again_later),
    (
      ["sub prefs"],
      true,
      ["sub prefs"],
      ["sub prefs", "unsub prefs"],
      ["sub prefs", "unsub prefs", "sub prefs"],
      false,
      true,
    ),
  )
}
