///|
test "no engine on the web: start says so" {
  assert_false(@core.start())
  assert_true(@core.fatal() is None)
}
