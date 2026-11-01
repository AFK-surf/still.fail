///|
test "the fixture sends each quote's own file as the core does" {
  @sffixture.fixture_reset()
  let src = @sffixture.fixture("chat")
  let key = "ws1/st1:s-c1"
  (src.call)("composer.quote", {
    "key": Json::string(key), "id": "q1", "fileId": "f1",
    "quote": { "author": "Ana", "text": "first", "comment": "  note  " },
    "attachment": { "name": "first.png", "path": "/first.png", "size": 12 },
  }, fn(_) {  })
  (src.call)("composer.quote", {
    "key": Json::string(key), "id": "q2", "fileId": "f2",
    "quote": { "author": "Ana", "text": "second" },
    "attachment": { "name": "second.png", "path": "/second.png", "size": 34 },
  }, fn(_) {  })
  (src.call)("composer.quote", {
    "key": Json::string(key), "id": "q3", "quote": { "author": "Ana", "text": "words only" },
  }, fn(_) {  })
  (src.call)("composer.quote", {
    "key": Json::string(key), "id": "q4", "fileId": "f4",
    "quote": { "author": "Ana", "text": "first again" },
    "attachment": { "name": "first.png", "path": "/first.png", "size": 12 },
  }, fn(_) {  })
  let answer : Ref[Result[Json, Json]?] = Ref(None)
  (src.call)("composer.take", { "key": Json::string(key) }, fn(r) { answer.val = Some(r) })
  let sent = match answer.val {
    Some(Ok(v)) => Some(v)
    _ => fail("the fixture did not take the draft")
  }
  let quotes = items(sent, "quotes")
  assert_eq(quotes.length(), 4)
  assert_eq(text(Some(quotes[0]), "file"), "first.png")
  assert_eq(text(Some(quotes[1]), "file"), "second.png")
  assert_true(field(Some(quotes[2]), "file") is None)
  assert_eq(text(Some(quotes[3]), "file"), "first.png")
  assert_eq(items(sent, "attachments").length(), 2)
  assert_eq(text(Some(quotes[0]), "comment"), "note")
  assert_true(field(Some(quotes[0]), "id") is None)
}
