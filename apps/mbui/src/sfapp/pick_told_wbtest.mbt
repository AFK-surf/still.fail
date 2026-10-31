// What is picked as told (sfbase's pick.mbt `picked`): a passage picked tells an identity of its own once, what is known
// of it said with it; built again, nothing more; let go, told once; picked again, even in the same message, another.

///|
/// What `picked` tells while `f` runs, each telling once (an effect following it from now).
fn picked_told(f : () -> Unit) -> Array[@sfbase.Picked] {
  let told : Array[@sfbase.Picked] = []
  let first = Ref(true)
  let stop = @signals.effect(fn() {
    let p = @sfbase.picked.get()
    if first.val {
      first.val = false
    } else {
      told.push(p)
    }
  })
  f()
  stop()
  told
}

///|
test "a passage held with a finger: an identity told once, the message and where it runs said with it; built again, nothing more; let go, told once; held again in the same message, another" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let told = picked_told(fn() {
    hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
    // (built again, frame after frame: the same passage)
    t.run_for(@ui.move_most_ms)
    t.tap(195.0, 300.0)
    t.run_for(pick_bar_in_ms)
    hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
    t.run_for(pick_bar_in_ms)
  })
  assert_eq(told.length(), 3, msg="\{told}")
  let one = told[0]
  assert_true(one.serial > 0 && one.ts != "" && one.a >= 0 && one.b > one.a, msg="\{one}")
  assert_eq(told[1], @sfbase.picked_none)
  let two = told[2]
  assert_true(two.ts == one.ts && two.serial > one.serial, msg="\{one} then \{two}")
  assert_eq(@sfbase.picked.get(), two)
}

///|
test "a run begun anew: nothing picked told, no identity of a run before given again" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let before = @sfbase.picked.get().serial
  assert_true(before > 0)
  new_run()
  assert_eq(@sfbase.picked.get(), @sfbase.picked_none)
  let t2 = fake_core(calls)
  hold_on(t2, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(@sfbase.picked.get().serial > before, msg="\{@sfbase.picked.get()} after \{before}")
}

///|
/// A mouse's passage of the page's last answer: pressed `from` past its start, dragged to `to` past it and let go there
/// (its own moments, from `at`; a frame between each when `framed`, else none), then a frame: what is told picked then.
fn mouse_picked(t : @ui.Tester, from : Double, to : Double, framed : Bool) -> @sfbase.Picked {
  // (apart from the press before: a press of its own, not its double click)
  t.run_for(@ui.move_most_ms)
  let (rx, ry, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let y = ry + 8.0
  let at = t.time() + between_frames_ms
  t.advance(at - t.time())
  let steps = [(0, from, 0.0), (1, (from + to) / 2.0, 40.0), (1, to, 80.0), (2, to, 120.0)]
  for s in steps {
    let (kind, x, dt) = s
    if framed && t.time() < at + dt {
      t.frame_at(at + dt)
    }
    t.touch_at(kind, rx + x, y, at + dt)
  }
  t.frame_at(at + 140.0)
  @sfbase.picked.get()
}

///|
test "a mouse's passage picked anew in the same message (another passage, or the same again): another identity, frames between or none; built again, the same" {
  for framed in [true, false] {
    let t = tape_chat(0, 750.0, 830.0)
    t.host_says_finger(Some(false))
    @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
    t.run_for(@ui.move_most_ms)
    let one = mouse_picked(t, 4.0, 120.0, framed)
    assert_true(one.serial > 0, msg="framed \{framed}: \{one}")
    let two = mouse_picked(t, 40.0, 200.0, framed)
    assert_true(two.ts == one.ts && two.serial > one.serial, msg="framed \{framed}: \{one} then \{two}")
    let three = mouse_picked(t, 40.0, 200.0, framed)
    assert_true(three.serial > two.serial, msg="framed \{framed}: \{two} then \{three}")
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfbase.picked.get(), three, msg="framed \{framed}")
  }
}
