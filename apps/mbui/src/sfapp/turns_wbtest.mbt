// What changes a chat's list's height waits for nothing (mbui's view/list_motion.mbt): a row comes, what is under a
// post changes, the moment it does, together; each one's room goes to its new height from then (Ctx::row_size).

///|
test "turns: rows coming and what changes under a post go the moment they are asked, together, none waiting" {
  new_run()
  let tu = turns_of("test")
  let phase = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      tu.step(c)
      match phase.val {
        0 => {
          ignore(tu.in_turn(c, "k", false))
          phase.val = 1
        }
        1 => {
          ignore(tu.in_turn(c, "k", true))
          tu.admit(c, "a")
          tu.admit(c, "b")
          phase.val = 2
        }
        _ => ignore(tu.in_turn(c, "k", true))
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
  let at = tu.started_at("k")
  assert_true(at >= 0.0)
  assert_eq(tu.started_at("a"), at)
  assert_eq(tu.started_at("b"), at)
  t.assert_idle()
}

///|
test "turns: what goes from under a post on screen goes at once, as out of sight (no frame of the list's says which)" {
  new_run()
  let tu = turns_of("test")
  let shown = Ref(true)
  let t = @ui.Tester::new(
    fn(c) {
      ignore(tu.in_turn(c, "k", shown.val))
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
