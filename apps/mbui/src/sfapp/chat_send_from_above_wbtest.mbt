// A chat's page made with its inside nodes (sfbase's chat_page_nodes on), read above its end, its rows on the host's
// pixels: words sent take the list back to its foot (chat_body_node's sent_here_count: ListPlace::to_end), which ends
// at its foot as its foot is when it gets there (the sent row measured taller than counted, the composer shrunk), never
// short of it (the coordinator of the migration, 2026-11-14: 50.9 short, the sent words never seen). A go-to: in the
// press's frame the list stands at its foot, the sent words' bubble flying in as at its foot, no glide beside the
// flight (the coordinator of the migration, 2026-11-15; till then it glided there from the frame after); then, every
// frame a host draws, it goes down only, to rest with the sent row's foot on the pinned foot's top, at its foot; the
// answer that comes after followed there. On 小屏 and 大屏.

///|
/// The words sent: enough to take several lines, so the row they are sent in comes out taller than the list counts it
/// and the composer, grown with them, shrinks as it is emptied.
let csa_words : String = "从上面发的这几句话要长一些，长到在输入框里折成好几行，发出去以后这一条消息也比列表先估计的高，输入框随后变矮。"

///|
/// The screens: name, width, height, platform.
let csa_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)]

///|
/// The fixture's station's pace (fix_pace's): what is sent delivered (its agent's line coming under it) only after the
/// list has come to rest, its answer soon after.
let csa_pace : (Double, Double, Double) = (3000.0, 500.0, 300.0)

///|
/// How long after the press the list is looked at before the delivery, and how long after the answer.
let csa_rest_ms : Double = 2500.0

///|
let csa_after_ms : Double = 1500.0

///|
/// The fixture's chat with its page's inside nodes on `screen`, its rows on the host's pixels, at rest at its end.
fn csa_open(screen : (String, Double, Double, Int)) -> @ui.Tester {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  fix_pace.val = csa_pace
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.set_rows_on_pixels(true)
  nav_rested(t)
  files_page_over(t, w, h)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What is seen of the chat's list (the page's list under the composer's field): how far it is scrolled, whether it is at its foot, where its last row in sight ends, and where its pinned foot's top is drawn.
priv struct CsaList {
  at : Double
  at_foot : Bool
  last_foot : Double
  foot_top : Double
  count : Int
}

///|
fn csa_list(t : @ui.Tester, at : String) -> CsaList {
  guard composer_field(t) is Some((fx, _, fw, _)) else { @halt.saying("\{at}: no composer's field") }
  let cx = fx + fw / 2.0
  for l in @ui.view_tree().unwrap().lists_seen() {
    guard l.rows.iter().any(fn(r) { r.2.0 <= cx && cx <= r.2.0 + r.2.2 }) else { continue }
    guard l.rows.last() is Some(last) else { continue }
    return { at: l.at, at_foot: l.at_foot, last_foot: last.2.1 + last.2.3, foot_top: l.foot_top, count: l.count }
  }
  @halt.saying("\{at}: no list under the composer")
}

///|
/// How far the list's pinned foot's top is under where its last row in sight ends.
fn csa_gap(t : @ui.Tester, at : String) -> Double {
  let l = csa_list(t, at)
  l.foot_top - l.last_foot
}

///|
/// Half a pixel of the host's, in points.
fn csa_half_px() -> Double {
  0.5 / @ui.view_tree().unwrap().rows_grid_now()
}

///|
/// Read up from its end by the wheel, at rest there.
fn csa_read_up(t : @ui.Tester, screen : (String, Double, Double, Int)) -> Unit {
  let (_, w, h, _) = screen
  t.move_to(w / 2.0, h / 2.0)
  t.wheel(w / 2.0, h / 2.0, -500.0)
  t.run_for(@ui.move_most_ms + 300.0)
}

///|
/// Sent (`send`) read above the end on `screen`: in the press's frame at its foot (a go-to);
/// every frame a host draws to csa_rest_ms after it down only, at rest at its foot with its last row (the sent one) on the
/// pinned foot's top; the answer come after followed there.
fn csa_sent_lands(t : @ui.Tester, name : String, send : () -> Unit) -> Unit raise {
  let before = csa_list(t, name)
  assert_false(before.at_foot, msg="\{name}: at its end before sending")
  send()
  let pressed = csa_list(t, name)
  assert_true(pressed.at_foot, msg="\{name}: not at its end in the press's frame (at \{pressed.at})")
  let seen : Array[CsaList] = []
  t.each_frame(Some(fn() { seen.push(csa_list(t, name)) }))
  t.run_shown(csa_rest_ms)
  t.each_frame(None)
  let mut was = pressed.at
  for i, s in seen {
    assert_true(s.at >= was - 0.01, msg="\{name}, frame \{i}: up again, \{was} to \{s.at}")
    was = s.at
  }
  let rest = csa_list(t, name)
  assert_true(rest.count > before.count, msg="\{name}: nothing sent (\{before.count} keys before, \{rest.count} at rest)")
  assert_true(rest.at_foot, msg="\{name}: not at its foot at rest (at \{rest.at})")
  let gap = csa_gap(t, name)
  assert_true(
    gap.abs() <= csa_half_px(),
    msg="\{name}: the sent row's foot \{gap} over the pinned foot's top at rest",
  )
  // (delivered, its line come, its answer after: followed at its foot; its turn over after the answer, its line gone
  // leaving its room under the answer, list_foot_room_test's rule: the answer over the pinned foot, never under it)
  let (deliver, answer, end) = csa_pace
  t.run_for(deliver + answer + end + csa_after_ms - csa_rest_ms)
  let after = csa_list(t, name)
  assert_true(after.at_foot, msg="\{name}: not at its foot after the answer")
  assert_true(after.count > rest.count, msg="\{name}: no answer come (\{rest.count} keys at rest, \{after.count} after)")
  let gap = csa_gap(t, name)
  assert_true(gap >= -csa_half_px(), msg="\{name}: the answer's foot \{-gap} under the pinned foot's top")
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏, read above its end: words sent take it down only to its foot, the sent words' row on the composer's top, the answer followed" {
  for screen in csa_screens {
    let name = screen.0
    let t = csa_open(screen)
    assert_true(csa_list(t, name).at_foot, msg="\{name}: not at its end as it opened")
    csa_read_up(t, screen)
    guard composer_field(t) is Some((fx, fy, fw, fh)) else { fail("\{name}: no composer's field") }
    t.tap(fx + fw / 2.0, fy + fh / 2.0)
    t.type_text(csa_words)
    t.run_for(@ui.move_most_ms)
    csa_sent_lands(t, name, fn() { tap_send(t) })
  }
}

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the list held by a tall answer's top (ListPlace::follow_from standing), words sent: down only to its foot, at rest there, the next message followed" {
  for screen in rp_screens {
    let name = screen.0
    let (t, clock, _) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
    let held = csa_list(t, name)
    assert_false(held.at_foot, msg="\{name}: at its foot, the answer's top not holding it")
    let seen : Array[CsaList] = []
    t.each_frame(Some(fn() { seen.push(csa_list(t, name)) }))
    rp_send(t, "收到，我先看")
    t.run_shown(rp_rest_ms)
    t.each_frame(None)
    let mut was = held.at
    for i, s in seen {
      assert_true(s.at >= was - 0.01, msg="\{name}, frame \{i}: up again, \{was} to \{s.at}")
      was = s.at
    }
    let rest = csa_list(t, name)
    assert_true(rest.at_foot, msg="\{name}: not at its foot at rest (at \{rest.at})")
    let gap = csa_gap(t, name)
    assert_true(gap.abs() <= csa_half_px(), msg="\{name}: its last row's foot \{gap} over the pinned foot's top at rest")
    // (the limit gone: the next message followed at its foot)
    let _ = rp_frames(t, clock, fn() { rp_said(171, rp_next) }, rp_next, rp_rest_ms)
    let after = csa_list(t, name)
    assert_true(after.at_foot && t.drawn_of(rp_next) is Some(_), msg="\{name}: the next message not followed (at \{after.at})")
  }
  fix_clock.val = None
}

///|
/// The first words of a second tall answer, come after words sent took the list to its foot.
let csa_second : String = "第二个回答从这里读起"

///|
test "a chat's page made with its inside nodes, on 小屏 and 大屏: the list held by a tall answer's top, words sent: at rest at its foot, then a tall answer comes: held by its top" {
  for screen in rp_screens {
    let name = screen.0
    let (t, clock, _) = rp_answer(screen, long_reply + "\n\n" + rp_paras(30), "work")
    rp_send(t, "收到，我先看")
    fix_clock_set(clock, clock.val + fix_deliver_ms)
    t.draw()
    t.run_for(rp_rest_ms)
    let rest = csa_list(t, name)
    assert_true(rest.at_foot, msg="\{name}: not at its foot at rest after the send (at \{rest.at})")
    // (at its foot by the glide the send asked: the answer followed no further than its top a margin under the bar)
    let ys = rp_frames(t, clock, fn() { rp_said(190, csa_second + "\n\n" + long_reply + "\n\n" + rp_paras(30)) }, csa_second, rp_rest_ms)
    let (wrong, at) = rp_never_over(name, ys)
    if wrong is Some(w) {
      fail("\{name}: \{w}")
    }
    assert_true((at - rp_held_at(name)).abs() < rp_half_px, msg="\{name}: its words rest at \{at}")
    let held = csa_list(t, name)
    assert_false(held.at_foot, msg="\{name}: at its foot, the answer's top not holding it (at \{held.at})")
  }
  fix_clock.val = None
}
