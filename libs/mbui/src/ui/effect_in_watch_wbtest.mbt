// An effect made as a frame is read (frame_body under the frame's watch: a build, an after_build, a Ctx::tell) is the
// watch's whatever owner is set, let go as it reads the next frame: told as it is made (@signals.effect_in_watch, a
// fault: frame_watch.mbt). kitdemo's pick and op checks made one so and never heard the host's word (2026-11-12). One
// made in a timer or a fiber of the window's runtime, or in the handler of a message left for the frame, is not: they
// run outside the frame's reading (fx_frame_start, fx_untracked_wbtest.mbt; take_messages, take_untracked_wbtest.mbt).

///|
/// A Tester whose first build makes an effect in an after_build as kitdemo's checks did (`untracked`: made outside the
/// frame's reading, as they are now), its signal set after two more frames: how often the effect ran, the last it
/// read, where it was told it was made in a watch.
fn effect_made_in_after_build(untracked : Bool) -> (Int, Int, Array[String]) {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let seen : Array[Int] = []
  let told : Array[String] = []
  let was = @signals.effect_in_watch.val
  @signals.effect_in_watch.val = Some(fn(loc) { told.push(loc.to_string()) })
  let asked = Ref(false)
  let t = Tester::new(fn(c) {
    if !asked.val {
      asked.val = true
      c.after_build("effect", fn() {
        let make = fn() {
          let owner = @signals.set_owner(None)
          @signals.effect(fn() { seen.push(s.get()) }) |> ignore
          @signals.set_owner(owner) |> ignore
        }
        if untracked {
          @signals.untracked(make)
        } else {
          make()
        }
      })
    }
    c.text("x", wrap=false) |> ignore
  })
  t.draw()
  outside_came()
  t.draw()
  s.set(7)
  t.draw()
  @signals.effect_in_watch.val = was
  (seen.length(), seen.last().unwrap_or(-1), told)
}

///|
test "an effect made in an after_build with no owner of its own: told as made in the frame's watch, let go by its next read" {
  assert_true(@signals.effect_in_watch.val is Some(_))
  let (runs, last, told) = effect_made_in_after_build(false)
  assert_eq((runs, last), (1, 0))
  assert_eq(told.length(), 1)
  // (where it was made said: this file's line)
  assert_true(told[0].contains("effect_in_watch_wbtest.mbt"), msg=told[0])
}

///|
test "an effect made in an after_build, untracked with its owner set: not told, follows what it reads" {
  assert_eq(effect_made_in_after_build(true), (2, 7, []))
}
