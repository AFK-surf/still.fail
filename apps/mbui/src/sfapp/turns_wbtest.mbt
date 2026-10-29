// What changes a chat's list's height waits for nothing (turns.mbt, docs/list-motion.md): a row comes, what is under a
// post changes, the moment it does, together; each one's room goes to its new height from then (Ctx::row_size).

///|
test "turns: rows coming and what changes under a post go the moment they are asked, together, none waiting" {
  reset()
  let tu = turns_of("test")
  let phase = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      tu.step(c, -1.0)
      match phase.val {
        0 => {
          ignore(tu.in_turn(c, "k", false, close_turn_ms, seen=true))
          phase.val = 1
        }
        1 => {
          ignore(tu.in_turn(c, "k", true, close_turn_ms, seen=true))
          tu.admit(c, "a", row_turn_ms)
          tu.admit(c, "b", row_turn_ms)
          phase.val = 2
        }
        _ => ignore(tu.in_turn(c, "k", true, close_turn_ms, seen=true))
      }
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
    platform=2,
  )
  t.draw()
  t.draw()
  assert_eq(tu.shown.get("k"), Some(true))
  assert_false(tu.waiting.contains("a"))
  assert_false(tu.waiting.contains("b"))
  let at = tu.started_at("k")
  assert_true(at >= 0.0)
  assert_eq(tu.started_at("a"), at)
  assert_eq(tu.started_at("b"), at)
  t.assert_idle()
}

///|
test "turns: what goes from under a post on screen goes at once, as out of sight (no frame of the list's says which)" {
  reset()
  let tu = turns_of("test")
  let shown = Ref::new(true)
  let t = @ui.Tester::new(
    fn(c) {
      ignore(tu.in_turn(c, "k", shown.val, close_turn_ms, seen=true))
      c.box(fn() {  }) |> ignore
    },
    w=100.0,
    h=100.0,
    platform=2,
  )
  t.draw()
  shown.val = false
  t.draw()
  assert_eq(tu.shown.get("k"), Some(false))
  assert_true(tu.started_at("k") >= 0.0)
}
