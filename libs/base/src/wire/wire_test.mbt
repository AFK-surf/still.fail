// The bytes held to what the core's device mesh writes (client/core-ts/src/mesh.ts: `Control.send`, `Link.request`),
// each expectation the text JSON.stringify gives there.

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
