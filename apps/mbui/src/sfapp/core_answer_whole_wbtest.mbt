// A core's answer to a call, as the device takes it (posted on the "core" channel, sfcore's start: what is taken as it
// comes, @core.receive_said, else @core.receive as the frame begins): one change, whatever its callback does. A
// callback that goes to another page and writes something else (new_profile.mbt's useMachineLogin, its page put in
// place) is seen by what reads both before it and after it, never between.

///|
test "a call's answer whose callback pushes a page and writes something else: what reads both sees them before and after, never one done and the other not yet" {
  new_run()
  @ui.on_message("core", @core.receive)
  @ui.on_message_said("core", @core.receive_said)
  let t = @ui.Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.draw()
  // (the core this test is: what the client sends it kept, its answer posted as a device's core posts it)
  let sent : Array[String] = []
  @core.serve(fn(s) { sent.push(s) }) |> ignore
  let nav : @ui.Nav[String] = @ui.Nav::new("home")
  let chosen = @signals.signal("")
  let seen : Array[(Int, String)] = []
  let owner = @signals.set_owner(None)
  @signals.effect(fn() {
    let now = (nav.depth(), chosen.get())
    if seen.last() != Some(now) {
      seen.push(now)
    }
  })
  |> ignore
  @signals.set_owner(owner) |> ignore
  @core.call("profile.useMachineLogin", on_done=fn(_) {
    nav.push("profile")
    chosen.set("cc")
  })
  let mut id = -1
  for s in sent {
    let j = @json.parse(s) catch { _ => continue }
    if j is Object(m) &&
      m.get("call") is Some(String("profile.useMachineLogin")) &&
      m.get("id") is Some(Number(n, ..)) {
      id = n.to_int()
    }
  }
  t.post("core", "{\"id\":\{id},\"ok\":{}}")
  t.frame(ms=0.0)
  @core.serve_end()
  assert_eq(seen, [(1, ""), (2, "cc")])
}
