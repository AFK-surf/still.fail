// A page made once on the tape swiped back from its edge as one of an old view is (tape_bar_wbtest's): across, the page
// under it; across and back where it began, the page stays.

///|
/// 记忆 made once on the tape, 600 wide by 760, a finger where the app takes the swipe (an iPad's): its panel.
fn tape_memories_made(made? : Bool = true) -> (@ui.Tester, @ui.Laid, Int) raise {
  new_run()
  // (its old view where not `made`: what the swipe did before)
  @sfdesk.pane_makes.val = made
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=600.0, h=760.0, platform=1)
  say_room(t, "medium", "medium")
  t.draw()
  open_page(Settings)
  t.run_for(@ui.move_most_ms)
  t.click(Link, label="记忆")
  t.run_for(@ui.move_most_ms)
  page_over(t, 600.0)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  (t, p, app.nav.depth())
}

///|
test "on the tape 记忆 made once over settings, a swipe from its edge as its old view takes one: across and back where it began, the tape moved with it and back, the page in use; across, the sidebar brought over" {
  let seen = fn(made : Bool) raise {
  let (t, p, depth) = tape_memories_made(made~)
  let y = p.y + 20.0
  t.touch(0, p.x + 6.0, y)
  for i in 1..=6 {
    t.advance(@ui.input_step_ms)
    t.touch(1, p.x + 6.0 + 194.0 * i.to_double() / 6.0, y)
  }
  // (taken over as it goes: the tape pulled by it, as far as it went)
  let moved = @signals.untracked(fn() { @sfdesk.wide.tape_drag.get() }) > 0.0
  for i in 1..=6 {
    t.advance(@ui.input_step_ms)
    t.touch(1, p.x + 200.0 - 194.0 * i.to_double() / 6.0, y)
  }
  t.touch(2, p.x + 6.0, y)
  t.run_for(@ui.move_most_ms)
  // (the page's panel where it was, the tape pulled no more)
  let back_at = match tape_page_panel(t) {
    Some(q) => q.x == p.x
    None => false
  }
  let stayed = (
    app.nav.depth() - depth,
    @sfdesk.wide.tape_at.get(),
    back_at && @signals.untracked(fn() { @sfdesk.wide.tape_drag.get() }) == 0.0,
  )
  t.drag(p.x + 6.0, y, p.x + 400.0, y, steps=10)
  t.run_for(@ui.move_most_ms)
  @sfdesk.pane_makes.val = true
  (moved, stayed, app.nav.depth() - depth, @sfdesk.wide.tape_at.get())
  }
  let old = seen(false)
  let made = seen(true)
  assert_eq(made, old)
  assert_eq(made, (true, (0, @sfdesk.TapePane::Page, true), 0, @sfdesk.TapePane::Side))
}

///|
test "on the tape 记忆 made once, the window made wider between a finger going down at its edge and its swipe taken over: the tape pulled from where it went down, as its old view's is" {
  let pulled = fn(made : Bool) raise {
    let (t, p, _) = tape_memories_made(made~)
    let (x, y) = (p.x + 6.0, p.y + 20.0)
    t.touch(0, x, y)
    // (what holds the page moved and grown under the finger before it goes past the slop)
    t.resize(680.0, 760.0)
    t.advance(@ui.input_step_ms)
    t.touch(1, x + 30.0, y)
    t.advance(@ui.input_step_ms)
    t.touch(1, x + 80.0, y)
    let drag = @signals.untracked(fn() { @sfdesk.wide.tape_drag.get() })
    t.touch(2, x + 80.0, y)
    t.run_for(@ui.move_most_ms)
    @sfdesk.pane_makes.val = true
    drag
  }
  let old = pulled(false)
  let made = pulled(true)
  assert_true(old > 0.0 && made == old, msg="\{made} \{old}")
}

///|
/// 更新日志 made once on the tape over 关于, each pressed as a person does, 600 wide by 760, a finger where the app takes
/// the swipe (an iPad's): its panel.
fn tape_changelog_made() -> (@ui.Tester, @ui.Laid, Int) raise {
  new_run()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=600.0, h=760.0, platform=1)
  say_room(t, "medium", "medium")
  t.draw()
  open_page(Settings)
  t.run_for(@ui.move_most_ms)
  // (关于 pressed in the settings' list (at its end: scrolled to it), 更新日志 in 关于's: each over the one before)
  t.wheel(150.0, 500.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  t.click(Link, label="关于")
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() == Setting(About) else { fail("关于 not reached: \{@sfbase.page_kind(app.nav.top())}") }
  // (its page brought over the sidebar, as a person brings it to press in it)
  page_over(t, 600.0)
  t.click(Link, label="更新日志")
  t.run_for(@ui.move_most_ms)
  guard app.nav.top() == Setting(Changelog) else { fail("更新日志 not reached: \{@sfbase.page_kind(app.nav.top())}") }
  page_over(t, 600.0)
  guard tape_page_panel(t) is Some(p) else { fail("no page") }
  (t, p, app.nav.depth())
}

///|
test "on the tape 更新日志 made once over 关于, a swipe from its edge: across and back where it began, the page in use; across, 关于 again" {
  // (across and back where it began, let go there: what is shown then, how deep, the tape's pane)
  let back = fn() raise {
    let (t, p, depth) = tape_changelog_made()
    let y = p.y + 20.0
    t.touch(0, p.x + 6.0, y)
    for i in 1..=6 {
      t.advance(@ui.input_step_ms)
      t.touch(1, p.x + 6.0 + 194.0 * i.to_double() / 6.0, y)
    }
    // (what took it as it went: the tape pulled (its own back), or the stack's)
    let tape = @signals.untracked(fn() { @sfdesk.wide.tape_drag.get() }) > 0.0
    for i in 1..=6 {
      t.advance(@ui.input_step_ms)
      t.touch(1, p.x + 200.0 - 194.0 * i.to_double() / 6.0, y)
    }
    t.touch(2, p.x + 6.0, y)
    t.run_for(@ui.move_most_ms)
    (tape, app.nav.depth() - depth, app.nav.top() == Setting(About), @sfdesk.wide.tape_at.get())
  }
  // (across: what is shown then, how deep, the tape's pane)
  let across = fn() raise {
    let (t, p, depth) = tape_changelog_made()
    // (a finger across, as the swipe back above is made)
    let y = p.y + 20.0
    t.touch(0, p.x + 6.0, y)
    for i in 1..=10 {
      t.advance(@ui.input_step_ms)
      t.touch(1, p.x + 6.0 + 394.0 * i.to_double() / 10.0, y)
    }
    t.touch(2, p.x + 400.0, y)
    t.run_for(@ui.move_most_ms)
    (app.nav.depth() - depth, app.nav.top() == Setting(About), @sfdesk.wide.tape_at.get())
  }
  // (across and back where it began, let go there: taken by the stack's own back over 关于 (the tape not pulled), called
  // off, 更新日志 still on top)
  let made_back = back()
  assert_eq(made_back, (false, 0, false, @sfdesk.TapePane::Page), msg="\{Repr(made_back)}")
  // (across: 关于 again)
  let made = across()
  assert_eq(made, (-1, true, @sfdesk.TapePane::Page), msg="\{Repr(made)}")
}
