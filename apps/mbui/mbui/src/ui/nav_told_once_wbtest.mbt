// What one cause does to a stack is told as one (nav.mbt's told_once): what reads the stack as it changes (its depth,
// whether its root shows, how it moves) sees it as it was and then as the cause left it, never half done between (its
// pages pushed or popped, its slide not yet set out). Each test says the states a reaction reading it saw, in turn,
// each only where it differs from the one before.

///|
/// A stack of letters held by the window's tree, and what a reaction reading it saw: its depth, whether its root shows,
/// how it moves (0 at rest, 1 coming in, 2 going), each told where it differs from the one before.
fn told_seen() -> (Tester, Nav[String], Array[(Int, Bool, Int)]) {
  let (t, nav, _) = stacked()
  let seen : Array[(Int, Bool, Int)] = []
  let owner = @signals.set_owner(None)
  @signals.effect(fn() {
    let now = (nav.depth(), nav.root_shows(), nav.mode)
    if seen.last() != Some(now) {
      seen.push(now)
    }
  })
  |> ignore
  @signals.set_owner(owner) |> ignore
  (t, nav, seen)
}

///|
test "a page pushed: the stack seen at rest, then two deep with its root beside the page coming in, then at rest over it; never two deep with nothing beside" {
  let (t, nav, seen) = told_seen()
  nav.push("b")
  t.draw()
  t.run_for(move_most_ms)
  assert_eq(seen, [(1, true, 0), (2, true, 1), (2, false, 0)])
}

///|
test "a page risen: as a page pushed, never two deep with nothing beside" {
  let (t, nav, seen) = told_seen()
  nav.rise("b")
  t.draw()
  t.run_for(move_most_ms)
  assert_eq(seen, [(1, true, 0), (2, true, 1), (2, false, 0)])
}

///|
test "a page popped: the stack seen two deep at rest, then one deep with the page going, then at rest; never one deep at rest with the page still to go" {
  let (t, nav, seen) = told_seen()
  nav.push("b")
  t.draw()
  t.run_for(move_most_ms)
  let before = seen.length()
  assert_true(nav.pop())
  t.draw()
  t.run_for(move_most_ms)
  assert_eq(seen[before - 1:].to_array(), [(2, false, 0), (1, true, 2), (1, true, 0)])
}

///|
test "a page let go of by a finger: as a page popped, never one deep at rest with the page still to go" {
  let (t, nav, seen) = told_seen()
  nav.push("b")
  t.draw()
  t.run_for(move_most_ms)
  let before = seen.length()
  // (as a finger dragging it back lets it go far enough: on back from where it is, Nav::let_go)
  nav.let_go(0.0)
  t.draw()
  t.run_for(move_most_ms)
  assert_eq(seen[before - 1:].to_array(), [(2, false, 0), (1, true, 2), (1, true, 0)])
}
