///|
test "emission waits for explicit picture requests, not incidental cached pictures" {
  let lines : Array[String] = []
  script.val = Some(lines)
  emit_answered(["picture", "chat.pin"])
  assert_eq(lines, ["answered chat.pin"])
  emit_answered_to("picture", 1)
  assert_eq(lines, ["answered chat.pin", "answered picture"])
  script.val = None
}

///|
test "emission waits for explicit machine session requests, not cached offers" {
  let lines : Array[String] = []
  script.val = Some(lines)
  emit_answered(["machineSessions.list", "chat.pin"])
  assert_eq(lines, ["answered chat.pin"])
  emit_answered_to("machineSessions.list", 1)
  assert_eq(lines, ["answered chat.pin", "answered machineSessions.list"])
  script.val = None
}

///|
test "emission waits for an explicit chat place report, not incidental frame reports" {
  let lines : Array[String] = []
  script.val = Some(lines)
  emit_answered(["chat.place", "chat.pin", "chat.place"])
  assert_eq(lines, ["answered chat.pin"])
  emit_answered_to("chat.place", 1)
  assert_eq(lines, ["answered chat.pin", "answered chat.place"])
  let next : Array[String] = []
  script.val = Some(next)
  emit_wait(125.0)
  emit_answered(["chat.place"])
  emit("until result")
  assert_eq(next, ["wait 125", "now until result"])
  script.val = None
}

///|
test "emission waits for an explicit drive place report, not periodic player reports" {
  let lines : Array[String] = []
  script.val = Some(lines)
  emit_answered(["drive.place", "drive.read", "drive.place"])
  assert_eq(lines, ["answered drive.read"])
  emit_answered_to("drive.place", 1)
  assert_eq(lines, ["answered drive.read", "answered drive.place"])
  script.val = None
}

///|
test "a recording script is complete only after the flow ends" {
  let lines : Array[String] = []
  script.val = Some(lines)
  emit("tap action")
  assert_eq(lines, ["tap action"])
  emit_end()
  assert_eq(lines, ["tap action", "# flow complete"])
  assert_true(script.val is None)
}

///|
test "incidental host calls are scoped to the steps that need them" {
  let lines : Array[String] = []
  script.val = Some(lines)
  incidental_calls.val = ["drive.read"]
  emit_answered(["drive.read", "drive.browse"])
  assert_eq(lines, ["answered drive.browse"])
  emit_answered_to("drive.read", 1)
  assert_eq(lines, ["answered drive.browse", "answered drive.read"])
  incidental_calls.val = []
  emit_answered(["drive.read"])
  assert_eq(lines, ["answered drive.browse", "answered drive.read", "answered drive.read"])
  script.val = None
}
