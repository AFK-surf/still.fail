///|
test "no engine given by the page: start says so" {
  assert_false(@core.start())
  assert_true(@core.fatal() is None)
}
