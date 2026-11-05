// 大屏 with keyboard and mouse: a chat opened from the chats' list, its composer has the cursor on the first frame that
// draws its field, asked as the chat comes in (composer_keyboard_node), not a frame on, once the field is laid out.

///|
test "大屏 by mouse: a chat opened from the list, its composer's field has the cursor on the first frame that draws it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  let home = t.semantics().filter(fn(s) { !s.hidden && s.role.to_string() == "TextField" }).map(fn(s) { s.label })
  // (each frame drawn as a row of the list is pressed and the chat comes in: the first that draws the composer's
  // field, whether it had the cursor)
  let seen : Ref[String?] = Ref(None)
  let had = Ref(false)
  t.each_frame(Some(fn() {
    if seen.val is Some(_) {
      return
    }
    let fields = t.semantics().filter(fn(s) { !s.hidden && "\{s.role}" == "TextField" && !home.contains(s.label) })
    if fields.length() > 0 {
      seen.val = Some(fields.map(fn(s) { "\{s.label} focused=\{s.focused}" }).join(", "))
      had.val = fields.iter().any(fn(s) { s.focused })
    }
  }))
  t.move(150.0, 800.0 * 0.3)
  t.press_at(150.0, 800.0 * 0.3)
  t.release(150.0, 800.0 * 0.3)
  t.run_for(@ui.move_most_ms * 2.0)
  t.each_frame(None)
  assert_true(seen.val is Some(_), msg="the chat's composer drawn")
  assert_true(had.val, msg="the first frame drawing the composer: \{seen.val}")
}
