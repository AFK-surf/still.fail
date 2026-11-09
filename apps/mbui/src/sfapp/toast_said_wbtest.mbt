// What a write says (toast_later) as the window's toast: each saying its own toast, what its action does its own; one
// said again with no frame between the last said, the one before never shown; one going out as another is said
// touching nothing of the new one's.

///|
/// The home fixture 390 by 844 to touch, its first pages in.
fn said_tester() -> @ui.Tester {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=390.0, h=844.0, platform=2)
  t.draw()
  t
}

///|
/// Toast `words`'s action (撤销) pressed where it is read out; whether there was one.
fn press_undo(t : @ui.Tester) -> Bool {
  match t.query(Button, label="撤销") {
    Some(b) => {
      let (x, y, w, h) = b.rect
      t.tap(x + w / 2.0, y + h / 2.0)
      true
    }
    None => false
  }
}

///|
test "the same words said twice with their 撤销, no frame between: one toast, the second's; its 撤销 does the second's once, the first's never" {
  let t = said_tester()
  let first = Ref(0)
  let second = Ref(0)
  @sfbase.toast_later("已归档「夜里的构建又失败了」", action="撤销", run=fn() { first.val = first.val + 1 })
  @sfbase.toast_later("已归档「夜里的构建又失败了」", action="撤销", run=fn() { second.val = second.val + 1 })
  t.frame()
  t.run_for(@kit.presence_in_ms)
  let shown = t.all(Status, label="已归档「夜里的构建又失败了」").length()
  let pressed = press_undo(t)
  t.run_for(@kit.presence_out_ms)
  let again = press_undo(t)
  t.run_for(@sf.toast_action_ms)
  assert_eq((shown, pressed, again, first.val, second.val), (1, true, false, 0, 1))
}

///|
test "a toast said as the one before it would time out: the one before goes, the new one stays past that time, its 撤销 its own" {
  let t = said_tester()
  let first = Ref(0)
  let second = Ref(0)
  let from = t.time()
  @sfbase.toast_later("已归档「夜里的构建又失败了」", action="撤销", run=fn() { first.val = first.val + 1 })
  t.frame()
  t.run_for(@sf.toast_action_ms - 50.0)
  @sfbase.toast_later("已归档「收集视频」", action="撤销", run=fn() { second.val = second.val + 1 })
  t.frame()
  // (past when the one before would have gone, and its way out)
  t.run_for(from + @sf.toast_action_ms + @kit.presence_out_ms + 50.0 - t.time())
  let stays = (
    t.query(Status, label="已归档「收集视频」") is Some(_),
    t.query(Status, label="已归档「夜里的构建又失败了」") is None,
    app.toast.get().words,
  )
  let pressed = press_undo(t)
  t.run_for(@kit.presence_out_ms)
  assert_eq((stays, pressed, first.val, second.val), ((true, true, "已归档「收集视频」"), true, 0, 1))
}

///|
/// Whether a toast saying `words` is said (read out: the window's toast's Status), from the frame it is said in on. Its
/// first frame draws it at none of its opacity, as the old view's toast did (its words' alpha 0 then, found by
/// Tester::find all the same, which finds the window's tree's words only where they are seen): seen as it has come in.
fn toast_said(t : @ui.Tester, words : String) -> Bool {
  t.query(Status, label=words) is Some(_)
}

///|
test "a toast held and moved across slowly: its 撤销 where it is drawn, pressed there, read out there; back as it is let go" {
  let t = said_tester()
  @sfbase.toast_later("已归档「夜里的构建又失败了」", action="撤销")
  t.frame()
  t.run_for(@kit.presence_in_ms)
  let at_rest = t.query(Button, label="撤销").unwrap().rect
  let (x, y, _, h) = t.query(Status, label="已归档「夜里的构建又失败了」").unwrap().rect
  // (slowly: a point a move, a finger's moves apart; less than a third of it, so that it comes back as it is let go)
  t.hold_drag(x + 10.0, y + h / 2.0, x + 10.0 + toast_held_by, y + h / 2.0, steps=toast_held_by.to_int())
  let held = t.query(Button, label="撤销").unwrap().rect
  // (pressed where it is drawn now: past its end as it rests, inside it as it is moved)
  let tree = @ui.view_tree().unwrap()
  let button = tree.said_order().iter().find_first(fn(sn) { sn.said.map(fn(s) { s.role == Button && s.label == "撤销" }).unwrap_or(false) }).map(fn(sn) { sn.id })
  let past = at_rest.0 + at_rest.2 + toast_held_by / 2.0
  let pressed = match button {
    Some(id) => tree.target_at(past, at_rest.1 + at_rest.3 / 2.0) == Pressed(id)
    None => false
  }
  t.release(x + 10.0 + toast_held_by, y + h / 2.0)
  let back = t.query(Button, label="撤销").unwrap().rect
  assert_eq((held.0 - at_rest.0, pressed, back == at_rest, t.query(Status, label="已归档「夜里的构建又失败了」") is Some(_)), (toast_held_by, true, true, true), msg="\{at_rest} \{held} \{back}")
}

///|
/// How far across a toast is held (points): less than a third of it, so that it comes back as it is let go.
let toast_held_by : Double = 30.0

///|
test "a toast with its 撤销 coming in: its 撤销's ground faded as the toast's ground is, not as its words are" {
  let t = said_tester()
  @sfbase.toast_later("已归档「夜里的构建又失败了」", action="撤销")
  t.frame()
  // (on its way in, its ground whole before its words: toast_look's)
  t.run_for(@kit.presence_in_ms / 4.0)
  let near = fn(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) {
    (a.0 - b.0).abs() < 0.5 && (a.1 - b.1).abs() < 0.5 && (a.2 - b.2).abs() < 0.5 && (a.3 - b.3).abs() < 0.5
  }
  let alpha_of = fn(r : (Double, Double, Double, Double)) {
    t.drawn_rects().iter().find_first(fn(d) { near((d.0, d.1, d.2, d.3), r) }).map(fn(d) { (d.4 & 0xFFL).to_int() })
  }
  // (its capsule: as wide and tall as it is read out, where it is drawn on its way up)
  let (sx, _, sw, sh) = t.query(Status, label="已归档「夜里的构建又失败了」").unwrap().rect
  let toast = t.drawn_rects().iter().find_first(fn(d) { (d.0 - sx).abs() < 0.5 && (d.2 - sw).abs() < 0.5 && (d.3 - sh).abs() < 0.5 }).map(fn(d) { (d.4 & 0xFFL).to_int() })
  let undo = alpha_of(t.query(Button, label="撤销").unwrap().rect)
  // (its capsule's ground the toast's ink at 15%, as the toast's ground is: toast_button's)
  let as_faded = match (toast, undo) {
    (Some(g), Some(u)) => (u.to_double() - g.to_double() * 0.15).abs() <= 1.0
    _ => false
  }
  assert_true(as_faded, msg="\{toast} \{undo}")
}
