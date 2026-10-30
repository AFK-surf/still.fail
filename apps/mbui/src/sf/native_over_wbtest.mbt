///|
/// The ids of the actions handed to the system's bars, in their order.
fn over_ids() -> Array[String] {
  native_over.acts.map(fn(a) { a.0 })
}

///|
test "what is up over the window says its actions as one set: built again, what it no longer says gone, none twice; another up in its place, only its own; none as a frame starts" {
  native_bars_reset()
  native_bars.on.set(true)
  native_over_clear()
  // (built: three said; built again in the frame: one no longer said, one said twice)
  native_over_up("屏幕") |> ignore
  for id in ["close", "center", "full"] {
    native_over_act(id, id, "x", fn() {  })
  }
  native_over_up("屏幕") |> ignore
  native_over_act("close", "close", "x", fn() {  })
  native_over_act("full", "full", "x", fn() {  })
  native_over_act("full", "full", "x", fn() {  })
  let again = over_ids()
  // (another page up in its place)
  native_over_up("文件") |> ignore
  native_over_act("download", "download", "x", fn() {  })
  let other = over_ids()
  // (a frame starts: none up, none said)
  native_over_clear()
  let start = (native_over.up, over_ids())
  native_bars_reset()
  assert_eq((again, other, start), (["over/close", "over/full"], ["over/download"], (false, [])))
}
