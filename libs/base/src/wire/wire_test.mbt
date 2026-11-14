// The bytes held to what the core's device mesh writes (client/core-ts/src/mesh.ts: `Control.send`, `Link.request`),
// each expectation the text JSON.stringify gives there; and an event stream read as the core in TypeScript read one
// (client/core-ts/test/sse.test.ts, whose stream and events these are, holds the same reader built for JavaScript).

///|
test "a control line is the credential, then what is said with it" {
  inspect(@wire.hello_line("t-alice"), content="{\"credential\":\"t-alice\"}\n")
  let says : Map[String, Json] = { "client": 7, "name": "a \"b\" \\ c\n\u{1}é/" }
  let also : Map[String, Json] = { "claim": { "k": [1, true, null] }, "client": 8 }
  inspect(
    @wire.hello_line("x", says~, also~, traceparent="00-ab-cd-01"),
    content="{\"credential\":\"x\",\"client\":8,\"name\":\"a \\\"b\\\" \\\\ c\\n\\u0001é/\",\"claim\":{\"k\":[1,true,null]},\"traceparent\":\"00-ab-cd-01\"}\n",
  )
}

///|
test "a request's head line" {
  inspect(@wire.head_line("GET", "/events?since=r1.4", []), content="{\"method\":\"GET\",\"path\":\"/events?since=r1.4\",\"headers\":{}}\n")
  inspect(
    @wire.head_line("POST", "/a", [("x-a", "1"), ("x-b", "two")], more={ "socket": true }),
    content="{\"method\":\"POST\",\"path\":\"/a\",\"headers\":{\"x-a\":\"1\",\"x-b\":\"two\"},\"socket\":true}\n",
  )
}

///|
test "lines come off what is carried, the rest stays" {
  let carry = @wire.Carry::new()
  carry.push(b"{\"status\":20")
  assert_true(carry.line() is None)
  carry.push(b"0}\nbody\nmore")
  assert_eq(carry.line(), Some("{\"status\":200}"))
  assert_eq(carry.length(), 9)
  assert_eq(carry.take(), b"body\nmore")
  assert_eq(carry.length(), 0)
}

///|
test "a reply's head" {
  guard @wire.reply_head("{\"status\":201,\"headers\":{\"content-type\":\"application/json\",\"n\":3}}") is Head(status, headers) else {
    fail("not read")
  }
  assert_eq(status, 201)
  assert_eq(headers, [("content-type", "application/json"), ("n", "3")])
  assert_true(@wire.reply_head("{\"status\":200}") is Head(200, []))
  assert_true(@wire.reply_head("{\"status\":\"200\"}") is NoStatus)
  assert_true(@wire.reply_head("{\"status\":70000}") is NoStatus)
  assert_true(@wire.reply_head("{\"status\":1.5}") is NoStatus)
  assert_true(@wire.reply_head("null") is NoStatus)
  assert_true(@wire.reply_head("{\"status\":") is Unreadable(_))
}

///|
test "events come as their blocks end, whatever the chunks" {
  let text = "id: r.0\n\nevent: message\r\nid: r.1\r\ndata: {\"n\":1}\r\n\r\nevent: missed\ndata: {}\n\ndata: a\ndata:b\n\n: a comment\n\nevent: late\ndata: x"
  let whole = @wire.Sse::new().feed(@utf8.encode(text))
  let expected : Array[@wire.Event] = [
    { name: "", data: "", id: Some("r.0") },
    { name: "message", data: "{\"n\":1}", id: Some("r.1") },
    { name: "missed", data: "{}", id: None },
    { name: "message", data: "a\nb", id: None },
  ]
  assert_true(whole == expected)
  // a byte at a time
  let sse = @wire.Sse::new()
  let one : Array[@wire.Event] = []
  for b in @utf8.encode(text) {
    one.append(sse.feed(Bytes::make(1, b)))
  }
  assert_true(one == expected)
  // what was begun ends with the chunk that ends it
  let ended = sse.feed(b"\n\n")
  assert_true(ended == [{ name: "late", data: "x", id: None }])
}

///|
/// The events of `stream` fed in the chunks `cuts` (byte offsets, ascending) cut it into.
fn fed(stream : Bytes, cuts : Array[Int]) -> Array[@wire.Event] {
  let sse = @wire.Sse::new()
  let out : Array[@wire.Event] = []
  let mut at = 0
  for cut in [..cuts, stream.length()] {
    out.append(sse.feed(stream[at:cut].to_owned()))
    at = cut
  }
  out
}

///|
/// The stream of the core's own test of its reader, and its events.
fn stream_and_events() -> (Bytes, Array[@wire.Event]) {
  let long = "长".repeat(3000)
  let stream = "event: entry\nid: 1f2e.1\ndata: {\"text\":\"整理发布清单\"}\n\n" + "data: one\ndata: two\n\n" +
    "id: 1f2e.2\n\n" + ": a comment\nevent: state\r\ndata:{\"busy\":true}\r\n\r\n" + "event: entry\nid: 1f2e.3\ndata: {\"text\":\"" +
    long +
    "\"}\n\n"
  let events : Array[@wire.Event] = [
    { name: "entry", data: "{\"text\":\"整理发布清单\"}", id: Some("1f2e.1") },
    { name: "message", data: "one\ntwo", id: None },
    { name: "", data: "", id: Some("1f2e.2") },
    { name: "state", data: "{\"busy\":true}", id: None },
    { name: "entry", data: "{\"text\":\"" + long + "\"}", id: Some("1f2e.3") },
  ]
  (@utf8.encode(stream), events)
}

///|
test "a stream cut anywhere is the same events: in a character, between a block's two newlines" {
  let (stream, events) = stream_and_events()
  assert_true(fed(stream, []) == events)
  assert_true(fed(stream, Array::makei(stream.length() - 1, i => i + 1)) == events)
  for at = 1; at < stream.length(); at = at + 7 {
    assert_true(fed(stream, [at]) == events)
  }
}

///|
test "a stream cut at random is the same events as it grows past what is kept and is moved in it" {
  let (once, events) = stream_and_events()
  let mut stream = once
  let want : Array[@wire.Event] = [..events]
  for _ in 0..<19 {
    stream = stream + once
    want.append(events)
  }
  let mut seed = 7
  for _ in 0..<30 {
    let cuts = []
    let mut at = 0
    while true {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff
      at = at + 1 + seed % 5000
      if at >= stream.length() {
        break
      }
      cuts.push(at)
    }
    assert_true(fed(stream, cuts) == want)
  }
}

///|
test "what is no whole block yet waits for the rest" {
  let sse = @wire.Sse::new()
  assert_true(sse.feed(b"event: entry\ndata: {") == [])
  assert_true(sse.feed(b"\"a\":1}\n") == [])
  assert_true(sse.feed(b"\n") == [{ name: "entry", data: "{\"a\":1}", id: None }])
  assert_true(sse.feed(b"") == [])
}

///|
test "a name and an id are said without what JavaScript's trim takes off, data as it came but one space" {
  // (as the core's reader in TypeScript: `line.slice(6).trim()`; MoonBit's own `trim` takes off four characters)
  let blank = "\u{0B}\u{0C}\u{A0}\u{1680}\u{2000}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}\t "
  let text = "event:" + blank + "a b" + blank + "\nid:" + blank + "7" + blank + "\ndata:  x \u{3000}\n\n"
  assert_true(
    @wire.Sse::new().feed(@utf8.encode(text)) == [{ name: "a b", data: " x \u{3000}", id: Some("7") }],
  )
  // what is no white space to JavaScript stays: a next line (U+0085), a zero width space, a Mongolian vowel separator
  let kept = "event: \u{85}a\u{200B}\u{180E}\ndata: 1\n\n"
  assert_true(
    @wire.Sse::new().feed(@utf8.encode(kept)) == [{ name: "\u{85}a\u{200B}\u{180E}", data: "1", id: None }],
  )
  // an id of white space alone is an id, empty
  assert_true(@wire.Sse::new().feed(b"id: \t\n\n") == [{ name: "", data: "", id: Some("") }])
}

///|
test "a byte order mark at a block's head is not of its text, further in it is" {
  // (as JavaScript's TextDecoder, which read each block there, takes one off: so the first line after it is read)
  let sse = @wire.Sse::new()
  assert_true(
    sse.feed(b"\xEF\xBB\xBFdata: a\n\n\xEF\xBB\xBFevent: e\ndata: b\n\n") ==
    [{ name: "message", data: "a", id: None }, { name: "e", data: "b", id: None }],
  )
  assert_true(sse.feed(b"data: \xEF\xBB\xBFc\n\xEF\xBB\xBFdata: d\n\n") == [{ name: "message", data: "\u{FEFF}c", id: None }])
}

///|
test "bytes that are no UTF-8 are read as U+FFFD, one for each run that could have begun a character" {
  // (the WHATWG's decoding, which the core's reader in TypeScript had of TextDecoder)
  let sse = @wire.Sse::new()
  assert_true(
    sse.feed(b"data: \x80|\xE6\x95|\xF0\x9F\x98|\xC0\xAF|\xED\xA0\x80|\xFF\n\n") ==
    [{ name: "message", data: "\u{FFFD}|\u{FFFD}|\u{FFFD}|\u{FFFD}\u{FFFD}|\u{FFFD}\u{FFFD}\u{FFFD}|\u{FFFD}", id: None }],
  )
}

///|
test "a CR is dropped wherever it is, and a field no line begins with is no field" {
  let sse = @wire.Sse::new()
  assert_true(
    sse.feed(b"da\rta: a\rb\r\n\r\nretry: 3\ndata\n data: x\nevent\n\n\n\ndata:\n\n") ==
    [{ name: "message", data: "ab", id: None }, { name: "message", data: "", id: None }],
  )
}
