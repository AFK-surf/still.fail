// The page on top followed as the stack is told it (switch.mbt page_switch_said): one change told whole once, what it
// ends at alone; two told apart each, no frame drawn between them; a new chat left for a chat leaves nothing behind.

///|
/// The chat a new chat is left for here.
fn switch_chat() -> Page {
  Chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
}

///|
/// A window's tree following the page on top (page_switch_said), the stack at the chat; what fresh_reset puts back
/// marked (the new chat's room 5) so that it is seen whether it was done.
fn switch_said_tester() -> @ui.Tester {
  @sfbase.reset()
  page_switch_reset()
  fresh_reset()
  app.nav.push(switch_chat())
  let t = @ui.Tester::new(fn(_c) {  }, tree=fn(root) { page_switch_said(root, fn() { true }) }, w=1280.0, h=800.0)
  t.draw()
  fresh.room.set(5.0)
  fresh.foot.set(5.0)
  t
}

///|
test "the page on top told whole: a new chat put on and taken off in one change seen as the chat it ends at, nothing of a switch done" {
  let t = switch_said_tester()
  @signals.start_batch()
  app.nav.push(NewChat)
  app.nav.pop() |> ignore
  @signals.end_batch()
  t.draw()
  assert_true(page_switch.was == Some(switch_chat()))
  // (no new chat come to: nothing put back)
  assert_eq((fresh.room.get(), fresh.foot.get()), (5.0, 5.0))
}

///|
test "the page on top told apart: a new chat come to, then left for the chat, no frame between: each done, nothing of the new chat set going" {
  let t = switch_said_tester()
  app.nav.push(NewChat)
  // (come to: put back as its page begins)
  assert_true(page_switch.was == Some(NewChat))
  assert_eq(fresh.room.get(), 0.0)
  fresh.room.set(5.0)
  app.nav.pop() |> ignore
  // (left for another chat: gone at once, nothing of it set leaving over the chat)
  assert_true(page_switch.was == Some(switch_chat()))
  assert_eq(fresh.room.get(), 5.0)
  t.draw()
}

///|
test "the page on top: a new chat become its chat in place (its words sent) no switch of the new chat left" {
  let t = switch_said_tester()
  app.nav.push(NewChat)
  fresh.room.set(7.0)
  // (as the new chat's words are sent: became said first, the page become the chat after)
  fresh.became.set(Some({ station: "ws1/st1", session: "s-new", title: "", station_name: "Willow" }))
  app.nav.become(Chat({ station: "ws1/st1", session: "s-new", title: "", station_name: "Willow" }))
  assert_eq(fresh.room.get(), 7.0)
  t.draw()
}
