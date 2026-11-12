// What topic_bytes counts of a subscription let go of keeping its value (`keep`) and asked again with its version.

///|
test "kept as let go of: what comes before the core's version is not for what was let go of, a same is no value" {
  let lines = [
    "{\"out\":{\"id\":1,\"subscribe\":{\"topic\":\"stations\",\"scope\":\"ws\"},\"keyed\":true}}",
    "{\"in\":{\"id\":1,\"value\":[1]}}",
    "{\"out\":{\"id\":1,\"unsubscribe\":true,\"keep\":true}}",
    "{\"in\":{\"id\":1,\"delta\":[{\"path\":[],\"set\":[2]}]}}",
    "{\"in\":{\"id\":1,\"v\":\"k:1\"}}",
    "{\"out\":{\"id\":2,\"subscribe\":{\"topic\":\"stations\",\"scope\":\"ws\"},\"keyed\":true,\"have\":\"k:1\"}}",
    "{\"in\":{\"id\":2,\"same\":true}}",
    "{\"out\":{\"id\":2,\"unsubscribe\":true}}",
    "{\"in\":{\"id\":2,\"delta\":[{\"path\":[],\"set\":[3]}]}}",
  ]
  let got = tape_topics(lines.join("\n"))
  // (one value whole, none again; only the delta after a let go of without keep is for what was let go of)
  assert_eq((got.again, got.unheld), (0, 1))
}

///|
test "kept as let go of and asked again: what changed from what was kept is no value sent whole, nor one again" {
  let lines = [
    "{\"out\":{\"id\":1,\"subscribe\":{\"topic\":\"chat\",\"station\":\"ws/a\",\"session\":\"s\"},\"keyed\":true}}",
    "{\"in\":{\"id\":1,\"value\":{\"n\":1}}}",
    "{\"out\":{\"id\":1,\"unsubscribe\":true,\"keep\":true}}",
    "{\"in\":{\"id\":1,\"v\":\"k:1\"}}",
    "{\"out\":{\"id\":2,\"subscribe\":{\"topic\":\"chat\",\"station\":\"ws/a\",\"session\":\"s\"},\"keyed\":true,\"have\":\"k:1\"}}",
    "{\"in\":{\"id\":2,\"delta\":[{\"path\":[\"n\"],\"set\":2}],\"kept\":true}}",
  ]
  let got = tape_topics(lines.join("\n"))
  // (the one value whole of the run, counted once; the kept one's difference a delta as any)
  assert_eq((got.again, got.unheld, got.topics.get("chat")), (0, 0, Some(1)))
}
