// What a record keeps of a site's page's requests (hostcall.mbt site_event_kept): no credential's value.

///|
test "a site's request on a run's record: its credentials' headers and query fields kept as \"-\", the rest as said" {
  let e = "{\"req\":3,\"method\":\"GET\",\"path\":\"/api/x?id=4&access_token=abc123&page=2\",\"page\":false," +
    "\"headers\":[[\"Authorization\",\"Bearer s3cret\"],[\"Cookie\",\"sid=xyz\"],[\"X-Api-Key\",\"k-777\"]," +
    "[\"User-Agent\",\"WebKit\"],[\"Accept\",\"*/*\"]]}"
  let kept = site_event_kept(e).stringify()
  for v in ["s3cret", "xyz", "k-777", "abc123"] {
    assert_false(kept.contains(v), msg=kept)
  }
  for v in ["User-Agent", "WebKit", "*/*", "id=4", "page=2", "access_token=-", "/api/x"] {
    assert_true(kept.contains(v), msg=kept)
  }
  // (what is not an event's JSON: nothing of it)
  assert_eq(site_event_kept("not json Bearer x").stringify(), "\"-\"")
}

///|
test "a site's request's body on a run's record: a JSON object's or a form's credential fields \"-\"" {
  let as_text = fn(b : Bytes) { String::from_array(Array::makei(b.length(), fn(i) { b[i].to_int().unsafe_to_char() })) }
  let json = as_text(site_body_kept(b"{\"name\":\"svc\",\"password\":\"hunter2\",\"opts\":{\"api_key\":\"k9\"}}"))
  assert_false(json.contains("hunter2") || json.contains("k9"), msg=json)
  assert_true(json.contains("svc"), msg=json)
  let form = as_text(site_body_kept(b"user=al&session_id=zz9&x=1"))
  assert_eq(form, "user=al&session_id=-&x=1")
  // (what names none: as it was, to the byte)
  assert_eq(site_body_kept(b"plain words"), b"plain words")
}
