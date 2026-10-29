// 72-bar-archive (e2e/traces/bar-archive.trace): the chat's bar's 归档 (Chat.kt ChatBar, shown while nothing is left in
// the chat): Home at once, 已归档 said by its title (with its 撤销), the chat gone from the list (chat.archive).

///|
test "72-bar-archive" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("bar-archive"), seed~)
    // (made by alice's other device before the app starts: a live run's step, the trace has what came of it)
    f.before("peer create 从栏上归档 085454 post:都弄好了 085454")
    f.before("wait-chat 从栏上归档 085454")
    f.see("从栏上归档 085454")
    f.see("都弄好了 085454")
    f.tap("从栏上归档 085454")
    f.run_for(@ui.move_most_ms)
    f.see("icon:archive")
    f.tap("icon:archive")
    // Home at once, 已归档 said by its title with its 撤销: its time on screen, the chat popped meanwhile
    f.see("=已归档「从栏上归档 085454」")
    f.see("=撤销")
    f.run_for(@sfapp.toast_action_ms)
    f.gone("=从栏上归档 085454")
    // the toast gone
    // (its time out at the last frame: it starts going with the one after)
    f.t.draw()
    f.run_to_rest("toast")
    f.end()
  })
}

///|
/// run_to_rest at the run's pace: a motion said since the last step and over is at its end; another's having moved
/// (the toast here) does not make one never said (a sheet) at its end.
test "run_to_rest: only what was said" {
  let f = @sfreplay.Flow::start(@sfreplay.trace("bar-archive"), seed=0)
  f.before("peer create 从栏上归档 085454 post:都弄好了 085454")
  f.before("wait-chat 从栏上归档 085454")
  f.see("从栏上归档 085454")
  f.see("都弄好了 085454")
  f.tap("从栏上归档 085454")
  f.run_for(@ui.move_most_ms)
  f.see("icon:archive")
  f.tap("icon:archive")
  f.see("=已归档「从栏上归档 085454」")
  f.run_for(@sfapp.toast_action_ms)
  f.gone("=从栏上归档 085454")
  f.t.draw()
  // the toast going, to its end
  f.run_to(f.t.rest_of("toast"))
  assert_true(f.rest_passed("toast"))
  assert_false(f.rest_passed("dv-sheet"))
  ignore(f.end())
}
