///|
test "a draft's workspace: its station's, or a new chat's own" {
  assert_eq(draft_workspace("ws1/st1:ember:c-4e57ffe156"), "ws1")
  assert_eq(draft_workspace("ws1/st1:s-c1"), "ws1")
  assert_eq(draft_workspace("new:ws1"), "ws1")
}
