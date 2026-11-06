// What a recorded host frame says of itself (tester_host.mbt), held where it could say wrong: what of the picture
// changed that the parts drawn again leave out (host_missed), and whether the old frame was built for the inputs handed
// to it alone (HostFrame's for_old_input).

///|
/// An instance drawn, by its numbers' hash, reaching `reach` (x0, y0, x1, y1).
fn drawn_as(hash : Int64, reach : (Double, Double, Double, Double)) -> HostDrawn {
  { hash, reach, numbers: FixedArray::make(inst_size, 0.0) }
}

///|
test "two instances that overlap drawn the other way round, each as it was: missed where they overlap unless drawn again there, and glass over them with it; apart, or the same order, nothing" {
  let red = drawn_as(1L, (10.0, 10.0, 60.0, 60.0))
  let blue = drawn_as(2L, (40.0, 40.0, 90.0, 90.0))
  let green = drawn_as(3L, (100.0, 100.0, 150.0, 150.0))
  // (red over blue now, blue over red before: where they overlap shows the other)
  assert_eq(host_missed([red, blue], [blue, red], [], [], 200.0, 200.0), [
    "drawn the other way round at (40, 40, 60, 60)",
  ])
  assert_eq(host_missed([red, blue], [blue, red], [], [(40.0, 40.0, 20.0, 20.0)], 200.0, 200.0), [])
  // (glass over them blurs what is under it: copied again only where drawn again)
  assert_eq(host_missed([red, blue], [blue, red], [(0.0, 0.0, 100.0, 100.0)], [(40.0, 40.0, 20.0, 20.0)], 200.0, 200.0), [
    "glass copying (0, 0, 100, 100) under a change",
  ])
  // (one that moves among others, past one it overlaps and one it does not)
  assert_eq(host_missed([red, green, blue], [blue, red, green], [], [], 200.0, 200.0), [
    "drawn the other way round at (40, 40, 60, 60)",
  ])
  assert_eq(host_missed([red, green], [green, red], [], [], 200.0, 200.0), [])
  assert_eq(host_missed([red, blue], [red, blue], [(0.0, 0.0, 100.0, 100.0)], [], 200.0, 200.0), [])
}

///|
/// A window whose old frame holds a button whose words read `other`, pressed and let go on it (an input handed to the old
/// frame: what reads what came from outside is built again), `set` told before the press, after it, or not, each as a
/// host draws its frames: the frames recorded from the press on.
fn old_pressed(set : String) -> Array[HostFrame] raise {
  let other = @signals.signal(0)
  let t = Tester::new(
    fn(c) {
      let id = c.id("words")
      c.clicked(id) |> ignore
      c.box(w=Px(80.0), h=Px(40.0), id~, fn() { c.text("words \{other.get()}") |> ignore }) |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  t.run_as_host(100.0)
  t.record_host()
  if set == "before" {
    other.set(1)
  }
  finger(0, 20.0, 10.0)
  if set == "after" {
    other.set(1)
  }
  t.run_as_host(50.0)
  finger(2, 20.0, 10.0)
  t.run_as_host(50.0)
  t.host_frames()
}

///|
test "the old frame built for the inputs handed to it alone, so said; not where something else changed before or after them as well, and nothing of it counted once frames are no longer recorded" {
  let frames = old_pressed("")
  let built = frames.filter(fn(f) { f.old_built })
  // (the press's frame built for it, and the one after for what it left (inputs_taken): none else)
  assert_true(built.length() > 0 && built[0].for_old_input && built[0].old_inputs.length() > 0, msg="\{frames}")
  assert_true(
    built.iter().all(fn(f) { f.for_old_input || f.left_by == "the inputs it took (inputs_taken)" }),
    msg="\{frames}",
  )
  for set in ["before", "after"] {
    let frames = old_pressed(set)
    let first = frames.filter(fn(f) { f.old_built })
    assert_true(first.length() > 0 && !first[0].for_old_input && first[0].old_inputs.length() > 0, msg="\{set}: \{frames}")
  }
  // (a run not recorded: nothing counted, nothing said)
  ignore(Tester::new(fn(_c) {  }, w=300.0, h=200.0))
  let other = @signals.signal(0)
  other.set(1)
  assert_eq(@signals.sets_made(), 0)
  assert_false(causes_counted.val)
}

