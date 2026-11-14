// The bytes held to what the core's device mesh writes (client/core-ts/src/mesh.ts: `Control.send`, `Link.request`),
// each expectation the text JSON.stringify gives there; and an event stream read as the core in TypeScript reads one
// (client/core-ts/test/sse.test.ts, whose stream and events these are, holds that reader; sse_made_test.mbt holds
// this one to it case by case).

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
test "a request's head line with what each kind of request says after its headers, as the device mesh in TypeScript writes each" {
  // Each expectation is what Node printed for that mesh's own expression of the head (client/core-ts/src/mesh.ts:
  // `Link.request` 576, `ask` 622, `socket` 585, `duplex` 591, each written by `#open` as JSON.stringify and a
  // newline, 514), run on these heads 2026-11-14.
  // A request: a header said twice keeps its first place and takes the later value (Object.fromEntries).
  inspect(
    @wire.head_line("PUT", "/files/a b?x=1&y=é", [("content-type", "text/plain"), ("x-n", "1"), ("content-type", "application/json")]),
    content="{\"method\":\"PUT\",\"path\":\"/files/a b?x=1&y=é\",\"headers\":{\"content-type\":\"application/json\",\"x-n\":\"1\"}}\n",
  )
  // An ask: no body, its further fields after the headers.
  let adb : Map[String, Json] = {
    "adb": { "offer": { "connect": 5555, "pair": null, "name": "Pixel \"8\"" }, "phone": "abababab" },
  }
  inspect(
    @wire.head_line("POST", "/adb", [], more=adb),
    content="{\"method\":\"POST\",\"path\":\"/adb\",\"headers\":{},\"adb\":{\"offer\":{\"connect\":5555,\"pair\":null,\"name\":\"Pixel \\\"8\\\"\"},\"phone\":\"abababab\"}}\n",
  )
  // A socket: `socket` true.
  inspect(
    @wire.head_line("GET", "/preview/3000/ws", [("sec-websocket-protocol", "vite-hmr")], more={ "socket": true }),
    content="{\"method\":\"GET\",\"path\":\"/preview/3000/ws\",\"headers\":{\"sec-websocket-protocol\":\"vite-hmr\"},\"socket\":true}\n",
  )
  // A duplex: what it is of, with a number that is no whole one.
  let screen : Map[String, Json] = {
    "screen": { "id": "main", "width": 1280.5, "fps": 30, "audio": true, "opus": true, "self": "cdcdcdcd" },
  }
  inspect(
    @wire.head_line("GET", "/screens/view", [("idempotency-key", "k1")], more=screen),
    content="{\"method\":\"GET\",\"path\":\"/screens/view\",\"headers\":{\"idempotency-key\":\"k1\"},\"screen\":{\"id\":\"main\",\"width\":1280.5,\"fps\":30,\"audio\":true,\"opus\":true,\"self\":\"cdcdcdcd\"}}\n",
  )
  // Several fields, in the order given, their own fields in theirs; numbers as JavaScript writes them.
  let several : Map[String, Json] = { "a": 1, "b": [1.5, 0, 1.0e21, 1.0e-7, "</script>😀"], "a2": { "z": 1, "a": 2 } }
  inspect(
    @wire.head_line("GET", "/x", [], more=several),
    content="{\"method\":\"GET\",\"path\":\"/x\",\"headers\":{},\"a\":1,\"b\":[1.5,0,1e+21,1e-7,\"</script>😀\"],\"a2\":{\"z\":1,\"a\":2}}\n",
  )
  // A number that is none is null, wherever it is, in a head's line and in a control line.
  let zero = 0.0
  let none : Map[String, Json] = {
    "a": Json::number(zero / zero),
    "b": [Json::number(1.0 / zero), { "c": Json::number(-1.0 / zero) }, 2],
  }
  inspect(
    @wire.head_line("GET", "/x", [], more=none),
    content="{\"method\":\"GET\",\"path\":\"/x\",\"headers\":{},\"a\":null,\"b\":[null,{\"c\":null},2]}\n",
  )
  inspect(@wire.hello_line("x", says=none), content="{\"credential\":\"x\",\"a\":null,\"b\":[null,{\"c\":null},2]}\n")
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
fn fed(stream : Bytes, cuts : Array[Int]) -> Array[@wire.Event] raise {
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
  // (as JavaScript's TextDecoder, which reads each block there, takes one off: so the first line after it is read)
  let sse = @wire.Sse::new()
  assert_true(
    sse.feed(b"\xEF\xBB\xBFdata: a\n\n\xEF\xBB\xBFevent: e\ndata: b\n\n") ==
    [{ name: "message", data: "a", id: None }, { name: "e", data: "b", id: None }],
  )
  assert_true(sse.feed(b"data: \xEF\xBB\xBFc\n\xEF\xBB\xBFdata: d\n\n") == [{ name: "message", data: "\u{FEFF}c", id: None }])
}

///|
test "bytes that are no UTF-8 are read as U+FFFD, one for each run that could have begun a character" {
  // (the WHATWG's decoding, which the core's reader in TypeScript has of TextDecoder)
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

///|
/// The events a reader keeping `most` bytes of a block gives for `stream` fed in the chunks `cuts` cut it into, and
/// whether it then failed as a block too long: asked once more with nothing at the end, since a feed that gave
/// events fails only at the next.
fn bounded(stream : Bytes, cuts : Array[Int], most : Int) -> (Array[@wire.Event], Bool) {
  let sse = @wire.Sse::new(most~)
  let out : Array[@wire.Event] = []
  let mut at = 0
  for cut in [..cuts, stream.length(), stream.length()] {
    out.append(sse.feed(stream[at:cut].to_owned())) catch {
      @wire.TooLong(most=said) => {
        guard said == most else { return (out, false) }
        return (out, true)
      }
    }
    at = cut
  }
  (out, false)
}

///|
/// The bound `sse` fails by as it is fed `chunk`; None where it reads it.
fn refused(sse : @wire.Sse, chunk : Bytes) -> Int? {
  ignore(sse.feed(chunk)) catch {
    @wire.TooLong(most~) => return Some(most)
  }
  None
}

///|
/// `stream` cut every way the made cases are: whole, a byte at a time, and in two at each place.
fn cuttings(stream : Bytes) -> Array[Array[Int]] {
  let ways : Array[Array[Int]] = [[], Array::makei(stream.length() - 1, i => i + 1)]
  for at in 1..<stream.length() {
    ways.push([at])
  }
  ways
}

///|
test "a block is kept up to its reader's bound, and one a byte longer ends the reading, whatever the chunks" {
  let a : @wire.Event = { name: "message", data: "a", id: None }
  let b : @wire.Event = { name: "message", data: "b", id: None }
  // "data: xxx" is 9 bytes: kept, with the events round it. Its CRs are not counted.
  for text in ["data: a\n\ndata: xxx\n\ndata: b\n\n", "data: a\r\n\r\ndata: xxx\r\n\r\ndata: b\r\n\r\n"] {
    let stream = @utf8.encode(text)
    for cuts in cuttings(stream) {
      let (events, over) = bounded(stream, cuts, 9)
      assert_true(events == [a, { name: "message", data: "xxx", id: None }, b])
      assert_false(over)
    }
  }
  // "data: xxxx" is 10: what came before it is given, nothing of it or after it, and the reader has failed.
  let stream = b"data: a\n\ndata: xxxx\n\ndata: b\n\n"
  for cuts in cuttings(stream) {
    let (events, over) = bounded(stream, cuts, 9)
    assert_true(events == [a])
    assert_true(over)
  }
}

///|
test "what has no blank line is held up to the bound and no further; a reader that failed stays failed" {
  // 4 bytes and a newline may still be a block of 4: waited for.
  let sse = @wire.Sse::new(most=4)
  assert_true(sse.feed(b"abcd\n") == [])
  assert_true(sse.feed(b"\n") == [])
  // A byte more with no blank line is a block too long, whatever comes after.
  assert_true(sse.feed(b"abcd") == [])
  assert_true(sse.feed(b"e") == [])
  assert_eq(refused(sse, b"f"), Some(4))
  assert_eq(refused(sse, b"\n\ndata: late\n\n"), Some(4))
}

///|
test "a stream with no blank line passes the bound a device keeps by default: refused, not held" {
  let sse = @wire.Sse::new()
  // 16 MiB of a line with no end, a MiB a chunk: held. Two bytes more: refused.
  let chunk = Bytes::make(1024 * 1024, b'x')
  for _ in 0..<16 {
    assert_true(sse.feed(chunk) == [])
  }
  assert_true(sse.feed(b"x") == [])
  assert_eq(refused(sse, b"x"), Some(16777216))
  assert_eq(@wire.max_event, 16777216)
}

///|
test "an event of very many data lines is its lines, a newline between two" {
  let lines = 5000
  let block = StringBuilder()
  let expected = StringBuilder()
  for i in 0..<lines {
    block.write_string("data: line \{i}\n")
    if i > 0 {
      expected.write_char('\n')
    }
    expected.write_string("line \{i}")
  }
  block.write_char('\n')
  let events = @wire.Sse::new().feed(@utf8.encode(block.to_string()))
  assert_true(events == [{ name: "message", data: expected.to_string(), id: None }])
}

///|
test "a reader told to keep the most an Int says reads as one with no bound in reach: no sum of it wraps" {
  let sse = @wire.Sse::new(most=0x7FFF_FFFF)
  assert_true(sse.feed(b"data: a\n\ndata: b") == [{ name: "message", data: "a", id: None }])
  assert_true(sse.feed(b"\n") == [])
  assert_true(sse.feed(b"\n") == [{ name: "message", data: "b", id: None }])
  assert_true(sse.feed(b"") == [])
}
