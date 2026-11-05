// A complete chat value carries the same row changes as incremental core updates.

///|
test "joining messages in a replacement value changes only the affected row's version" {
  let before = ChatMessages::of_value(Some({ "messages": [
    { "seq": 1, "ts": "first", "text": "先看一下列表", "mine": true },
    { "seq": 2, "ts": "second", "text": "另外一行" },
  ] }))
  let first = before.row(0)
  let second = before.row(1)
  let after = ChatMessages::of_value(Some({ "messages": [
    { "seq": 2, "ts": "second", "text": "另外一行" },
    { "seq": 1, "ts": "first", "text": "先看一下列表", "mine": true, "followed": true },
  ] }), was=before)
  assert_true(after.row(1).message().followed)
  assert_true(shown_sign(Said(first)) != shown_sign(Said(after.row(1))),
    msg="removing the timestamp must tell the list that this row changed")
  assert_eq(after.row(0).version, second.version)
  assert_true(!first.message().followed)
  let again = ChatMessages::of_value(Some({ "messages": [
    { "seq": 2, "ts": "second", "text": "另外一行" },
    { "seq": 1, "ts": "first", "text": "先看一下列表", "mine": true, "followed": true },
  ] }), was=after)
  assert_eq(again.row(1).version, after.row(1).version)
}
