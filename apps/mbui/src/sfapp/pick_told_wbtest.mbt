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
