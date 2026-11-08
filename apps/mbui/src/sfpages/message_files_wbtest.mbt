///|
test "a staged file flies to its message after the station moves it" {
  let staged = "/station/uploads/2026-11-08-12-00-00-123abc-report.txt"
  let sent = "/station/session/uploads/2026-11-08-12-00-00-123abc-report.txt"
  assert_eq(file_flight_key(sent, [sent], [staged]), staged)
  assert_eq(file_flight_key(staged, [staged], [staged]), staged)
  // Windows stations keep the same name when they move it too.
  let win_staged = "C:\\station\\uploads\\2026-11-08-12-00-00-123abc-report.txt"
  let win_sent = "C:\\station\\session\\uploads\\2026-11-08-12-00-00-123abc-report.txt"
  assert_eq(file_flight_key(win_sent, [win_sent], [win_staged]), win_staged)
}

///|
test "a file flight does not guess when the stored name is ambiguous or outside uploads" {
  let staged = "/station/uploads/unique-report.txt"
  let sent = "/station/session/uploads/unique-report.txt"
  let another = "/other/uploads/unique-report.txt"
  assert_eq(file_flight_key(sent, [sent], [staged, another]), sent)
  assert_eq(file_flight_key(sent, [sent, another], [staged]), sent)
  assert_eq(file_flight_key("/other/unique-report.txt", ["/other/unique-report.txt"], [staged]), "/other/unique-report.txt")
  assert_eq(file_flight_key(sent, [sent], ["upload:unique-report.txt"]), sent)
  assert_eq(file_flight_key(sent, [sent], ["quote:0"]), sent)
}
