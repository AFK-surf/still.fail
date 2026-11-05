///|
test "full values preserve versions by key and tell content changes after patches" {
  let rows = @rows.TopicList::new(["items"], ["id"], Some({ "items": [
    { "id": "a", "text": "before" }, { "id": "b", "text": "kept" },
  ] }))
  rows.take({ "path": ["items"], "key": ["id"], "put": { "id": "a", "text": "patched" } }) |> ignore
  assert_eq(rows.version(0), 1)
  rows.given(Some({ "items": [
    { "id": "b", "text": "kept" }, { "id": "a", "text": "replaced" },
  ] }))
  assert_eq(rows.version(0), 0)
  assert_eq(rows.version(1), 2)
  let copy = @rows.TopicList::new(["items"], ["id"], Some({ "items": [
    { "id": "a", "text": "replaced" }, { "id": "b", "text": "changed" },
  ] }), was=rows)
  assert_eq(copy.version(0), 2)
  assert_eq(copy.version(1), 1)
  assert_eq(rows.value(0), { "id": "b", "text": "kept" })
  assert_eq(rows.version(0), 0)
}
