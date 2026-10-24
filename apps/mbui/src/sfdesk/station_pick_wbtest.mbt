///|
test "a draft's station: its key's before the chat (whose own key may hold a ':'), or a new chat's" {
  assert_eq(draft_station("ws1/st1:ember:c-4e57ffe156"), "ws1/st1")
  assert_eq(draft_station("ws1/st1:s-c1"), "ws1/st1")
  assert_eq(draft_station("new:ws1/st1"), "ws1/st1")
}
