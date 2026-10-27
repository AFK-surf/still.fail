///|
test "a chat asked for here is its row's before and after its station makes it (its clientKey)" {
  let r : ChatRef = { station: "ws1/st1", session: "new:chat-1", title: "新对话", station_name: "Studio" }
  let asked = chat_item({ "id": "new:chat-1", "session": "new:chat-1", "station": "ws1/st1" })
  let made = chat_item({ "id": "c20", "session": "s-c20", "clientKey": "new:chat-1", "station": "ws1/st1" })
  let other = chat_item({ "id": "c21", "session": "s-c21", "station": "ws1/st1" })
  let elsewhere = chat_item({ "id": "c20", "session": "s-c20", "clientKey": "new:chat-1", "station": "ws1/st2" })
  assert_true(row_is(asked, r))
  assert_true(row_is(made, r))
  assert_false(row_is(other, r))
  assert_false(row_is(elsewhere, r))
  assert_true(row_is(made, { ..r, session: "s-c20" }))
  assert_true(row_is(made, { ..r, session: "c20" }))
  assert_false(row_is(other, { ..r, session: "" }))
}
