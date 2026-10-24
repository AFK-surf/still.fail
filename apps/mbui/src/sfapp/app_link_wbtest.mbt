///|
test "still.fail's desktop app's links, as the cloud's pages" {
  assert_eq(app_link("stillfail://o/ws1/st1/chat1?service=web"), "https://app.still.fail/o/ws1/st1/chat1?service=web")
  assert_eq(app_link("ember://o/ws1/st1/chat1"), "https://app.still.fail/o/ws1/st1/chat1")
  assert_eq(app_link("stillfail-beta://o/ws1/st1/chat1"), "https://app.still.fail/o/ws1/st1/chat1")
  assert_eq(app_link("https://app.still.fail/w/a/s/b/chats/c"), "https://app.still.fail/w/a/s/b/chats/c")
}
